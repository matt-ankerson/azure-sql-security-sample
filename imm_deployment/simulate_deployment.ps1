#
# Invoke the deployment in a similar fashion to that of the immersion platform.
# - Create Resource Group
# - Push out the deployment template.
# - Invoke the post-deploy script.
#
# This script should not be included as part of the actual immersion deployment.

$resourceGroupName = "sql-security-007"
$msolcred = Get-Credential
$tenantId = Get-AzureRmSubscription | Select-Object -ExpandProperty TenantId
$subscriptionId = Get-AzureRmSubscription | Select-Object -ExpandProperty SubscriptionId
$region = "East US"
$userEmail = "matta@intergenusalive.onmicrosoft.com"

# Bring the post deploy function into scope
. "$(Split-Path $MyInvocation.MyCommand.Path)\postdeploy.ps1"

#------------------------------#
# Get or create Resource group #
#------------------------------#

Write-Host "Acquiring resource group $($resourceGroupName)"

$resourceGroup = try {
    Get-AzureRmResourceGroup -Name $resourceGroupName -Verbose
} catch {
    if ($_.Exception.Message -eq 'Provided resource group does not exist.') { 
        $null 
    } else {
        throw
    }
}

if (-not $resourceGroup) {
        Write-Host "Creating resource group $($resourceGroupName)..."
        $resourceGroup = New-AzureRmResourceGroup -Name $resourceGroupName -Location $region -Verbose
}

if (-not $resourceGroup) {
    Write-Warning 'No resource group!'
    return
}

$resourceGroupName = $resourceGroup.ResourceGroupName


#---------------------------------#
# Start Resource Group deployment #
#---------------------------------#

$template = "$(Split-Path $MyInvocation.MyCommand.Path)\deploytemplate.json"
$params = "$(Split-Path $MyInvocation.MyCommand.Path)\template_parameters.json"

$armResult = New-AzureRmResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile $template -TemplateParameterFile $params -Verbose


#--------------------#
# Invoke post-deploy #
#--------------------#

if ($armResult) {
    # Start post-deploy
    Start-ImmersionPostDeployScript $msolcred $tenantId $subscriptionId $region $userEmail "userPassword" $resourceGroupName "storageAccountName"
} else {
    Write-Warning "ARM provisioning failed."
}
