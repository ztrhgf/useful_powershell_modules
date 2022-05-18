function Get-AzureADAppRegistration {
    <#
    .SYNOPSIS
    Function for getting Azure AD App registration(s) as can be seen in Azure web portal.

    .DESCRIPTION
    Function for getting Azure AD App registration(s) as can be seen in Azure web portal.
    App registrations are global app representations with unique ID across all tenants. Enterprise app is then its local representation for specific tenant.

    .PARAMETER objectId
    (optional) objectID of app registration.

    If not specified, all app registrations will be processed.

    .PARAMETER credential
    Credentials for connecting to AzureAD.

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
    Get-AzureADAppRegistration

    Get all data for all AzureAD application registrations.

    .EXAMPLE
    Get-AzureADAppRegistration -objectId 1234-1234-1234 -data 'owner'

    Get basic + owner data for selected AzureAD application registration.
    #>

    [CmdletBinding()]
    param (
        [string] $objectId,

        [System.Management.Automation.PSCredential] $credential,

        [ValidateSet('owner', 'permission', 'users&Groups')]
        [string[]] $data = ('owner', 'permission', 'users&Groups')
    )

    if ($credential) {
        Connect-AzureAD2 -ErrorAction Stop -credential $credential
    } else {
        Connect-AzureAD2 -ErrorAction Stop
    }

    $param = @{}
    if ($objectId) { $param.objectId = $objectId }
    else { $param.all = $true }

    Get-AzureADApplication @param | % {
        $appObj = $_

        $appName = $appObj.DisplayName
        $appID = $appObj.AppId

        Write-Warning "Processing $appName"

        Write-Verbose "Getting corresponding Service Principal"
        $SPObject = Get-AzureADServicePrincipal -Filter "AppId eq '$appID'"
        $SPObjectId = $SPObject.ObjectId
        if ($SPObjectId) {
            Write-Verbose " - found service principal (enterprise app) with objectId: $SPObjectId"

            $appObj | Add-Member -MemberType NoteProperty -Name AppRoleAssignmentRequired -Value $SPObject.AppRoleAssignmentRequired
        } else {
            Write-Error "Registered app '$appName' doesn't have corresponding service principal (enterprise app). This shouldn't happen"
        }

        if ($data -contains 'owner') {
            Write-Verbose "Getting owner"

            $ownerResult = Get-AzureADApplicationOwner -ObjectId $appObj.ObjectId -All:$true | % {
                if ($_.UserPrincipalName) {
                    $name = $_.UserPrincipalName
                } elseif (!$_.UserPrincipalName -and $_.DisplayName) {
                    $name = $_.DisplayName + " **<This is an Application>**"
                } else {
                    $name = ""
                }

                $_ | select @{name = 'Name'; expression = { $name } }, ObjectId, ObjectType, AccountEnabled
            }

            $appObj | Add-Member -MemberType NoteProperty -Name Owner -Value $ownerResult
        }

        if ($data -contains 'permission') {
            Write-Verbose "Getting permission grants"

            if ($SPObjectId) {
                $SPPermission = Get-AzureADSPPermissions -objectId $SPObjectId
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
                $appObj | Add-Member -MemberType NoteProperty -Name UsersAndGroups -Value (Get-AzureADAppUsersAndGroups -objectId $SPObjectId | select * -ExcludeProperty ObjectId, DeletionTimestamp, ObjectType, Id, ResourceId, ResourceDisplayName)
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