#Requires -Module MSAL.PS
function New-AzureDevOpsAuthHeader {
    <#
    .SYNOPSIS
    Function for getting authentication header for web requests against Azure DevOps.

    .DESCRIPTION
    Function for getting authentication header for web requests against Azure DevOps.

    Function uses MSAL to authenticate (requires MSAL.PS module).

    .EXAMPLE
    $header = New-AzureDevOpsAuthHeader
    Invoke-WebRequest -Uri $uri -Headers $header

    .NOTES
    https://docs.microsoft.com/en-us/rest/api/azure/devops/?view=azure-devops-rest-7.1
    PowerShell module AzSK.ADO > ContextHelper.ps1 > GetCurrentContext
    https://stackoverflow.com/questions/56355274/getting-oauth-tokens-for-azure-devops-api-consumption
    https://stackoverflow.com/questions/52896114/use-azure-ad-token-to-authenticate-with-azure-devops
    #>

    [CmdletBinding()]
    param ()

    # TODO oAuth auth https://github.com/microsoft/azure-devops-auth-samples/tree/master/OAuthWebSample
    # $msalToken = Get-MsalToken -TenantId $TenantID -ClientId $ClientID -UserCredential $Credential -Scopes ([String]::Concat($($ApplicationIdUri), '/user_impersonation')) -ErrorAction Stop

    $clientId = "872cd9fa-d31f-45e0-9eab-6e460a02d1f1" # Visual Studio
    $adoResourceId = "499b84ac-1321-427f-aa17-267ca6975798" # Azure DevOps app ID
    $msalToken = Get-MsalToken -Scopes "$adoResourceId/.default" -ClientId $clientId

    if ($msalToken.accessToken) {
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f "", $msalToken.accessToken)))
        return @{Authorization = "Basic $base64AuthInfo" }
    } else {
        throw "Unable to obtain DevOps MSAL token"
    }
}