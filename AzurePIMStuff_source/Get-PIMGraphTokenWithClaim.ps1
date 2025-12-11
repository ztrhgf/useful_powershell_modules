function Get-PIMGraphTokenWithClaim {
    <#
    .SYNOPSIS
    Retrieves an MS Graph access token with specific claims and scopes suitable for activating PIM roles using interactive authentication.

    .DESCRIPTION
    This function acquires an OAuth2 access token for Microsoft Graph.
    It is specifically designed to handle 'claims' challenges, which are often required for Privileged Identity Management (PIM) role activation (step-up authentication).
    The function leverages the 'Microsoft.Identity.Client.dll' found in the 'Az.Accounts' module.

    .PARAMETER TenantId
    The Azure Active Directory Tenant ID. Defaults to the global variable '$_tenantId'.

    .PARAMETER Scope
    An array of permission scopes to request.

    'RoleAssignmentSchedule.ReadWrite.Directory' as permission needed to activate the PIM role is automatically added if not present.

    .PARAMETER Claim
    A JSON string containing the claims challenge required for the token.

    This is typically obtained from the 'WWW-Authenticate' header of a failed request or in ErrorDetails.Message property of error returned by Invoke-MgGraphRequest.

    .PARAMETER AsString
    If specified, returns the access token as a plain string. By default, it returns a SecureString.

    .EXAMPLE
    # acrs == Authentication context
    # c1 == id of the authentication context defined in Azure Conditional Access policies
    $claim = '{"access_token":{"acrs":{"essential":true, "value":"c1"}}}'
    $secureToken = Get-PIMGraphTokenWithClaim -Claim $claim

    # Re-connect Graph SDK using the Strong Token
    Connect-MgGraph -AccessToken $secureToken -NoWelcome

    .NOTES
    https://learn.microsoft.com/en-us/entra/identity-platform/developer-guide-conditional-access-authentication-context

    - Requires the 'Az.Accounts' module to be installed.
    - Performs interactive authentication (pop-up window).
    #>

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string] $tenantId = $_tenantId,

        [string[]] $scope,

        [Parameter(Mandatory = $true)]
        [string] $claim,

        [switch] $asString
    )

    if (!$tenantId) {
        throw "$($MyInvocation.MyCommand): TenantId is required."
    }

    if (!($claim | ConvertFrom-Json -ErrorAction SilentlyContinue -OutVariable jsonObj)) {
        throw "$($MyInvocation.MyCommand): Claim is not a valid JSON string."
    }

    if ("RoleAssignmentSchedule.ReadWrite.Directory" -notin $scope) {
        $scope += "RoleAssignmentSchedule.ReadWrite.Directory"
    }

    # Load Microsoft.Identity.Client.dll Assembly ([Microsoft.Identity.Client.PublicClientApplicationBuilder] type) from Az.Accounts module
    if (!("Microsoft.Identity.Client.PublicClientApplicationBuilder" -as [Type])) {
        # to avoid dll conflicts try loaded modules first
        $modulePath = (Get-Module Az.Accounts | Sort-Object Version -Descending | Select-Object -First 1).ModuleBase

        if (!$modulePath) {
            $modulePath = (Get-Module Az.Accounts -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).ModuleBase
        }
        if ($modulePath) {
            $dllPath = Get-ChildItem -Path $modulePath -Filter "Microsoft.Identity.Client.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($dllPath) {
                Add-Type -Path $dllPath.FullName
            } else {
                throw "Microsoft.Identity.Client.dll not found in Az.Accounts module."
            }
        } else {
            throw "No Az.Accounts module found. Please install the Az PowerShell module."
        }
    }

    # Build Public Client App
    $clientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e" # Microsoft Graph PowerShell Client ID
    $pca = [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($clientId).WithAuthority("https://login.microsoftonline.com/$tenantId").WithRedirectUri("http://localhost").Build()

    # Create Interactive Request
    $request = $pca.AcquireTokenInteractive($scope)

    $request = $request.WithClaims($claim)

    # Execute and return Token
    $token = $request.ExecuteAsync().GetAwaiter().GetResult().AccessToken

    if (!$token) {
        throw "$($MyInvocation.MyCommand): Failed to acquire token with claims."
    }

    if ($asString) {
        $token
    } else {
        ConvertTo-SecureString $token -AsPlainText -Force
    }
}