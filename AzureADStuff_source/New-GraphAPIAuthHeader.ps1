function New-GraphAPIAuthHeader {
    <#
    .SYNOPSIS
    Function for generating header that can be used for authentication of Graph API requests.

    .DESCRIPTION
    Function for generating header that can be used for authentication of Graph API requests.
    Credentials can be given or existing AzureAD session can be reused to obtain auth. header.

    .PARAMETER credential
    Credentials for Graph API authentication (AppID + AppSecret) that will be used to obtain auth. header.

    .PARAMETER reuseExistingAzureADSession
    Switch for using existing AzureAD session (created via Connect-AzureAD) to obtain auth. header.

    .PARAMETER TenantDomainName
    Name of your Azure tenant.

    .PARAMETER showDialogType
    Modify behavior of auth. dialog window.

    Possible values are: auto, always, never.

    Default is 'never'.

    .EXAMPLE
    $header = New-GraphAPIAuthHeader -credential $cred
    $URI = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/'
    $managedDevices = (Invoke-RestMethod -Headers $header -Uri $URI -Method Get).value

    .EXAMPLE
    (there is existing AzureAD session already (made via Connect-AzureAD))
    $header = New-GraphAPIAuthHeader -reuseExistingAzureADSession
    $URI = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/'
    $managedDevices = (Invoke-RestMethod -Headers $header -Uri $URI -Method Get).value

    .NOTES
    https://adamtheautomator.com/powershell-graph-api/#AppIdSecret
    https://thesleepyadmins.com/2020/10/24/connecting-to-microsoft-graphapi-using-powershell/
    https://github.com/microsoftgraph/powershell-intune-samples
    https://tech.nicolonsky.ch/explaining-microsoft-graph-access-token-acquisition/
    https://gist.github.com/psignoret/9d73b00b377002456b24fcb808265c23
    #>

    [CmdletBinding()]
    [Alias("New-IntuneAuthHeader", "Get-IntuneAuthHeader")]
    param (
        [Parameter(ParameterSetName = "authenticate")]
        [System.Management.Automation.PSCredential] $credential,

        [Parameter(ParameterSetName = "reuseSession")]
        [switch] $reuseExistingAzureADSession,

        [ValidateNotNullOrEmpty()]
        $tenantDomainName = $_tenantDomain,

        [ValidateSet('auto', 'always', 'never')]
        [string] $showDialogType = 'never'
    )

    if (!$credential -and !$reuseExistingAzureADSession) {
        $credential = (Get-Credential -Message "Enter AppID as UserName and AppSecret as Password")
    }
    if (!$credential -and !$reuseExistingAzureADSession) { throw "Credentials for creating Graph API authentication header is missing" }

    if (!$tenantDomainName -and !$reuseExistingAzureADSession) { throw "TenantDomainName is missing" }

    Write-Verbose "Getting token"

    if ($reuseExistingAzureADSession) {
        # get auth. token using the existing session created by the AzureAD PowerShell module
        try {
            # test if connection already exists
            $c = Get-AzureADCurrentSessionInfo -ea Stop
        } catch {
            throw "There is no active session to AzureAD. Omit reuseExistingAzureADSession parameter or call this function after Connect-AzureAD."
        }

        try {
            $ErrorActionPreference = "Stop"

            $context = [Microsoft.Open.Azure.AD.CommonLibrary.AzureRmProfileProvider]::Instance.Profile.Context
            $authenticationFactory = [Microsoft.Open.Azure.AD.CommonLibrary.AzureSession]::AuthenticationFactory
            $msGraphEndpointResourceId = "MsGraphEndpointResourceId"
            $msGraphEndpoint = $context.Environment.Endpoints[$msGraphEndpointResourceId]
            $auth = $authenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id.ToString(), $null, [Microsoft.Open.Azure.AD.CommonLibrary.ShowDialog]::$showDialogType, $null, $msGraphEndpointResourceId)

            $token = $auth.AuthorizeRequest($msGraphEndpointResourceId)

            return @{ Authorization = $token }
        } catch {
            throw "Unable to obtain auth. token:`n`n$($_.exception.message)`n`n$($_.invocationInfo.PositionMessage)`n`nTry change of showDialogType parameter?"
        }
    } else {
        # authenticate to obtain the token
        $body = @{
            Grant_Type    = "client_credentials"
            Scope         = "https://graph.microsoft.com/.default"
            Client_Id     = $credential.username
            Client_Secret = $credential.GetNetworkCredential().password
        }

        $connectGraph = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantDomainName/oauth2/v2.0/token" -Method POST -Body $body

        $token = $connectGraph.access_token

        if ($token) {
            return @{ Authorization = "Bearer $($token)" }
        } else {
            throw "Unable to obtain token"
        }
    }
}