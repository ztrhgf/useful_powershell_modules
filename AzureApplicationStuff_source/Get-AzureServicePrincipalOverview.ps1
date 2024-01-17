#requires -modules Microsoft.Graph.Authentication, Microsoft.Graph.Applications
function Get-AzureServicePrincipalOverview {
    <#
    .SYNOPSIS
    Function for getting overall information for AzureAD Service principal(s).

    .DESCRIPTION
    Function for getting overall information for AzureAD Service principal(s).

    Basic information gathered using Get-MgServicePrincipal command will be enriched with new properties partly by based on values in 'data' parameter.

    .PARAMETER objectId
    (optional) objectId of the service principal you want information for.

    .PARAMETER data
    Type of extra data you want to get.

    Possible values:
     - owner
        get service principal owner
        - output is saved in property: Owner
     - permission
        get delegated permissions (OAuth2PermissionGrants) and application permissions (AppRoleAssignments)
        - output is saved in properties: Permission_AdminConsent, Permission_UserConsent
     - users&Groups
        get explicit Users and Groups roles (omits users and groups listed because they gave permission consent)
        - output is saved in property: UsersAndGroups
     - lastUsed
        get last date this service principal was used according the audit logs
        - output is saved in property: lastUsed

    By default all these possible values are selected (this can take dozens of minutes!).

    .PARAMETER credential
    Credentials for AzureAD authentication.

    .PARAMETER header
    Header for authentication of graph calls.
    Use if calling Get-AzureServicePrincipalOverview several times in short time period. Otherwise you will end with error: We couldn't sign you in.
    Header object can be created via New-GraphAPIAuthHeader function.

    .EXAMPLE
    Get-AzureServicePrincipalOverview

    Get all data for all service principals.

    .EXAMPLE
    Get-AzureServicePrincipalOverview -objectId 1234-1234-1234 -data 'owner', 'permission'

    Get basic service principal data plus owner and permissions for SP with given objectId.

    .NOTES
    Nice similar solution https://github.com/michevnew/PowerShell/blob/master/app_Permissions_inventory_GraphAPI.ps1
    #>

    [CmdletBinding()]
    param (
        [string] $objectId,

        [ValidateSet('owner', 'permission', 'users&Groups', 'lastUsed')]
        [string[]] $data = ('owner', 'permission', 'users&Groups', 'lastUsed'),

        [System.Management.Automation.PSCredential] $credential,

        $header
    )

    #region authenticate
    if ($credential) {
        Connect-AzAccount2 -credential $credential -ErrorAction Stop
        Connect-MgGraphViaCred -credential $credential -ErrorAction Stop
    } else {
        Connect-AzAccount2 -ErrorAction Stop
        $null = Connect-MgGraph -ErrorAction Stop
    }
    if (!$header) {
        $header = New-GraphAPIAuthHeader -ErrorAction Stop
    }
    #endregion authenticate

    if ($data -contains 'permission') {
        # it is much faster to get all SP permissions at once instead of one-by-one processing in foreach (thanks to caching)
        Write-Verbose "Getting granted permission(s)"

        $param = @{ ErrorAction = 'Continue' }
        if ($objectId) { $param.objectId = $objectId }

        $SPPermission = Get-AzureServicePrincipalPermissions @param
    }

    $param = @{}
    if ($objectId) { $param.ServicePrincipalId = $objectId }
    else { $param.All = $true }

    Get-MgServicePrincipal @param | % {
        $SP = $_

        $SPName = $SP.AppDisplayName
        if (!$SPName) { $SPName = $SP.DisplayName }
        Write-Warning "Processing '$SPName' ($($SP.AppId))"

        if ($data -contains 'owner') {
            Write-Verbose "Getting owner"
            $SP = $SP | select *, @{n = 'Owner'; e = { Get-MgServicePrincipalOwner -ServicePrincipalId $_.Id -All | Expand-MgAdditionalProperties } }
        }

        if ($data -contains 'permission') {
            $permission = $SPPermission | ? ClientObjectId -EQ $SP.Id

            $SP = $SP | select *, @{n = 'Permission_AdminConsent'; e = { $permission | ? { $_.ConsentType -eq "AllPrincipals" -or $_.PermissionType -eq 'Application' } | select Permission, ResourceDisplayName, PermissionDisplayName, PermissionType } }
            $SP = $SP | select *, @{n = 'Permission_UserConsent'; e = { $permission | ? { $_.PermissionType -eq 'Delegated' -and $_.ConsentType -ne "AllPrincipals" } | select Permission, ResourceDisplayName, PermissionDisplayName, PrincipalObjectId, PrincipalDisplayName, PermissionType } }
        }

        if ($data -contains 'users&Groups') {
            Write-Verbose "Getting explicitly assigned users and groups"
            # show just explicitly added members, not added via granting consent
            $consentPrincipalId = @($SP.Permission_AdminConsent.PrincipalObjectId) + @($SP.Permission_UserConsent.PrincipalObjectId)
            $SP = $SP | select *, @{n = 'UsersAndGroups'; e = { Get-AzureServicePrincipalUsersAndGroups -objectId $SP.Id | select CreatedDateTime, PrincipalDisplayName, PrincipalId, PrincipalType | ? PrincipalId -NotIn $consentPrincipalId } }
        }

        #region check secrets
        $sResult = @()
        $cResult = @()

        #region process secret(s)
        $secret = $SP.PasswordCredentials
        $cert = $SP.KeyCredentials

        foreach ($s in $secret) {
            $startDate = $s.StartDate
            $endDate = $s.EndDate

            $sResult += [PSCustomObject]@{
                StartDate = $startDate
                EndDate   = $endDate
            }
        }

        foreach ($c in $cert) {
            $startDate = $c.StartDate
            $endDate = $c.EndDate

            $cResult += [PSCustomObject]@{
                StartDate = $startDate
                EndDate   = $endDate
            }
        }
        #endregion process secret(s)

        # expired secret
        $expiredSecret = $sResult | ? { $_.EndDate -and ($_.EndDate -le (Get-Date) -and !($_.EndDate -gt (Get-Date))) }
        if ($expiredSecret) {
            $expiredSecret = $true
        } else {
            if ($sResult) {
                $expiredSecret = $false
            } else {
                $expiredSecret = $null
            }
        }
        # $SP = $SP | Add-Member -MemberType NoteProperty -Name ExpiredSecret -Value $expiredSecret
        $SP = $SP | select *, @{n = 'ExpiredSecret'; e = { $expiredSecret } }

        # expired certificate
        $expiredCertificate = $cResult | ? { $_.EndDate -and ($_.EndDate -le (Get-Date) -and !($_.EndDate -gt (Get-Date))) }
        if ($expiredCertificate) {
            $expiredCertificate = $true
        } else {
            if ($cResult) {
                $expiredCertificate = $false
            } else {
                $expiredCertificate = $null
            }
        }
        # $SP = $SP | Add-Member -MemberType NoteProperty -Name ExpiredCertificate -Value $expiredCertificate
        $SP = $SP | select *, @{n = 'ExpiredCertificate'; e = { $expiredCertificate } }
        #endregion check secrets

        if ($data -contains 'lastUsed') {
            Write-Verbose "Getting last used date"
            # Get-AzureADAuditSignInLogs has problems with throttling 'Too Many Requests', Invoke-GraphAPIRequest has builtin fix for that
            $signInResult = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/auditLogs/signIns?api-version=beta&`$filter=(appId eq '$($SP.AppId)')&`$top=1&`$orderby=createdDateTime desc" -header $header
            if ($signInResult.count -ge 1) {
                $SP = $SP | select *, @{n = 'LastUsed'; e = { $signInResult.CreatedDateTime } }
            } else {
                $SP = $SP | select *, @{n = 'LastUsed'; e = { $null } }
            }
        }

        #output
        $SP
    }
}