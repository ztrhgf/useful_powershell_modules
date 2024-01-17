#requires -modules Microsoft.Graph.Authentication, Microsoft.Graph.Applications
function Get-AzureAppRegistration {
    <#
    .SYNOPSIS
    Function for getting Azure AD App registration(s) as can be seen in Azure web portal.

    .DESCRIPTION
    Function for getting Azure AD App registration(s) as can be seen in Azure web portal.
    App registrations are global app representations with unique ID across all tenants. Enterprise app is then its local representation for specific tenant.

    .PARAMETER objectId
    (optional) objectID of app registration.

    If not specified, all app registrations will be processed.

    .PARAMETER data
    Type of extra data you want to get.

    Possible values:
     - owner
        get service principal owner
     - permission
        get delegated (OAuth2PermissionGrants) and application (AppRoleAssignments) permissions
     - users&Groups
        get explicit Users and Groups roles (omits users and groups listed because they gave permission consent)

    By default all these possible values are selected (this can take several minutes!).

    .EXAMPLE
    Get-AzureAppRegistration

    Get all data for all AzureAD application registrations.

    .EXAMPLE
    Get-AzureAppRegistration -objectId 1234-1234-1234 -data 'owner'

    Get basic + owner data for selected AzureAD application registration.
    #>

    [CmdletBinding()]
    param (
        [string] $objectId,

        [ValidateSet('owner', 'permission', 'users&Groups')]
        [string[]] $data = ('owner', 'permission', 'users&Groups')
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): The context is invalid. Please login using Connect-MgGraph."
    }

    $param = @{}
    if ($objectId) { $param.ApplicationId = $objectId }
    else { $param.All = $true }
    if ($data -contains 'owner') {
        $param.ExpandProperty = 'Owners'
    }

    Get-MgApplication @param | % {
        $appObj = $_

        $appName = $appObj.DisplayName
        $appID = $appObj.AppId

        Write-Verbose "Processing $appName"

        Write-Verbose "Getting corresponding Service Principal"

        $SPObject = Get-MgServicePrincipal -Filter "AppId eq '$appID'"

        $SPObjectId = $SPObject.Id
        if ($SPObjectId) {
            Write-Verbose " - found service principal (enterprise app) with objectId: $SPObjectId"

            $appObj | Add-Member -MemberType NoteProperty -Name AppRoleAssignmentRequired -Value $SPObject.AppRoleAssignmentRequired
        } else {
            Write-Warning "Registered app '$appName' doesn't have corresponding service principal (enterprise app)"
        }

        if ($data -contains 'owner') {
            $appObj = $appObj | select *, @{n = 'Owners'; e = { $appObj.Owners | Expand-MgAdditionalProperties } } -ExcludeProperty 'Owners'
        }

        if ($data -contains 'permission') {
            Write-Verbose "Getting permission grants"

            if ($SPObjectId) {
                $SPPermission = Get-AzureServicePrincipalPermissions -objectId $SPObjectId
            } else {
                Write-Verbose "Unable to get permissions because corresponding ent. app is missing"
                $SPPermission = $null
            }

            $appObj | Add-Member -MemberType NoteProperty -Name Permission_AdminConsent -Value ($SPPermission | ? { $_.ConsentType -eq "AllPrincipals" -or $_.PermissionType -eq 'Application' } | select Permission, ResourceDisplayName, PermissionDisplayName, PermissionType)
            $appObj | Add-Member -MemberType NoteProperty -Name Permission_UserConsent -Value ($SPPermission | ? { $_.PermissionType -eq 'Delegated' -and $_.ConsentType -ne "AllPrincipals" } | select Permission, ResourceDisplayName, PermissionDisplayName, PrincipalObjectId, PrincipalDisplayName, PermissionType)
        }

        if ($data -contains 'users&Groups') {
            Write-Verbose "Getting users&Groups assignments"

            if ($SPObjectId) {
                $appObj | Add-Member -MemberType NoteProperty -Name UsersAndGroups -Value (Get-AzureServicePrincipalUsersAndGroups -objectId $SPObjectId | select * -ExcludeProperty AppRoleId, DeletedDateTime, ObjectType, Id, ResourceId, ResourceDisplayName, AdditionalProperties)
            } else {
                Write-Verbose "Unable to get role assignments because corresponding ent. app is missing"
            }
        }

        $appObj | Add-Member -MemberType NoteProperty -Name EnterpriseAppId -Value $SPObjectId

        # expired secret?
        $expiredPasswordCredentials = $appObj.PasswordCredentials | ? { $_.EndDate -and ($_.EndDate -le (Get-Date) -and !($appObj.PasswordCredentials.EndDate -gt (Get-Date))) }
        if ($expiredPasswordCredentials) {
            $expiredPasswordCredentials = $true
        } else {
            if ($appObj.PasswordCredentials) {
                $expiredPasswordCredentials = $false
            } else {
                $expiredPasswordCredentials = $null
            }
        }
        $appObj | Add-Member -MemberType NoteProperty -Name ExpiredPasswordCredentials -Value $expiredPasswordCredentials

        # expired certificate?
        $expiredKeyCredentials = $appObj.KeyCredentials | ? { $_.EndDate -and ($_.EndDate -le (Get-Date) -and !($appObj.KeyCredentials.EndDate -gt (Get-Date))) }
        if ($expiredKeyCredentials) {
            $expiredKeyCredentials = $true
        } else {
            if ($appObj.KeyCredentials) {
                $expiredKeyCredentials = $false
            } else {
                $expiredKeyCredentials = $null
            }
        }
        $appObj | Add-Member -MemberType NoteProperty -Name ExpiredKeyCredentials -Value $expiredKeyCredentials
        #endregion add secret(s)

        # output
        $appObj
    }
}