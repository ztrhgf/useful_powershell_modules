function New-AzureDevOpsAuthHeader {
    <#
    .SYNOPSIS
    Function for getting authentication header for web requests against Azure DevOps.

    .DESCRIPTION
    Function for getting authentication header for web requests against Azure DevOps.

    .PARAMETER useMsal
    Switch to use MSAL authentication.

    Function uses Az token by default.

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
    param (
        [switch] $useMsal
    )

    # TODO oAuth auth https://github.com/microsoft/azure-devops-auth-samples/tree/master/OAuthWebSample
    # $msalToken = Get-MsalToken -TenantId $TenantID -ClientId $ClientID -UserCredential $Credential -Scopes ([String]::Concat($($ApplicationIdUri), '/user_impersonation')) -ErrorAction Stop

    $clientId = "872cd9fa-d31f-45e0-9eab-6e460a02d1f1" # Visual Studio
    $adoResourceId = "499b84ac-1321-427f-aa17-267ca6975798" # Azure DevOps app ID

    if ($useMsal) {
        if (!(Get-Module MSAL.PS) -and !(Get-Module MSAL.PS -ListAvailable)) {
            throw "Module MSAL.PS is missing. Function $($MyInvocation.MyCommand) cannot continue"
        }

        $msalToken = Get-MsalToken -Scopes "$adoResourceId/.default" -ClientId $clientId

        if ($msalToken.accessToken) {
            $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f "", $msalToken.accessToken)))
            $header = @{
                'Authorization' = "Basic $base64AuthInfo"
                'Content-Type'  = 'application/json'
            }
        } else {
            throw "Unable to obtain DevOps MSAL token"
        }
    } else {
        if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
            throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
        }

        $secureToken = (Get-AzAccessToken -ResourceUrl $adoResourceId -AsSecureString).Token
        $token = [PSCredential]::New('dummy', $secureToken).GetNetworkCredential().Password
        $header = @{
            'Authorization' = 'Bearer ' + $token
            'Content-Type'  = 'application/json'
        }
    }

    return $header
}