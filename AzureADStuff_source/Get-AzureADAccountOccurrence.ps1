#Requires -Module AzureAD
#Requires -Module Az.Accounts
#Requires -Module Pnp.PowerShell
#Requires -Module MSAL.PS
function Get-AzureADAccountOccurrence {
    <#
    .SYNOPSIS
    Function for getting AzureAD account occurrences through various parts of Azure.

    Only Azure based objects are scanned (not dir-synced ones).

    .DESCRIPTION
    Function for getting AzureAD account occurrences through various parts of AzureAD.

    Only Azure based objects are scanned (not dir-synced ones).

    You can search occurrences of 'user', 'group', 'servicePrincipal', 'device' objects.

    These Azure parts are searched by default: 'IAM', 'GroupMembership', 'DirectoryRoleMembership', 'UserConsent', 'Manager', 'Owner', 'SharepointSiteOwner', 'Users&GroupsRoleAssignment'

    .PARAMETER userPrincipalName
    UPN of the user you want to search occurrences for.

    .PARAMETER objectId
    ObjectId of the 'user', 'group', 'servicePrincipal' or 'device' you want to search occurrences for.

    .PARAMETER data
    Array of Azure parts you want to search in.

    By default:
    'IAM' - IAM assignments of the root, subscriptions, management groups, resource groups, resources where searched account is assigned
    'GroupMembership' - groups where searched account is a member
    'DirectoryRoleMembership' - directory roles where searched account is a member
    'UserConsent' - user granted consents
    'Manager' - accounts where searched user is manager
    'Owner' - accounts where searched user is owner
    'SharepointSiteOwner' - sharepoint sites where searched account is owner
    'Users&GroupsRoleAssignment' - applications Users and groups tab where searched account is assigned
    'DevOps' - occurrences in DevOps organizations

    Based on the object type you are searching occurrences for, this can be automatically trimmed. Because for example device cannot be manager etc.

    .EXAMPLE
    Get-AzureADAccountOccurrence -objectId 1234-1234-1234

    Search for all occurrences of the account with id 1234-1234-1234.

    .EXAMPLE
    Get-AzureADAccountOccurrence -objectId 1234-1234-1234 -data UserConsent, Manager

    Search just for user perm. consents which searched account has given and accounts where searched account is manager of.

    .EXAMPLE
    Get-AzureADAccountOccurrence -userPrincipalName novak@contoso.com

    Search for all occurrences of the account with UPN novak@contoso.com.

    .NOTES
    In case of 'data' parameter edit, don't forget to modify _getAllowedSearchType and Remove-AzureADAccountOccurrence functions too
    #>

    [CmdletBinding()]
    param (
        [ValidateNotNullOrEmpty()]
        [ValidateScript( {
                If ($_ -notmatch "@") {
                    throw "Username isn't UPN"
                } else {
                    $true
                }
            })]
        [string[]] $userPrincipalName,

        [string[]] $objectId,

        [ValidateSet('IAM', 'GroupMembership', 'DirectoryRoleMembership', 'UserConsent', 'Manager', 'Owner', 'SharepointSiteOwner', 'Users&GroupsRoleAssignment', 'DevOps')]
        [ValidateNotNullOrEmpty()]
        [string[]] $data = @('IAM', 'GroupMembership', 'DirectoryRoleMembership', 'UserConsent', 'Manager', 'Owner', 'SharepointSiteOwner', 'Users&GroupsRoleAssignment', 'DevOps')
    )

    if (!$userPrincipalName -and !$objectId) {
        throw "You haven't specified userPrincipalname nor objectId parameter"
    }

    #region connect
    # connect to AzureAD
    Write-Verbose "Connecting to Azure for use with cmdlets from the AzureAD PowerShell modules"
    $null = Connect-AzureAD2 -asYourself -ea Stop

    Write-Verbose "Connecting to Azure for use with cmdlets from the Az PowerShell modules"
    $null = Connect-AzAccount2 -ea Stop

    # connect Graph API
    Write-Verbose "Creating Graph API auth header"
    $header = New-GraphAPIAuthHeader -reuseExistingAzureADSession -showDialogType auto -ea Stop

    # connect sharepoint online
    if ($data -contains 'SharepointSiteOwner') {
        Write-Verbose "Connecting to Sharepoint"
        Connect-PnPOnline2 -asMFAUser -ea Stop
    }
    #endregion connect

    # translate UPN to ObjectId
    if ($userPrincipalName) {
        $userPrincipalName | % {
            $UPN = $_

            $AADUserobj = Get-AzureADUser -Filter "userprincipalname eq '$UPN'"
            if (!$AADUserobj) {
                Write-Error "Account $UPN was not found in AAD"
            } else {
                Write-Verbose "Translating $UPN to $($AADUserobj.ObjectId) ObjectId"
                $objectId += $AADUserobj.ObjectId
            }
        }
    }

    #region helper functions
    # function for deciding what kind of data make sense to search through when you have object of specific kind
    function _getAllowedSearchType {
        param ($searchedData)

        switch ($searchedData) {
            'IAM' {
                $allowedObjType = 'user', 'group', 'servicePrincipal'
            }

            'GroupMembership' {
                $allowedObjType = 'user', 'group', 'servicePrincipal', 'device'
            }

            'DirectoryRoleMembership' {
                $allowedObjType = 'user', 'group', 'servicePrincipal'
            }

            'UserConsent' {
                $allowedObjType = 'user'
            }

            'Manager' {
                $allowedObjType = 'user'
            }

            'Owner' {
                $allowedObjType = 'user', 'servicePrincipal'
            }

            'SharepointSiteOwner' {
                $allowedObjType = 'user'
            }

            'Users&GroupsRoleAssignment' {
                $allowedObjType = 'user', 'group'
            }

            'DevOps' {
                $allowedObjType = 'user', 'group'
            }

            default { throw "Undefined data to search $searchedData (edit _getAllowedSearchType function)" }
        }

        if ($objectType -in $allowedObjType) {
            return $true
        } else {
            Write-Warning "Skipping '$searchedData' data search because object of type $objectType cannot be there"

            return $false
        }
    }

    # function for translating DevOps membership hrefs to actual groups
    function _getMembership {
        param ([string[]] $membershipHref, [string] $organizationName)

        $membershipHref | % {
            Invoke-WebRequest -Uri $_ -Method get -ContentType "application/json" -Headers $header | select -exp content | ConvertFrom-Json | select -exp value | select -exp containerDescriptor | % {
                $groupOrg = $devOpsOrganization | ? { $_.OrganizationName -eq $organizationName }
                $group = $groupOrg.groups | ? descriptor -EQ $_
                if ($group) {
                    $group
                } else {
                    Write-Error "Group with descriptor $_ wasn't found"
                    [PSCustomObject]@{
                        ContainerDescriptor = $_
                    }
                }
            }
        }
    }
    #endregion helper functions

    #region pre-cache data
    if ('IAM' -in $data) {
        Write-Warning "Caching AzureAD Role Assignments. This can take several minutes!"
        $azureADRoleAssignments = Get-AzureADRoleAssignments
    }
    if ('SharepointSiteOwner' -in $data) {
        Write-Warning "Caching Sharepoint sites ownership. This can take several minutes!"
        $sharepointSiteOwner = Get-SharepointSiteOwner
    }

    if ('DevOps' -in $data) {
        Write-Warning "Caching DevOps organizations."
        $devOpsOrganization = Get-AzureDevOpsOrganizationOverview

        #TODO poresit strankovani!
        Write-Warning "Caching DevOps organizations groups."
        $header = New-AzureDevOpsAuthHeader
        $devOpsOrganization | % {
            $organizationName = $_.OrganizationName
            Write-Verbose "Getting groups for DevOps organization $organizationName"
            $groups = $null # in case of error this wouldn't be nulled
            try {
                $groups = Invoke-WebRequest -Uri "https://vssps.dev.azure.com/$organizationName/_apis/graph/groups?api-version=7.1-preview.1" -Method get -ContentType "application/json" -Headers $header -ea Stop | select -exp content | ConvertFrom-Json | select -exp value
            } catch {
                if ($_ -match "is not authorized to access this resource|UnauthorizedRequestException") {
                    Write-Warning "You don't have rights to get groups data for DevOps organization $organizationName."
                } else {
                    Write-Error $_
                }
            }

            $_ | Add-Member -MemberType NoteProperty -Name Groups -Value $groups
        }

        #TODO poresit strankovani!
        Write-Warning "Caching DevOps organizations users."
        $header = New-AzureDevOpsAuthHeader
        $devOpsOrganization | % {
            $organizationName = $_.OrganizationName
            Write-Verbose "Getting users for DevOps organization $organizationName"
            $users = $null # in case of error this wouldn't be nulled
            try {
                $users = Invoke-WebRequest -Uri "https://vssps.dev.azure.com/$organizationName/_apis/graph/users?api-version=7.1-preview.1" -Method get -ContentType "application/json" -Headers $header -ea Stop | select -exp content | ConvertFrom-Json | select -exp value
            } catch {
                if ($_ -match "is not authorized to access this resource|UnauthorizedRequestException") {
                    Write-Warning "You don't have rights to get users data for DevOps organization $organizationName."
                } else {
                    Write-Error $_
                }
            }

            $_ | Add-Member -MemberType NoteProperty -Name Users -Value $users
        }
    }
    #endregion pre-cache data

    # object types that are allowed for searching
    $allowedObjectType = 'user', 'group', 'servicePrincipal', 'device'

    foreach ($id in $objectId) {
        $AADAccountObj = Get-AzureADObjectByObjectId -ObjectId $id
        if (!$AADAccountObj) {
            Write-Error "Account $id was not found in AAD"
        }

        # progress variables
        $i = 0
        $progressActivity = "Account '$($AADAccountObj.DisplayName)' ($id) occurrences"

        $objectType = $AADAccountObj.ObjectType

        if ($objectType -notin $allowedObjectType) {
            Write-Warning "Skipping '$($AADAccountObj.DisplayName)' ($id) because it is disallowed object type ($objectType)"
            continue
        } else {
            Write-Warning "Processing '$($AADAccountObj.DisplayName)' ($id)"
        }

        # define base object
        $result = [PSCustomObject]@{
            UPN                             = $AADAccountObj.UserPrincipalName
            DisplayName                     = $AADAccountObj.DisplayName
            ObjectType                      = $objectType
            ObjectId                        = $id
            IAM                             = @()
            MemberOfDirectoryRole           = @()
            MemberOfGroup                   = @()
            Manager                         = @()
            PermissionConsent               = @()
            Owner                           = @()
            SharepointSiteOwner             = @()
            AppUsersAndGroupsRoleAssignment = @()
            DevOpsOrganizationOwner         = @()
            DevOpsMemberOf                  = @()
        }

        #region get AAD account occurrences

        #region IAM
        if ('IAM' -in $data -and (_getAllowedSearchType 'IAM')) {
            Write-Verbose "Getting IAM assignments"
            Write-Progress -Activity $progressActivity -Status "Getting IAM assignments" -PercentComplete (($i++ / $data.Count) * 100)

            $azureADRoleAssignments | ? objectId -EQ $id | % {
                $result.IAM += $_
            }
        }
        #endregion IAM

        #region DirectoryRoleMembership
        if ('DirectoryRoleMembership' -in $data -and (_getAllowedSearchType 'DirectoryRoleMembership')) {
            Write-Verbose "Getting Directory Role Membership assignments"
            Write-Progress -Activity $progressActivity -Status "Getting Directory Role Membership assignments" -PercentComplete (($i++ / $data.Count) * 100)

            Get-AzureADMSRoleAssignment -Filter "principalId eq '$id'" | % {
                $_ | Add-Member -Name RoleName -MemberType NoteProperty -Value (Get-AzureADMSRoleDefinition -Id $_.roleDefinitionId | select -ExpandProperty DisplayName)
                $result.MemberOfDirectoryRole += $_
            }
        }
        #endregion DirectoryRoleMembership

        #region Group membership
        if ('GroupMembership' -in $data -and (_getAllowedSearchType 'GroupMembership')) {
            Write-Verbose "Getting Group memberships"
            Write-Progress -Activity $progressActivity -Status "Getting Group memberships" -PercentComplete (($i++ / $data.Count) * 100)

            # reauthenticate just in case previous steps took too much time and the token has expired in the meantime
            Write-Verbose "Creating new auth token, just in case it expired"
            $header = New-GraphAPIAuthHeader -reuseExistingAzureADSession -showDialogType auto -ea Stop

            Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/v1.0/users/$id/transitiveMemberOf" -header $header | ? { $_ } | % {
                if ($_.'@odata.type' -eq '#microsoft.graph.directoryRole') {
                    # directory roles are added in different IF, moreover this query doesn't return custom roles
                } elseif ($_.'@odata.context') {
                    # not a member
                } else {
                    $result.MemberOfGroup += $_
                }
            }
        }
        #endregion Group membership

        #region user perm consents
        if ('UserConsent' -in $data -and (_getAllowedSearchType 'UserConsent')) {
            Write-Verbose "Getting permission consents"
            Write-Progress -Activity $progressActivity -Status "Getting permission consents" -PercentComplete (($i++ / $data.Count) * 100)

            Get-AzureADUserOAuth2PermissionGrant -ObjectId $id -All:$true | % {
                $result.PermissionConsent += $_ | select *, @{name = 'AppName'; expression = { (Get-AzureADServicePrincipal -ObjectId $_.ClientId).DisplayName } }, @{name = 'ResourceDisplayName'; expression = { (Get-AzureADServicePrincipal -ObjectId $_.ResourceId).DisplayName } }
            }
        }
        #endregion user perm consents

        #region is manager
        if ('Manager' -in $data -and (_getAllowedSearchType 'Manager')) {
            Write-Verbose "Getting Direct report"
            Write-Verbose "Just Cloud based objects are outputted"
            Write-Progress -Activity $progressActivity -Status "Getting Direct Report (managedBy)" -PercentComplete (($i++ / $data.Count) * 100)

            Get-AzureADUserDirectReport -ObjectId $id | ? DirSyncEnabled -NE 'True' | % {
                $result.Manager += $_
            }
        }
        #endregion is manager

        #region is owner
        # group, ent. app, app reg. and device ownership
        if ('Owner' -in $data -and (_getAllowedSearchType 'Owner')) {
            Write-Verbose "Getting application, group etc ownership"
            Write-Progress -Activity $progressActivity -Status "Getting group, app and device ownership" -PercentComplete (($i++ / $data.Count) * 100)
            switch ($objectType) {
                'user' {
                    Get-AzureADUserOwnedObject -ObjectId $id | % {
                        $result.Owner += $_
                    }

                    Write-Verbose "Getting device(s) ownership"
                    Get-AzureADUserOwnedDevice -ObjectId $id | % {
                        $result.Owner += $_
                    }
                }

                'servicePrincipal' {
                    Get-AzureADServicePrincipalOwnedObject -ObjectId $id | % {
                        $result.Owner += $_
                    }
                }

                default {
                    throw "Undefined condition for $objectType objectType when searching for 'Owner'"
                }
            }
        }

        #sharepoint sites owner
        if ('SharepointSiteOwner' -in $data -and (_getAllowedSearchType 'SharepointSiteOwner')) {
            Write-Verbose "Getting Sharepoint sites ownership"
            Write-Progress -Activity $progressActivity -Status "Getting Sharepoint sites ownership" -PercentComplete (($i++ / $data.Count) * 100)
            $sharepointSiteOwner | ? { $_.Owner -contains $userPrincipalName -or $_.Owner -contains $AADAccountObj.DisplayName } | % {
                $result.SharepointSiteOwner += $_
            }
        }
        #endregion is owner

        #region App Users and groups role assignments
        if ('Users&GroupsRoleAssignment' -in $data -and (_getAllowedSearchType 'Users&GroupsRoleAssignment')) {
            Write-Verbose "Getting applications 'Users and groups' role assignments"
            Write-Progress -Activity $progressActivity -Status "Getting applications 'Users and groups' role assignments" -PercentComplete (($i++ / $data.Count) * 100)

            function GetRoleName {
                param ($objectId, $roleId)
                if ($roleId -eq '00000000-0000-0000-0000-000000000000') {
                    return 'default'
                } else {
                    Get-AzureADServicePrincipal -ObjectId $objectId | select -ExpandProperty AppRoles | ? id -EQ $roleId | select -ExpandProperty DisplayName
                }
            }

            switch ($objectType) {
                'user' {
                    # filter out assignments based on group membership
                    Get-AzureADUserAppRoleAssignment -ObjectId $id -All:$true | ? PrincipalDisplayName -EQ $AADAccountObj.DisplayName | select *, @{name = 'AppRoleDisplayName'; expression = { GetRoleName -objectId $_.ResourceId -roleId $_.Id } } | % {
                        $result.AppUsersAndGroupsRoleAssignment += $_
                    }
                }

                'group' {
                    Get-AzureADGroupAppRoleAssignment -ObjectId $id -All:$true | select *, @{name = 'AppRoleDisplayName'; expression = { GetRoleName -objectId $_.ResourceId -roleId $_.Id } } | % {
                        $result.AppUsersAndGroupsRoleAssignment += $_
                    }
                }

                default {
                    throw "Undefined condition for $objectType objectType when searching for 'Users&GroupsRoleAssignment'"
                }
            }
        }
        #endregion App Users and groups role assignments

        #region devops
        # https://docs.microsoft.com/en-us/rest/api/azure/devops/
        if ('DevOps' -in $data -and (_getAllowedSearchType 'DevOps')) {
            Write-Verbose "Getting DevOps occurrences"
            Write-Progress -Activity $progressActivity -Status "Getting DevOps occurrences" -PercentComplete (($i++ / $data.Count) * 100)

            $header = New-AzureDevOpsAuthHeader # auth. token has just minutes lifetime!
            $devOpsOrganization | % {
                $organization = $_
                $organizationName = $organization.OrganizationName
                $organizationOwner = $organization.Owner

                if ($organizationOwner -eq $AADAccountObj.UserPrincipalName -or $organizationOwner -eq $AADAccountObj.DisplayName) {
                    $result.DevOpsOrganizationOwner += $organization
                }

                if ($objectType -eq 'user') {
                    $userInOrg = $organization.users | ? originId -EQ $AADAccountObj.ObjectId

                    if ($userInOrg) {
                        # user is used in this DevOps organization
                        $memberOf = _getMembership $userInOrg._links.memberships.href $organizationName
                        $result.DevOpsMemberOf += [PSCustomObject]@{
                            OrganizationName = $organizationName
                            MemberOf         = $memberOf
                            Descriptor       = $userInOrg.descriptor
                        }
                    } else {
                        # try to find it as an orphaned guest (has special principalname)
                        $orphanGuestUserInOrg = $organization.users | ? { $_.displayName -EQ $AADAccountObj.displayName -and $_.directoryAlias -Match "#EXT#$" -and $_.principalName -Match "OIDCONFLICT_UpnReuse_" }
                        if ($orphanGuestUserInOrg) {
                            Write-Warning "$($AADAccountObj.displayName) guest user is used in DevOps organization '$organizationName' but it is orphaned record (guest user was assigned to this organization than deleted and than invited again with the same UPN"
                        }
                    }
                } elseif ($objectType -eq 'group') {
                    $groupInOrg = $organization.groups | ? originId -EQ $AADAccountObj.ObjectId

                    if ($groupInOrg) {
                        # group is used in this DevOps organization
                        $memberOf = _getMembership $groupInOrg._links.memberships.href $organizationName
                        $result.DevOpsMemberOf += [PSCustomObject]@{
                            OrganizationName = $organizationName
                            MemberOf         = $memberOf
                            Descriptor       = $groupInOrg.descriptor
                        }
                    }
                } else {
                    throw "Undefined object type $objectType"
                }

                # # uzivatele vcetne clenstvi ve skupinach
                # Invoke-WebRequest -Uri "https://vssps.dev.azure.com/ondrejs4/_apis/identities?searchFilter=General&filterValue=$UPN&queryMembership=Direct&api-version=7.1-preview.1" -Method get -ContentType "application/json" -Headers $header | select -exp content | ConvertFrom-Json | select -exp value
                # # skupiny a urovne pristupu (ale jen to nejake orezane, jen 3 skupiny)
                # Invoke-WebRequest -Uri "https://vsaex.dev.azure.com/ondrejs4/_apis/userentitlementsummary" -Method get -ContentType "application/json" -Headers $h | select -exp content | ConvertFrom-Json
                # # ziskani podrobnych user dat vcetne lastlogin atd dle zadaneho ID uzivatele (ale projectEntitlements zase neukazuje vse)
                # Invoke-WebRequest -Uri "https://vsaex.dev.azure.com/ondrejs4/_apis/userentitlements/24cc0ecb-fd00-6302-b3a9-03cf4a0cb8ad" -Method get -ContentType "application/json" -Headers $h | select -exp content | ConvertFrom-Json
            }
        }
        #endregion devops

        #endregion get AAD account occurrences

        Write-Progress -Completed -Activity $progressActivity

        $result
    }
}