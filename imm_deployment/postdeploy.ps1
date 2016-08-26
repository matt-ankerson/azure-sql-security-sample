param (
    [Parameter(Mandatory = $true, HelpMessage = 'Resource Group name for this deployment.')]
    [string] $global:resourceGroupName,

    [Parameter(Mandatory = $true, HelpMessage = 'The name of the Azure Active Directory instance for use with this deployment.')]
    [string] $global:aadTenant# = "intergenusalive.onmicrosoft.com"
)

#
# Post-deployment steps - to be run after the successful
#   deployment of 'deploytemplate.json'.
#
#   Steps completed:
#       - Get outputs from ARM deployment.
#       - Provisions application in Azure AD.
#       - Creates access policies for Azure Key Vault.
#       - Updates config for web application
#       - Inserts seed data in SQL database.
#

#------------------------------#
# Set up some useful functions #
#------------------------------#
. "$(Split-Path $MyInvocation.MyCommand.Path)\DeploymentLib.ps1"

#---------------------------------------------#
# Get the outputs from the latest deployment. #
#---------------------------------------------#

Write-Host 'Fetching ARM outputs'

$global:deployOutputs = (Get-AzureRMResourceGroupDeployment "$($global:resourceGroupName)").Outputs

#--------------------------------#
# Setup some necessary variables #
#--------------------------------#
$global:region = $global:deployOutputs['region']
$global:username = $global:deployOutputs['username']
$global:password = $global:deployOutputs['password']

$global:keyVaultName = $global:deployOutputs['keyVaultName']
$global:siteName = $global:deployOutputs['siteName']
$global:sqlServerName = $global:deployOutputs['sqlServerName']
$global:sqlServerDbName = $global:deployOutputs['sqlServerDbName']

$global:aadSecretGuid = New-Guid
$global:aadSecretBytes = [System.Text.Encoding]::UTF8.GetBytes($global:aadSecretGuid)
$global:aadDisplayName = "sqlinj$($global:resourceGroupName)"
$global:aadIdentifierUris = @("https://$(global:resourceGroupName)")
$global:aadSecret = @{
    'type'='Symmetric';
    'usage'='Verify';
    'endDate'=[DateTime]::UtcNow.AddDays(365).ToString('u').Replace(' ', 'T');
    'keyId'=$global:aadSecretGuid;
    'startDate'=[DateTime]::UtcNow.AddDays(-1).ToString('u').Replace(' ', 'T');  
    'value'=[System.Convert]::ToBase64String($global:aadSecretBytes);
}

# ADAL JSON token - necessary for making requests to Graph API
$global:token = GetAuthToken -TenantName $global:aadTenant
# REST API header with auth token
$global:authHeader = @{
    'Content-Type'='application/json';
    'Authorization'=$global:token.CreateAuthorizationHeader()
}

#------------------------------------#
# Provision a new application in AAD #
#------------------------------------#
#
# Note: Running this script multiple times will result in a HTTP error
#       as the application has already been created.
#

Write-Host 'Provisioning application in AAD'

$resource = "applications"
$payload = @{
    'displayName' = $global:aadDisplayName;
    'homepage' = 'https://www.contoso.com';
    'identifierUris' = $global:aadIdentifierUris;
    'keyCredentials' = @($global:aadSecret)
}
$payload = ConvertTo-Json -InputObject $payload
$uri = "https://graph.windows.net/$($global:aadTenant)/$($resource)?api-version=1.6"
$result = (Invoke-RestMethod -Uri $uri -Headers $global:authHeader -Body $payload -Method POST -Verbose).value


# Interrogate AAD for the necessary configuration values.

Write-Host 'Pulling configuration values from AAD'

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


#----------------------------------#
# Create Key Vault Access Policies #
#----------------------------------#

Write-Host 'Creating Key Vault Access Policies'

# Create access policy for application.
# - grants the app permission to read secrets
Set-AzureRmKeyVaultAccessPolicy -VaultName $global:keyVaultName -ResourceGroupName $global:resourceGroupName -ObjectId $global:aadApplicationObjectId -PermissionsToSecrets 'List,Get' -PermissionsToKeys get,wrapkey,unwrapkey,sign,verify

# Create access policy for user.
# - grants the user permission to read and write secrets
Set-AzureRmKeyVaultAccessPolicy -VaultName $global:keyVaultName -ResourceGroupName $global:resourceGroupName -ObjectId $global:aadUserObjectId -PermissionsToSecrets 'List,Get' -PermissionsToKeys create,get,wrapkey,unwrapkey,sign,verify


#------------------------------#
# Update website configuration #
#------------------------------#

Write-Host 'Updating site config'

# Get the web app.
$webApp = Get-AzureRmWebApp -ResourceGroupName "$($global:resourceGroupName)" -Name "$($global:siteName)"
# Pull out the site settings.
$appSettingsList = $webApp.SiteConfig.AppSettings

# Build an object containing the app settings.
$appSettings = @{}
ForEach ($kvp in $appSettingsList) {
    $appSettings[$kvp.Name] = $kvp.Value
}

# Add the necessary settings to the settings object
$appSettings['administratorLogin'] = $global:username
$appSettings['administratorLoginPassword'] = $global:password
$appSettings['applicationLogin'] = $global:username
$appSettings['applicationLoginPassword'] = $global:password
$appSettings['applicationADID'] = $global:aadClientId
$appSettings['applicationADSecret'] = $global:aadAppSecret

# Push the new app settings back to the web app
Set-AzureRmWebApp -ResourceGroupName "$($global:resourceGroupName)" -Name "$($global:siteName)" -AppSettings $appSettings


#----------------------------------------------#
# Run SQL scripts to populate necessary tables #
#----------------------------------------------#

Write-Host 'Executing database bootstrap scripts'

$sql_scripts = @(
    "$script_dir\sql\store_inserts.sql"
)

$sqlServer         = $OUTPUTS['sqlServerName']
$sqlServerUsername = $OUTPUTS['sqlServerUsername']
$sqlServerPassword = $OUTPUTS['sqlServerPassword']
$sqlServerDatabase = $OUTPUTS['sqlServerDbName']

$sqlTimeoutSeconds = [int] [TimeSpan]::FromMinutes(8).TotalSeconds 
$sqlConnectionTimeoutSeconds = [int] [TimeSpan]::FromMinutes(2).TotalSeconds

Push-Location
try {
    foreach ($script_path in $sql_scripts) {
        Write-Host "Executing $script_path"
        Invoke-Sqlcmd -ServerInstance $sqlServer -Username $sqlServerUsername -Password $sqlServerPassword -Database $sqlServerDatabase -InputFile $script_path -QueryTimeout $sqlTimeoutSeconds -ConnectionTimeout $sqlConnectionTimeoutSeconds
    }
} catch {
    Write-Warning "Error executing $sql_script (consider executing manually)`n$($_.Exception)"
}
finally {
    # Work around Invoke-Sqlcmd randomly changing the working directory
    Pop-Location
}

Write-Host "Bye"
