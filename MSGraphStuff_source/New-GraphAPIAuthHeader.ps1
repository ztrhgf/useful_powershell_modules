#requires -modules MSAL.PS, Az.Accounts

function New-GraphAPIAuthHeader {
    <#
    .SYNOPSIS
    Function for generating header that can be used for authentication of Graph API requests (via Invoke-RestMethod).

    .DESCRIPTION
    Function for generating header that can be used for authentication of Graph API requests (via Invoke-RestMethod).

    Authentication can be done in several ways:
     - (default behavior) reuse existing AzureAD session created using Connect-AzAccount
        - advantages:
            - unattended
        - disadvantages:
            - token cannot be used for some high privilege API calls (you'll get forbidden error), check 'useMSAL' parameter help for more information
     - connect as a current user using MSAL authentication library
        - advantages:
            - token contains all user assigned delegated scopes
            - supports specifying permission scopes
        - disadvantages:
            - (can be) interactive
     - connect using application credentials
        - advantages:
            - unattended
            - token contains all granted application permissions
        - disadvantages:
            - you have to create such application and grant it required application permissions

    .PARAMETER credential
    Application credentials (AppID + AppSecret) that should be used (instead of the current user) to obtain auth. header.

    .PARAMETER tenantDomainName
    Name of your Azure tenant.
    Mandatory for application and MSAL authentication.

    For example: "contoso.onmicrosoft.com"

    .PARAMETER useMSAL
    Switch for using MSAL authentication library for auth. token creation.
    When 'credential' parameter is NOT used, existing AzureAD session will be used (created via Connect-AzAccount aka 'Azure PowerShell' app is used) to obtain the token.
    But such token will contains only 'Directory.AccessAsUser.All' delegated permission therefore it cannot be used for access API which requires high privileged permission.
    Such privileged calls will end with 'forbidden' error, so for such cases use MSAL authentication library instead. It uses 'Microsoft Graph PowerShell' app instead and returns all user assigned permission by default.

    For more information check https://github.com/Azure/azure-powershell/issues/14085#issuecomment-1163204817

    .PARAMETER tokenLifeTime
    Token lifetime in minutes.
    Will be saved into the header 'ExpiresOn' key and can be used for expiration detection (need to create new token).
    By default it is random number between 60 and 90 minutes (https://learn.microsoft.com/en-us/azure/active-directory/develop/access-tokens#access-token-lifetime) but can be changed in tenant policy.

    Default is 60.

    .PARAMETER scope
    Graph API permission scopes that should be requested when 'useMSAL' parameter is used.

    For example: 'https://graph.microsoft.com/User.Read', 'https://graph.microsoft.com/Files.ReadWrite'

    .EXAMPLE
    $cred = Get-Credential -Message "Enter application credentials (AppID + AppSecret) that should be used to obtain auth. header."
    $header = New-GraphAPIAuthHeader -credential $cred -tenantDomainName "contoso.onmicrosoft.com"

    $URI = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/'
    $managedDevices = (Invoke-RestMethod -Headers $header -Uri $URI -Method Get).value

    Authenticate using given application credentials.

    .EXAMPLE
    Connect-AzAccount

    $header = New-GraphAPIAuthHeader

    $URI = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/'
    $managedDevices = (Invoke-RestMethod -Headers $header -Uri $URI -Method Get).value

    Authenticate as current user.

    .EXAMPLE
    Connect-AzAccount

    $header = New-GraphAPIAuthHeader -useMSAL

    $URI = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/'
    $managedDevices = (Invoke-RestMethod -Headers $header -Uri $URI -Method Get).value

    Use MSAL for auth. token creation. Can help if token created by calling New-GraphAPIAuthHeader without any parameters (reusing existing AzureAD session) fails with 'forbidden' error when used.

    .EXAMPLE
    Connect-AzAccount

    $header = New-GraphAPIAuthHeader -useMSAL -scope 'https://graph.microsoft.com/Device.Read'

    $URI = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/'
    $managedDevices = (Invoke-RestMethod -Headers $header -Uri $URI -Method Get).value

    Use MSAL for auth. token creation. Can help if token created by calling New-GraphAPIAuthHeader without any parameters (reusing existing AzureAD session) fails with 'forbidden' error when used.

    .NOTES
    https://adamtheautomator.com/powershell-graph-api/#AppIdSecret
    https://thesleepyadmins.com/2020/10/24/connecting-to-microsoft-graphapi-using-powershell/
    https://github.com/microsoftgraph/powershell-intune-samples
    https://tech.nicolonsky.ch/explaining-microsoft-graph-access-token-acquisition/
    https://gist.github.com/psignoret/9d73b00b377002456b24fcb808265c23
    https://learn.microsoft.com/en-us/answers/questions/922137/using-microsoft-graph-powershell-to-create-script
    #>

    [Alias("New-IntuneAuthHeader", "Get-IntuneAuthHeader", "New-MgAuthHeader")]
    [CmdletBinding()]
    param (
        [System.Management.Automation.PSCredential] $credential,

        [ValidateNotNullOrEmpty()]
        [Alias("tenantId")]
        $tenantDomainName = $_tenantDomain,

        [switch] $useMSAL,

        [string[]] $scope,

        [int] $tokenLifeTime
    )

    #region checks
    if ($useMSAL) {
        Write-Verbose "Checking for MSAL.PS module..."
        if (!(Get-Module MSAL.PS) -and !(Get-Module MSAL.PS -ListAvailable)) {
            throw "Module MSAL.PS is missing. Function $($MyInvocation.MyCommand) cannot continue"
        }
    }

    if (!$credential -and !$useMSAL) {
        Write-Verbose "Checking for Az.Accounts module..."
        if (!(Get-Module Az.Accounts) -and !(Get-Module Az.Accounts -ListAvailable)) {
            throw "Module Az.Accounts is missing. Function $($MyInvocation.MyCommand) cannot continue"
        }
    }

    if ($tokenLifeTime -and (!$credential -or ($credential -and $useMSAL))) {
        Write-Warning "'tokenLifeTime' parameter will be ignored. It can be used only with 'credential' but without 'useMSAL' parameter."
    }

    if ($scope -and !$useMSAL) {
        Write-Warning "'scope' parameter will be ignored, because 'useMSAL' parameter is not used"
    }
    #endregion checks

    Write-Verbose "Getting token"

    if ($credential) {
        # use service principal credentials to obtain the auth. token

        Write-Verbose "Using provided application credentials"

        if ($useMSAL) {
            # authenticate using MSAL

            if (!$tenantDomainName) {
                throw "tenantDomainName parameter has to be set (something like contoso.onmicrosoft.com)"
            }

            $param = @{
                ClientId     = $credential.username
                ClientSecret = $credential.password
                TenantId     = $tenantDomainName
            }
            if ($scope) { $param.scopes = $scope }

            $token = Get-MsalToken @param

            if ($token.AccessToken) {
                $authHeader = @{
                    ExpiresOn     = $token.ExpiresOn
                    Authorization = "Bearer $($token.AccessToken)"
                }

                return $authHeader
            } else {
                throw "Unable to obtain token"
            }
        } else {
            # authenticate using direct API call

            $body = @{
                Grant_Type    = "client_credentials"
                Scope         = "https://graph.microsoft.com/.default"
                Client_Id     = $credential.username
                Client_Secret = $credential.GetNetworkCredential().password
            }

            Write-Verbose "Setting TLS 1.2"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

            Write-Verbose "Connecting to $tenantDomainName"
            $connectGraph = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantDomainName/oauth2/v2.0/token" -Method POST -Body $body

            $token = $connectGraph.access_token

            if ($token) {
                if (!$tokenLifeTime) {
                    $tokenLifeTime = 60
                }

                $authHeader = @{
                    ExpiresOn     = (Get-Date).AddMinutes($tokenLifeTime - 10) # shorter by 10 minutes just for sure
                    Authorization = "Bearer $($token)"
                }

                return $authHeader
            } else {
                throw "Unable to obtain token"
            }
        }
    }

    if ($useMSAL) {
        # authenticate using MSAL as a current user

        Write-Verbose "Interactively as an user using MSAL"
        $param = @{
            ClientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e" # 14d82eec-204b-4c2f-b7e8-296a70dab67e for 'Microsoft Graph PowerShell'
        }
        if ($tenantDomainName) { $param.TenantId = $tenantDomainName }
        if ($scope) { $param.scopes = $scope }

        $token = Get-MsalToken @param

        if ($token.AccessToken) {
            $authHeader = @{
                ExpiresOn     = $token.ExpiresOn
                Authorization = "Bearer $($token.AccessToken)"
            }

            return $authHeader
        } else {
            throw "Unable to obtain token"
        }
    } else {
        # get auth. token using the existing session created by the Connect-AzAccount command (from Az.Accounts PowerShell module)

        Write-Verbose "Non-interactively as an user using existing AzureAD session (created using Connect-AzAccount)"

        try {
            # test if connection already exists
            $azConnectionToken = Get-AzAccessToken -AsSecureString -ResourceTypeName MSGraph -ea Stop

            # use AZ connection

            Write-Warning "Creating auth token from existing user ($($azConnectionToken.UserId)) session. If token usage ends with 'forbidden' error, use New-GraphAPIAuthHeader with 'useMSAL' parameter!"

            $authHeader = @{
                ExpiresOn     = $azConnectionToken.ExpiresOn
                Authorization = $azConnectionToken.token
            }

            return $authHeader
        } catch {
            throw "There is no active session to AzureAD. Call this function after Connect-AzAccount or use 'useMSAL' parameter or provide application credentials using 'credential' parameter."
        }
    }
}