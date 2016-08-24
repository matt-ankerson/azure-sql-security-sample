#
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

# Configure some useful globals:
#
# Name of the Azure AD instance
#$global:tenant = "immersionp29.onmicrosoft.com"
$global:tenant = "intergenusalive.onmicrosoft.com"

$global:aadAppDisplayName = "AzureSqlInjDemoApp"
$global:aadAppIdentifierUris = @('https://AzureSqlInjDemoApp')
$global:aadAppSecretGuid = New-Guid
$guidBytes = [System.Text.Encoding]::UTF8.GetBytes($global:aadAppSecretGuid)
$global:aadAppSecret = @{
    'type'='Symmetric';
    'usage'='Verify';
    'endDate'=[DateTime]::UtcNow.AddDays(365).ToString('u').Replace(' ', 'T');
    'keyId'=$global:aadAppSecretGuid;
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

# Provision an application in AAD.
$resource = "applications"
$payload = @{
    'displayName'=$global:aadAppDisplayName;
    'homepage'='https://www.contoso.com';
    'identifierUris'= $global:aadAppIdentifierUris;
    'keyCredentials'=@($global:aadAppSecret)
}
$payload = ConvertTo-Json -InputObject $payload
$uri = "https://graph.windows.net/$($global:tenant)/$($resource)?api-version=1.6"
$result = (Invoke-RestMethod -Uri $uri -Headers $global:authHeader -Body $payload -Method POST -Verbose).value

# Make the AAD application generate a Client Key / Secret


# Interrogate AAD for the necessary configuration values.
#
# Pull the app manifest for the application.
$resource = "applications"
$uri = "https://graph.windows.net/$($global:tenant)/$($resource)?api-version=1.6&`$filter`=identifierUris/any(c:c+eq+'$($global:aadAppIdentifierUris)')"
$result = (Invoke-RestMethod -Uri $uri -Headers $global:authHeader -Method GET -Verbose).value

# Extract configuration values
Get-AzureRmSubscription | Select-Object TenantId | Format-Table # Tenant ID
$result | Select-Object objectId | Format-Table     # Application object ID
$result | Select-Object appId | Format-Table        # App ID / Client ID
$global:aadAppSecretGuid | Format-Table             # AAD APP Secret
# !!user object ID is in the oauth2Permissions property!!

