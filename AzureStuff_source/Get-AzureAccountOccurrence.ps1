#Requires -Module Microsoft.Graph.Authentication, Microsoft.Graph.Applications, Microsoft.Graph.DeviceManagement.Enrollment, Microsoft.Graph.DirectoryObjects, Microsoft.Graph.Users, Microsoft.Graph.Identity.SignIns, Microsoft.Graph.Identity.Governance
#Requires -Module Az.Accounts
#Requires -Module Pnp.PowerShell
#Requires -Module MSAL.PS
#Requires -Module ExchangeOnlineManagement
function Get-AzureAccountOccurrence {
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
    'KeyVaultAccessPolicy' - KeyVault access policies grants
    'ExchangeRole' - Exchange Admin Roles

    Based on the object type you are searching occurrences for, this can be automatically trimmed. Because for example device cannot be manager etc.

    .PARAMETER tenantId
    Name of the tenant if different then the default one should be used.

    .EXAMPLE
    Get-AzureAccountOccurrence -objectId 1234-1234-1234

    Search for all occurrences of the account with id 1234-1234-1234.

    .EXAMPLE
    Get-AzureAccountOccurrence -objectId 1234-1234-1234 -data UserConsent, Manager

    Search just for user perm. consents which searched account has given and accounts where searched account is manager of.

    .EXAMPLE
    Get-AzureAccountOccurrence -userPrincipalName novak@contoso.com

    Search for all occurrences of the account with UPN novak@contoso.com.

    .NOTES
    In case of 'data' parameter edit, don't forget to modify _getAllowedSearchType and Remove-AzureAccountOccurrence functions too
    #>

    [CmdletBinding()]
    [Alias("Get-AzureADAccountOccurrence")]
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

        [ValidateScript( {
                $StringGuid = $_
                $ObjectGuid = [System.Guid]::empty
                if ([System.Guid]::TryParse($StringGuid, [System.Management.Automation.PSReference]$ObjectGuid)) {
                    $true
                } else {
                    throw "$_ is not a valid GUID"
                }
            })]
        [string[]] $objectId,

        [ValidateSet('IAM', 'GroupMembership', 'DirectoryRoleMembership', 'UserConsent', 'Manager', 'Owner', 'SharepointSiteOwner', 'Users&GroupsRoleAssignment', 'DevOps', 'KeyVaultAccessPolicy', 'ExchangeRole')]
        [ValidateNotNullOrEmpty()]
        [string[]] $data = @('IAM', 'GroupMembership', 'DirectoryRoleMembership', 'UserConsent', 'Manager', 'Owner', 'SharepointSiteOwner', 'Users&GroupsRoleAssignment', 'DevOps', 'KeyVaultAccessPolicy', 'ExchangeRole'),

        [string] $tenantId
    )

    if (!$userPrincipalName -and !$objectId) {
        throw "You haven't specified userPrincipalname nor objectId parameter"
    }

    if ($tenantId) {
        $tenantIdParam = @{
            tenantId = $tenantId
        }
    } else {
        $tenantIdParam = @{}
    }

    #region connect
    # connect to AzureAD
    $null = Connect-MgGraph -ea Stop
    $null = Connect-AzAccount2 @tenantIdParam -ea Stop

    # create Graph API auth. header
    Write-Verbose "Creating Graph API auth header"
    $graphAuthHeader = New-GraphAPIAuthHeader @tenantIdParam -ea Stop

    # connect sharepoint online
    if ($data -contains 'SharepointSiteOwner') {
        Write-Verbose "Connecting to Sharepoint"
        Connect-PnPOnline2 -asMFAUser -ea Stop
    }

    if ($data -contains 'ExchangeRole') {
        Write-Verbose "Connecting to Exchange"
        Connect-O365 -service exchange -ea Stop
    }
    #endregion connect

    # translate UPN to ObjectId
    if ($userPrincipalName) {
        $userPrincipalName | % {
            $UPN = $_

            $AADUserobj = Get-MgUser -Filter "userPrincipalName eq '$UPN'"
            if (!$AADUserobj) {
                Write-Error "Account $UPN was not found in AAD"
            } else {
                Write-Verbose "Translating $UPN to $($AADUserobj.Id) Id"
                $objectId += $AADUserobj.Id
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

            'KeyVaultAccessPolicy' {
                $allowedObjType = 'user', 'group', 'servicePrincipal'
            }

            'ExchangeRole' {
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
            Invoke-WebRequest -Uri $_ -Method get -ContentType "application/json" -Headers $devOpsAuthHeader | select -exp content | ConvertFrom-Json | select -exp value | select -exp containerDescriptor | % {
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
    #TODO cache only in case some allowed account type for such data is searched
    if ('IAM' -in $data) {
        Write-Warning "Caching AzureAD Role Assignments. This can take several minutes!"
        $azureADRoleAssignments = Get-AzureRoleAssignments @tenantIdParam
    }
    if ('SharepointSiteOwner' -in $data) {
        Write-Warning "Caching Sharepoint sites ownership. This can take several minutes!"
        $sharepointSiteOwner = Get-SharepointSiteOwner
    }

    if ('DevOps' -in $data) {
        Write-Warning "Caching DevOps organizations."
        $devOpsOrganization = Get-AzureDevOpsOrganizationOverview @tenantIdParam

        #TODO poresit strankovani!
        Write-Warning "Caching DevOps organizations groups."
        $devOpsAuthHeader = New-AzureDevOpsAuthHeader
        $devOpsOrganization | % {
            $organizationName = $_.OrganizationName
            Write-Verbose "Getting groups for DevOps organization $organizationName"
            $groups = $null # in case of error this wouldn't be nulled
            try {
                $groups = Invoke-WebRequest -Uri "https://vssps.dev.azure.com/$organizationName/_apis/graph/groups?api-version=7.1-preview.1" -Method get -ContentType "application/json" -Headers $devOpsAuthHeader -ea Stop | select -exp content | ConvertFrom-Json | select -exp value
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
        $devOpsAuthHeader = New-AzureDevOpsAuthHeader
        $devOpsOrganization | % {
            $organizationName = $_.OrganizationName
            Write-Verbose "Getting users for DevOps organization $organizationName"
            $users = $null # in case of error this wouldn't be nulled
            try {
                $users = Invoke-WebRequest -Uri "https://vssps.dev.azure.com/$organizationName/_apis/graph/users?api-version=7.1-preview.1" -Method get -ContentType "application/json" -Headers $devOpsAuthHeader -ea Stop | select -exp content | ConvertFrom-Json | select -exp value
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

    if ('KeyVaultAccessPolicy' -in $data) {
        Write-Warning "Caching KeyVault Access Policies. This can take several minutes!"
        $keyVaultList = @()
        $CurrentContext = Get-AzContext
        $Subscriptions = Get-AzSubscription -TenantId $CurrentContext.Tenant.Id
        foreach ($Subscription in ($Subscriptions | Sort-Object Name)) {
            Write-Verbose "Changing to Subscription $($Subscription.Name) ($($Subscription.SubscriptionId))"

            $Context = Set-AzContext -TenantId $Subscription.TenantId -SubscriptionId $Subscription.Id -Force

            Get-AzKeyVault -WarningAction SilentlyContinue | % {
                $keyVaultList += Get-AzKeyVault -VaultName $_.VaultName -WarningAction SilentlyContinue
            }
        }
    }

    if ('ExchangeRole' -in $data) {
        Write-Warning "Caching Exchange roles."
        $exchangeRoleAssignments = @()

        Get-RoleGroup | % {
            $roleName = $_.name
            $roleDN = $_.displayname
            $roleCapabilities = $_.capabilities

            $exchangeRoleAssignments += Get-RoleGroupMember -Identity $roleName -ResultSize unlimited | select @{n = 'Role'; e = { $roleName } }, @{name = 'RoleDisplayName'; e = { $roleDN } }, @{n = 'RoleCapabilities'; e = { $roleCapabilities } }, *
        }
    }
    #endregion pre-cache data

    # object types that are allowed for searching
    $allowedObjectType = 'user', 'group', 'servicePrincipal', 'device'

    foreach ($id in $objectId) {
        $AADAccountObj = Get-MgDirectoryObjectById -Ids $id | Expand-MgAdditionalProperties
        if (!$AADAccountObj) {
            Write-Error "Account $id was not found in AAD"
            continue
        }

        # progress variables
        $i = 0
        $progressActivity = "Account '$($AADAccountObj.displayName)' ($id) occurrences"

        $objectType = $AADAccountObj.ObjectType

        if ($objectType -notin $allowedObjectType) {
            Write-Warning "Skipping '$($AADAccountObj.displayName)' ($id) because it is disallowed object type ($objectType)"
            continue
        } else {
            Write-Warning "Processing '$($AADAccountObj.displayName)' ($id)"
        }

        # define base object
        $result = [PSCustomObject]@{
            UPN                             = $AADAccountObj.userPrincipalName
            DisplayName                     = $AADAccountObj.displayName
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
            KeyVaultAccessPolicy            = @()
            ExchangeRole                    = @()
        }

        #region get AAD account occurrences
        #region Exchange Role assignments
        if ('ExchangeRole' -in $data -and (_getAllowedSearchType 'ExchangeRole')) {
            Write-Verbose "Getting Exchange role assignments"
            Write-Progress -Activity $progressActivity -Status "Getting Exchange role assignments" -PercentComplete (($i++ / $data.Count) * 100)

            $result.ExchangeRole = @($exchangeRoleAssignments | ? ExternalDirectoryObjectId -EQ $id)
        }
        #endregion Exchange Role assignments

        #region KeyVault Access Policy
        if ('KeyVaultAccessPolicy' -in $data -and (_getAllowedSearchType 'KeyVaultAccessPolicy')) {
            Write-Verbose "Getting KeyVault Access Policy assignments"
            Write-Progress -Activity $progressActivity -Status "Getting KeyVault Access Policy assignments" -PercentComplete (($i++ / $data.Count) * 100)

            $keyVaultList | % {
                $keyVault = $_
                $accessPolicies = $keyVault.AccessPolicies | ? { $_.objectId -eq $id }

                if ($accessPolicies) {
                    $result.KeyVaultAccessPolicy += $keyVault | select *, @{n = 'AccessPolicies'; e = { $accessPolicies } } -ExcludeProperty AccessPolicies, AccessPoliciesText
                }
            }
        }
        #endregion KeyVault Access Policy

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

            Get-MgRoleManagementDirectoryRoleAssignment -Filter "principalId eq '$id'" | % {
                $_ | Add-Member -Name 'RoleName' -MemberType NoteProperty -Value (Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $_.RoleDefinitionId | select -ExpandProperty DisplayName)
                $result.MemberOfDirectoryRole += $_
            }
        }
        #endregion DirectoryRoleMembership

        #region Group membership
        if ('GroupMembership' -in $data -and (_getAllowedSearchType 'GroupMembership')) {
            Write-Verbose "Getting Group memberships"
            Write-Progress -Activity $progressActivity -Status "Getting Group memberships" -PercentComplete (($i++ / $data.Count) * 100)

            # reauthenticate just in case previous steps took too much time and the token has expired in the meantime
            if (!$graphAuthHeader -or ($graphAuthHeader -and $graphAuthHeader.ExpiresOn -le [datetime]::Now)) {
                Write-Verbose "Creating new auth token, just in case it expired"
                $graphAuthHeader = New-GraphAPIAuthHeader @tenantIdParam -ea Stop
            }

            switch ($objectType) {
                'user' { $searchLocation = "users" }
                'group' { $searchLocation = "groups" }
                'device' { $searchLocation = "devices" }
                'servicePrincipal' { $searchLocation = "servicePrincipals" }
                default { throw "Undefined object type '$objectType'" }
            }

            Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/v1.0/$searchLocation/$id/memberOf" -header $graphAuthHeader | ? { $_ } | % {
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

            Get-MgUserOauth2PermissionGrant -UserId $id -All | % {
                $result.PermissionConsent += $_ | select *, @{name = 'AppName'; expression = { (Get-MgServicePrincipal -ServicePrincipalId $_.ClientId).DisplayName } }, @{name = 'ResourceDisplayName'; expression = { (Get-MgServicePrincipal -ServicePrincipalId $_.ResourceId).DisplayName } }
            }
        }
        #endregion user perm consents

        #region is manager
        if ('Manager' -in $data -and (_getAllowedSearchType 'Manager')) {
            Write-Verbose "Getting Direct report"
            Write-Verbose "Just Cloud based objects are outputted"
            Write-Progress -Activity $progressActivity -Status "Getting Direct Report (managedBy)" -PercentComplete (($i++ / $data.Count) * 100)

            # TODO nevraci DirSyncedEnabled
            Get-MgUserDirectReport -UserId $id -All | Expand-MgAdditionalProperties | % {
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
                    Get-MgUserOwnedObject -UserId $id -All | Expand-MgAdditionalProperties | % {
                        $result.Owner += $_
                    }

                    Write-Verbose "Getting device(s) ownership"
                    Get-MgUserOwnedDevice -UserId $id -All | Expand-MgAdditionalProperties | % {
                        $result.Owner += $_
                    }
                }

                'servicePrincipal' {
                    Get-MgServicePrincipalOwnedObject -ServicePrincipalId $id -All | Expand-MgAdditionalProperties | % {
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
            $sharepointSiteOwner | ? { ($userPrincipalName -and $_.Owner -contains $userPrincipalName) -or ($AADAccountObj.displayName -and $_.Owner -contains $AADAccountObj.displayName) } | % {
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
                    Get-MgServicePrincipal -ServicePrincipalId $objectId -Property AppRoles | select -ExpandProperty AppRoles | ? id -EQ $roleId | select -ExpandProperty DisplayName
                }
            }

            switch ($objectType) {
                'user' {
                    # filter out assignments based on group membership
                    Get-MgUserAppRoleAssignment -UserId $id -All | ? PrincipalDisplayName -EQ $AADAccountObj.displayName | select *, @{name = 'AppRoleDisplayName'; expression = { GetRoleName -objectId $_.ResourceId -roleId $_.AppRoleId } } | % {
                        $result.AppUsersAndGroupsRoleAssignment += $_
                    }
                }

                'group' {

                    Get-MgGroupAppRoleAssignment -GroupId $id -All | select *, @{name = 'AppRoleDisplayName'; expression = { GetRoleName -objectId $_.ResourceId -roleId $_.AppRoleId } } | % {
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

            $devOpsAuthHeader = New-AzureDevOpsAuthHeader # auth. token has just minutes lifetime!
            $devOpsOrganization | % {
                $organization = $_
                $organizationName = $organization.OrganizationName
                $organizationOwner = $organization.Owner

                if ($organizationOwner -eq $AADAccountObj.userPrincipalName -or $organizationOwner -eq $AADAccountObj.displayName) {
                    $result.DevOpsOrganizationOwner += $organization
                }

                if ($objectType -eq 'user') {
                    $userInOrg = $organization.users | ? originId -EQ $AADAccountObj.Id

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
                    $groupInOrg = $organization.groups | ? originId -EQ $AADAccountObj.Id

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
            }
        }
        #endregion devops

        #endregion get AAD account occurrences

        Write-Progress -Completed -Activity $progressActivity

        $result
    }
}