#Requires -Module Pnp.PowerShell
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

    if (!(Get-Module Pnp.PowerShell) -and !(Get-Module Pnp.PowerShell -ListAvailable)) {
        throw "Module Pnp.PowerShell is missing. Function $($MyInvocation.MyCommand) cannot continue"
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