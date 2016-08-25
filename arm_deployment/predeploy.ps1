
param (
    [Parameter(Mandatory = $false, HelpMessage = 'Resource Group name for this deployment. Should be globally unique. Will be created if not exists. Random name will be used if this parameter is absent.')]
    [string] $paramResourceGroupName,

    [Parameter(Mandatory = $false, HelpMessage = 'Storage Account name for this deployment. Should be globally unique. Will be created if not exists. Random name will be used if this parameter is absent.')]
    [string] $paramStorageAccountName = $null,

    [Parameter(Mandatory = $false, HelpMessage = 'Username to be used for SQL server and the web application.')]
    [string] $paramUsername = "azuresqlsecurity123!",

        [Parameter(Mandatory = $false, HelpMessage = 'Password to be used for SQL server and the web application.')]
    [string] $paramPassword = "azuresqlsecuritydemo123!",

     [Parameter(Mandatory = $false, HelpMessage = 'The name of the Azure Active Directory instance for use with this deployment.')]
    [string] $paramAADInstanceName = "intergenusalive.onmicrosoft.com",
    #[string] $paramAADInstanceName = "immersionp29.onmicrosoft.com",

    [Parameter(Mandatory = $false, HelpMessage = 'The Azure region to deploy into.')]
    [string] $paramRegion = "East US"
)

# Predeployment operations for Azure SQL Security Demo.
#
# This script is non-interactive.
# This script assumes that Login-AzureRmAccount has already been run and will 
# use the default subscription. 
# TODO: Perhaps there should be support for selecting a different sub.
#
# Steps:
# 1. Build web application
# 2. Provision application in Azure AD.
# 3. Interrogate Azure AD for configuration data.
# 4. Invoke ARM deployment (push out deployment template).
# 

# Import useful functions from deployment library file
. "$(Split-Path $MyInvocation.MyCommand.Path)\DeploymentLib.ps1"

#-------------------------#
# Set up useful variables #
#-------------------------#

$global:region = $paramRegion
$global:username = $paramUsername
$global:password = $paramPassword

if (-not $paramResourceGroupName) {
    $resourceGroupNameSuffix = -join ((65..90) + (97..122) | Get-Random -Count 6 | % {[char]$_})
    $global:resourceGroupName = "imm-sql-security$($resourceGroupNameSuffix.ToLower())"
} else {
    $global:resourceGroupName = $paramResourceGroupName
}
if (-not $paramStorageAccountName) {
    $storageAccountNameSuffix = -join ((65..90) + (97..122) | Get-Random -Count 6 | % {[char]$_})
    $global:storageAccountName = "sqlsecurity$($storageAccountNameSuffix.ToLower())"
} else {
    $global:storageAccountName = $paramStorageAccountName
}

# Name of the Azure AD instance
$global:tenant = $paramAADInstanceName
$global:aadSecretGuid = New-Guid
$global:aadDisplayName = "SqlInj$($global:resourceGroupName)"
$global:aadIdentifierUris = @("https://$($global:resourceGroupName)")
$guidBytes = [System.Text.Encoding]::UTF8.GetBytes($global:aadSecretGuid)

$global:aadSecret = @{
    'type'='Symmetric';
    'usage'='Verify';
    'endDate'=[DateTime]::UtcNow.AddDays(365).ToString('u').Replace(' ', 'T');
    'keyId'=$global:aadSecretGuid;
    'startDate'=[DateTime]::UtcNow.AddDays(-1).ToString('u').Replace(' ', 'T');  
    'value'=[System.Convert]::ToBase64String($guidBytes);
}

# ADAL JSON token - necessary for making requests to Graph API
$global:token = GetAuthToken -TenantName $global:tenant
# REST API header with auth token
$global:authHeader = @{
    'Content-Type'='application/json';
    'Authorization'=$global:token.CreateAuthorizationHeader()
}

#-----------------------#
# Build web application #
#-----------------------#
 
Write-Host 'Building web app'

tool_nuget restore '..\src' -noninteractive

$log_path = (join-path $out_dir "msbuild.log")
tool_msbuild '..\src\ContosoOnlineBikeStore\ContosoOnlineBikeStore.csproj' /p:Platform="AnyCPU" /T:Package /P:PackageLocation="$out_dir" /P:_PackageTempDir="$temp_dir" /fileLoggerParameters:LogFile="$log_path"

# Scan for build error
if (-not (test-path $log_path)) {
    Write-Warning "Unable to find msbuild log file $log_path"
    return
}

$build_success = ((Select-String -Path $log_path -Pattern "Build FAILED." -SimpleMatch) -eq $null) -and $LASTEXITCODE -eq 0

if (-not $build_success) {
    Write-Warning "Error building project. See build log: $log_path"
    return
}

#------------------------------------------#
# Find local machines' external ip address #
#------------------------------------------#

Write-Host 'Finding external IP address (this may take a while)'

$global:external_ip_address = (Invoke-WebRequest 'http://bot.whatismyipaddress.com/' -TimeoutSec 240).Content.Trim()

if (-not $global:external_ip_address) {
    Write-Warning 'Unable to determine external IP Address! Please try again.'
    return
}
else {
    Write-Host "Found external IP Address: $($global:external_ip_address)"
}

#------------------------------#
# Get or create Resource group #
#------------------------------#

Write-Host "Acquiring resource group $($global:resourceGroupName)"

$global:resourceGroup = try {
    Get-AzureRmResourceGroup -Name $global:resourceGroupName -Verbose
} catch {
    if ($_.Exception.Message -eq 'Provided resource group does not exist.') { 
        $null 
    } else {
        throw
    }
}

if (-not $global:resourceGroup) {
        Write-Host "Creating resource group $($global:resourceGroupName)..."
        $global:resourceGroup = New-AzureRmResourceGroup -Name $global:resourceGroupName -Location $global:region -Verbose
}

if (-not $global:resourceGroup) {
    Write-Warning 'No resource group!'
    return
}

$global:resourceGroupName = $global:resourceGroup.ResourceGroupName

#-------------------------------#
# Get or create storage account #
#-------------------------------#

Write-Host "Acquiring storage account $($global:storageAccountName)"

$global:storageAccount = try {

    Get-AzureRmStorageAccount -ResourceGroupName $global:resourceGroupName -Name $global:storageAccountName -Verbose
} catch {

    if ($_.Exception.Message.Contains('not found')) { $null } else { throw } 
}

if (-not $global:storageAccount) {
        Write-Host "Creating storage account $($global:storageAccountName)..."

        $global:storageAccount = New-AzureRmStorageAccount -ResourceGroupName $global:resourceGroupName -Name $global:storageAccountName -Type "Standard_LRS" -Location $global:region -Verbose
}

if (-not $global:storageAccount) {
    Write-Warning 'No storage account'
    return
}

$global:storageAccountName = $global:storageAccount.StorageAccountName

Write-Host "Using storage account $($global:storageAccountName)"

$global:storageAccountKey = Get-AzureRmStorageAccountKey -ResourceGroupName $global:resourceGroupName -Name $global:storageAccountName

if (-not $global:storageAccountKey) {
    Write-Warning 'Could not retrieve storage account key'
    return
}

# Get key 1. Older versions of powershell use .Key1
if (-not $global:storageAccountKey.Key1) {
    $global:storageAccountKey = $global:storageAccountKey.Value[0]
} else {
    $global:storageAccountKey = $global:storageAccountKey.Key1
}

#----------------------------#
# Upload web deploy packages #
#----------------------------#

Write-Host 'Uploading deployment package to blob storage'

Write-Host 'Connecting to blob storage'
$deploymentContainerName = 'deployment'

# Connect to blob storage
$blobContext = New-AzureStorageContext -StorageAccountName $global:storageAccountName -StorageAccountKey $storageAccountKey
if (-not $blobContext) {
    Write-Warning "Failed to connect to Azure Storage"
    return
}

# Verify or create container
$container = 
    try {
        Get-AzureStorageContainer -Context $blobContext -Name $deploymentContainerName
    }
    catch {
        if ($_.Exception.Message.Contains('Can not find the container')) { $null } else { throw }
    }

if (-not $container) {
    Write-Host "Creating Container"
    $container = New-AzureStorageContainer -Context $blobContext -Name $deploymentContainerName -Permission Blob
}

if (-not $container) {
    Write-Warning "Failed to create deployment container"
    return
}

# Upload web deploy package

Write-Host 'Uploading web app'

$webDeployPackageName = 'ContosoOnlineBikeStore.zip'
$webDeployPackage = (join-path $out_dir $webDeployPackageName)

$blobResult = Set-AzureStorageBlobContent -Context $blobContext `
                                                   -Container $deploymentContainerName `
                                                   -Blob $webDeployPackageName `
                                                   -File $webDeployPackage `
                                                   -Force
if (-not $blobResult) {
    Write-Warning "Failed to upload blob $webDeployPackageName"
    return
}

$global:webAppPackageUri = $blobResult.ICloudBlob.Uri.AbsoluteUri;

Write-Host "Uploaded web app to $($global:webAppPackageUri)"

#------------------------------------#
# Provision a new application in AAD #
#------------------------------------#

# Note: Running this script multiple times will result in a HTTP error
#       as the application has already been created. This is a non-
#       breaking issue.
#
$resource = "applications"
$payload = @{
    'displayName'=$global:aadDisplayName;
    'homepage'='https://www.contoso.com';
    'identifierUris'= $global:aadIdentifierUris;
    'keyCredentials'=@($global:aadSecret)
}
$payload = ConvertTo-Json -InputObject $payload
$uri = "https://graph.windows.net/$($global:tenant)/$($resource)?api-version=1.6"
$result = (Invoke-RestMethod -Uri $uri -Headers $global:authHeader -Body $payload -Method POST -Verbose).value


# Interrogate AAD for the necessary configuration values.
#
# Pull the app manifest for the application.
$resource = "applications"
$uri = "https://graph.windows.net/$($global:tenant)/$($resource)?api-version=1.6&`$filter`=identifierUris/any(c:c+eq+'$($global:aadIdentifierUris)')"
$result = (Invoke-RestMethod -Uri $uri -Headers $global:authHeader -Method GET -Verbose).value

# Extract configuration values
$keyObject = foreach($i in $result.keyCredentials) { $i }
$oauthObject = foreach($i in $result.oauth2Permissions) { $i }

# Tenant ID
$global:aadTenantId = Get-AzureRmSubscription | Select-Object -ExpandProperty TenantId
# Application object ID
$global:aadApplicationObjectId = $result | Select-Object -ExpandProperty objectId
# App ID / Client ID
$global:aadClientId = $result | Select-Object -ExpandProperty appId
# Application Secret/Key
$global:aadAppSecret = $keyObject | Select-Object -ExpandProperty keyId
# User object ID
$global:aadUserObjectId = $oauthObject | Select-Object -ExpandProperty id

#---------------------------------------------------#
# Begin Resource Deployment (end of pre-deployment) #
#---------------------------------------------------#

Write-Host 'Starting resource group deployment'

$template = "$script_dir\deploytemplate.json"

$params = @{
    'resourceGroup'                     = $global:resourceGroupName;
    'webAppPackageUrl'                  = $global:webAppPackageUri;
    'externalIpAddress'                 = $global:external_ip_address;
    # Below: app settings for web app.
    'administratorLogin'                = $global:username;
    'administratorLoginPassword'        = $global:password;
    'applicationLogin'                  = $global:username;
    'applicationLoginPassword'          = $global:password;
    'siteName'                          = $global:resourceGroupName;
    'location'                          = $global:region;
    'userObjectID'                      = $global:aadUserObjectId;
    'ApplicationObjectId'               = $global:aadApplicationObjectId;
    'ClientId'                          = $global:aadClientId;
    'ActiveDirectoryAppSecret'          = $global:aadAppSecret;
    'applicationADSecret'               = $global:aadAppSecret;
}

$armResult = New-AzureRmResourceGroupDeployment -ResourceGroupName $global:resourceGroupName -TemplateFile $template -TemplateParameterObject $params -Verbose

if (-not $armResult -or $armResult.ProvisioningState -ne 'Succeeded') {
    Write-Warning 'An error occured during provisioning'
    Write-Output $armResult
    return
}

#-----------------------#
# Begin post-deployment #
#-----------------------#

# Copy output values into a dictionary for easy consumption
$OUTPUTS = @{}

foreach ($name in $armResult.Outputs.Keys) {
    $OUTPUTS[$name] = $armResult.Outputs[$name].Value
}

# Invoke post-deployment script.
