function New-M365DefenderAuthHeader {
    <#
    .SYNOPSIS
    Function creates authentication header for accessing Microsoft 365 Defender API.

    .DESCRIPTION
    Function creates authentication header for accessing Microsoft 365 Defender API.

    Support authentication using Managed identity, current user, app secret.

    .PARAMETER credential
    Application ID (as username), application secret (as password).

    .PARAMETER identity
    Use managed identity to authenticate.
    https://learn.microsoft.com/en-us/answers/questions/1394819/authenticate-to-microsoft-defender-for-endpoint-ap

    .PARAMETER tenantId
    ID of your tenant.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    # Send the webrequest and get the results.
    $url = "https://api.securitycenter.microsoft.com/api/alerts?`$filter=alertCreationTime ge $dateTime"
    $response = Invoke-WebRequest -Method Get -Uri $url -Headers $header -ErrorAction Stop

    # Extract the alerts from the results.
    $alerts = ($response | ConvertFrom-Json).value | ConvertTo-Json

    Interactive authentication using provided credentials.

    .EXAMPLE
    Connect-AzAccount

    $header = New-M365DefenderAuthHeader

    Silent authentication using currently authenticated user.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader -credential $credential

    Silent authentication using provided credentials.

    .EXAMPLE
    Connect-AzAccount -identity

    $header = New-M365DefenderAuthHeader -identity

    Silent authentication using managed identity.

    .NOTES
    https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/api/exposed-apis-create-app-webapp?view=o365-worldwide#use-powershell
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ParameterSetName = "Credential")]
        [System.Management.Automation.PSCredential] $credential,

        [Parameter(Mandatory = $true, ParameterSetName = "ManagedIdentity")]
        [switch] $identity,

        [Parameter(Mandatory = $false, ParameterSetName = "Credential")]
        [ValidateNotNullOrEmpty()]
        $tenantId = $_tenantDomain
    )

    if ($credential -and !$tenantId) {
        throw "TenantId parameter cannot be empty!"
    }

    if ($identity) {
        # connecting using managed identity

        if (!(Get-Command "Get-AzAccessToken" -ea SilentlyContinue)) {
            throw "'Get-AzAccessToken' command is missing (module Az.Accounts). Unable to continue"
        }

        $sourceAppIdUri = 'https://api.securitycenter.microsoft.com/.default'
        $response = Get-AzAccessToken -ResourceUri $sourceAppIdUri
        $token = $response.token

        if (!$token) {
            throw "Unable to obtain an auth. token. Are you authenticated using managed identity via 'Connect-AzAccount -Identity'?"
        }
    } else {
        # connecting using credentials

        if ($credential) {
            # connecting using provided credentials
            $oAuthUri = "https://login.microsoftonline.com/$tenantId/oauth2/token"
            $authBody = [Ordered]@{
                scope         = 'https://api.securitycenter.microsoft.com/.default'
                client_id     = $credential.username
                client_secret = $credential.GetNetworkCredential().password
                grant_type    = 'client_credentials'
            }

            $authResponse = Invoke-RestMethod -Method Post -Uri $oAuthUri -Body $authBody -ErrorAction Stop
            $token = $authResponse.access_token
        } else {
            # connecting using existing Azure session
            $AccessToken = Get-AzAccessToken -ResourceUri 'https://api.securitycenter.microsoft.com' -ErrorAction Stop
            $token = $AccessToken.token
        }

        if (!$token) {
            throw "Unable to obtain an auth. token"
        }
    }

    $headers = @{
        'Content-Type' = 'application/json'
        Accept         = 'application/json'
        Authorization  = "Bearer $token"
    }

    return $headers
}