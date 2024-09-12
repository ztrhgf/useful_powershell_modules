function Connect-AzAccount2 {
    <#
    .SYNOPSIS
    Function for connecting to Azure using Connect-AzAccount command (Az.Accounts module).

    .DESCRIPTION
    Function for connecting to Azure using Connect-AzAccount command (Az.Accounts module).
    In case there is already existing valid connection, no new will be created.

    .PARAMETER credential
    Credentials (User or App) for connecting to Azure.
    For App credentials tenantId must be set too!

    .PARAMETER applicationId
    ID of the service principal that will be used for connection.

    .PARAMETER certificateThumbprint
    Thumbprint of the locally stored certificate that will be used for connection.
    Certificate has to be placed in personal machine store and user running this function has to have permission to read its private key.

    .PARAMETER servicePrincipal
    Switch for using App/Service Principal authentication instead of User auth.

    .PARAMETER tenantId
    Azure tenant ID.
    Mandatory when App authentication is used.

    .EXAMPLE
    Connect-AzAccount2

    Authenticate to Azure interactively using user credentials. Doesn't work for accounts with MFA!

    .EXAMPLE
    $credential = get-credential
    Connect-AzAccount2 -credential $credential

    Authenticate to Azure using given user credentials. Doesn't work for accounts with MFA!

    .EXAMPLE
    $credential = get-credential
    Connect-AzAccount2 -servicePrincipal -credential $credential -tenantId 1234-1234-1234

    Authenticate to Azure using given app credentials (service principal).

    .EXAMPLE
    $thumbprint = Get-ChildItem Cert:\LocalMachine\My | ? subject -EQ "CN=contoso.onmicrosoft.com" | select -ExpandProperty Thumbprint
    $null = Connect-AzAccount2 -ApplicationId 'cd2ae428-35f9-41b4-a527-71f2f8f1e5cf' -CertificateThumbprint $thumbprint -ServicePrincipal

    Authenticate using certificate.

    .NOTES
    Requires module Az.Accounts.
    #>

    [CmdletBinding()]
    param (
        [System.Management.Automation.PSCredential] $credential,

        [string] $applicationId,

        [string] $certificateThumbprint,

        [switch] $servicePrincipal,

        [string] $tenantId = $_tenantId
    )

    #region checks
    $azAccesstoken = Get-AzAccessToken -AsSecureString -ErrorAction SilentlyContinue

    #region check whether there is valid existing session
    $tenantIsDomainName = $false
    $correctTenant = $false

    if ($azAccesstoken -and $azAccesstoken.ExpiresOn -gt [datetime]::now) {
        if ($tenantId -like "*.*") {
            $tenantIsDomainName = $true
        }
        if (($tenantIsDomainName -and $azAccesstoken.UserId -like "*@$tenantId") -or (!$tenantIsDomainName -and $azAccesstoken.TenantId -eq $tenantId)) {
            $correctTenant = $true
        }
    }
    #endregion check whether there is valid existing session

    #region check whether there is valid existing session created via required account
    $userId = $null
    $correctAccount = $false

    if ($azAccesstoken -and ($applicationId -or $credential) -and ($azAccesstoken.UserId -eq $applicationId -or $azAccesstoken.UserId -eq $credential.UserName)) {
        # there is an existing token that uses required account already
        $correctAccount = $true
    }
    if ($azAccesstoken -and !$applicationId -and !$credential) {
        # there is an existing token that can be used, because no explicit credentials were specified
        $correctAccount = $true
    }
    #endregion check whether there is valid existing session created via required account
    #endregion checks

    if ($azAccesstoken -and $correctTenant -and $correctAccount) {
        Write-Verbose "Already connected to the Azure using $($azAccesstoken.UserId)"
        return
    } else {
        if ($servicePrincipal -and !$tenantId) {
            throw "When servicePrincipal auth is used tenantId has to be set"
        }

        $param = @{}
        if ($servicePrincipal) { $param.servicePrincipal = $true }
        if ($tenantId) { $param.tenantId = $tenantId }
        if ($credential) { $param.credential = $credential }
        if ($applicationId) { $param.applicationId = $applicationId }
        if ($certificateThumbprint) { $param.certificateThumbprint = $certificateThumbprint }

        Connect-AzAccount @param
    }
}

function Connect-PnPOnline2 {
    <#
    .SYNOPSIS
    Proxy function for Connect-PnPOnline with some enhancements like: automatic MFA auth if MFA detected, skipping authentication if already authenticated etc.

    .DESCRIPTION
    Proxy function for Connect-PnPOnline with some enhancements like: automatic MFA auth if MFA detected, skipping authentication if already authenticated etc.

    .PARAMETER credential
    Credential object you want to use to authenticate to Sharepoint Online

    .PARAMETER appAuth
    Switch for using application authentication instead of the user one.

    .PARAMETER asMFAUser
    Switch for using user with MFA enabled authentication (i.e. interactive auth)

    .PARAMETER useWebLogin
    Switch for using WebLogin instead of Interactive authentication.

    - weblogin auth
        Legacy cookie based authentication. Notice this type of authentication is limited in its functionality. We will for instance not be able to acquire an access token for the Graph, and as a result none of the Graph related cmdlets will work. Also some of the functionality of the provisioning engine (Get-PnPSiteTemplate, Get-PnPTenantTemplate, Invoke-PnPSiteTemplate, Invoke-PnPTenantTemplate) will not work because of this reason. The cookies will in general expire within a few days and if you use -UseWebLogin within that time popup window will appear that will disappear immediately, this is expected. Use -ForceAuthentication to reset the authentication cookies and force a new login.

    - interactive auth
        Connects to the Azure AD, acquires an access token and allows PnP PowerShell to access both SharePoint and the Microsoft Graph. By default it will use the PnP Management Shell multi-tenant application behind the scenes, so make sure to run `Register-PnPManagementShellAccess` first.

    .PARAMETER url
    Your sharepoint online url ("https://contoso-admin.sharepoint.com")

    .EXAMPLE
    Connect-PnPOnline2

    Connect to Sharepoint Online using user interactive authentication.

    .EXAMPLE
    Connect-PnPOnline2 -asMFAUser

    Connect to Sharepoint Online using (MFA-enabled) user interactive authentication.

    .EXAMPLE
    Connect-PnPOnline2 -appAuth

    Connect to Sharepoint Online using application interactive authentication.

    .EXAMPLE
    Connect-PnPOnline2 -appAuth -credential $cred

    Connect to Sharepoint Online using application non-interactive authentication.

    .EXAMPLE
    Connect-PnPOnline2 -credential $cred

    Connect to Sharepoint Online using (non-MFA enabled!) user non-interactive authentication.

    .NOTES
    Requires Pnp.PowerShell module.
    #>

    [CmdletBinding()]
    param (
        [System.Management.Automation.PSCredential] $credential,

        [switch] $appAuth,

        [switch] $asMFAUser,

        [switch] $useWebLogin,

        [ValidateNotNullOrEmpty()]
        [string] $url = $_SPOConnectionUri
    )

    if (!$url) {
        throw "Parameter 'url' cannot be empty."
    }

    if ($appAuth -and $asMFAUser) {
        Write-Warning "asMFAUser switch cannot be used with appAuth. Ignoring asMFAUser."
        $asMFAUser = $false
    }

    if ($credential -and $asMFAUser) {
        Write-Warning "When logging using MFA-enabled user, credentials cannot be passed i.e. it has to be interactive login"
        $credential = $null
    }

    try {
        $existingConnection = Get-PnPConnection -ea Stop
    } catch {
        Write-Verbose "There isn't any PNP connection"
    }

    if (!$existingConnection -or !($existingConnection | ? { $_.URL -like "$url*" }) -or ($useWebLogin -and $existingConnection.ConnectionType -ne "O365") -or (!$useWebLogin -and $existingConnection.ConnectionType -ne "TenantAdmin")) {
        Write-Verbose "Connecting to Sharepoint"
        if ($credential -and !$appAuth) {
            try {
                Connect-PnPOnline -Url $url -Credentials $credential -ea Stop
            } catch {
                if ($_ -match "you must use multi-factor authentication to access") {
                    Write-Error "Account $($credential.UserName) has MFA enabled, therefore interactive logon is needed"
                    Connect-PnPOnline -Url $url -Interactive -ForceAuthentication
                } else {
                    throw $_
                }
            }
        } elseif ($credential -and $appAuth) {
            Connect-PnPOnline -Url $url -ClientId $credential.UserName -ClientSecret $credential.GetNetworkCredential().password
        } else {
            # credential is missing
            if ($asMFAUser) {
                if ($useWebLogin) {
                    # weblogin acquires ACS generated token, which will not work for things like exporting the site header and footer as it won't be able to acquire an access token for Graph
                    Connect-PnPOnline -Url $url -UseWebLogin -ForceAuthentication
                } else {
                    # interactive uses PnP Management Shell Azure app registration to connect as delegated permissions
                    Connect-PnPOnline -Url $url -Interactive -ForceAuthentication
                }
            } elseif ($appAuth) {
                $credential = Get-Credential -Message "Using App auth. Enter ClientId and ClientSecret."
                Connect-PnPOnline -Url $url -ClientId $credential.UserName -ClientSecret $credential.GetNetworkCredential().password
            } else {
                Connect-PnPOnline -Url $url
            }
        }
    } else {
        Write-Verbose "Already connected to Sharepoint"
    }
}

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

function Start-AzureSync {
    <#
        .SYNOPSIS
        Invoke Azure AD sync cycle command (Start-ADSyncSyncCycle) on the server where 'Azure AD Connect' is installed.

        .DESCRIPTION
        Invoke Azure AD sync cycle command (Start-ADSyncSyncCycle) on the server where 'Azure AD Connect' is installed.

        .PARAMETER Type
        Type of sync.

        Initial (full) or just delta.

        Delta is default.

        .PARAMETER ADSynchServer
        Name of the server where 'Azure AD Connect' is installed

        .EXAMPLE
        Start-AzureSync -ADSynchServer ADSYNCSERVER
        Invokes synchronization between on-premises AD and AzureAD on server ADSYNCSERVER by running command Start-ADSyncSyncCycle there.
    #>

    [Alias("Sync-ADtoAzure", "Start-AzureADSync")]
    [cmdletbinding()]
    param (
        [ValidateSet('delta', 'initial')]
        [string] $type = 'delta',

        [ValidateNotNullOrEmpty()]
        [string] $ADSynchServer
    )

    $ErrState = $false
    do {
        try {
            Invoke-Command -ScriptBlock { Start-ADSyncSyncCycle -PolicyType $using:type } -ComputerName $ADSynchServer -ErrorAction Stop | Out-Null
            $ErrState = $false
        } catch {
            $ErrState = $true
            Write-Warning "Start-AzureSync: Error in Sync:`n$_`nRetrying..."
            Start-Sleep 5
        }
    } while ($ErrState -eq $true)
}

Export-ModuleMember -function Connect-AzAccount2, Connect-PnPOnline2, New-AzureDevOpsAuthHeader, Start-AzureSync

Export-ModuleMember -alias Start-AzureADSync, Sync-ADtoAzure
