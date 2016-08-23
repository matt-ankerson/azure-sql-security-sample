
# Predeployment operations for Azure SQL Security Demo.
#
# This script assumes that Login-AzureRmAccount has already been run.
#
# Steps:
# 1. Provision application in Azure AD.
# 2. Interrogate Azure AD for configuration data.
# 3. Invoke ARM deployment (push out deployment template).
# 

# Import useful functions from deployment library file
. "$(Split-Path $MyInvocation.MyCommand.Path)\DeploymentLib.ps1"

# Name of the Azure AD instance
#$global:tenant = "immersionp29.onmicrosoft.com"
$global:tenant = "intergenusalive.onmicrosoft.com"

# ADAL JSON token - necessary for making requests to Graph API
$global:token = GetAuthToken -TenantName $global:tenant
# REST API header with auth token
$global:authHeader = @{
    'Content-Type'='application/json';
    'Authorization'=$global:token.CreateAuthorizationHeader()
}

# Create an application.
$resource = "applications"
$payload = @{
    'displayName'='AzureSqlInjDemoApp';
    'homepage'='https://www.contoso.com';
    'identifierUris'= @('https://AzureSqlInjDemoApp')
}
$payload = ConvertTo-Json -InputObject $payload
$uri = "https://graph.windows.net/$($global:tenant)/$($resource)?api-version=1.6"
$result = (Invoke-RestMethod -Uri $uri -Headers $global:authHeader -Body $payload -Method POST -Verbose).value
Write-Host $result

#$users | Select-Object DisplayName, UserPrincipalName, UserType | Format-Table
