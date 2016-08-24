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

# Name of the Azure AD instance
#$global:tenant = "immersionp29.onmicrosoft.com"
$global:tenant = "intergenusalive.onmicrosoft.com"

$global:aadSecretGuid = New-Guid
$global:aadDisplayName = "AzureSqlInjDemoApp"
$global:aadIdentifierUris = @('https://AzureSqlInjDemoApp')
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

# Provision an application in AAD.
#
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

$global:aadTenantId = Get-AzureRmSubscription | Select-Object -ExpandProperty TenantId      # Tenant ID
$global:aadApplicationObjectId = $result | Select-Object -ExpandProperty objectId           # Application object ID
$global:aadClientId = $result | Select-Object -ExpandProperty appId                         # App ID / Client ID
$global:aadAppSecret = $keyObject | Select-Object -ExpandProperty keyId                     # Application Secret/Key
$global:aadUserObjectId = $oauthObject | Select-Object -ExpandProperty id                   # User object ID

