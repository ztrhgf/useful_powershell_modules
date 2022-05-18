function Get-AzureADEnterpriseApplication {
    <#
    .SYNOPSIS
    Function for getting Azure AD Service Principal(s) \ Enterprise Application(s) as can be seen in Azure web portal.

    .DESCRIPTION
    Function for getting Azure AD Service Principal(s) \ Enterprise Application(s) as can be seen in Azure web portal.

    .PARAMETER objectId
    (optional) objectID(s) of Service Principal(s) \ Enterprise Application(s).

    If not specified, all enterprise applications will be processed.

    .PARAMETER data
    Type of extra data you want to get to the ones returned by Get-AzureADServicePrincipal.

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
    Get-AzureADEnterpriseApplication

    Get all data for all AzureAD enterprise applications. Builtin apps are excluded.

    .EXAMPLE
    Get-AzureADEnterpriseApplication -excludeAppWithAppRegistration

    Get all data for all AzureAD enterprise applications. Builtin apps and apps for which app registration exists are excluded.

    .EXAMPLE
    Get-AzureADEnterpriseApplication -objectId 1234-1234-1234 -data 'owner'

    Get basic + owner data for selected AzureAD enterprise application.
    #>

    [CmdletBinding()]
    [Alias("Get-AzureADServicePrincipal2")]
    param (
        [string[]] $objectId,

        [ValidateSet('owner', 'permission', 'users&Groups')]
        [string[]] $data = ('owner', 'permission', 'users&Groups'),

        [switch] $includeBuiltInApp,

        [switch] $excludeAppWithAppRegistration
    )

    try {
        # test if connection already exists
        $null = Get-AzureADCurrentSessionInfo -ea Stop
    } catch {
        throw "You must call the Connect-AzureAD cmdlet before calling any other cmdlets."
    }

    $servicePrincipalList = $null

    if ($data -contains 'permission' -and !$objectId) {
        # it is much faster to get all SP permissions at once instead of one-by-one processing in foreach (thanks to caching)
        Write-Verbose "Getting granted permission(s)"

        $SPPermission = Get-AzureADSPPermissions -ErrorAction 'Continue'
    }

    if (!$objectId) {
        $enterpriseApp = Get-AzureADServicePrincipal -Filter "servicePrincipalType eq 'Application'" -All:$true

        if ($excludeAppWithAppRegistration) {
            $appRegistrationObj = Get-AzureADApplication -All:$true
            $enterpriseApp = $enterpriseApp | ? AppId -NotIn $appRegistrationObj.AppId
        }

        if (!$includeBuiltInApp) {
            $enterpriseApp = $enterpriseApp | ? tags -Contains 'WindowsAzureActiveDirectoryIntegratedApp'
        }

        $servicePrincipalList = $enterpriseApp
    } else {
        $objectId | % {
            $servicePrincipalList += Get-AzureADServicePrincipal -ObjectId $_
        }
    }

    $servicePrincipalList | ? { $_ } | % {
        $SPObj = $_

        Write-Verbose "Processing '$($SPObj.DisplayName)' ($($SPObj.ObjectId))"

        if ($data -contains 'owner') {
            Write-Verbose "Getting owner"

            $ownerResult = Get-AzureADServicePrincipalOwner -ObjectId $SPObj.ObjectId -All:$true | % {
                if ($_.UserPrincipalName) {
                    $name = $_.UserPrincipalName
                } elseif (!$_.UserPrincipalName -and $_.DisplayName) {
                    $name = $_.DisplayName + " **<This is an Application>**"
                } else {
                    $name = ""
                }

                $_ | select @{name = 'Name'; expression = { $name } }, ObjectId, ObjectType, AccountEnabled
            }

            $SPObj | Add-Member -MemberType NoteProperty -Name Owner -Value $ownerResult
        }

        if ($data -contains 'permission') {
            Write-Verbose "Getting permission grants"

            if ($SPPermission) {
                $permission = $SPPermission | ? ClientObjectId -EQ $SPObj.ObjectId
            } else {
                $permission = Get-AzureADSPPermissions -objectId $SPObj.ObjectId
            }

            $SPObj | Add-Member -MemberType NoteProperty -Name Permission_AdminConsent -Value ($permission | ? { $_.ConsentType -eq "AllPrincipals" -or $_.PermissionType -eq 'Application' } | select Permission, ResourceDisplayName, PermissionDisplayName, PermissionType)
            $SPObj | Add-Member -MemberType NoteProperty -Name Permission_UserConsent -Value ($permission | ? { $_.PermissionType -eq 'Delegated' -and $_.ConsentType -ne "AllPrincipals" } | select Permission, ResourceDisplayName, PermissionDisplayName, PrincipalObjectId, PrincipalDisplayName, PermissionType)
        }

        if ($data -contains 'users&Groups') {
            Write-Verbose "Getting users&Groups assignments"

            $SPObj | Add-Member -MemberType NoteProperty UsersAndGroups -Value (Get-AzureADAppUsersAndGroups -objectId $SPObj.ObjectId | select * -ExcludeProperty ObjectId, DeletionTimestamp, ObjectType, Id, ResourceId, ResourceDisplayName)
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