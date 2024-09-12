#Requires -Module Az.Accounts
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