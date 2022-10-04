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

    .PARAMETER useADAL
    Switch for using ADAL for auth. token creation.
    Can solve problem with 'forbidden' errors when default token creation method is used, but can be used only under user accounts.

    .EXAMPLE
    $header = New-GraphAPIAuthHeader -credential $cred
    $URI = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/'
    $managedDevices = (Invoke-RestMethod -Headers $header -Uri $URI -Method Get).value

    .EXAMPLE
    (there is existing AzureAD session already (made via Connect-AzureAD))
    $header = New-GraphAPIAuthHeader -reuseExistingAzureADSession
    $URI = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/'
    $managedDevices = (Invoke-RestMethod -Headers $header -Uri $URI -Method Get).value

    .EXAMPLE
    (there is existing AzureAD session already (made via Connect-AzureAD))
    $header = New-GraphAPIAuthHeader -reuseExistingAzureADSession -useADAL
    $URI = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/'
    $managedDevices = (Invoke-RestMethod -Headers $header -Uri $URI -Method Get).value

    Use ADAL for auth. token creation. Can help if default method leads to 'forbidden' errors when token is used.

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
        [Alias("tenantId")]
        $tenantDomainName = $_tenantDomain,

        [ValidateSet('auto', 'always', 'never')]
        [string] $showDialogType = 'never',

        [Parameter(ParameterSetName = "reuseSession")]
        [switch] $useADAL
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

            if ($useADAL) {
                # https://github.com/microsoftgraph/powershell-intune-samples/blob/master/ManagedDevices/Win10_PrimaryUser_Set.ps1
                $context = [Microsoft.Open.Azure.AD.CommonLibrary.AzureRmProfileProvider]::Instance.Profile.Context
                $upn = $context.account.id
                Write-Verbose "Connecting using $upn"
                $tenant = (New-Object "System.Net.Mail.MailAddress" -ArgumentList $upn).Host

                Write-Verbose "Checking for AzureAD module..."
                $AadModule = Get-Module -Name "AzureAD" -ListAvailable

                if ($AadModule -eq $null) {
                    Write-Verbose "AzureAD PowerShell module not found, looking for AzureADPreview"
                    $AadModule = Get-Module -Name "AzureADPreview" -ListAvailable
                }

                if ($AadModule -eq $null) {
                    throw "AzureAD Powershell module not installed...Install by running 'Install-Module AzureAD' or 'Install-Module AzureADPreview' from an elevated PowerShell prompt"
                }

                # Getting path to ActiveDirectory Assemblies
                # If the module count is greater than 1 find the latest version
                if ($AadModule.count -gt 1) {
                    $Latest_Version = ($AadModule | select version | Sort-Object)[-1]

                    $aadModule = $AadModule | ? { $_.version -eq $Latest_Version.version }

                    # Checking if there are multiple versions of the same module found
                    if ($AadModule.count -gt 1) {
                        $aadModule = $AadModule | select -Unique
                    }

                    $adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
                    $adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"
                } else {
                    $adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
                    $adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"
                }

                [System.Reflection.Assembly]::LoadFrom($adal) | Out-Null
                [System.Reflection.Assembly]::LoadFrom($adalforms) | Out-Null
                $clientId = "d1ddf0e4-d672-4dae-b554-9d5bdfd93547"
                $redirectUri = "urn:ietf:wg:oauth:2.0:oob"
                $resourceAppIdURI = "https://graph.microsoft.com"
                $authority = "https://login.microsoftonline.com/$Tenant"

                $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority

                # https://msdn.microsoft.com/en-us/library/azure/microsoft.identitymodel.clients.activedirectory.promptbehavior.aspx
                # Change the prompt behaviour to force credentials each time: Auto, Always, Never, RefreshSession
                $platformParameters = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters" -ArgumentList $showDialogType

                $userId = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.UserIdentifier" -ArgumentList ($upn, "OptionalDisplayableId")

                $authResult = $authContext.AcquireTokenAsync($resourceAppIdURI, $clientId, $redirectUri, $platformParameters, $userId).Result

                # If the accesstoken is valid then create the authentication header
                if ($authResult.AccessToken) {
                    # Creating header for Authorization token
                    $authHeader = @{
                        'Authorization' = "Bearer " + $authResult.AccessToken
                        'ExpiresOn'     = $authResult.ExpiresOn
                    }

                    return $authHeader
                } else {
                    throw "Authorization Access Token is null, please re-run authentication..."
                }
            } else {
                # don't use ADAL

                # tento zpusob nekdy nefugnuje (dostavam forbidden)
                $context = [Microsoft.Open.Azure.AD.CommonLibrary.AzureRmProfileProvider]::Instance.Profile.Context
                $authenticationFactory = [Microsoft.Open.Azure.AD.CommonLibrary.AzureSession]::AuthenticationFactory
                $msGraphEndpointResourceId = "MsGraphEndpointResourceId"
                $msGraphEndpoint = $context.Environment.Endpoints[$msGraphEndpointResourceId]
                $auth = $authenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id.ToString(), $null, [Microsoft.Open.Azure.AD.CommonLibrary.ShowDialog]::$showDialogType, $null, $msGraphEndpointResourceId)

                $token = $auth.AuthorizeRequest($msGraphEndpointResourceId)

                $authHeader = @{
                    Authorization = $token
                }

                return $authHeader
            }
        } catch {
            throw "Unable to obtain auth. token:`n`n$($_.exception.message)`n`n$($_.invocationInfo.PositionMessage)`n`nTry change the showDialogType parameter?"
        }
    } else {
        # authenticate to obtain the token
        $body = @{
            Grant_Type    = "client_credentials"
            Scope         = "https://graph.microsoft.com/.default"
            Client_Id     = $credential.username
            Client_Secret = $credential.GetNetworkCredential().password
        }

        Write-Verbose "Connecting to $tenantDomainName"
        $connectGraph = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantDomainName/oauth2/v2.0/token" -Method POST -Body $body

        $token = $connectGraph.access_token

        if ($token) {
            $authHeader = @{
                Authorization = "Bearer $($token)"
            }

            return $authHeader
        } else {
            throw "Unable to obtain token"
        }
    }
}