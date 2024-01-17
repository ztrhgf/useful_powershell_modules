
#requires -modules Microsoft.Graph.Beta.Applications, Microsoft.Graph.Applications
function Get-AzureEnterpriseApplication {
    <#
    .SYNOPSIS
    Function for getting Azure AD Service Principal(s) \ Enterprise Application(s) as can be seen in Azure web portal.

    .DESCRIPTION
    Function for getting Azure AD Service Principal(s) \ Enterprise Application(s) as can be seen in Azure web portal.

    .PARAMETER objectId
    (optional) objectID(s) of Service Principal(s) \ Enterprise Application(s).

    If not specified, all enterprise applications will be processed.

    .PARAMETER data
    Type of extra data you want to get to the ones returned by Get-AzureServicePrincipal.

    Possible values:
     - owner
        get service principal owner
     - permission
        get delegated (OAuth2PermissionGrants) and application (AppRoleAssignments) permissions
     - users&Groups
        get explicit Users and Groups roles (omits users and groups listed because they gave permission consent)

    By default all these possible values are selected (this can take several minutes!).

    .PARAMETER includeBuiltInApp
    Switch for including also builtin Azure apps.

    .PARAMETER excludeAppWithAppRegistration
    Switch for excluding enterprise app(s) for which exists corresponding app registration.

    .EXAMPLE
    Get-AzureEnterpriseApplication

    Get all data for all AzureAD enterprise applications. Builtin apps are excluded.

    .EXAMPLE
    Get-AzureEnterpriseApplication -excludeAppWithAppRegistration

    Get all data for all AzureAD enterprise applications. Builtin apps and apps for which app registration exists are excluded.

    .EXAMPLE
    Get-AzureEnterpriseApplication -objectId 1234-1234-1234 -data 'owner'

    Get basic + owner data for selected AzureAD enterprise application.

    .NOTES
    TO be able to retrieve security custom attributes, you need to be member of the "Attribute Assignment Reader" group!
    #>

    [CmdletBinding()]
    param (
        [string[]] $objectId,

        [ValidateSet('owner', 'permission', 'users&Groups')]
        [string[]] $data = ('owner', 'permission', 'users&Groups'),

        [switch] $includeBuiltInApp,

        [switch] $excludeAppWithAppRegistration
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): The context is invalid. Please login using Connect-MgGraph."
    }

    # to get custom security attributes
    $servicePrincipalList = $null

    if ($data -contains 'permission' -and !$objectId -and $includeBuiltInApp) {
        # it is much faster to get all SP permissions at once instead of one-by-one processing in foreach (thanks to caching)
        Write-Verbose "Getting granted permission(s)"

        $SPPermission = Get-AzureServicePrincipalPermissions
    }

    if (!$objectId) {
        $param = @{
            Filter = "servicePrincipalType eq 'Application'"
            All    = $true
        }
        if ($data -contains 'owner') {
            $param.ExpandProperty = 'owners'
        }
        $enterpriseApp = Get-MgServicePrincipal @param

        if ($excludeAppWithAppRegistration) {
            $appRegistrationObj = Get-MgApplication -All
            $enterpriseApp = $enterpriseApp | ? AppId -NotIn $appRegistrationObj.AppId
        }

        if (!$includeBuiltInApp) {
            # https://learn.microsoft.com/en-us/troubleshoot/azure/active-directory/verify-first-party-apps-sign-in
            # f8cdef31-a31e-4b4a-93e4-5f571e91255a is the Microsoft Service's Azure AD tenant ID
            # $enterpriseApp = $enterpriseApp | ? AppOwnerOrganizationId -NE "f8cdef31-a31e-4b4a-93e4-5f571e91255a"
            $enterpriseApp = $enterpriseApp | ? tags -Contains 'WindowsAzureActiveDirectoryIntegratedApp'
        }

        $servicePrincipalList = $enterpriseApp
    } else {
        $objectId | % {
            $param = @{
                ServicePrincipalId = $_
            }
            if ($data -contains 'owner') {
                $param.ExpandProperty = 'owners'
            }
            $servicePrincipalList += Get-MgServicePrincipal @param
        }
    }

    $servicePrincipalList | ? { $_ } | % {
        $SPObj = $_

        Write-Verbose "Processing '$($SPObj.DisplayName)' ($($SPObj.Id))"

        # fill CustomSecurityAttributes attribute (easier this way then explicitly specifying SELECT)
        # membership in role "Attribute Assignment Reader" is needed!
        $SPObj.CustomSecurityAttributes = Get-MgBetaServicePrincipal -ServicePrincipalId $SPObj.Id -Select CustomSecurityAttributes | select -ExpandProperty CustomSecurityAttributes #| Expand-MgAdditionalProperties

        if ($data -contains 'owner') {
            $SPObj = $SPObj | select *, @{n = 'Owners'; e = { $SPObj.Owners | Expand-MgAdditionalProperties } } -ExcludeProperty 'Owners'
        }

        if ($data -contains 'permission') {
            Write-Verbose "Getting permission grants"

            if ($SPPermission) {
                $permission = $SPPermission | ? ClientObjectId -EQ $SPObj.Id
            } else {
                $permission = Get-AzureServicePrincipalPermissions -objectId $SPObj.Id
            }

            $SPObj | Add-Member -MemberType NoteProperty -Name Permission_AdminConsent -Value ($permission | ? { $_.ConsentType -eq "AllPrincipals" -or $_.PermissionType -eq 'Application' } | select Permission, ResourceDisplayName, PermissionDisplayName, PermissionType)
            $SPObj | Add-Member -MemberType NoteProperty -Name Permission_UserConsent -Value ($permission | ? { $_.PermissionType -eq 'Delegated' -and $_.ConsentType -ne "AllPrincipals" } | select Permission, ResourceDisplayName, PermissionDisplayName, PrincipalObjectId, PrincipalDisplayName, PermissionType)
        }

        if ($data -contains 'users&Groups') {
            Write-Verbose "Getting users&Groups assignments"

            $SPObj | Add-Member -MemberType NoteProperty UsersAndGroups -Value (Get-AzureServicePrincipalUsersAndGroups -objectId $SPObj.Id | select * -ExcludeProperty AppRoleId, DeletedDateTime, ObjectType, Id, ResourceId, ResourceDisplayName, AdditionalProperties)
        }

        # expired secret?
        $expiredCertificate = $SPObj.PasswordCredentials | ? { $_.EndDate -and ($_.EndDate -le (Get-Date) -and !($SPObj.PasswordCredentials.EndDate -gt (Get-Date))) }
        if ($expiredSecret) {
            $expiredSecret = $true
        } else {
            if ($SPObj.PasswordCredentials) {
                $expiredSecret = $false
            } else {
                $expiredSecret = $null
            }
        }
        $SPObj | Add-Member -MemberType NoteProperty ExpiredSecret -Value $expiredSecret

        # expired certificate?
        $expiredCertificate = $SPObj.KeyCredentials | ? { $_.EndDate -and ($_.EndDate -le (Get-Date) -and !($SPObj.KeyCredentials.EndDate -gt (Get-Date))) }
        if ($expiredCertificate) {
            $expiredCertificate = $true
        } else {
            if ($SPObj.KeyCredentials) {
                $expiredCertificate = $false
            } else {
                $expiredCertificate = $null
            }
        }
        $SPObj | Add-Member -MemberType NoteProperty expiredCertificate -Value $expiredCertificate

        # output
        $SPObj
    }
}