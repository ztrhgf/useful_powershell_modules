function Add-AzureAppUserConsent {
    <#
    .SYNOPSIS
    Function for granting consent on behalf of a user to chosen application over selected resource(s) (enterprise app(s)) and permission(s) and assign the user default app role to be able to see the app in his 'My Apps'.

    .DESCRIPTION
    Function for granting consent on behalf of a user to chosen application over selected resource(s) (enterprise app(s)) and permission(s) and assign the user default app role to be able to see the app in his 'My Apps'.

    Consent can be explicitly specified or copied from some existing one.

    .PARAMETER clientAppId
    ID of application you want to grant consent on behalf of a user.

    .PARAMETER consent
    Hashtable where:
    - key is objectId of the resource (enterprise app) you are granting permissions to
    - value is list of permissions strings (scopes)

    Both can be found at Permissions tab of the enterprise app in Azure portal, when you select particular permission.

    For example:
    $consent = @{
        "02ad85cd-02ce-4902-a349-1af61152a021" = "User.Read", "Contacts.ReadWrite", "Calendars.ReadWrite", "Mail.Send", "Mail.ReadWrite", "EWS.AccessAsUser.All"
    }

    .PARAMETER copyExistingConsent
    Switch for getting consent details (resource ObjectId and permissions) from existing user consent.
    You will be asked for confirmation before proceeding.

    .PARAMETER userUpnOrId
    User UPN or ID.

    .EXAMPLE
    $consent = @{
        "88690023-f9e1-4728-9028-cdcc6bf67d22" = "User.Read"
        "02ad85cd-02ce-4902-a349-1af61152a021" = "User.Read", "Contacts.ReadWrite", "Calendars.ReadWrite", "Mail.Send", "Mail.ReadWrite", "EWS.AccessAsUser.All"
    }

    Add-AzureAppUserConsent -clientAppId "00b263e4-3497-4630-b082-3197csadd7c" -consent $consent -userUpnOrId "dealdesk@contoso.onmicrosoft.com"

    Grants consent on behalf of the "dealdesk@contoso.onmicrosoft.com" user to application "Salesforce Inbox" (00b263e4-3497-4630-b082-3197csadd7c) and given permissions on resource (ent. application) "Office 365 Exchange Online" (02ad85cd-02ce-4902-a349-1af61152a021) and "Windows Azure Active Directory" (88690023-f9e1-4728-9028-cdcc6bf67d22).

    .EXAMPLE
    Add-AzureAppUserConsent -clientAppId "00b263e4-3497-4630-b082-3197csadd7c" -copyExistingConsent -userUpnOrId "dealdesk@contoso.onmicrosoft.com"

    Grants consent on behalf of the "dealdesk@contoso.onmicrosoft.com" user to application "Salesforce Inbox" (00b263e4-3497-4630-b082-3197csadd7c) based on one of the existing consents.

    .NOTES
    https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/grant-consent-single-user
    #>

    [CmdletBinding()]
    param (
        # The app for which consent is being granted
        [Parameter(Mandatory = $true)]
        [string] $clientAppId,

        [Parameter(Mandatory = $true, ParameterSetName = "explicit")]
        [hashtable] $consent,

        [Parameter(ParameterSetName = "copyConsent")]
        [switch] $copyExistingConsent,

        [Parameter(Mandatory = $true)]
        # The user on behalf of whom access will be granted. The app will be able to access the API on behalf of this user.
        [string] $userUpnOrId
    )

    $ErrorActionPreference = "Stop"

    #region connect to Microsoft Graph PowerShell
    # we need User.ReadBasic.All to get
    # users' IDs, Application.ReadWrite.All to list and create service principals,
    # DelegatedPermissionGrant.ReadWrite.All to create delegated permission grants,
    # and AppRoleAssignment.ReadWrite.All to assign an app role.
    # WARNING: These are high-privilege permissions!

    Import-Module Microsoft.Graph.Authentication
    Import-Module Microsoft.Graph.Applications
    Import-Module Microsoft.Graph.Users
    Import-Module Microsoft.Graph.Identity.SignIns

    $null = Connect-MgGraph -Scopes ("User.ReadBasic.All", "Application.ReadWrite.All", "DelegatedPermissionGrant.ReadWrite.All", "AppRoleAssignment.ReadWrite.All")
    #endregion connect to Microsoft Graph PowerShell

    $clientSp = Get-MgServicePrincipal -Filter "appId eq '$($clientAppId)'"
    if (-not $clientSp) {
        throw "Enterprise application with Application ID $clientAppId doesn't exist"
    }

    # prepare consent from the existing one
    if ($copyExistingConsent) {
        $consent = @{}

        Get-MgServicePrincipalOauth2PermissionGrant -ServicePrincipalId $clientSp.id -All | group resourceId | select @{n = 'ResourceId'; e = { $_.Name } }, @{n = 'ScopeToGrant'; e = { $_.group | select -First 1 | select -ExpandProperty scope } } | % {
            $consent.($_.ResourceId) = $_.ScopeToGrant
        }

        if (!$consent.Keys) {
            throw "There is no existing user consent that can be cloned. Use parameter consent instead."
        } else {
            "Following consent(s) will be added:"
            $consent.GetEnumerator() | % {
                $resourceSp = Get-MgServicePrincipal -Filter "id eq '$($_.key)'"
                if (!$resourceSp) {
                    throw "Resource with ObjectId $($_.key) doesn't exist"
                }
                " - resource '$($resourceSp.DisplayName)' permission: $(($_.value | sort) -join ', ')"
            }

            $choice = ""
            while ($choice -notmatch "^[Y|N]$") {
                $choice = Read-Host "`nContinue? (Y|N)"
            }
            if ($choice -eq "N") {
                break
            }
        }
    }

    #region create a delegated permission that grants the client app access to the API, on behalf of the user.
    $user = Get-MgUser -UserId $userUpnOrId
    if (!$user) {
        throw "User $userUpnOrId doesn't exist"
    }

    foreach ($item in $consent.GetEnumerator()) {
        $resourceId = $item.key
        $scope = $item.value

        if (!$scope) {
            throw "You haven't specified any scope for resource $resourceId"
        }

        $resourceSp = Get-MgServicePrincipal -Filter "id eq '$resourceId'"
        if (!$resourceSp) {
            throw "Resource with ObjectId $resourceId doesn't exist"
        }

        # convert scope string (perm1 perm2) i.e. permission joined by empty space (returned by Get-AzureADServicePrincipalOAuth2PermissionGrant) into array
        if ($scope -match "\s+") {
            $scope = $scope -split "\s+" | ? { $_ }
        }

        $scopeToGrant = $scope

        # check if user already granted some permissions to this app for such resource
        # and skip such permissions to avoid errors
        $scopeAlreadyGranted = Get-MgOauth2PermissionGrant -Filter "principalId eq '$($user.Id)' and clientId eq '$($clientSp.Id)' and resourceId eq '$resourceId'" | select -ExpandProperty Scope
        if ($scopeAlreadyGranted) {
            Write-Verbose "Some permission(s) ($($scopeAlreadyGranted.trim())) are already granted to an app '$($clientSp.Id)' and resourceId '$resourceId'"
            $scopeAlreadyGrantedList = $scopeAlreadyGranted.trim() -split "\s+"

            $scopeToGrant = $scope | ? { $_ } | % {
                if ($_ -in $scopeAlreadyGrantedList) {
                    Write-Warning "Permission '$_' is already granted. Skipping"
                } else {
                    $_
                }
            }

            if (!$scopeToGrant) {
                Write-Warning "All permissions for resource $resourceId are already granted. Skipping"
                continue
            }
        }

        Write-Warning "Grant user consent on behalf of '$userUpnOrId' for application '$($clientSp.DisplayName)' to have following permission(s) '$(($scopeToGrant.trim() | sort) -join ', ')' over API '$($resourceSp.DisplayName)'"

        $grant = New-MgOauth2PermissionGrant -ResourceId $resourceSp.Id -Scope ($scopeToGrant -join " ") -ClientId $clientSp.Id -ConsentType "Principal" -PrincipalId $user.Id
    }
    #endregion create a delegated permission that grants the client app access to the API, on behalf of the user.

    #region assign the app to the user.
    # this ensures that the user can sign in if assignment is required, and ensures that the app shows up under the user's My Apps.
    $userAssignableRole = $clientSp.AppRoles | ? { $_.AllowedMemberTypes -contains "User" }
    if ($userAssignableRole) {
        Write-Warning "A default app role assignment cannot be created because the client application exposes user-assignable app roles ($($userAssignableRole.DisplayName -join ', ')). You must assign the user a specific app role for the app to be listed in the user's My Apps access panel."
    } else {
        if (Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $clientSp.Id -Property AppRoleId, PrincipalId | ? PrincipalId -EQ $user.Id) {
            # user already have some app role assigned
            Write-Verbose "User already have some app role assigned. Skipping default app role assignment."
        } else {
            # the app role ID 00000000-0000-0000-0000-000000000000 is the default app role
            # indicating that the app is assigned to the user, but not for any specific app role.
            Write-Verbose "Assigning default app role to the user"
            $assignment = New-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $clientSp.Id -ResourceId $clientSp.Id -PrincipalId $user.Id -AppRoleId "00000000-0000-0000-0000-000000000000"
        }
    }
    #endregion assign the app to the user.
}

function Add-AzureGuest {
    <#
    .SYNOPSIS
    Function for inviting guest user to Azure AD.

    .DESCRIPTION
    Function for inviting guest user to Azure AD.

    .PARAMETER displayName
    Display name of the user.
    Suffix (guest) will be added automatically.

    a.k.a Jan Novak

    .PARAMETER emailAddress
    Email address of the user.

    a.k.a novak@seznam.cz

    .PARAMETER parentTeamsGroup
    Optional parameter.

    Name of Teams group, where the guest should be added as member. (it can take several minutes, before this change propagates!)

    .EXAMPLE
    Add-AzureGuest -displayName "Jan Novak" -emailAddress "novak@seznam.cz"
    #>

    [CmdletBinding()]
    [Alias("New-AzureADGuest")]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript( {
                If ($_ -match "\(guest\)") {
                    throw "$_ (guest) will be added automatically."
                } else {
                    $true
                }
            })]
        [string] $displayName
        ,
        [Parameter(Mandatory = $true)]
        [ValidateScript( {
                If ($_ -match "@") {
                    $true
                } else {
                    Throw "$_ isn't email address"
                }
            })]
        [string] $emailAddress
        ,
        [ValidateScript( {
                If ($_ -notmatch "^External_") {
                    throw "$_ doesn't allow guest members (doesn't start with External_ prefix, so guests will be automatically removed)"
                } else {
                    $true
                }
            })]
        [string] $parentTeamsGroup
    )

    $null = Connect-MgGraph

    # naming conventions
    (Get-Variable displayName).Attributes.Clear()
    $displayName = $displayName.trim() + " (guest)"
    $emailAddress = $emailAddress.trim()

    "Creating Guest: $displayName EMAIL: $emailaddress"

    $null = New-MgInvitation -InvitedUserDisplayName $displayName -InvitedUserEmailAddress $emailAddress -InviteRedirectUrl "https://myapps.microsoft.com" -SendInvitationMessage:$true -InvitedUserType Guest

    if ($parentTeamsGroup) {
        $groupID = Get-MgGroup -Filter "displayName eq '$parentTeamsGroup'" | select -exp Id
        if (!$groupID) { throw "Unable to find group $parentTeamsGroup" }
        $guestId = Get-MgUser -Filter "mail eq '$emailaddress'" | select -exp Id
        New-MgGroupMember -GroupId $groupID -DirectoryObjectId $guestId
    }
}

function Disable-AzureGuest {
    <#
    .SYNOPSIS
    Function for disabling guest user in Azure AD.

    .DESCRIPTION
    Function for disabling guest user in Azure AD.

    Do NOT REMOVE the account, because lot of connected systems use UPN as identifier instead of SID.
    Therefore if someone in the future add such guest again, he would get access to all stuff, previous guest had access to.

    .PARAMETER displayName
    Display name of the user.

    If not specified, GUI with all guests will popup.

    .EXAMPLE
    Disable-AzureGuest -displayName "Jan Novak (guest)"

    Disables "Jan Novak (guest)" guest Azure AD account.

    .EXAMPLE
    Disable-AzureGuest

    Show GUI with all available guest accounts. The selected one will be disabled.
    #>

    [CmdletBinding()]
    [Alias("Remove-AzureADGuest")]
    param (
        [string[]] $displayName
    )

    $null = Connect-MgGraph -ea Stop

    $guestId = @()

    if (!$displayName) {
        # Get all the Guest Users
        $guest = Get-MgUser -All -Filter "UserType eq 'Guest' and AccountEnabled eq true" | select DisplayName, Mail, Id | Out-GridView -OutputMode Multiple -Title "Select accounts for disable"
        $guestId = $guest.id
    } else {
        $displayName | % {
            $guest = Get-MgUser -Filter "DisplayName eq '$_' and UserType eq 'Guest' and AccountEnabled eq true"
            if ($guest) {
                $guestId += $guest.Id
            } else {
                Write-Warning "$_ wasn't found or it is not guest account or is disabled already"
            }
        }
    }

    if ($guestId) {
        $guestId | % {
            "Blocking guest $_"

            # block Sign-In
            Update-MgUser -UserId $_ -AccountEnabled:$false

            # invalidate Azure AD Tokens
            $null = Revoke-MgUserSignInSession -UserId $_ -Confirm:$false
        }
    } else {
        Write-Warning "No guest to disable"
    }
}

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

function Get-AzureAppConsentRequest {
    <#
    .SYNOPSIS
    Function for getting AzureAD app consent requests.

    .DESCRIPTION
    Function for getting AzureAD app consent requests.

    .PARAMETER header
    Graph api authentication header.
    Can be create via New-GraphAPIAuthHeader.

    .PARAMETER openAdminConsentPage
    Switch for opening web page with form for granting admin consent for each not yet review application.

    .EXAMPLE
    $header = New-GraphAPIAuthHeader
    Get-AzureAppConsentRequest -header $header

    .NOTES
    Requires at least permission ConsentRequest.Read.All (to get requests), Directory.Read.All (to get service principal publisher)
    https://docs.microsoft.com/en-us/graph/api/appconsentapprovalroute-list-appconsentrequests?view=graph-rest-1.0&tabs=http
    https://docs.microsoft.com/en-us/graph/api/resources/consentrequests-overview?view=graph-rest-1.0
    #>

    [CmdletBinding()]
    param (
        $header,

        [switch] $openAdminConsentPage
    )

    if (!$header) {
        try {
            $header = New-GraphAPIAuthHeader -ErrorAction Stop
        } catch {
            throw "Unable to retrieve authentication header for graph api. Create it using New-GraphAPIAuthHeader and pass it using header parameter"
        }
    }

    Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/identityGovernance/appConsent/appConsentRequests" -header $Header | % {
        $userConsentRequestsUri = $_.'userConsentRequests@odata.context' -replace [regex]::escape('$metadata#')
        Write-Verbose "Getting user consent requests via '$userConsentRequestsUri'"
        $userConsentRequests = Invoke-GraphAPIRequest -uri $userConsentRequestsUri -header $Header

        $userConsentRequests = $userConsentRequests | select status, reason, @{name = 'createdBy'; expression = { $_.createdBy.user.userPrincipalName } }, createdDateTime, @{name = 'approval'; expression = { $_.approval.steps | select @{name = 'reviewedBy'; expression = { $_.reviewedBy.userPrincipalName } }, reviewResult, reviewedDateTime, justification } }, @{name = 'RequestId'; expression = { $_.Id } }

        $appVerifiedPublisher = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$filter=(appId%20eq%20%27$($_.appId)%27)&`$select=verifiedPublisher" -header $Header
        if ($appVerifiedPublisher | Get-Member | ? Name -EQ 'verifiedPublisher') {
            $appVerifiedPublisher = $appVerifiedPublisher.verifiedPublisher.DisplayName
        } else {
            # service principal wasn't found (new application)
            $appVerifiedPublisher = "*unknown*"
        }

        $_ | select appDisplayName, consentType, @{name = 'verifiedPublisher'; expression = { $appVerifiedPublisher } }, @{name = 'pendingScopes'; e = { $_.pendingScopes.displayName } }, @{name = 'consentRequest'; expression = { $userConsentRequests } }

        if ($openAdminConsentPage -and $userConsentRequests.status -eq 'InProgress') {
            Open-AzureAdminConsentPage -appId $_.appId
        }
    }
}

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

function Get-AzureAppVerificationStatus {
    param (
        [Parameter(Mandatory = $false, ParameterSetName = "entApp")]
        [string] $servicePrincipalObjectId,

        [Parameter(Mandatory = $false, ParameterSetName = "appReg")]
        [string] $appRegObjectId,

        $header
    )

    if (!$header) {
        try {
            $header = New-GraphAPIAuthHeader -ErrorAction Stop
        } catch {
            throw "Unable to retrieve authentication header for graph api. Create it using New-GraphAPIAuthHeader and pass it using header parameter"
        }
    }

    if ($appRegObjectId) {
        $URL = "https://graph.microsoft.com/v1.0/applications/$appRegObjectId`?`$select=displayName,verifiedPublisher"
    } elseif ($servicePrincipalObjectId) {
        $URL = "https://graph.microsoft.com/v1.0/servicePrincipals/$servicePrincipalObjectId`?`$select=displayName,verifiedPublisher"
    } else {
        $URL = "https://graph.microsoft.com/v1.0/servicePrincipals?`$select=displayName,verifiedPublisher"
    }

    Invoke-GraphAPIRequest -uri $URL -header $header | select displayName, @{name = 'publisherName'; expression = { $_.verifiedPublisher.displayName } }, @{name = 'publisherId'; expression = { $_.verifiedPublisher.verifiedPublisherId } }, @{name = 'publisherAdded'; expression = { Get-Date $_.verifiedPublisher.addedDateTime } }
}

function Get-AzureAssessNotificationEmail {
    <#
    .SYNOPSIS
    Function returns email(s) of organization technical contact(s) and privileged roles members.

    .DESCRIPTION
    Function returns email(s) of organization technical contact(s) and privileged roles members.

    .EXAMPLE
    $authHeader = New-GraphAPIAuthHeader
    Get-AzureAssessNotificationEmail -authHeader $authHeader

    .NOTES
    Stolen from Get-AADAssessNotificationEmailsReport function (module AzureADAssessment)
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $authHeader
    )

    #region get Organization Technical Contacts
    $OrganizationData = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/organization?`$select=technicalNotificationMails" -header $authHeader
    if ($OrganizationData) {
        foreach ($technicalNotificationMail in $OrganizationData.technicalNotificationMails) {
            $result = [PSCustomObject]@{
                notificationType           = "Technical Notification"
                notificationScope          = "Tenant"
                recipientType              = "emailAddress"
                recipientEmail             = $technicalNotificationMail
                recipientEmailAlternate    = $null
                recipientId                = $null
                recipientUserPrincipalName = $null
                recipientDisplayName       = $null
            }

            $user = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/users?`$select=id,userPrincipalName,displayName,mail,otherMails,proxyAddresses&`$filter=proxyAddresses/any(c:c eq 'smtp:$technicalNotificationMail') or otherMails/any(c:c eq 'smtp:$technicalNotificationMail')" -header $authHeader | Select-Object -First 1
        }

        if ($user) {
            $result.recipientType = 'user'
            $result.recipientId = $user.id
            $result.recipientUserPrincipalName = $user.userPrincipalName
            $result.recipientDisplayName = $user.displayName
            $result.recipientEmailAlternate = $user.otherMails -join ';'
        }

        $group = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/groups?`$filter=proxyAddresses/any(c:c eq 'smtp:$technicalNotificationMail')" -header $authHeader | Select-Object -First 1
        if ($group) {
            $result.recipientType = 'group'
            $result.recipientId = $group.id
            $result.recipientDisplayName = $group.displayName
        }

        Write-Output $result
    }
    #endregion get Organization Technical Contacts

    #region get email addresses of all users with privileged roles
    $DirectoryRoleData = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/directoryRoles?`$select=id,displayName&`$expand=members" -header $authHeader

    foreach ($role in $DirectoryRoleData) {
        foreach ($roleMember in $role.members) {
            $member = $null
            if ($roleMember.'@odata.type' -eq '#microsoft.graph.user') {
                $member = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/users?`$select=id,userPrincipalName,displayName,mail,otherMails,proxyAddresses&`$filter=id eq '$($roleMember.id)'" -header $authHeader | Select-Object -First 1
            } elseif ($roleMember.'@odata.type' -eq '#microsoft.graph.group') {
                $member = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/groups?`$select=id,displayName,mail,proxyAddresses&`$filter=id eq '$($roleMember.id)'" -header $authHeader | Select-Object -First 1
            } elseif ($roleMember.'@odata.type' -eq '#microsoft.graph.servicePrincipal') {
                $member = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=id,displayName&`$filter=id eq '$($roleMember.id)'" -header $authHeader | Select-Object -First 1
            } else {
                Write-Error "Undefined type $($roleMember.'@odata.type')"
            }

            [PSCustomObject]@{
                notificationType           = $role.displayName
                notificationScope          = 'Role'
                recipientType              = ($roleMember.'@odata.type') -replace '#microsoft.graph.', ''
                recipientEmail             = ($member.'mail')
                recipientEmailAlternate    = ($member.'otherMails') -join ';'
                recipientId                = ($member.'id')
                recipientUserPrincipalName = ($member.'userPrincipalName')
                recipientDisplayName       = ($member.'displayName')
            }
        }
    }
    #endregion get email addresses of all users with privileged roles
}

function Get-AzureAuthenticatorLastUsedDate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$upnList
    )

    foreach ($upn in $upnList) {
        # filter is case sensitive in Get-MgAuditLogSignIn and UPNs seems to be always in lower case
        $upn = $upn.tolower()

        Write-Warning "Processing $upn"

        $mfaMethod = Get-MgBetaUserAuthenticationMethod -UserId $upn | Expand-MgAdditionalProperties

        $mobileAuthenticatorList = $mfaMethod | ? ObjectType -EQ "microsoftAuthenticatorAuthenticationMethod"

        if (!$mobileAuthenticatorList) {
            Write-Warning "$upn doesn't have an authenticator app set"
            continue
        }

        if ($mobileAuthenticatorList.count -lt 2) {
            Write-Warning "$upn doesn't have more than one authenticator set"
            continue
        }

        $mobileAuthenticatorList = $mobileAuthenticatorList | select *, @{n = 'LastTimeUsedUTC'; e = { $null } }, @{n = 'OperatingSystem'; e = { $null } } -ExcludeProperty '@odata.type', 'ObjectType'

        # get all successfully completed MFA prompts
        # 0 = Success
        # 50140 = "This occurred due to 'Keep me signed in' interrupt when the user was signing in."
        $successfulMFAPrompt = Get-MgBetaAuditLogSignIn -all -Filter "UserPrincipalName eq '$upn' and AuthenticationRequirement eq 'multiFactorAuthentication' and conditionalAccessStatus eq 'success'" -Property * | ? { $_.Status.ErrorCode -in 0, 50140 -and ($_.AuthenticationDetails.AuthenticationStepResultDetail | % { if ($_ -in 'MFA successfully completed', 'MFA completed in Azure AD', 'User approved', 'MFA required in Azure AD', 'MFA requirement satisfied by strong authentication') { $true } }) }

        if (!$successfulMFAPrompt) {
            Write-Warning "No completed MFA prompts found (in last 30 days?)"
        } else {
            foreach ($mfaPrompt in $successfulMFAPrompt) {
                if ($mobileAuthenticatorList.count -eq ($mobileAuthenticatorList.LastTimeUsedUTC | ? { $_ }).count) {
                    # I have last used date for each registered authenticator
                    Write-Verbose "I have LastTimeUsedUTC for each authenticator app"
                    break
                }
                # "### $($mfaPrompt.AppDisplayName)"
                $mobileAuthenticatorId = $mfaPrompt.AuthenticationAppDeviceDetails.DeviceId # je ve skutecnosti ID z Get-MgUserAuthenticationMethod
                if (!$mobileAuthenticatorId) {
                    Write-Verbose "This isn't event where authenticator was used, skipping"
                    continue
                }

                $correspondingAuthenticator = $mobileAuthenticatorList | ? Id -EQ $mobileAuthenticatorId

                if (!$correspondingAuthenticator) {
                    Write-Verbose "Authenticator with ID $mobileAuthenticatorId doesn't exist anymore"
                } else {
                    if ($correspondingAuthenticator.LastTimeUsedUTC) {
                        Write-Verbose "$mobileAuthenticatorId was already processed"
                        continue
                    } else {
                        Write-Verbose "$mobileAuthenticatorId setting LastTimeUsedUTC $($mfaPrompt.CreatedDateTime) OperatingSystem $($mfaPrompt.AuthenticationAppDeviceDetails.OperatingSystem)"
                        $correspondingAuthenticator.LastTimeUsedUTC = $mfaPrompt.CreatedDateTime
                        $correspondingAuthenticator.OperatingSystem = $mfaPrompt.AuthenticationAppDeviceDetails.OperatingSystem
                    }
                }
            }
        }

        #TODO u authenticatoru bez udaju zjistit kdy se zaregistroval, mozna je novy a jeste ho nepouzil

        [PSCustomObject]@{
            UPN                 = $upn
            MobileAuthenticator = $mobileAuthenticatorList
        }
    }
}

function Get-AzureCompletedMFAPrompt {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$upnList
    )

    foreach ($upn in $upnList) {
        # filter is case sensitive in Get-MgAuditLogSignIn
        $upn = $upn.tolower()

        Write-Warning "Processing $upn"

        $mfaMethod = Get-MgBetaUserAuthenticationMethod -UserId $upn | Expand-MgAdditionalProperties

        # get all successfully completed MFA prompts
        # 0 = Success
        # 50140 = "This occurred due to 'Keep me signed in' interrupt when the user was signing in."
        $successfulMFAPrompt = Get-MgBetaAuditLogSignIn -all -Filter "UserPrincipalName eq '$upn' and AuthenticationRequirement eq 'multiFactorAuthentication' and conditionalAccessStatus eq 'success'" -Property * | ? { $_.Status.ErrorCode -in 0, 50140 -and ($_.AuthenticationDetails.AuthenticationStepResultDetail | % { if ($_ -in 'MFA successfully completed', 'MFA completed in Azure AD', 'User approved', 'MFA required in Azure AD', 'MFA requirement satisfied by strong authentication') { $true } }) }

        if (!$successfulMFAPrompt) {
            Write-Warning "No completed MFA prompts found"
            continue
        }

        foreach ($mfaPrompt in $successfulMFAPrompt) {
            $authenticationMethod = $mfaPrompt.AuthenticationDetails | ? { $_.AuthenticationMethod -notin "Previously satisfied", "Password" -and $_.Succeeded -eq $true }
            if ($authenticationMethod) {
                $authMethod = $authenticationMethod.AuthenticationMethod
                if (!$authMethod) {
                    # sometimes AuthenticationMethod is empty, but AuthenticationStepResultDetail contains 'MFA completed in Azure AD'
                    $authMethod = $authenticationMethod.AuthenticationStepResultDetail
                }
                $authDetail = $authenticationMethod.AuthenticationMethodDetail
                if (!$authDetail -and $mfaPrompt.AuthenticationAppDeviceDetails.DeviceId) {
                    $authDetail = $mfaPrompt.AuthenticationAppDeviceDetails
                }
            } else {
                $authMethod = $mfaPrompt.MfaDetail.AuthMethod
                $authDetail = $mfaPrompt.MfaDetail.AuthDetail
            }

            [PSCustomObject]@{
                UPN                = $upn
                CreatedDateTimeUTC = $mfaPrompt.CreatedDateTime
                AuthMethod         = $authMethod
                AuthDetail         = $authDetail
                AuthDeviceId       = $mfaPrompt.AuthenticationAppDeviceDetails.DeviceId
                AuditEvent         = $mfaPrompt
            }
        }
    }
}

function Get-AzureDeviceWithoutBitlockerKey {
    [CmdletBinding()]
    param ()

    Get-BitlockerEscrowStatusForAzureADDevices | ? { $_.BitlockerKeysUploadedToAzureAD -eq $false -and $_.userPrincipalName -and $_.lastSyncDateTime -and $_.isEncrypted }
}

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

function Get-AzureGroupMemberRecursive {
    <#
    .SYNOPSIS
    Function for getting Azure group members recursively.

    .DESCRIPTION
    Function for getting Azure group members recursively.

    Some advanced filtering options are available.

    .PARAMETER id
    Id of the group whose members you want to retrieve.

    .PARAMETER excludeDisabled
    Switch for excluding disabled members from the output.

    .PARAMETER includeNestedGroup
    Switch for including nested groups in the output (otherwise just their members will be included).

    .PARAMETER allowedMemberType
    What type of members should be outputted.

    Available options: 'User', 'Device', 'All'.

    By default 'All'.

    .EXAMPLE
    Get-AzureGroupMemberRecursive -groupId 330a6343-da12-4999-bf87-a0ae60a68bbc

    .NOTES
    Requires following graph modules: Microsoft.Graph.Groups, Microsoft.Graph.Authentication, Microsoft.Graph.DirectoryObjects
    #>

    [Alias("Get-MgGroupMemberRecursive")]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias("GroupId")]
        [guid] $id,

        [switch] $excludeDisabled,

        [switch] $includeNestedGroup,

        [ValidateSet('User', 'Device', 'All')]
        [string] $allowedMemberType = 'All'
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): The context is invalid. Please login using Connect-MgGraph."
    }

    foreach ($member in (Get-MgGroupMember -GroupId $id -All)) {
        $memberType = $member.AdditionalProperties["@odata.type"].split('.')[-1]
        $memberId = $member.Id

        if ($memberType -eq "group") {
            if ($includeNestedGroup) {
                $member | Expand-MgAdditionalProperties
            }

            $param = @{
                allowedMemberType = $allowedMemberType
            }
            if ($includeDisabled) { $param.includeDisabled = $true }

            Write-Verbose "Expanding members of group $memberId"
            Get-AzureGroupMemberRecursive -Id $memberId @param
        } else {
            if ($allowedMemberType -ne 'All' -and $memberType -ne $allowedMemberType) {
                Write-Verbose "Skipping $memberType member $memberId, because not of $allowedMemberType type."
                continue
            }

            if ($excludeDisabled) {
                $accountEnabled = (Get-MgDirectoryObject -DirectoryObjectId $memberId -Property accountEnabled).AdditionalProperties.accountEnabled
                if (!$accountEnabled) {
                    Write-Verbose "Skipping $memberType member $memberId, because not enabled."
                    continue
                }
            }

            $member | Expand-MgAdditionalProperties
        }
    }
}

function Get-AzureGroupSettings {
    <#
    .SYNOPSIS
    Function for getting group settings.
    Official Get-MgGroup -Property Settings doesn't return anything for some reason.

    .DESCRIPTION
    Function for getting group settings.
    Official Get-MgGroup -Property Settings doesn't return anything for some reason.

    .PARAMETER groupId
    Group ID.

    .EXAMPLE
    Get-AzureGroupSettings -groupId 01c19ec3-e1bb-44f3-ab36-86071b745375

    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $groupId
    )

    Invoke-MgGraphRequest -Uri "v1.0/groups/$groupId/settings" -OutputType PSObject | select -exp value | select *, @{n = 'ValuesAsObject'; e = {
            # return settings values as proper hashtable
            $hash = @{}
            $_.Values | % { $hash.($_.name) = $_.value }
            $hash
        }
    } #-ExcludeProperty Values
}

function Get-AzureManagedIdentity {
    <#
    .SYNOPSIS
    Function for getting Azure AD Managed Identity(ies).

    .DESCRIPTION
    Function for getting Azure AD Managed Identity(ies).

    .PARAMETER objectId
    (optional) objectID of Managed Identity(ies).

    If not specified, all app registrations will be processed.

    .EXAMPLE
    Get-AzureManagedIdentity

    Get all Managed Identities.

    .EXAMPLE
    Get-AzureManagedIdentity -objectId 1234-1234-1234

    Get selected Managed Identity.
    #>

    [CmdletBinding()]
    param (
        [string[]] $objectId
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): The context is invalid. Please login using Connect-MgGraph."
    }

    $servicePrincipalList = @()

    if (!$objectId) {
        $servicePrincipalList = Get-MgServicePrincipal -Filter "servicePrincipalType eq 'ManagedIdentity'" -All
    } else {
        $objectId | % {
            $servicePrincipalList += Get-MgServicePrincipal -ServicePrincipalId $_
        }
    }

    $azureSubscriptions = Get-AzSubscription

    $servicePrincipalList | % {
        $SPObj = $_

        # output
        $SPObj | select *, @{n = 'SubscriptionId'; e = { $_.alternativeNames | ? { $_ -Match "/subscriptions/([^/]+)/" } | % { ([regex]"/subscriptions/([^/]+)/").Matches($_).captures.groups[1].value } } }, @{name = 'SubscriptionName'; expression = { $alternativeNames = $_.alternativeNames; $azureSubscriptions | ? { $_.Id -eq ($alternativeNames | ? { $_ -Match "/subscriptions/([^/]+)/" } | % { ([regex]"/subscriptions/([^/]+)/").Matches($_).captures.groups[1].value }) } | select -exp Name } }, @{n = 'ResourceGroup'; e = { $_.alternativeNames | ? { $_ -Match "/resourcegroups/([^/]+)/" } | % { ([regex]"/resourcegroups/([^/]+)/").Matches($_).captures.groups[1].value } } },
        @{n = 'Type'; e = { if ($_.alternativeNames -match "/Microsoft.ManagedIdentity/userAssignedIdentities/") { 'UserManagedIdentity' } else { 'SystemManagedIdentity' } } }
    }
}

function Get-AzureResource {
    <#
    .SYNOPSIS
    Returns resources for all or just selected Azure subscription(s).

    .DESCRIPTION
    Returns resources for all or just selected Azure subscription(s).

    .PARAMETER subscriptionId
    ID of subscription you want to get resources for.

    .PARAMETER selectCurrentSubscription
    Switch for getting data just for currently set subscription.

    .EXAMPLE
    Get-AzureResource

    Returns resources for all subscriptions.

    .EXAMPLE
    Get-AzureResource -subscriptionId 1234-1234-1234-1234

    Returns resources for subscription with ID 1234-1234-1234-1234.

    .EXAMPLE
    Get-AzureResource -selectCurrentSubscription

    Returns resources just for current subscription.
    #>

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [Parameter(ParameterSetName = "subscriptionId")]
        [string] $subscriptionId,

        [Parameter(ParameterSetName = "currentSubscription")]
        [switch] $selectCurrentSubscription
    )

    # get Current Context
    $currentContext = Get-AzContext

    # get Azure Subscriptions
    if ($selectCurrentSubscription) {
        Write-Verbose "Only running for current subscription $($currentContext.Subscription.Name)"
        $subscriptions = Get-AzSubscription -SubscriptionId $currentContext.Subscription.Id -TenantId $currentContext.Tenant.Id
    } elseif ($subscriptionId) {
        Write-Verbose "Only running for selected subscription $subscriptionId"
        $subscriptions = Get-AzSubscription -SubscriptionId $subscriptionId -TenantId $currentContext.Tenant.Id
    } else {
        Write-Verbose "Running for all subscriptions in tenant"
        $subscriptions = Get-AzSubscription -TenantId $currentContext.Tenant.Id
    }

    Write-Verbose "Getting information about Role Definitions..."
    $allRoleDefinition = Get-AzRoleDefinition

    foreach ($subscription in $subscriptions) {
        Write-Verbose "Changing to Subscription $($subscription.Name)"

        $Context = Set-AzContext -TenantId $subscription.TenantId -SubscriptionId $subscription.Id -Force

        # getting information about Role Assignments for chosen subscription
        Write-Verbose "Getting information about Role Assignments..."
        $allRoleAssignment = Get-AzRoleAssignment

        Write-Verbose "Getting information about Resources..."

        Get-AzResource | % {
            $resourceId = $_.ResourceId
            Write-Verbose "Processing $resourceId"

            $roleAssignment = $allRoleAssignment | ? { $resourceId -match [regex]::escape($_.scope) -or $_.scope -like "/providers/Microsoft.Authorization/roleAssignments/*" -or $_.scope -like "/providers/Microsoft.Management/managementGroups/*" } | select RoleDefinitionName, DisplayName, Scope, SignInName, ObjectType, ObjectId, @{n = 'CustomRole'; e = { ($allRoleDefinition | ? Name -EQ $_.RoleDefinitionName).IsCustom } }, @{n = 'Inherited'; e = { if ($_.scope -eq $resourceId) { $false } else { $true } } }

            $_ | select *, @{n = "SubscriptionName"; e = { $subscription.Name } }, @{n = "SubscriptionId"; e = { $subscription.SubscriptionId } }, @{n = 'IAM'; e = { $roleAssignment } } -ExcludeProperty SubscriptionId, ResourceId, ResourceType
        }
    }
}

function Get-AzureRoleAssignments {
    <#
    .SYNOPSIS
    Returns RBAC role assignments (IAM tab for root, subscriptions, management groups, resource groups, resources) from all or just selected Azure subscription(s). It is possible to filter just roles assigned to user, group or service principal.

    .DESCRIPTION
    Returns RBAC role assignments (IAM tab for root, subscriptions, management groups, resource groups, resources) from all or just selected Azure subscription(s). It is possible to filter just roles assigned to user, group or service principal.

    From security perspective these roles are important:
    Owner
    Contributor
    User Access Administrator
    Virtual Machine Contributor
    Virtual Machine Administrator
    Avere Contributor

    When given to managed identity and scope is whole resource group or subscription (because of lateral movement)!

    .PARAMETER subscriptionId
    ID of subscription you want to get role assignments for.

    .PARAMETER selectCurrentSubscription
    Switch for getting data just for currently set subscription.

    .PARAMETER userPrincipalName
    UPN of the User whose assignments you want to get.

    .PARAMETER objectId
    ObjectId of the User, Group or Service Principal whose assignments you want to get.

    .PARAMETER tenantId
    Tenant ID if different then the default one should be used.

    .EXAMPLE
    Get-AzureRoleAssignments

    Returns RBAC role assignments for all subscriptions.

    .EXAMPLE
    Get-AzureRoleAssignments -subscriptionId 1234-1234-1234-1234

    Returns RBAC role assignments for subscription with ID 1234-1234-1234-1234.

    .EXAMPLE
    Get-AzureRoleAssignments -selectCurrentSubscription

    Returns RBAC role assignments just for current subscription.

    .EXAMPLE
    Get-AzureRoleAssignments -selectCurrentSubscription -userPrincipalName john@contoso.com

    Returns RBAC role assignments of the user john@contoso.com just for current subscription.

    .NOTES
    Required Azure permissions:
    - Global reader
    - Security Reader assigned at 'Tenant Root Group'

    https://m365internals.com/2021/11/30/lateral-movement-with-managed-identities-of-azure-virtual-machines/?s=09
    https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
    #>

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [Alias("Get-AzureRBACRoleAssignments", "Get-AzureIAMRoleAssignments")]
    param (
        [Parameter(ParameterSetName = "subscriptionId")]
        [string] $subscriptionId,

        [Parameter(ParameterSetName = "currentSubscription")]
        [Switch] $selectCurrentSubscription,

        [string] $userPrincipalName,

        [string] $objectId,

        [string] $tenantId
    )

    if ($objectId -and $userPrincipalName) {
        throw "You cannot use parameters objectId and userPrincipalName at the same time"
    }

    if ($tenantId) {
        $null = Connect-AzAccount2 -tenantId $tenantId -ErrorAction Stop
    } else {
        $null = Connect-AzAccount2 -ErrorAction Stop
    }

    # get Current Context
    $CurrentContext = Get-AzContext

    # get Azure Subscriptions
    if ($selectCurrentSubscription) {
        Write-Verbose "Only running for current subscription $($CurrentContext.Subscription.Name)"
        $Subscriptions = Get-AzSubscription -SubscriptionId $CurrentContext.Subscription.Id -TenantId $CurrentContext.Tenant.Id
    } elseif ($subscriptionId) {
        Write-Verbose "Only running for selected subscription $subscriptionId"
        $Subscriptions = Get-AzSubscription -SubscriptionId $subscriptionId -TenantId $CurrentContext.Tenant.Id
    } else {
        Write-Verbose "Running for all subscriptions in tenant"
        $Subscriptions = Get-AzSubscription -TenantId $CurrentContext.Tenant.Id
    }

    function _scopeType {
        param ([string] $scope)

        if ($scope -match "^/$") {
            return 'root'
        } elseif ($scope -match "^/subscriptions/[^/]+$") {
            return 'subscription'
        } elseif ($scope -match "^/subscriptions/[^/]+/resourceGroups/[^/]+$") {
            return "resourceGroup"
        } elseif ($scope -match "^/subscriptions/[^/]+/resourceGroups/[^/]+/.+$") {
            return 'resource'
        } elseif ($scope -match "^/providers/Microsoft.Management/managementGroups/.+") {
            return 'managementGroup'
        } else {
            throw 'undefined type'
        }
    }

    Write-Verbose "Getting Role Definitions..."
    $roleDefinition = Get-AzRoleDefinition

    foreach ($Subscription in ($Subscriptions | Sort-Object Name)) {
        Write-Verbose "Changing to Subscription $($Subscription.Name) ($($Subscription.SubscriptionId))"

        $Context = Set-AzContext -TenantId $Subscription.TenantId -SubscriptionId $Subscription.Id -Force

        # getting information about Role Assignments for chosen subscription
        Write-Verbose "Getting information about Role Assignments..."
        try {
            $param = @{
                ErrorAction = 'Stop'
            }
            if ($objectId) {
                $param.objectId = $objectId
            } elseif ($userPrincipalName) {
                # -ExpandPrincipalGroups for also assignments based on group membership
                $param.SignInName = $userPrincipalName
            }

            Get-AzRoleAssignment @param | Select-Object RoleDefinitionName, DisplayName, SignInName, ObjectType, ObjectId, @{n = 'AssignmentScope'; e = { $_.Scope } }, @{n = "SubscriptionId"; e = { $Subscription.SubscriptionId } }, @{n = 'ScopeType'; e = { _scopeType $_.scope } }, @{n = 'CustomRole'; e = { ($roleDefinition | ? { $_.Name -eq $_.RoleDefinitionName }).IsCustom } }, @{n = "SubscriptionName"; e = { $Subscription.Name } }
        } catch {
            if ($_ -match "The current subscription type is not permitted to perform operations on any provider namespace. Please use a different subscription") {
                Write-Warning "At subscription '$($Subscription.Name)' there is no resource provider registered"
            } elseif ($_ -match "Operation returned an invalid status code 'BadRequest'") {
                Write-Warning "You don't have permissions at '$($Subscription.Name)' subscription"
            } else {
                Write-Error $_
            }
        }
    }
}

function Get-AzureServiceAccount {
    <#
    .SYNOPSIS
    Function for getting information about Azure user service account.
    As a hack for storing user manager and description, we use helper ACL group 'ACL_Owner_<svcAccID>'.

    .DESCRIPTION
    Function for getting information about Azure user service account.
    As a hack for storing user manager and description, we use helper ACL group 'ACL_Owner_<svcAccID>'.

    .PARAMETER UPN
    UPN of the service account.
    For exmaple: svc_test@contoso.onmicrosoft.com

    .EXAMPLE
    Get-AzureServiceAccount -UPN svc_test@contoso.onmicrosoft.com
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidatePattern('.+@.+$')]
        [string] $UPN
    )

    $ErrorActionPreference = "Stop"

    $null = Connect-MgGraph -Scopes User.Read.All, Group.Read.All

    # check that such user does exist
    if (!($svcUser = Get-MgUser -Filter "userPrincipalName eq '$UPN'")) {
        Write-Warning "User $UPN doesn't exists"
    }

    $groupName = "ACL_Owner_" + $svcUser.Id

    if (!($svcGroup = Get-MgGroup -Filter "displayName eq '$groupName'")) {
        Write-Warning "Group $groupName doesn't exists. This shouldn't happen!"
    }

    if ($svcGroup) {
        $managedBy = Get-MgGroupMember -GroupId $svcGroup.Id
        if ($managedBy.count -gt 1) { Write-Warning "There is more than one manager. This shouldn't happen!" }
    }

    $object = [PSCustomObject]@{
        userPrincipalName = $UPN
        Description       = $svcGroup.Description
        ManagedByObjectId = $managedBy.Id
        ManagedBy         = $managedBy.AdditionalProperties.displayName
    }

    return $object
}

function Get-AzureServicePrincipalBySecurityAttribute {
    <#
    .SYNOPSIS
    Function returns service principals with given security attribute set.

    .DESCRIPTION
    Function returns service principals with given security attribute set.

    .PARAMETER attributeSetName
    Name of the security attribute set.

    .PARAMETER attributeName
    Name of the security attribute.

    .PARAMETER attributeValue
    Value of the security attribute.

    .EXAMPLE
    Get-AzureServicePrincipalBySecurityAttribute -attributeSetName Security -attributeName SecurityLevel -attributeValue 5

    .NOTES
    To be able to read security attributes you need to be member of 'Attribute Assignment Reader' or 'Attribute Assignment Administrator' or have following Graph API permissions. For SP 'CustomSecAttributeAssignment.Read.All' and 'Application.Read.All', for Users 'CustomSecAttributeAssignment.Read.All' and 'User.Read.All'

    https://learn.microsoft.com/en-us/graph/custom-security-attributes-examples?tabs=powershell
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $attributeSetName,

        [Parameter(Mandatory = $true)]
        [string] $attributeName,

        [Parameter(Mandatory = $true)]
        [string[]] $attributeValue
    )

    Write-Warning "To be able to read security attributes you need to be member of 'Attribute Assignment Reader' or 'Attribute Assignment Administrator' or have following Graph API permissions. For SP 'CustomSecAttributeAssignment.Read.All' and 'Application.Read.All', for Users 'CustomSecAttributeAssignment.Read.All' and 'User.Read.All'"

    # beta api is needed to get custom security attributes
    $filter = @()

    $attributeValue | % {
        $filter += "customSecurityAttributes/$attributeSetName/$attributeName eq '$_'"
    }

    $filter = $filter -join " or "

    Get-MgBetaServicePrincipal -All -Filter $filter -Property AppId, Id, AppDisplayName, AccountEnabled, DisplayName, CustomSecurityAttributes -ConsistencyLevel eventual -CountVariable CountVar -ErrorAction Stop
}

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
            $SP = $SP | select *, @{n = 'UsersAndGroups'; e = { Get-AzureAppUsersAndGroups -objectId $SP.Id | select CreatedDateTime, PrincipalDisplayName, PrincipalId, PrincipalType | ? PrincipalId -NotIn $consentPrincipalId } }
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

function Get-AzureServicePrincipalPermissions {
    <#
    .SYNOPSIS
        Lists granted delegated (OAuth2PermissionGrants) and application (AppRoleAssignments) permissions of the service principal (ent. app).

    .PARAMETER objectId
        Service principal objectId. If not specified, all service principals will be processed.

    .PARAMETER DelegatedPermissions
        If set, will return delegated permissions. If neither this switch nor the ApplicationPermissions switch is set,
        both application and delegated permissions will be returned.

    .PARAMETER ApplicationPermissions
        If set, will return application permissions. If neither this switch nor the DelegatedPermissions switch is set,
        both application and delegated permissions will be returned.

    .PARAMETER UserProperties
        The list of properties of user objects to include in the output. Defaults to DisplayName only.

    .PARAMETER ServicePrincipalProperties
        The list of properties of service principals (i.e. apps) to include in the output. Defaults to DisplayName only.

    .PARAMETER ShowProgress
        Whether or not to display a progress bar when retrieving application permissions (which could take some time).

    .PARAMETER PrecacheSize
        The number of users to pre-load into a cache. For tenants with over a thousand users,
        increasing this may improve performance of the script.
    .EXAMPLE
        PS C:\> Get-AzureServicePrincipalPermissions -objectId f1c5b03c-6605-46ac-8ddb-453b953af1fc
        Generates report of all permissions granted to app f1c5b03c-6605-46ac-8ddb-453b953af1fc.

    .EXAMPLE
        PS C:\> Get-AzureServicePrincipalPermissions | Export-Csv -Path "permissions.csv" -NoTypeInformation
        Generates a CSV report of all permissions granted to all apps.

    .EXAMPLE
        PS C:\> Get-AzureServicePrincipalPermissions -ApplicationPermissions -ShowProgress | Where-Object { $_.Permission -eq "Directory.Read.All" }
        Get all apps which have application permissions for Directory.Read.All.

    .EXAMPLE
        PS C:\> Get-AzureServicePrincipalPermissions -UserProperties @("DisplayName", "UserPrincipalName", "Mail") -ServicePrincipalProperties @("DisplayName", "AppId")
        Gets all permissions granted to all apps and includes additional properties for users and service principals.

    .NOTES
        https://docs.microsoft.com/en-us/microsoft-365/security/office-365-security/detect-and-remediate-illicit-consent-grants?view=o365-worldwide
    #>

    [CmdletBinding()]
    [Alias("Get-AzureSPPermissions")]
    param(
        [string] $objectId,

        [switch] $DelegatedPermissions,

        [switch] $ApplicationPermissions,

        [string[]] $UserProperties = @("DisplayName"),

        [string[]] $ServicePrincipalProperties = @("DisplayName"),

        [switch] $ShowProgress,

        [int] $PrecacheSize = 999
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): The context is invalid. Please login using Connect-MgGraph."
    }

    # An in-memory cache of objects by {object ID} and by {object class, object ID}
    $script:ObjectByObjectId = @{}
    $script:ObjectByObjectClassId = @{}

    #region helper functions
    # Function to add an object to the cache
    function CacheObject ($Object, $ObjectType) {
        if ($Object) {
            if (-not $script:ObjectByObjectClassId.ContainsKey($ObjectType)) {
                $script:ObjectByObjectClassId[$ObjectType] = @{}
            }
            $script:ObjectByObjectClassId[$ObjectType][$Object.Id] = $Object
            $script:ObjectByObjectId[$Object.Id] = $Object
        }
    }

    # Function to retrieve an object from the cache (if it's there), or from Azure AD (if not).
    function GetObjectByObjectId ($ObjectId) {
        if (-not $script:ObjectByObjectId.ContainsKey($ObjectId)) {
            Write-Verbose ("Querying Azure AD for object '{0}'" -f $ObjectId)
            try {
                $object = Get-MgDirectoryObjectById -Ids $ObjectId | Expand-MgAdditionalProperties
                CacheObject -Object $object -ObjectType $object.ObjectType
            } catch {
                Write-Verbose "Object not found."
                $_
            }
        }
        return $script:ObjectByObjectId[$ObjectId]
    }

    # Function to retrieve OAuth2PermissionGrants
    function GetOAuth2PermissionGrants {
        if ($objectId) {
            Get-MgServicePrincipalOauth2PermissionGrant -ServicePrincipalId $objectId -All
        } else {
            Get-MgOauth2PermissionGrant -All
        }
    }
    #endregion helper functions

    $empty = @{} # Used later to avoid null checks

    # Get ServicePrincipal object(s) and add to the cache
    if ($objectId) {
        Write-Verbose "Retrieving $objectId ServicePrincipal object..."
        Get-MgServicePrincipal -ServicePrincipalId $objectId | ForEach-Object {
            CacheObject -Object $_ -ObjectType "servicePrincipal"
        }
    } else {
        Write-Verbose "Retrieving all ServicePrincipal objects..."
        Get-MgServicePrincipal -All | ForEach-Object {
            CacheObject -Object $_ -ObjectType "servicePrincipal"
        }
    }

    $servicePrincipalCount = $script:ObjectByObjectClassId['ServicePrincipal'].Count

    if ($DelegatedPermissions -or (!$DelegatedPermissions -and !$ApplicationPermissions)) {
        # Get one page of User objects and add to the cache
        if (!$objectId) {
            Write-Verbose ("Retrieving up to {0} User objects..." -f $PrecacheSize)
            Get-MgUser -Top $PrecacheSize | Where-Object {
                CacheObject -Object $_ -ObjectType "user"
            }
        }

        # Get all existing OAuth2 permission grants, get the client, resource and scope details
        Write-Verbose "Retrieving OAuth2PermissionGrants..."

        GetOAuth2PermissionGrants | ForEach-Object {
            $grant = $_
            if ($grant.Scope) {
                $grant.Scope.Split(" ") | Where-Object { $_ } | ForEach-Object {
                    $scope = $_
                    $resource = GetObjectByObjectId -ObjectId $grant.ResourceId

                    $permission = $resource.oauth2PermissionScopes | Where-Object { $_.value -eq $scope }

                    $grantDetails = [ordered]@{
                        "PermissionType"        = "Delegated"
                        "ClientObjectId"        = $grant.ClientId
                        "ResourceObjectId"      = $grant.ResourceId
                        "GrantId"               = $grant.Id
                        "Permission"            = $scope
                        # "PermissionId"          = $permission.Id
                        "PermissionDisplayName" = $permission.adminConsentDisplayName
                        "PermissionDescription" = $permission.adminConsentDescription
                        "ConsentType"           = $grant.ConsentType
                        "PrincipalObjectId"     = $grant.PrincipalId
                    }

                    # Add properties for client and resource service principals
                    if ($ServicePrincipalProperties.Count -gt 0) {

                        $client = GetObjectByObjectId -ObjectId $grant.ClientId
                        $resource = GetObjectByObjectId -ObjectId $grant.ResourceId

                        $insertAtClient = 2
                        $insertAtResource = 3
                        foreach ($propertyName in $ServicePrincipalProperties) {
                            $grantDetails.Insert($insertAtClient++, "Client$propertyName", $client.$propertyName)
                            $insertAtResource++
                            $grantDetails.Insert($insertAtResource, "Resource$propertyName", $resource.$propertyName)
                            $insertAtResource ++
                        }
                    }

                    # Add properties for principal (will all be null if there's no principal)
                    if ($UserProperties.Count -gt 0) {

                        $principal = $empty
                        if ($grant.PrincipalId) {
                            $principal = GetObjectByObjectId -ObjectId $grant.PrincipalId
                        }

                        foreach ($propertyName in $UserProperties) {
                            $grantDetails["Principal$propertyName"] = $principal.$propertyName
                        }
                    }

                    New-Object PSObject -Property $grantDetails
                }
            }
        }
    }

    if ($ApplicationPermissions -or (!$DelegatedPermissions -and !$ApplicationPermissions)) {
        # Iterate over all ServicePrincipal objects and get app permissions
        Write-Verbose "Retrieving AppRoleAssignments..."

        if ($objectId) {
            $spObjectId = $objectId
        } else {
            $spObjectId = $script:ObjectByObjectClassId['ServicePrincipal'].GetEnumerator() | % { $_.Value.Id }
        }

        $spObjectId | ForEach-Object { $i = 0 } {
            Write-Progress "Processing $_ service principal"
            if ($ShowProgress) {
                Write-Progress -Activity "Retrieving application permissions..." `
                    -Status ("Checked {0}/{1} apps" -f $i++, $servicePrincipalCount) `
                    -PercentComplete (($i / $servicePrincipalCount) * 100)
            }

            $serviceAppRoleAssignedTo = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $_ -All

            $serviceAppRoleAssignedTo | Where-Object { $_.PrincipalType -eq "ServicePrincipal" } | ForEach-Object {
                $assignment = $_

                $resource = GetObjectByObjectId -ObjectId $assignment.ResourceId
                $appRole = $resource.AppRoles | Where-Object { $_.id -eq $assignment.AppRoleId }

                $grantDetails = [ordered]@{
                    "PermissionType"        = "Application"
                    "ClientObjectId"        = $assignment.PrincipalId
                    "ResourceObjectId"      = $assignment.ResourceId
                    "Permission"            = $appRole.value
                    # "PermissionId"          = $assignment.appRoleId
                    "PermissionDisplayName" = $appRole.displayName
                    "PermissionDescription" = $appRole.description
                }

                # Add properties for client and resource service principals
                if ($ServicePrincipalProperties.Count -gt 0) {

                    $client = GetObjectByObjectId -ObjectId $assignment.PrincipalId

                    $insertAtClient = 2
                    $insertAtResource = 3
                    foreach ($propertyName in $ServicePrincipalProperties) {
                        $grantDetails.Insert($insertAtClient++, "Client$propertyName", $client.$propertyName)
                        $insertAtResource++
                        $grantDetails.Insert($insertAtResource, "Resource$propertyName", $resource.$propertyName)
                        $insertAtResource ++
                    }
                }

                New-Object PSObject -Property $grantDetails
            }
        }
    }
}

function Get-AzureServicePrincipalUsersAndGroups {
    <#
    .SYNOPSIS
    Get users and groups roles of (selected) service principal.

    .DESCRIPTION
    Get users and groups roles of (selected) service principal.

    .PARAMETER objectId
    ObjectId of service principal.

    If not provided all service principals will be processed.

    .EXAMPLE
    Get-AzureServicePrincipalUsersAndGroups

    Returns all service principals and their users and groups roles assignments.

    .EXAMPLE
    Get-AzureServicePrincipalUsersAndGroups -objectId 123123

    Returns service principal with objectId 123123 and its users and groups roles assignments.

    .NOTES
    https://github.com/MicrosoftDocs/azure-docs/issues/48159
    #>

    [CmdletBinding()]
    param (
        [string] $objectId
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): The context is invalid. Please login using Connect-MgGraph."
    }

    $param = @{}
    if ($objectId) {
        Write-Verbose "Get $objectId service principal"
        $param.ServicePrincipalId = $objectId
    } else {
        Write-Verbose "Get all service principals"
        $param.all = $true
    }

    Get-MgServicePrincipal @param | % {
        # Build a hash table of the service principal's app roles. The 0-Guid is
        # used in an app role assignment to indicate that the principal is assigned
        # to the default app role (or rather, no app role).
        $appRoles = @{ [Guid]::Empty.ToString() = "(default)" }
        $_.AppRoles | % { $appRoles[$_.Id] = $_.DisplayName }

        Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $_.Id -All | % {
            $_ | Add-Member -Name "AppRoleDisplayName" -Value $appRoles[$_.AppRoleId] -MemberType NoteProperty -PassThru
        }
    }
}

function Get-AzureSkuAssignment {
    <#
    .SYNOPSIS
    Function returns users with selected Sku license.

    .DESCRIPTION
    Function returns users with selected Sku license.

    .PARAMETER sku
    SkuId or SkuPartNumber of the O365 license Sku.
    If not provided, all users and their Skus will be outputted.

    SkuId/SkuPartNumber can be found via: Get-MgSubscribedSku -All

    .PARAMETER assignmentType
    Limit what kind of license assignment the user needs to have.

    Possible values are: 'direct', 'inherited'

    By default users with both types are displayed.

    .EXAMPLE
    Get-AzureSkuAssignment -sku "f8a1db68-be16-40ed-86d5-cb42ce701560"

    Get all users with selected sku (defined by id).

    .EXAMPLE
    Get-AzureSkuAssignment -sku "POWER_BI_PRO"

    Get all users with selected sku.

    .EXAMPLE
    Get-AzureSkuAssignment

    Get all users and their skus.

    .EXAMPLE
    Get-AzureSkuAssignment -assignmentType direct

    Get all users which have some sku assigned directly.

    .EXAMPLE
    Get-AzureSkuAssignment -sku "POWER_BI_PRO" -assignmentType inherited

    Get all users with selected sku if it is inherited.
    #>

    [CmdletBinding()]
    param (
        [ArgumentCompleter( {
                param ($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)

                Get-MgSubscribedSku -Property SkuPartNumber, SkuId -All | ? SkuPartNumber -Like "*$WordToComplete*" | select -ExpandProperty SkuPartNumber
            })]
        [string] $sku,

        [ValidateSet('direct', 'inherited')]
        [string[]] $assignmentType = ('direct', 'inherited'),

        [string[]] $userProperty = ('id', 'userprincipalname', 'assignedLicenses', 'LicenseAssignmentStates')
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): The context is invalid. Please login using Connect-MgGraph."
    }

    # add mandatory property
    if ($userProperty -notcontains 'assignedLicenses') { $userProperty += 'assignedLicenses' }
    if ($userProperty -notcontains 'LicenseAssignmentStates') { $userProperty += 'LicenseAssignmentStates' }

    $param = @{
        Select = $userProperty
        All    = $true
    }

    if ($sku) {
        $skuId = Get-MgSubscribedSku -Property SkuPartNumber, SkuId -All | ? { $_.SkuId -eq $sku -or $_.SkuPartNumber -eq $sku } | select -ExpandProperty SkuId
        if (!$skuId) {
            throw "Sku with id $skuId doesn't exist"
        }
        $param.Filter = "assignedLicenses/any(u:u/skuId eq $skuId)"
    }

    if ($assignmentType.count -eq 2) {
        # has some license
        $whereFilter = { $_.assignedLicenses }
    } elseif ($assignmentType -contains 'direct') {
        # direct assignment
        if ($sku) {
            $whereFilter = { $_.assignedLicenses -and ($_.LicenseAssignmentStates | ? { $_.SkuId -eq $skuId -and $_.AssignedByGroup -eq $null }) }
        } else {
            $whereFilter = { $_.assignedLicenses -and ($_.LicenseAssignmentStates.AssignedByGroup -eq $null).count -ge 1 }
        }
    } else {
        # inherited assignment
        if ($sku) {
            $whereFilter = { $_.assignedLicenses -and ($_.LicenseAssignmentStates | ? { $_.SkuId -eq $skuId -and $_.AssignedByGroup -ne $null }) }
        } else {
            $whereFilter = { $_.assignedLicenses -and $_.LicenseAssignmentStates.AssignedByGroup -ne $null }
        }
    }

    Get-MgUser @param | select $userProperty | ? $whereFilter
}

function Get-AzureSkuAssignmentError {
    <#
    .SYNOPSIS
    Function returns users that have problems with licenses assignment.

    .DESCRIPTION
    Function returns users that have problems with licenses assignment.
    #>

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): The context is invalid. Please login using Connect-MgGraph."
    }

    $userWithLicenseProblem = Get-MgUser -Property UserPrincipalName, Id, LicenseAssignmentStates -All | ? { $_.LicenseAssignmentStates.state -eq 'error' }

    foreach ($user in $userWithLicenseProblem) {
        $errorLicense = $user.LicenseAssignmentStates | ? State -EQ "Error"

        foreach ($license in $errorLicense) {
            [PSCustomObject]@{
                UserPrincipalName   = $user.UserPrincipalName
                UserId              = $user.Id
                LicError            = $license.Error
                AssignedByGroup     = $license.AssignedByGroup
                AssignedByGroupName = (if ($license.AssignedByGroup) { (Get-MgGroup -GroupId $license.AssignedByGroup -Property DisplayName).DisplayName })
                LastUpdatedDateTime = $license.LastUpdatedDateTime
                SkuId               = $license.SkuId
                SkuName             = (Get-MgSubscribedSku -Property SkuPartNumber, SkuId -All | ? { $_.SkuId -eq $license.SkuId } | select -ExpandProperty SkuPartNumber)
            }
        }
    }

    <# logictejsi by bylo jit shora dolu (group > user), ale tam je problem s vracenim potrebnych dat
    Get-MgGroup -Property Id, DisplayName, AssignedLicenses, LicenseProcessingState, MembersWithLicenseErrors -Filter "HasMembersWithLicenseErrors eq true" | % {
        $groupId = $_.Id
        # kvuli bugu je potreba delat primy api call namisto pouziti property MembersWithLicenseErrors (je prazdna)
        Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups/$groupId/membersWithLicenseErrors" -OutputType PSObject | select -ExpandProperty value
    }
    #>
}

function Get-AzureUserAuthMethodChanges {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$upnList,

        [ValidateSet('StrongAuthenticationMethod', 'StrongAuthenticationPhoneAppDetail')]
        # SearchableDeviceKey == FIDO, 'passwordless phone sign-in'
        # StrongAuthenticationPhoneAppDetail == mobile authenticator app
        [string[]] $methodType = ('SearchableDeviceKey', 'StrongAuthenticationPhoneAppDetail')
    )

    # unfortunately I don't know how to directly get events just for specific user :(
    $allMFAMethodRegistration = Get-MgBetaAuditLogDirectoryAudit -All -Property * -Filter "Category eq 'UserManagement' and ActivityDisplayName eq 'Update user' and LoggedByService eq 'Core Directory' and InitiatedBy/App/DisplayName eq 'Azure MFA StrongAuthenticationService'"

    $allFIDOMFAMethodRegistration = Get-MgBetaAuditLogDirectoryAudit -All -Property * -Filter "Category eq 'UserManagement' and ActivityDisplayName eq 'Update user' and LoggedByService eq 'Core Directory' and InitiatedBy/App/DisplayName eq 'Device Registration Service'"



    #FIXME to vypada ze jde brat primo ty user eventy pres LoggedByService eq 'Device Registration Service' ?? (jen bych ignoroval 'Register device')
    ale asi neobsahuje ciste phone app??
    $userMFAMethodRegistration = Get-MgBetaAuditLogDirectoryAudit -All -Property * -Filter "Category eq 'UserManagement' and LoggedByService eq 'Device Registration Service' and InitiatedBy/User/Id eq '$userId'"


    foreach ($upn in $upnList) {
        $userId = Get-MgBetaUser -UserId $upn -Property Id -ErrorAction Stop | select -ExpandProperty Id

        # rozsekat dle typu pridavane metody, $allMFAMethodRegistration ted NEOBSAHUJE vsechny
        # keyIdentifier u FIDO je vlastne ID
        $userMFAMethodRegistration = $allMFAMethodRegistration | ? { $_.TargetResources.Id -eq $userId }

        $userMFAMethodRegistration | % {
            $event = $_
            $userAuthenticatorMFAMethodRegistrationOldValue = $event.TargetResources.ModifiedProperties | ? { $_.DisplayName -in $methodType -and $_.OldValue } | select -ExpandProperty OldValue | ConvertFrom-Json
            $userAuthenticatorMFAMethodRegistrationNewValue = $event.TargetResources.ModifiedProperties | ? { $_.DisplayName -in $methodType -and $_.NewValue } | select -ExpandProperty NewValue | ConvertFrom-Json

            $addedMethod = $userAuthenticatorMFAMethodRegistrationNewValue | ? { $_.Id -notin $userAuthenticatorMFAMethodRegistrationOldValue.Id }

            if ($addedMethod) {
                $addedMethod | select @{n = 'UPN'; e = { $upn } }, @{n = 'Action'; e = { 'Added' } }, @{n = 'DateTimeUTC'; e = { $event.ActivityDateTime } }, *
            }

            $removedMethod = $userAuthenticatorMFAMethodRegistrationOldValue | ? { $_.Id -notin $userAuthenticatorMFAMethodRegistrationNewValue.Id }

            if ($removedMethod) {
                $removedMethod | select @{n = 'UPN'; e = { $upn } }, @{n = 'Action'; e = { 'Removed' } }, @{n = 'DateTimeUTC'; e = { $event.ActivityDateTime } }, *
            }
        }

        $userMFAMethodRegistration = $allFIDOMFAMethodRegistration | ? { $_.TargetResources.Id -eq $userId }

        $userMFAMethodRegistration | % {
            $event = $_
            $userAuthenticatorMFAMethodRegistrationOldValue = $event.TargetResources.ModifiedProperties | ? { $_.DisplayName -in $methodType -and $_.OldValue } | select -ExpandProperty OldValue | ConvertFrom-Json
            $userAuthenticatorMFAMethodRegistrationNewValue = $event.TargetResources.ModifiedProperties | ? { $_.DisplayName -in $methodType -and $_.NewValue } | select -ExpandProperty NewValue | ConvertFrom-Json

            $addedMethod = $userAuthenticatorMFAMethodRegistrationNewValue | ? { $_.Id -notin $userAuthenticatorMFAMethodRegistrationOldValue.Id }

            if ($addedMethod) {
                $addedMethod | select @{n = 'UPN'; e = { $upn } }, @{n = 'Action'; e = { 'Added' } }, @{n = 'DateTimeUTC'; e = { $event.ActivityDateTime } }, *
            }

            $removedMethod = $userAuthenticatorMFAMethodRegistrationOldValue | ? { $_.Id -notin $userAuthenticatorMFAMethodRegistrationNewValue.Id }

            if ($removedMethod) {
                $removedMethod | select @{n = 'UPN'; e = { $upn } }, @{n = 'Action'; e = { 'Removed' } }, @{n = 'DateTimeUTC'; e = { $event.ActivityDateTime } }, *
            }
        }
    }
}

function Grant-AzureServicePrincipalPermission {
    <#
    .SYNOPSIS
    Function for granting application/delegated permission(s) for selected resource to selected account.

    .DESCRIPTION
    Function for granting application/delegated permission(s) for selected resource to selected account.

    By default grants permission to Graph Api resource.

    .PARAMETER servicePrincipalName
    Name of the service principal you want to grant permission(s) to.

    .PARAMETER servicePrincipalId
    ObjectId of the service principal you want to grant permissions(s) to.

    .PARAMETER resourceAppId
    ObjectId of the resource you want to grant permission(s) to.

    By default ObjectId of the Graph API resource a.k.a. GraphAggregatorService service principal.

    .PARAMETER permissionList
    List of permissions you want to grant.

    If not defined, Out-GridView table with all available permissions (of type defined in permissionType) will be interactively outputted, so the user can pick some.

    .PARAMETER permissionType
    Type of permission you want to add.

    Possible values are application, delegated.

    By default application is selected.

    .EXAMPLE
    Grant-AzureServicePrincipalPermission -servicePrincipalName "Merge EU Integration" -permissionList user.read.all ,GroupMember.Read.All, Group.Read.All, offline_access

    Grant selected 'application' type Graph Api permissions to application "Merge EU Integration".

    .EXAMPLE
    Grant-AzureServicePrincipalPermission -servicePrincipalName "Merge EU Integration"

    Shows table with all available 'application' type permissions for Graph Api, let the user pick some and grant them to application "Merge EU Integration".

    .EXAMPLE
    Grant-AzureServicePrincipalPermission -servicePrincipalId e9af2b82-335f-4160-9da6-0ad647affd7e -permissionList offline_access -permissionType delegated

    Grant selected 'delegated' type Graph Api permissions to application with selected ObjectId.
    #>

    [CmdletBinding(DefaultParameterSetName = 'name')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "name")]
        [string] $servicePrincipalName,

        [Parameter(Mandatory = $true, ParameterSetName = "id")]
        [string] $servicePrincipalId,

        [string] $resourceAppId = '00000003-0000-0000-c000-000000000000', # graph api

        [ArgumentCompleter( {
                param ($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)

                $resourceAppId = $FakeBoundParams.resourceAppId
                if (!$resourceAppId) { $resourceAppId = '00000003-0000-0000-c000-000000000000' }

                if (!$FakeBoundParams.permissionType -or $FakeBoundParams.permissionType -eq 'application') {
                    (Get-MgServicePrincipal -Filter "appId eq '$resourceAppId'").AppRoles.Value | ? { $_ -like "*$WordToComplete*" }
                } else {
                    (Get-MgServicePrincipal -Filter "appId eq '$resourceAppId'").Oauth2PermissionScopes.Value | ? { $_ -like "*$WordToComplete*" }
                }
            })]
        [string[]] $permissionList,

        [ValidateSet('application', 'delegated')]
        [string] $permissionType = "application"
    )

    # authenticate
    if ($permissionType -eq "application") {
        $graphScope = "Application.ReadWrite.All", "AppRoleAssignment.ReadWrite.All"
    } else {
        $graphScope = "Application.ReadWrite.All", "DelegatedPermissionGrant.ReadWrite.All"
    }
    $null = Connect-MgGraph -Scopes $graphScope -ea Stop

    # remove duplicates
    $permissionList = $permissionList | select -Unique

    # get account to which permissions will be granted
    if ($servicePrincipalName) {
        $servicePrincipal = Get-MgServicePrincipal -Filter "displayName eq '$servicePrincipalName'"
        if (!$servicePrincipal) { throw "Service principal '$servicePrincipalName' doesn't exist" }
    } else {
        $servicePrincipal = (Get-MgServicePrincipal -ServicePrincipalId $servicePrincipalId)
        if (!$servicePrincipal) { throw "Service principal '$servicePrincipalId' doesn't exist" }
    }

    # get application whose permissions will be granted
    $resourceServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$resourceAppId'" -Property Id, AppRoles, Oauth2PermissionScopes
    if (!$resourceServicePrincipal) { throw "Resource '$resourceAppId' doesn't exist" }

    # let the user pick permissions to grant interactively
    if (!$permissionList) {
        if ($permissionType -eq "application") {
            $availablePermission = (Get-MgServicePrincipal -Filter "appId eq '$resourceAppId'").AppRoles | select Value, DisplayName, Description
        } else {
            $availablePermission = (Get-MgServicePrincipal -Filter "appId eq '$resourceAppId'").Oauth2PermissionScopes | select Value, AdminConsentDisplayName, AdminConsentDescription
        }

        $permissionList = $availablePermission | sort Value | Out-GridView -Title "Select $permissionType permission(s) you want to grant" -OutputMode Multiple | select -ExpandProperty Value

        if (!$permissionList) {
            throw "You haven't selected any permission"
        }
    }

    Write-Verbose "Permission(s): $(($permissionList | sort) -join ', ') of the resource '$($resourceServicePrincipal.displayName)' will be granted to: $($servicePrincipal.displayName)"

    # get already assigned permissions
    if ($permissionType -eq "application") {
        $appRoleAssignment = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $servicePrincipal.Id | ? ResourceId -EQ $resourceServicePrincipal.Id
    } else {
        # if some permissions were already granted, update must be used instead of creation of the new grant
        $Oauth2PermissionGrant = Get-MgOauth2PermissionGrant -Filter "clientId eq '$($servicePrincipal.Id)' and ResourceId eq '$($resourceServicePrincipal.Id)' and consentType eq 'AllPrincipals'"
    }

    $delegatedPermissionList = @()
    if ($Oauth2PermissionGrant) {
        $delegatedPermissionList = @($Oauth2PermissionGrant.Scope -split " ")
    }

    #region grant requested permissions
    foreach ($permission in $permissionList) {
        if ($permissionType -eq "application") {
            # grant application permission
            # https://learn.microsoft.com/en-us/powershell/microsoftgraph/tutorial-grant-app-only-api-permissions?view=graph-powershell-1.0

            # check whether such permission exists
            $appRole = $resourceServicePrincipal.AppRoles | Where-Object { $_.Value -eq $permission -and $_.AllowedMemberTypes -contains "Application" }

            if (!$appRole) {
                Write-Warning "Application permission '$permission' wasn't found in '$resourceAppId' application. Skipping"
                continue
            } elseif ($appRole.Id -in $appRoleAssignment.AppRoleId) {
                Write-Warning "Application permission '$permission' is already granted. Skipping"
                continue
            }

            $params = @{
                PrincipalId = $servicePrincipal.Id
                ResourceId  = $resourceServicePrincipal.Id
                AppRoleId   = $appRole.Id
            }

            Write-Warning "Granting application permission '$permission'"
            $null = New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $servicePrincipal.Id -BodyParameter $params
        } else {
            # prepare delegated permission to add
            # https://learn.microsoft.com/en-us/powershell/microsoftgraph/tutorial-grant-delegated-api-permissions?view=graph-powershell-1.0

            # check whether such permission exists
            $Oauth2PermissionScope = $resourceServicePrincipal.Oauth2PermissionScopes | Where-Object { $_.Value -eq $permission }
            if (!$Oauth2PermissionScope) {
                Write-Warning "Delegated permission '$permission' wasn't found in '$resourceAppId' application. Skipping"
                continue
            }

            # check whether permission is already added
            if ($Oauth2PermissionGrant -and ($Oauth2PermissionGrant.Scope -split " " -contains $permission)) {
                Write-Warning "Delegated permission '$permission' is already granted. Skipping"
                continue
            }

            $delegatedPermissionList += $permission
        }
    }

    # grant delegated permission
    # delegated permissions have to be set at once, and not one by one
    if ($delegatedPermissionList) {
        Write-Warning "Granting delegated permission(s) '$($delegatedPermissionList -join " ")'"

        if ($Oauth2PermissionGrant) {
            # there is some permissions grant already, update it

            $params = @{
                "Scope" = ($delegatedPermissionList -join " ")
            }

            $null = Update-MgOauth2PermissionGrant -OAuth2PermissionGrantId $Oauth2PermissionGrant.Id -BodyParameter $params
        } else {
            # there is no existing permissions grant, create it

            $params = @{
                "ClientId"    = $servicePrincipal.Id
                "ConsentType" = "AllPrincipals"
                "ResourceId"  = $resourceServicePrincipal.Id
                "Scope"       = ($delegatedPermissionList -join " ")
            }

            $null = New-MgOauth2PermissionGrant -BodyParameter $params
        }
    }
    #endregion grant requested permissions
}

function New-AzureAutomationModule {
    <#
    .SYNOPSIS
    Function for uploading new (or updating existing) Azure Automation PSH module.

    Any module dependencies will be installed too.

    .DESCRIPTION
    Function for uploading new (or updating existing) Azure Automation PSH module.

    Any module dependencies will be installed too.

    If module exists, but in lower version, it will be updated.

    .PARAMETER moduleName
    Name of the PSH module.

    .PARAMETER moduleVersion
    (optional) version of the PSH module.

    .PARAMETER resourceGroupName
    Name of the Azure Resource Group.

    .PARAMETER automationAccountName
    Name of the Azure Automation Account.

    .PARAMETER runtimeVersion
    PSH runtime version.

    Possible values: 5.1, 7.1, 7.2.

    By default 5.1.

    .PARAMETER overridePSGalleryModuleVersion
    Hashtable of hashtables where you can specify what module version should be used for given runtime if no specific version is required.

    This is needed in cases, where module newest available PSGallery version isn't compatible with your runtime because of incorrect manifest.

    By default:

    $overridePSGalleryModuleVersion = @{
        # 2.x.x PnP.PowerShell versions (2.1.1, 2.2.0) requires PSH 7.2 even though manifest doesn't say it
        # so the wrong module version would be picked up which would cause an error when trying to import
        "PnP.PowerShell" = @{
            "5.1" = "1.12.0"
        }
    }

    .EXAMPLE
    Connect-AzAccount -Tenant "contoso.onmicrosoft.com" -SubscriptionName "AutomationSubscription"

    New-AzureAutomationModule -resourceGroupName test -automationAccountName test -moduleName "Microsoft.Graph.Groups"

    Imports newest supported version (for given Runtime) of the "Microsoft.Graph.Groups" module including all its dependencies.
    In case module "Microsoft.Graph.Groups" (with any version) and all its dependencies are already imported, nothing will happens.

    .EXAMPLE
    Connect-AzAccount -Tenant "contoso.onmicrosoft.com" -SubscriptionName "AutomationSubscription"

    New-AzureAutomationModule -resourceGroupName test -automationAccountName test -moduleName "Microsoft.Graph.Groups" -moduleVersion "2.11.1"

    Imports newest supported version (for given Runtime) of the "Microsoft.Graph.Groups" module including all its dependencies.
    In case module "Microsoft.Graph.Groups" with version "2.11.1" and all its dependencies are already imported, nothing will happens.
    Otherwise module will be replaced (including all dependencies that are required for this specific version).
    #>

    [CmdletBinding()]
    [Alias("New-AzAutomationModule2")]
    param (
        [Parameter(Mandatory = $true)]
        [string] $moduleName,

        [string] $moduleVersion,

        [Parameter(Mandatory = $true)]
        [string] $resourceGroupName,

        [Parameter(Mandatory = $true)]
        [string] $automationAccountName,

        [ValidateSet('5.1', '7.1', '7.2')]
        [string] $runtimeVersion = '5.1',

        [int] $indent = 0,

        [hashtable[]] $overridePSGalleryModuleVersion = @{
            # 2.x.x PnP.PowerShell versions (2.1.1, 2.2.0) requires PSH 7.2 even though manifest doesn't say it
            # so the wrong module version would be picked up which would cause an error when trying to import
            "PnP.PowerShell" = @{
                "5.1" = "1.12.0"
            }
        }
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    $indentString = "     " * $indent

    function _write {
        param ($string, $color)

        $param = @{
            Object = ($indentString + $string)
        }
        if ($color) {
            $param.ForegroundColor = $color
        }

        Write-Host @param
    }

    if ($moduleVersion) {
        $moduleVersionString = "($moduleVersion)"
    } else {
        $moduleVersionString = ""
    }

    _write "Processing module $moduleName $moduleVersionString" "Magenta"

    #region get PSGallery module data
    $param = @{
        # IncludeDependencies = $true # cannot be used, because always returns newest usable module version, I want to use existing modules if possible (to minimize the runtime & risk that something will stop working)
        Name        = $moduleName
        ErrorAction = "Stop"
    }
    if ($moduleVersion) {
        $param.RequiredVersion = $moduleVersion
    } elseif ($runtimeVersion -eq '5.1') {
        $param.AllVersions = $true
    }

    $moduleGalleryInfo = Find-Module @param
    #endregion get PSGallery module data

    # get newest usable module version for given runtime
    if (!$moduleVersion -and $runtimeVersion -eq '5.1') {
        # no specific version was selected and older PSH version is used, make sure module that supports it, will be found
        # for example (currently newest) pnp.powershell 2.3.0 supports only PSH 7.2
        $moduleGalleryInfo = $moduleGalleryInfo | ? { $_.AdditionalMetadata.PowerShellVersion -le $runtimeVersion } | select -First 1
    }

    if (!$moduleGalleryInfo) {
        Write-Error "No supported $moduleName module was found in PSGallery"
        return
    }

    # override module version
    if (!$moduleVersion -and $moduleName -in $overridePSGalleryModuleVersion.Keys -and $overridePSGalleryModuleVersion.$moduleName.$runtimeVersion) {
        $overriddenModule = $overridePSGalleryModuleVersion.$moduleName
        $overriddenModuleVersion = $overriddenModule.$runtimeVersion
        if ($overriddenModuleVersion) {
            _write " (no version specified and override for version exists, hence will be used ($overriddenModuleVersion))"
            $moduleVersion = $overriddenModuleVersion
        }
    }

    if (!$moduleVersion) {
        $moduleVersion = $moduleGalleryInfo.Version
        _write " (no version specified, newest supported version from PSGallery will be used ($moduleVersion))"
    }

    Write-Verbose "Getting current Automation modules"
    $currentAutomationModules = Get-AzAutomationModule -AutomationAccountName $automationAccountName -ResourceGroup $resourceGroupName -RuntimeVersion $runtimeVersion -ErrorAction Stop

    # check whether required module is present
    # there can be module in Failed state, just because update of such module failed, but if it has SizeInBytes set, it means its in working state
    $moduleExists = $currentAutomationModules | ? { $_.Name -eq $moduleName -and $_.SizeInBytes }
    if ($moduleVersion) {
        $moduleExists = $moduleExists | ? Version -EQ $moduleVersion
    }

    if ($moduleExists) {
        return ($indentString + "Module $moduleName ($($moduleExists.Version)) is already present")
    }

    _write " - Getting module $moduleName dependencies"
    $moduleDependency = $moduleGalleryInfo.Dependencies | Sort-Object { $_.name }

    # dependency must be installed first
    if ($moduleDependency) {
        #TODO znacit si jake moduly jsou required (at uz tam jsou nebo musim doinstalovat) a kontrolovat, ze jeden neni required s ruznymi verzemi == konflikt protoze nainstalovana muze byt jen jedna
        _write "  - Depends on: $($moduleDependency.Name -join ', ')"
        foreach ($module in $moduleDependency) {
            $requiredModuleName = $module.Name
            [version]$requiredModuleMinVersion = $module.MinimumVersion
            [version]$requiredModuleMaxVersion = $module.MaximumVersion
            [version]$requiredModuleReqVersion = $module.RequiredVersion
            $notInCorrectVersion = $false

            _write "   - Checking module $requiredModuleName (minVer: $requiredModuleMinVersion maxVer: $requiredModuleMaxVersion reqVer: $requiredModuleReqVersion)"

            # there can be module in Failed state, just because update of such module failed, but if it has SizeInBytes set, it means its in working state
            $existingRequiredModule = $currentAutomationModules | ? { $_.Name -eq $requiredModuleName -and ($_.ProvisioningState -eq "Succeeded" -or $_.SizeInBytes) }
            [version]$existingRequiredModuleVersion = $existingRequiredModule.Version

            # check that existing module version fits
            if ($existingRequiredModule -and ($requiredModuleMinVersion -or $requiredModuleMaxVersion -or $requiredModuleReqVersion)) {

                #TODO pokud nahrazuji existujici modul, tak bych se mel podivat, jestli jsou vsechny ostatni ok s jeho novou verzi
                if ($requiredModuleReqVersion -and $requiredModuleReqVersion -ne $existingRequiredModuleVersion) {
                    $notInCorrectVersion = $true
                    _write "     - module exists, but not in the correct version (has: $existingRequiredModuleVersion, should be: $requiredModuleReqVersion). Will be replaced" "Yellow"
                } elseif ($requiredModuleMinVersion -and $requiredModuleMaxVersion -and ($existingRequiredModuleVersion -lt $requiredModuleMinVersion -or $existingRequiredModuleVersion -gt $requiredModuleMaxVersion)) {
                    $notInCorrectVersion = $true
                    _write "     - module exists, but not in the correct version (has: $existingRequiredModuleVersion, should be: $requiredModuleMinVersion .. $requiredModuleMaxVersion). Will be replaced" "Yellow"
                } elseif ($requiredModuleMinVersion -and $existingRequiredModuleVersion -lt $requiredModuleMinVersion) {
                    $notInCorrectVersion = $true
                    _write "     - module exists, but not in the correct version (has: $existingRequiredModuleVersion, should be > $requiredModuleMinVersion). Will be replaced" "Yellow"
                } elseif ($requiredModuleMaxVersion -and $existingRequiredModuleVersion -gt $requiredModuleMaxVersion) {
                    $notInCorrectVersion = $true
                    _write "     - module exists, but not in the correct version (has: $existingRequiredModuleVersion, should be < $requiredModuleMaxVersion). Will be replaced" "Yellow"
                }
            }

            if (!$existingRequiredModule -or $notInCorrectVersion) {
                if (!$existingRequiredModule) {
                    _write "     - module is missing" "Yellow"
                }

                if ($notInCorrectVersion) {
                    #TODO kontrola, ze jina verze modulu nerozbije zavislost nejakeho jineho existujiciho modulu
                }

                #region install required module first
                $param = @{
                    moduleName            = $requiredModuleName
                    resourceGroupName     = $resourceGroupName
                    automationAccountName = $automationAccountName
                    runtimeVersion        = $runtimeVersion
                    indent                = $indent + 1
                }
                if ($requiredModuleMinVersion) {
                    $param.moduleVersion = $requiredModuleMinVersion
                }
                if ($requiredModuleMaxVersion) {
                    $param.moduleVersion = $requiredModuleMaxVersion
                }
                if ($requiredModuleReqVersion) {
                    $param.moduleVersion = $requiredModuleReqVersion
                }

                New-AzureAutomationModule @param
                #endregion install required module first
            } else {
                if ($existingRequiredModuleVersion) {
                    _write "     - module (ver. $existingRequiredModuleVersion) is already present"
                } else {
                    _write "     - module is already present"
                }
            }
        }
    } else {
        _write "  - No dependency found"
    }

    $uri = "https://www.powershellgallery.com/api/v2/package/$moduleName/$moduleVersion"
    _write " - Uploading module $moduleName ($moduleVersion)" "Yellow"
    $status = New-AzAutomationModule -AutomationAccountName $automationAccountName -ResourceGroup $resourceGroupName -Name $moduleName -ContentLinkUri $uri -RuntimeVersion $runtimeVersion

    $i = 0
    do {
        if ($i % 5 -eq 0) {
            _write "    Still working..."
        }

        Start-Sleep 5

        ++$i
    } while (!($requiredModule = Get-AzAutomationModule -AutomationAccountName $automationAccountName -ResourceGroup $resourceGroupName -RuntimeVersion $runtimeVersion -ErrorAction Stop | ? { $_.Name -eq $moduleName -and $_.ProvisioningState -in "Succeeded", "Failed" }))

    if ($requiredModule.ProvisioningState -ne "Succeeded") {
        Write-Error "Import failed. Check Azure Portal >> Automation Account >> Modules >> $moduleName details to get the reason."
    } else {
        _write " - Success" "Green"
    }
}

function Open-AzureAdminConsentPage {
    <#
    .SYNOPSIS
    Function for opening web page with admin consent to requested/selected permissions to selected application.

    .DESCRIPTION
    Function for opening web page with admin consent to requested/selected permissions to selected application.

    .PARAMETER appId
    Application (client) ID.

    .PARAMETER tenantId
    Your Azure tenant ID.

    .EXAMPLE
    Open-AzureAdminConsentPage -appId 123412341234 -scope openid, profile, email, user.read, Mail.Send

    Grant admin consent for selected permissions to app with client ID 123412341234.

    .EXAMPLE
    Open-AzureAdminConsentPage -appId 123412341234

    Grant admin consent for requested permissions to app with client ID 123412341234.

    .NOTES
    https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/grant-admin-consent
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $appId,

        [string] $tenantId = $_tenantId,

        [string[]] $scope,

        [switch] $justURL
    )

    if ($scope) {
        # grant custom permission
        $scope = $scope.trim() -join "%20"
        $URL = "https://login.microsoftonline.com/$tenantId/v2.0/adminconsent?client_id=$appId&scope=$scope"

        if ($justURL) {
            return $URL
        } else {
            Start-Process $URL
        }
    } else {
        # grant requested permissions
        $URL = "https://login.microsoftonline.com/$tenantId/adminconsent?client_id=$appId"
        if ($justURL) {
            return $URL
        } else {
            Start-Process $URL
        }
    }
}

function Remove-AzureAccountOccurrence {
    <#
    .SYNOPSIS
    Function for removal of selected AAD account occurrences in various parts of AAD.

    .DESCRIPTION
    Function for removal of selected AAD account occurrences in various parts of AAD.

    .PARAMETER inputObject
    PSCustomObject that is outputted by Get-AzureAccountOccurrence function.
    Contains information about account and its occurrences i.e. is used in this function as information about what to remove and from where.

    Object (as a output of Get-AzureAccountOccurrence) should have these properties:
        UPN
        DisplayName
        ObjectType
        ObjectId
        IAM
        MemberOfDirectoryRole
        MemberOfGroup
        PermissionConsent
        Owner
        SharepointSiteOwner
        AppUsersAndGroupsRoleAssignment
        KeyVaultAccessPolicy
        ExchangeRole

    .PARAMETER replaceByUser
    (optional) ObjectId or UPN of the AAD user that will replace processed user as a new owner/manager.
    But if there are other owners, the one being removed won't be replaced, just deleted!

    Cannot be used with replaceByManager.

    .PARAMETER replaceByManager
    Switch for using user's manager as a new owner/manager.
    Applies ONLY for processed USERS (because only users have managers) and not other object types!

    If there are other owners, the one being removed won't be replaced, just deleted!

    Cannot be used with replaceByUser.

    .PARAMETER whatIf
    Switch for omitting any changes, just output what would be done.

    .PARAMETER removeRegisteredDevice
    Switch for removal of registered devices. Otherwise registered devices stays intact.

    This doesn't apply to joined device.

    .PARAMETER informNewManOwn
    Switch for sending email notification to new owners/managers about what and why was transferred to them.

    .EXAMPLE
    Get-AzureAccountOccurrence -userPrincipalName pavel@contoso.com | Remove-AzureAccountOccurrence -whatIf

    Get all occurrences of specified user and just output what would be done with them.

    .EXAMPLE
    Get-AzureAccountOccurrence -userPrincipalName pavel@contoso.com | Remove-AzureAccountOccurrence

    Get all occurrences of specified user and remove them.
    In case user has registered some devices, they stay intact.

    .EXAMPLE
    Get-AzureAccountOccurrence -userPrincipalName pavel@contoso.com | Remove-AzureAccountOccurrence -removeRegisteredDevice

    Get all occurrences of specified user and remove them.
    In case user has registered some devices, they will be deleted.

    .EXAMPLE
    Get-AzureAccountOccurrence -userPrincipalName pavel@contoso.com | Remove-AzureAccountOccurrence -replaceByUser 1234-1234-1234-1234

    Get all occurrences of specified user and remove them.
    In case user is owner or manager on some object(s) he will be replaced there by specified user (for ownerships this apply only if removed user is last owner).
    In case user has registered some devices, they stay intact.

    .EXAMPLE
    Get-AzureAccountOccurrence -userPrincipalName pavel@contoso.com | Remove-AzureAccountOccurrence -replaceByManager

    Get all occurrences of specified user and remove them.
    In case user is owner or manager on some object(s) he will be replaced there by his manager (for ownerships this apply only if removed user is last owner).
    In case user has registered some devices, they stay intact.
    #>

    [CmdletBinding()]
    [Alias("Remove-AzureADAccountOccurrence")]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject] $inputObject,

        [string] $replaceByUser,

        [switch] $replaceByManager,

        [switch] $whatIf,

        [switch] $removeRegisteredDevice,

        [switch] $informNewManOwn
    )

    begin {
        if ($replaceByUser -and $replaceByManager) {
            throw "replaceByUser and replaceByManager cannot be used together. Choose one of them."
        }

        if ($informNewManOwn -and (!$replaceByUser -and !$replaceByManager)) {
            Write-Warning "Parameter 'informNewManOwn' will be ignored because no replacements will be made."
            $informNewManOwn = $false
        }

        #region connect
        # connect to AzureAD
        Write-Verbose "Connecting to AzureAD"
        $null = Connect-MgGraph -ea Stop -Scopes Directory.AccessAsUser.All, GroupMember.ReadWrite.All, User.Read.All, GroupMember.ReadWrite.All, DelegatedPermissionGrant.ReadWrite.All, Application.ReadWrite.All, AppRoleAssignment.ReadWrite.All

        Write-Verbose "Connecting to AzAccount"
        $null = Connect-AzAccount2 -ea Stop

        # connect sharepoint online
        if ($inputObject.SharepointSiteOwner) {
            Write-Verbose "Connecting to Sharepoint"
            Connect-PnPOnline2 -asMFAUser -ea Stop
        }

        if ($inputObject.ExchangeRole -or $inputObject.MemberOfGroup.MailEnabled) {
            Write-Verbose "Connecting to Exchange"
            Connect-O365 -service exchange -ea Stop
        }
        #endregion connect

        if ($informNewManOwn) {
            $newManOwnReport = @()
        }
    }

    process {
        # check replacement user account
        if ($replaceByUser) {
            $replacementAADAccountObj = Get-MgUser -UserId $replaceByUser
            if (!$replacementAADAccountObj) {
                throw "Replacement account $replaceByUser was not found in AAD"
            } else {
                $replacementAADAccountId = $replacementAADAccountObj.Id
                $replacementAADAccountDisplayName = $replacementAADAccountObj.DisplayName

                Write-Warning "'$replacementAADAccountDisplayName' will be new manager/owner instead of account that is being removed"
            }
        }

        $inputObject | % {
            <#
            Object (as a output of Get-AzureAccountOccurrence) should have these properties:
                UPN
                DisplayName
                ObjectType
                ObjectId
                IAM
                MemberOfDirectoryRole
                MemberOfGroup
                PermissionConsent
                Owner
                SharepointSiteOwner
                AppUsersAndGroupsRoleAssignment
                KeyVaultAccessPolicy
                ExchangeRole
            #>

            $accountId = $_.ObjectId
            $accountDisplayName = $_.DisplayName

            "Processing cleanup on account '$accountDisplayName' ($accountId)"

            $AADAccountObj = Get-MgDirectoryObjectById -Ids $accountId
            if (!$AADAccountObj) {
                Write-Error "Account $accountId was not found in AAD"
            }

            if ($replaceByManager) {
                if ($_.ObjectType -eq 'user') {
                    $replacementAADAccountObj = Get-MgUserManager -UserId $accountId | Expand-MgAdditionalProperties # so the $replacementAADAccountObj have user properties at root level therefore looks same as when Get-MgUser is used (because of $replaceByUser)
                    if (!$replacementAADAccountObj) {
                        throw "Account '$accountDisplayName' doesn't have a manager. Specify replacement account via 'replaceByUser' parameter?"
                    } else {
                        $replacementAADAccountId = $replacementAADAccountObj.Id
                        $replacementAADAccountDisplayName = $replacementAADAccountObj.DisplayName

                        Write-Warning "User's manager '$replacementAADAccountDisplayName' will be new manager/owner instead of account that is being removed"
                    }
                } else {
                    Write-Warning "Account $accountId isn't a user ($($_.ObjectType)). Parameter 'replaceByManager' will be ignored."
                }
            }


            # prepare base object for storing data for later email notification
            if ($informNewManOwn -and $replacementAADAccountObj) {
                $newManOwnObj = [PSCustomObject]@{
                    replacedUserObjectId = $accountId
                    replacedUserName     = $accountDisplayName
                    newUserEmail         = $replacementAADAccountObj.mail
                    newUserName          = $replacementAADAccountDisplayName
                    newUserObjectId      = $replacementAADAccountId
                    message              = @()
                }
            }

            #region remove AAD account occurrences

            #region IAM
            if ($_.IAM) {
                Write-Verbose "Removing IAM assignments"
                $tenantId = (Get-AzContext).tenant.id

                $_.IAM | select ObjectId, AssignmentScope, RoleDefinitionName -Unique | % {
                    # $Context = Set-AzContext -TenantId $tenantId -SubscriptionId $_.SubscriptionId -Force
                    "Removing IAM role '$($_.RoleDefinitionName)' at scope '$($_.AssignmentScope)'"
                    if (!$whatIf) {
                        $lock = Get-AzResourceLock -Scope $_.AssignmentScope
                        if ($lock) {
                            Write-Warning "Unable to delete IAM role, because resource is LOCKED via '$($lock.name)' lock"
                        } else {
                            Remove-AzRoleAssignment -ObjectId $_.ObjectId -Scope $_.AssignmentScope -RoleDefinitionName $_.RoleDefinitionName
                        }
                    }
                }
            }
            #endregion IAM

            #region group membership
            if ($_.MemberOfGroup) {
                $_.MemberOfGroup | % {
                    if ($_.onPremisesSyncEnabled) {
                        Write-Warning "Skipping removal from group '$($_.displayName)' ($($_.id)), because it is synced from on-premises AD"
                    } elseif ($_.membershipRule) {
                        Write-Warning "Skipping removal from group '$($_.displayName)' ($($_.id)), because it has rule-based membership"
                    } else {
                        "Removing from group '$($_.displayName)' ($($_.id))"
                        if (!$whatIf) {
                            if ($_.mailEnabled -and !$_.groupTypes) {
                                # distribution group
                                Remove-DistributionGroupMember -Identity $_.id -Member $accountId -BypassSecurityGroupManagerCheck -Confirm:$false
                            } else {
                                # Microsoft 365 group
                                Remove-MgGroupMemberByRef -GroupId $_.id -DirectoryObjectId $accountId
                            }
                        }
                    }
                }
            }
            #endregion group membership

            #region membership directory role
            if ($_.MemberOfDirectoryRole) {
                $_.MemberOfDirectoryRole | % {
                    "Removing from directory role '$($_.displayName)' ($($_.id))"
                    if (!$whatIf) {
                        Remove-MgDirectoryRoleScopedMember -DirectoryRoleId $_.id -ScopedRoleMembershipId $accountId
                    }
                }
            }
            #endregion membership directory role

            #region user perm consents
            if ($_.PermissionConsent) {
                $_.PermissionConsent | % {
                    "Removing user consent from app '$($_.AppName)', permission '$($_.scope)' to '$($_.ResourceDisplayName)'"
                    if (!$whatIf) {
                        Remove-MgOauth2PermissionGrant -OAuth2PermissionGrantId $_.Id
                    }
                }
            }
            #endregion user perm consents

            #region manager
            if ($_.Manager) {
                $_.Manager | % {
                    $managerOf = $_
                    $managerOfObjectType = $managerOf.ObjectType
                    $managerOfDisplayName = $managerOf.DisplayName
                    $managerOfObjectId = $managerOf.Id

                    switch ($managerOfObjectType) {
                        User {
                            "Removing as a manager of the $managerOfObjectType '$managerOfDisplayName' ($managerOfObjectId)"
                            if (!$whatIf) {
                                Remove-MgUserManagerByRef -UserId $managerOfObjectId
                            }
                            if ($replacementAADAccountObj) {
                                "Adding '$replacementAADAccountDisplayName' as a manager of the $managerOfObjectType '$managerOfDisplayName' ($managerOfObjectId)"
                                if (!$whatIf) {
                                    $newManager = @{
                                        "@odata.id" = "https://graph.microsoft.com/v1.0/users/$replacementAADAccountId"
                                    }

                                    Set-MgUserManagerByRef -UserId $managerOfObjectId -BodyParameter $newManager

                                    if ($informNewManOwn) {
                                        $newManOwnObj.message += @("new manager of the $managerOfObjectType '$managerOfDisplayName' ($managerOfObjectId)")
                                    }
                                }
                            }
                        }

                        Contact {
                            "Removing as a manager of the $managerOfObjectType '$managerOfDisplayName' ($managerOfObjectId)"
                            if (!$whatIf) {
                                Write-Warning "Remove manager of the $managerOfObjectType '$managerOfDisplayName' ($managerOfObjectId) manually!"
                            }
                            if ($replacementAADAccountObj) {
                                Write-Warning "Add '$replacementAADAccountDisplayName' as a manager of the $managerOfObjectType '$managerOfDisplayName' ($managerOfObjectId) manually!"
                            }
                        }

                        default {
                            Write-Error "Not defined action for object type $managerOfObjectType. User won't be removed as a manager of this object."
                        }
                    }
                }
            }
            #endregion manager

            #region ownership
            # application, group, .. owner
            if ($_.Owner) {
                $_.Owner | % {
                    $ownerOf = $_
                    $ownerOfObjectType = $ownerOf.ObjectType
                    $ownerOfDisplayName = $ownerOf.DisplayName
                    $ownerOfObjectId = $ownerOf.Id

                    switch ($ownerOfObjectType) {
                        Application {
                            # app registration
                            "Removing owner from app registration '$ownerOfDisplayName'"
                            if (!$whatIf) {
                                $null = Remove-MgApplicationOwnerByRef -ApplicationId $ownerOfObjectId -DirectoryObjectId $accountId
                            }

                            if ($replacementAADAccountObj) {
                                $recentObjOwner = Get-MgApplicationOwner -ApplicationId $ownerOfObjectId -All | ? Id -NE $accountId
                                if (!$recentObjOwner) {
                                    "Adding '$replacementAADAccountDisplayName' as owner of the '$ownerOfDisplayName' application"
                                    if (!$whatIf) {
                                        $newOwner = @{
                                            "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$replacementAADAccountId"
                                        }
                                        New-MgApplicationOwnerByRef -ApplicationId $ownerOfObjectId -BodyParameter $NewOwner

                                        if ($informNewManOwn) {
                                            $appId = Get-MgApplication -ApplicationId $ownerOfObjectId | select -ExpandProperty AppId
                                            $url = "https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/Overview/appId/$appId"
                                            $newManOwnObj.message += @("new owner of the '$ownerOfDisplayName' application ($url)")
                                        }
                                    }
                                } else {
                                    Write-Warning "App registration has some owners left. '$replacementAADAccountDisplayName' won't be added."
                                }
                            }
                        }

                        ServicePrincipal {
                            # enterprise apps owner
                            "Removing owner from service principal '$ownerOfDisplayName'"
                            if (!$whatIf) {
                                Remove-MgServicePrincipalOwnerByRef -ServicePrincipalId $ownerOfObjectId -DirectoryObjectId $accountId
                            }

                            if ($replacementAADAccountObj) {
                                $recentObjOwner = Get-MgServicePrincipalOwner -ServicePrincipalId $ownerOfObjectId -All | ? Id -NE $accountId
                                if (!$recentObjOwner) {
                                    "Adding '$replacementAADAccountDisplayName' as owner of the '$ownerOfDisplayName' service principal"
                                    if (!$whatIf) {
                                        $newOwner = @{
                                            "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/{$replacementAADAccountId}"
                                        }
                                        New-MgServicePrincipalOwnerByRef -ServicePrincipalId $ownerOfObjectId -BodyParameter $newOwner

                                        if ($informNewManOwn) {
                                            $appId = Get-MgServicePrincipal -ServicePrincipalId $ownerOfObjectId | select -ExpandProperty AppId
                                            $url = "https://portal.azure.com/#blade/Microsoft_AAD_IAM/ManagedAppMenuBlade/Overview/objectId/$ownerOfObjectId/appId/$appId"
                                            $newManOwnObj.message += @("new owner of the '$ownerOfDisplayName' service principal ($url)")
                                        }
                                    }
                                } else {
                                    Write-Warning "Service principal has some owners left. '$replacementAADAccountDisplayName' won't be added."
                                }
                            }
                        }

                        Group {
                            # adding new owner before removing the old one because group won't let you remove last owner
                            if ($replacementAADAccountObj) {
                                $recentObjOwner = Get-MgGroupOwner -GroupId $ownerOfObjectId -All | ? Id -NE $accountId
                                if (!$recentObjOwner) {
                                    "Adding '$replacementAADAccountDisplayName' as owner of the '$ownerOfDisplayName' group"
                                    if (!$whatIf) {
                                        $newOwner = @{
                                            "@odata.id" = "https://graph.microsoft.com/v1.0/users/{$replacementAADAccountId}"
                                        }
                                        New-MgGroupOwnerByRef -GroupId $ownerOfObjectId -BodyParameter $newOwner

                                        if ($informNewManOwn) {
                                            $url = "https://portal.azure.com/#blade/Microsoft_AAD_IAM/GroupDetailsMenuBlade/Overview/groupId/$ownerOfObjectId"
                                            $newManOwnObj.message += @("new owner of the '$ownerOfDisplayName' group ($url)")
                                        }
                                    }
                                } else {
                                    Write-Warning "Group has some owners left. '$replacementAADAccountDisplayName' won't be added."
                                }
                            }

                            "Removing owner from group '$ownerOfDisplayName'"
                            if (!$whatIf) {
                                Remove-MgGroupOwnerByRef -GroupId $ownerOfObjectId -DirectoryObjectId $accountId
                            }
                        }

                        Device {
                            if ($ownerOf.DeviceTrustType -eq 'Workplace') {
                                # registered device
                                if ($removeRegisteredDevice) {
                                    "Removing registered device '$ownerOfDisplayName' ($ownerOfObjectId)"
                                    if (!$whatIf) {
                                        Remove-MgDevice -DeviceId $ownerOfObjectId
                                    }
                                } else {
                                    Write-Warning "Registered device '$ownerOfDisplayName' won't be deleted nor owner of this device will be removed"
                                }
                            } else {
                                # joined device
                                "Removing owner from device '$ownerOfDisplayName' ($ownerOfObjectId)"
                                if (!$whatIf) {
                                    Remove-MgDeviceRegisteredOwnerByRef -DeviceId $ownerOfObjectId -DirectoryObjectId $accountId
                                }
                            }

                            if ($replacementAADAccountObj) {
                                Write-Verbose "Device owner won't be replaced by '$replacementAADAccountDisplayName' because I don't want to"
                            }
                        }

                        default {
                            Write-Error "Not defined action for object type $ownerOfObjectType. User won't be removed as a owner of this object."
                        }
                    }
                }
            }

            # sharepoint sites owner
            if ($_.SharepointSiteOwner) {
                $_.SharepointSiteOwner | % {
                    if ($_.template -like 'GROUP*') {
                        # it is sharepoint site based on group (owners are group members)
                        "Removing from group '$($_.Title)' that has owner rights on Sharepoint site '$($_.Site)'"
                        if (!$whatIf) {
                            Remove-PnPMicrosoft365GroupOwner -Identity $_.GroupId -Users $userPrincipalName
                        }

                        if ($replacementAADAccountObj) {
                            $recentObjOwner = Get-PnPMicrosoft365GroupOwner -Identity $_.GroupId -All:$true | ? Id -NE $accountId
                            if (!$recentObjOwner) {
                                "Adding '$replacementAADAccountDisplayName' as owner of the '$($_.Title)' group"
                                if (!$whatIf) {
                                    Add-PnPMicrosoft365GroupOwner -Identity $_.GroupId -Users $replacementAADAccountObj.UserPrincipalName

                                    if ($informNewManOwn) {
                                        $url = "https://portal.azure.com/#blade/Microsoft_AAD_IAM/GroupDetailsMenuBlade/Overview/groupId/$($_.GroupId)"
                                        $newManOwnObj.message += @("new owner of the '$($_.Title)' group ($url)")
                                    }
                                }
                            } else {
                                Write-Warning "Sharepoint site has some owners left. '$replacementAADAccountDisplayName' won't be added."
                            }
                        }
                    } else {
                        # it is common sharepoint site
                        Write-Warning "Remove owner from Sharepoint site '$($_.site)' manually!"
                        # "Removing from sharepoint site '$($_.site)'"
                        # https://www.sharepointdiary.com/2018/02/change-site-owner-in-sharepoint-online-using-powershell.html
                        # https://www.sharepointdiary.com/2020/05/sharepoint-online-grant-site-owner-permission-to-user-with-powershell.html

                        if ($replacementAADAccountObj) {
                            Write-Warning "Add '$($replacementAADAccountObj.UserPrincipalName)' as new owner at Sharepoint site '$($_.site)' manually!"
                            # "Adding '$replacementAADAccountDisplayName' as owner of the '$($_.site)' sharepoint site"
                            # Set-SPOSite https://contoso.sharepoint.com/sites/otest_communitysite_test_smazani -Owner admin@contoso.com # zda se ze funguje, ale vyzaduje Connect-SPOService -Url $_SPOConnectionUri
                            # Set-PnPSite -Identity $_.site -Owners $replacementAADAccountObj.UserPrincipalName # prida jen jako admina..ne primary admina (ownera)
                            # Set-PnPTenantSite -Identity $_.site -Owners $replacementAADAccountObj.UserPrincipalName # prida jen jako admina..ne primary admina (ownera)
                        }
                    }
                }
            }
            #endregion ownership

            #region app Users and groups role assignments
            if ($_.AppUsersAndGroupsRoleAssignment) {
                $_.AppUsersAndGroupsRoleAssignment | % {
                    "Removing $($_.PrincipalType) from app's '$($_.ResourceDisplayName)' role '$($_.AppRoleDisplayName)'"
                    if (!$whatIf) {
                        Remove-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $_.ResourceId -AppRoleAssignmentId $_.Id
                    }
                }
            }
            #endregion app Users and groups role assignments

            #region devops
            if ($_.DevOpsOrganizationOwner) {
                $_.DevOpsOrganizationOwner | % {
                    Write-Warning "Remove owner of DevOps organization '$($_.OrganizationName))' manually!"
                    if ($replacementAADAccountObj) {
                        Write-Warning "Add '$($replacementAADAccountObj.UserPrincipalName)' as new owner of the DevOps organization '$($_.OrganizationName))' manually!"
                    }
                }
            }

            if ($_.DevOpsMemberOf) {
                $header = New-AzureDevOpsAuthHeader

                $_.DevOpsMemberOf | % {
                    $accountDescriptor = $_.Descriptor
                    $organizationName = $_.OrganizationName
                    $_.memberOf | % {
                        $groupDescriptor = $_.descriptor
                        "Removing from DevOps organization's '$organizationName' group '$($_.principalName)'"

                        if (!$whatIf) {
                            $result = Invoke-WebRequest -Uri "https://vssps.dev.azure.com/$organizationName/_apis/graph/memberships/$accountDescriptor/$($groupDescriptor)?api-version=7.1-preview.1" -Method delete -ContentType "application/json" -Headers $header
                            if ($result.StatusCode -ne 200) {
                                Write-Error "Removal of account '$accountDisplayName' in DevOps organization '$organizationName' from group '$($_.displayName)' wasn't successful. Do it manually!"
                            }
                        }
                    }
                }
            }
            #endregion devops

            #region keyVaultAccessPolicy
            if ($_.KeyVaultAccessPolicy) {
                $_.KeyVaultAccessPolicy | % {
                    $vaultName = $_.VaultName
                    $removedObjectId = $_.AccessPolicies.ObjectId | select -Unique
                    "Removing Access from KeyVault $vaultName for '$removedObjectId'"

                    if (!$whatIf) {
                        Remove-AzKeyVaultAccessPolicy -VaultName $vaultName -ObjectId $removedObjectId -WarningAction SilentlyContinue
                    }
                }
            }
            #endregion keyVaultAccessPolicy

            #region exchangeRole
            if ($_.ExchangeRole) {
                $_.ExchangeRole | % {
                    $roleName = $_.name
                    $roleDN = $_.RoleDisplayName
                    if ($_.capabilities -eq 'Partner_Managed') {
                        Write-Warning "Skipping removal of account '$($_.Identity)' from Exchange role $roleName. Role is not managed by Exchange, but via some external entity"
                    } else {
                        "Removing account '$($_.Identity)' from Exchange role '$roleName' ($roleDN)"

                        if (!$whatIf) {
                            Remove-RoleGroupMember -Confirm:$false -Identity $roleName -Member $_.Identity -BypassSecurityGroupManage
                            rCheck
                        }
                    }
                }
            }
            #endregion exchangeRole

            #endregion remove AAD account occurrences

            # save object with made changes for later email notification
            if ($informNewManOwn -and $replacementAADAccountObj) {
                $newManOwnReport += $newManOwnObj
            }
        }
    }

    end {
        if ($informNewManOwn -and $newManOwnReport.count) {
            $newManOwnReport | % {
                if ($_.message) {
                    # there were some changes in ownership
                    if ($_.newUserEmail) {
                        # new owner/manager has email address defined
                        if ($replaceByManager) {
                            $newUserRole = "as his/her manager"
                        } else {
                            $newUserRole = "as chosen successor"
                        }

                        $body = "Hi,`nemployee '$($_.replacedUserName)' left the company and you $newUserRole are now:`n`n$(($_.message | % {" - $_"}) -join "`n")`n`nThese changes are related to Azure environment.`n`n`Sincerely your IT"

                        Write-Warning "Sending email to: $($_.newUserEmail) body:`n`n$body"
                        Send-Email -to $_.newUserEmail -subject "Notification of new Azure assets responsibility" -body $body
                    } else {
                        Write-Warning "Cannot inform new owner/manager '$($_.newUserName)' about transfer of Azure asset from '$($_.replacedUserName)'. Email address is missing.`n`n$($_.message -join "`n")"
                    }
                } else {
                    Write-Verbose "No asset was transferred to the '$($_.newUserName)' from the '$($_.replacedUserName)'"
                }
            }
        }
    }
}

function Remove-AzureAppUserConsent {
    <#
    .SYNOPSIS
    Function for removing permission consents.

    .DESCRIPTION
    Function for removing permission consents.

    For selected OAuth2PermissionGrantId(s) or OGV with filtered grants will be shown (based on servicePrincipalObjectId, principalObjectId, resourceObjectId you specify).

    .PARAMETER OAuth2PermissionGrantId
    ID of the OAuth permission grant(s).

    .PARAMETER servicePrincipalObjectId
    ObjectId of the enterprise app for which was the consent given.

    .PARAMETER principalObjectId
    ObjectId of the user which have given the consent.

    .PARAMETER resourceObjectId
    ObjectId of the resource to which the consent have given permission to.

    .EXAMPLE
    Remove-AzureAppUserConsent -OAuth2PermissionGrantId L5awNI6RwE-QWiIIWcNMqYIrr-lfQ2BBnaYK1kev_X5Q2a7DBw0rSKTgiBsrZi4z

    Consent with ID L5awNI6RwE-QWiIIWcNMqYIrr-lfQ2BBnaYK1kev_X5Q2a7DBw0rSKTgiBsrZi4z will be deleted.

    .EXAMPLE
    Remove-AzureAppUserConsent

    OGV with all grants will be shown and just selected consent(s) will be deleted.

    .EXAMPLE
    Remove-AzureAppUserConsent -principalObjectId 1234 -servicePrincipalObjectId 5678

    OGV with consent(s) related to user with ID 1234 and enterprise application with ID 5678 will be shown and just selected consent(s) will be deleted.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "id")]
        [string[]] $OAuth2PermissionGrantId,

        [Parameter(ParameterSetName = "filter")]
        [string] $servicePrincipalObjectId,

        [Parameter(ParameterSetName = "filter")]
        [string] $principalObjectId,

        [Parameter(ParameterSetName = "filter")]
        [string] $resourceObjectId
    )

    $null = Connect-MgGraph -ea Stop

    $objectByObjectId = @{}
    function GetObjectByObjectId ($objectId) {
        if (!$objectByObjectId.ContainsKey($objectId)) {
            Write-Verbose ("Querying Azure AD for object '{0}'" -f $objectId)
            try {
                $object = Get-MgDirectoryObjectById -Ids $objectId -ea stop
                $objectByObjectId.$objectId = $object
                return $object
            } catch {
                Write-Verbose "Object not found."
            }
        }
        return $objectByObjectId.$objectId
    }

    if ($OAuth2PermissionGrantId) {
        $OAuth2PermissionGrantId | % {
            Remove-MgOauth2PermissionGrant -OAuth2PermissionGrantId $_ -Confirm:$true
        }
    } else {
        $filter = ""

        if ($servicePrincipalObjectId) {
            if ($filter) { $filter = $filter + " and " }
            $filter = $filter + "clientId eq '$servicePrincipalObjectId'"
        }
        if ($principalObjectId) {
            if ($filter) { $filter = $filter + " and " }
            $filter = $filter + "principalId eq '$principalObjectId'"
        }
        if ($resourceObjectId) {
            if ($filter) { $filter = $filter + " and " }
            $filter = $filter + "resourceId eq '$resourceObjectId'"
        }

        $param = @{}
        if ($filter) { $param.filter = $filter }

        Get-MgOauth2PermissionGrant @param -Property ClientId, ConsentType, PrincipalId, ResourceId, Scope, Id | select @{n = 'App'; e = { (GetObjectByObjectId $_.ClientId).DisplayName } }, ConsentType, @{n = 'Principal'; e = { (GetObjectByObjectId $_.PrincipalId).DisplayName } }, @{n = 'Resource'; e = { (GetObjectByObjectId $_.ResourceId).DisplayName } }, Scope, Id | Out-GridView -OutputMode Multiple | % {
            Remove-MgOauth2PermissionGrant -OAuth2PermissionGrantId $_.Id -Confirm:$true
        }
    }
}

function Remove-AzureUserMemberOfDirectoryRole {
    <#
    .SYNOPSIS
    Function for removing given user from given Directory role.

    .DESCRIPTION
    Function for removing given user from given Directory role.

    .PARAMETER userId
    ID of the user.

    Can be retrieved using Get-MgUser.

    .PARAMETER roleId
    ID of the Directory role.

    Can be retrieved using Get-MgUserMemberOf.

    .EXAMPLE
    $aadUser = Get-MgUser -Filter "userPrincipalName eq '$UPN'"

    Get-MgUserMemberOf -UserId $aadUser.id -All | ? { $_.AdditionalProperties.'@odata.type' -eq "#microsoft.graph.directoryRole" } | % {
        Remove-AzureUserMemberOfDirectoryRole -userId $aadUser.id -roleId $_.id
    }
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $userId,
        [Parameter(Mandatory = $true)]
        [string] $roleId
    )

    # Use this endpoint when using the role Id
    $uri = "https://graph.microsoft.com/v1.0/directoryRoles/$roleId/members/$userId/`$ref"

    # Use this endpoint when using the role template ID
    # $uri = "https://graph.microsoft.com/v1.0/directoryRoles/roleTemplateId=$roleTemplateId/members/$userId/`$ref"

    $params = @{
        Headers = (New-GraphAPIAuthHeader -ea Stop)
        Method  = "Delete"
        Uri     = $uri
    }

    Write-Verbose "Invoking DELETE method against '$uri'"
    Invoke-RestMethod @params
}

function Revoke-AzureServicePrincipalPermission {
    <#
    .SYNOPSIS
    Function for revoking granted application/delegated permissions from selected account.

    .DESCRIPTION
    Function for revoking granted application/delegated permissions from selected account.

    .PARAMETER servicePrincipalName
    Name of the service principal you want to revoke permission(s) from.

    .PARAMETER servicePrincipalId
    ObjectId of the service principal you want to revoke permissions(s) from.

    .PARAMETER resourceAppId
    ObjectId of the resource you want to revoke permission(s).

    By default ObjectId of the Graph API resource a.k.a. GraphAggregatorService service principal.


    .PARAMETER permissionList
    List of permissions you want to revoke.

    If not defined, Out-GridView table with all available permissions (of type defined in permissionType) will be interactively outputted, so the user can pick some.

    .PARAMETER permissionType
    Type of permission you want to revoke.

    Possible values are application, delegated.

    By default application is selected.

    .PARAMETER all
    Switch to remove all permissions (of type defined in permissionType parameter).

    .EXAMPLE
    Revoke-AzureServicePrincipalPermission -servicePrincipalName "otest" -permissionList AgreementAcceptance.Read.All

    Revoke 'application' permission 'AgreementAcceptance.Read.All' for Graph Api resource from 'otest' ent. app (service principal)

    .EXAMPLE
    Revoke-AzureServicePrincipalPermission -servicePrincipalName "otest"

    Shows table with all assigned 'application' type permissions for Graph Api, let the user pick some and revoke them from application "otest".

    .EXAMPLE
    Revoke-AzureServicePrincipalPermission -servicePrincipalName "otest" -permissionList AccessReview.Read.All, AccessReview.ReadWrite.Membership -permissionType delegated

    Revoke 'delegated' permissions 'AccessReview.Read.All, AccessReview.ReadWrite.Membership' for Graph Api resource from 'otest' ent. app (service principal)

    .EXAMPLE
    Revoke-AzureServicePrincipalPermission -servicePrincipalName "otest" -All -permissionType delegated

    Revoke all 'delegated' permissions for Graph Api resource from 'otest' ent. app (service principal)
    #>

    [CmdletBinding(DefaultParameterSetName = 'name')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "name")]
        [string] $servicePrincipalName,

        [Parameter(Mandatory = $true, ParameterSetName = "id")]
        [string] $servicePrincipalId,

        [string] $resourceAppId = '00000003-0000-0000-c000-000000000000', # graph api

        [ArgumentCompleter( {
                param ($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)

                $resourceAppId = $FakeBoundParams.resourceAppId
                if (!$resourceAppId) { $resourceAppId = '00000003-0000-0000-c000-000000000000' }

                $resourceServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$resourceAppId'" -Property Id, AppRoles, Oauth2PermissionScopes

                if ($FakeBoundParams.servicePrincipalName) {
                    $servicePrincipal = Get-MgServicePrincipal -Filter "displayName eq '$($FakeBoundParams.servicePrincipalName)'"
                } else {
                    $servicePrincipal = (Get-MgServicePrincipal -ServicePrincipalId $FakeBoundParams.servicePrincipalId)
                }

                if (!$FakeBoundParams.permissionType -or $FakeBoundParams.permissionType -eq 'application') {
                    $appRoleAssignment = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $servicePrincipal.Id | ? ResourceId -EQ $resourceServicePrincipal.Id
                    $availablePermission = (Get-MgServicePrincipal -Filter "appId eq '$resourceAppId'" -Property AppRoles).AppRoles | select Value, Id
                    function _getScope {
                        param ($availablePermission, $appRoleId)
                        $availablePermission | ? Id -EQ $appRoleId | select -ExpandProperty Value
                    }
                    $appRoleAssignment | select @{n = 'scope'; e = { _getScope $availablePermission $_.AppRoleId } } | select -ExpandProperty scope | ? { $_ -like "*$WordToComplete*" }
                } else {
                    (Get-MgOauth2PermissionGrant -Filter "clientId eq '$($servicePrincipal.Id)' and ResourceId eq '$($resourceServicePrincipal.Id)' and consentType eq 'AllPrincipals'").Scope -split " " | ? { $_ -like "*$WordToComplete*" }
                }
            })]
        [string[]] $permissionList,

        [ValidateSet('application', 'delegated')]
        [string] $permissionType = "application",

        [switch] $all
    )

    if ($all -and $permissionList) {
        Write-Warning "Because 'All' parameter was used, 'permissionList' parameter will be ignored"
    }

    if ($all) {
        Write-Warning "All permissions of type '$permissionType' will be revoked"
    }

    # authenticate
    if ($permissionType -eq "application") {
        $graphScope = "Application.ReadWrite.All", "AppRoleAssignment.ReadWrite.All"
    } else {
        $graphScope = "Application.ReadWrite.All", "DelegatedPermissionGrant.ReadWrite.All"
    }
    $null = Connect-MgGraph -Scopes $graphScope -ea Stop

    # remove duplicates
    $permissionList = $permissionList | select -Unique

    # get account to which permissions will be revoked
    if ($servicePrincipalName) {
        $servicePrincipal = Get-MgServicePrincipal -Filter "displayName eq '$servicePrincipalName'"
        if (!$servicePrincipal) { throw "Service principal '$servicePrincipalName' doesn't exist" }
    } else {
        $servicePrincipal = (Get-MgServicePrincipal -ServicePrincipalId $servicePrincipalId)
        if (!$servicePrincipal) { throw "Service principal '$servicePrincipalId' doesn't exist" }
    }

    # get application whose permissions will be revoked
    $resourceServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$resourceAppId'" -Property Id, DisplayName, AppRoles, Oauth2PermissionScopes
    if (!$resourceServicePrincipal) { throw "Resource '$resourceAppId' doesn't exist" }

    # get assigned permissions
    if ($permissionType -eq "application") {
        $appRoleAssignment = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $servicePrincipal.Id | ? ResourceId -EQ $resourceServicePrincipal.Id
    } else {
        $Oauth2PermissionGrant = Get-MgOauth2PermissionGrant -Filter "clientId eq '$($servicePrincipal.Id)' and ResourceId eq '$($resourceServicePrincipal.Id)' and consentType eq 'AllPrincipals'"
    }

    if (!$appRoleAssignment -and !$Oauth2PermissionGrant) {
        Write-Warning "There are no permissions of '$permissionType' type assigned for resource $($resourceServicePrincipal.DisplayName) ($resourceAppId)"
        return
    }

    # get all assignable permissions
    if ($permissionType -eq "application") {
        $availablePermission = (Get-MgServicePrincipal -Filter "appId eq '$resourceAppId'" -Property AppRoles).AppRoles | ? Id -In $appRoleAssignment.AppRoleId | select Value, DisplayName, Description, Id
    } else {
        $availablePermission = $Oauth2PermissionGrant.Scope -split " "
    }

    # let the user pick permissions to remove interactively
    if (!$all -and !$permissionList) {
        if ($permissionType -eq "application") {
            $permissionList = $availablePermission | sort Value | Out-GridView -Title "Select $permissionType permission(s) you want to revoke" -OutputMode Multiple | select -ExpandProperty Value
        } else {
            $permissionList = $availablePermission | sort | Out-GridView -Title "Select $permissionType permission(s) you want to revoke" -OutputMode Multiple
        }

        if (!$permissionList) {
            throw "You haven't selected any permission"
        }
    }

    if ($permissionType -eq "application") {
        if ($all) {
            # remove all permissions
            Write-Warning "Removing all application permissions ($((($availablePermission.Value | sort ) -join ", ")))"
            $appRoleAssignment | % {
                Remove-MgServicePrincipalAppRoleAssignment -AppRoleAssignmentId $_.Id -ServicePrincipalId $servicePrincipal.Id
            }
        } else {
            # remove just some permissions
            $appRoleAssignment | ? AppRoleId -In ($availablePermission | ? Value -In $permissionList).Id | % {
                $permId = $_.Id
                $permValue = $availablePermission | ? Id -EQ ($appRoleAssignment | ? Id -EQ $permId).AppRoleId | select -ExpandProperty Value
                Write-Warning "Removing application permission ($permValue)"
                Remove-MgServicePrincipalAppRoleAssignment -AppRoleAssignmentId $_.Id -ServicePrincipalId $servicePrincipal.Id
            }
        }
    } else {
        if ($all) {
            # remove all permissions
            Write-Warning "Removing all delegated permissions ($(($availablePermission | sort ) -join ", "))"
            Remove-MgOauth2PermissionGrant -OAuth2PermissionGrantId $Oauth2PermissionGrant.Id
        } else {
            # remove just some permissions
            $preservePermission = $availablePermission | ? { $_ -notin $permissionList }

            if ($preservePermission) {
                $params = @{
                    Scope = ($preservePermission -join " ")
                }

                Write-Warning "Removing selected delegated permissions ($(($permissionList | sort ) -join ", "))"
                $null = Update-MgOauth2PermissionGrant -OAuth2PermissionGrantId $Oauth2PermissionGrant.Id -BodyParameter $params
            } else {
                # remove all permissions
                Write-Warning "Removing all delegated permissions ($(($availablePermission | sort ) -join ", "))"
                Remove-MgOauth2PermissionGrant -OAuth2PermissionGrantId $Oauth2PermissionGrant.Id
            }
        }
    }
}

function Set-AzureAppCertificate {
    <#
    .SYNOPSIS
    Function for creating (or replacing existing) authentication certificate for selected AzureAD Application.

    .DESCRIPTION
    Function for creating (or replacing existing) authentication certificate for selected AzureAD Application.

    Use this function with cerPath parameter (if you already have existing certificate you want to add) or rest of the parameters (if you want to create it first). If new certificate will be create, it will be named using application ObjectID of the corresponding enterprise app.

    .PARAMETER appObjectId
    ObjectId of the Azure application registration, to which you want to assign certificate.

    .PARAMETER cerPath
    Path to existing '.cer' certificate which should be added to the application.

    .PARAMETER StartDate
    Datetime object defining since when certificate will be valid.

    Default value is now.

    .PARAMETER EndDate
    Datetime object defining to when certificate will be valid.

    Default value is 2 years from now.

    .PARAMETER Password
    Secure string with password that will protect certificate private key.

    Choose strong one!

    .PARAMETER directory
    Path to folder where pfx (cert. with private key) certificate will be exported.

    .PARAMETER dontRemoveFromCertStore
    Switch to NOT remove certificate from the local cert. store after it is created&exported to pfx.

    .EXAMPLE
    Set-AzureAppCertificate -appObjectId cc210920-4c75-48ad-868b-6aa2dbcd1d51 -cerPath C:\cert\appCert.cer

    Adds certificate 'appCert' to the Azure application cc210920-4c75-48ad-868b-6aa2dbcd1d51.

    .EXAMPLE
    Set-AzureAppCertificate -appObjectId cc210920-4c75-48ad-868b-6aa2dbcd1d51 -password (Read-Host -AsSecureString)

    Creates new self signed certificate, export it as pfx (cert with private key) into working directory and adds its public counterpart (.cer) to the Azure application cc210920-4c75-48ad-868b-6aa2dbcd1d51.
    Certificate private key will be protected by entered password and it will be valid 2 years from now.
    #>

    [CmdletBinding(DefaultParameterSetName = 'createCert')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "cerExists")]
        [Parameter(Mandatory = $true, ParameterSetName = "createCert")]
        [string] $appObjectId,

        [Parameter(Mandatory = $true, ParameterSetName = "cerExists")]
        [ValidateScript( {
                if ($_ -match ".cer$" -and (Test-Path -Path $_)) {
                    $true
                } else {
                    throw "$_ is not a .cer file or doesn't exist"
                }
            })]
        [string] $cerPath,

        [Parameter(Mandatory = $false, ParameterSetName = "createCert")]
        [DateTime] $startDate = (Get-Date),

        [Parameter(Mandatory = $false, ParameterSetName = "createCert")]
        [ValidateScript( {
                if ($_ -gt (Get-Date)) {
                    $true
                } else {
                    throw "$_ has to be in the future"
                }
            })]
        [DateTime] $endDate = (Get-Date).AddYears(2),

        [Parameter(Mandatory = $true, ParameterSetName = "createCert")]
        [SecureString]$password,

        [Parameter(Mandatory = $false, ParameterSetName = "createCert")]
        [ValidateScript( {
                if (Test-Path -Path $_ -PathType Container) {
                    $true
                } else {
                    throw "$_ is not a folder or doesn't exist"
                }
            })]
        [string] $directory = (Get-Location),

        [switch] $dontRemoveFromCertStore
    )

    $null = Connect-MgGraph -ea Stop

    # test that app exists
    try {
        $application = Get-MgApplication -ApplicationId $appObjectId -ErrorAction Stop
    } catch {
        throw "Application registration with ObjectId $appObjectId doesn't exist"
    }

    $appCert = $application | select -exp KeyCredentials
    if ($appCert | ? EndDateTime -GT ([datetime]::Today)) {
        $choice = ""
        while ($choice -notmatch "^[Y|N]$") {
            $choice = Read-Host "There is a valid certificate(s) already. Do you really want to REPLACE it?! (Y|N)"
        }
        if ($choice -eq "N") {
            break
        }
    }

    if ($cerPath) {
        $cert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2($cerPath)
    } else {
        Write-Warning "Creating self signed certificate named '$appObjectId'"
        $cert = New-SelfSignedCertificate -CertStoreLocation 'cert:\currentuser\my' -Subject "CN=$appObjectId" -NotBefore $startDate -NotAfter $endDate -KeySpec Signature -KeyLength 2048 -KeyAlgorithm RSA -HashAlgorithm SHA256

        Write-Warning "Exporting '$appObjectId.pfx' to '$directory'"
        $pfxFile = Join-Path $directory "$appObjectId.pfx"
        $path = 'cert:\currentuser\my\' + $cert.Thumbprint
        $null = Export-PfxCertificate -Cert $path -FilePath $pfxFile -Password $password

        if (!$dontRemoveFromCertStore) {
            Write-Verbose "Removing created certificate from cert. store"
            Get-ChildItem 'cert:\currentuser\my' | ? { $_.thumbprint -eq $cert.Thumbprint } | Remove-Item
        }
    }

    # $keyValue = [System.Convert]::ToBase64String($cert.GetRawCertData())
    # $base64Thumbprint = [System.Convert]::ToBase64String($cert.GetCertHash())
    # $endDateTime = ($cert.NotAfter).ToUniversalTime().ToString( "yyyy-MM-ddTHH:mm:ssZ" )
    # $startDateTime = ($cert.NotBefore).ToUniversalTime().ToString( "yyyy-MM-ddTHH:mm:ssZ" )

    Write-Warning "Adding certificate to the application $($application.DisplayName)"

    # toto funguje s update-mgaaplication
    $keyCredentialParams = @{
        DisplayName = "certificate" # in reality this sets description field :D
        Type        = "AsymmetricX509Cert"
        Usage       = "Verify"
        Key         = $cert.GetRawCertData()
        # StartDateTime       = ($cert.NotBefore).ToUniversalTime().ToString( "yyyy-MM-ddTHH:mm:ssZ" )
        # EndDateTime         = ($cert.NotAfter).ToUniversalTime().ToString( "yyyy-MM-ddTHH:mm:ssZ" )
    }

    Update-MgApplication -ApplicationId $appObjectId -KeyCredential $keyCredentialParams
}

function Set-AzureDeviceExtensionAttribute {
    <#
    .SYNOPSIS
    Function for setting Azure device ExtensionAttribute.

    .DESCRIPTION
    Function for setting Azure device ExtensionAttribute.

    .PARAMETER deviceName
    Device name.

    .PARAMETER deviceId
    Device ID as returned by Get-MGDevice command.

    Can be used instead of device name.

    .PARAMETER extensionId
    Id number of the extension you want to set.

    Possible values are 1-15.

    .PARAMETER extensionValue
    Value you want to set. If empty, currently set value will be removed.

    .PARAMETER scope
    Permissions you want to use for connecting to Graph.

    Default is 'Directory.AccessAsUser.All' and can be used if you have Global or Intune administrator role.

    Possible values are: 'Directory.AccessAsUser.All', 'Device.ReadWrite.All', 'Directory.ReadWrite.All'

    .EXAMPLE
    Set-AzureDeviceExtensionAttribute -deviceName nn-69-ntb -extensionId 1 -extensionValue 'ntb'

    On device nn-69-ntb set value 'ntb' into device ExtensionAttribute1.

    .EXAMPLE
    Set-AzureDeviceExtensionAttribute -deviceName nn-69-ntb -extensionId 1

    On device nn-69-ntb empty current value saved in device ExtensionAttribute1.

    .NOTES
    https://blogs.aaddevsup.xyz/2022/05/how-to-use-microsoft-graph-sdk-for-powershell-to-update-a-registered-devices-extension-attribute/?utm_source=rss&utm_medium=rss&utm_campaign=how-to-use-microsoft-graph-sdk-for-powershell-to-update-a-registered-devices-extension-attribute
    #>

    [CmdletBinding(DefaultParameterSetName = 'deviceName')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "deviceName")]
        [string] $deviceName,

        [Parameter(Mandatory = $true, ParameterSetName = "deviceId")]
        [string] $deviceId,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 15)]
        $extensionId,

        [string] $extensionValue,

        [ValidateSet('Directory.AccessAsUser.All', 'Device.ReadWrite.All', 'Directory.ReadWrite.All')]
        [string] $scope = 'Directory.AccessAsUser.All'
    )

    #region checks
    if (!(Get-Module "Microsoft.Graph.Authentication" -ListAvailable -ea SilentlyContinue)) {
        throw "Microsoft.Graph.Authentication module is missing"
    }

    if (!(Get-Module "Microsoft.Graph.Identity.DirectoryManagement" -ListAvailable -ea SilentlyContinue)) {
        throw "Microsoft.Graph.Identity.DirectoryManagement module is missing"
    }
    #endregion checks

    # connect to Graph
    $null = Connect-MgGraph -Scopes $scope

    # get the device
    if ($deviceName) {
        $device = Get-MgDevice -Filter "DisplayName eq '$deviceName'"
        if (!$device) {
            throw "Device $deviceName wasn't found"
        }
    } else {
        $device = Get-MgDeviceById -DeviceId $deviceId -ErrorAction SilentlyContinue
        if (!$device) {
            throw "Device $deviceId wasn't found"
        }
        $deviceName = $device.DisplayName
    }

    if ($device.count -gt 1) {
        throw "There are more than one devices with name $device. Use DeviceId instead."
    }

    # get current value saved in attribute
    $currentExtensionValue = $device.AdditionalProperties.extensionAttributes."extensionAttribute$extensionId"

    # set attribute if necessary
    if (($currentExtensionValue -eq $extensionValue) -or ([string]::IsNullOrEmpty($currentExtensionValue) -and [string]::IsNullOrEmpty($extensionValue))) {
        Write-Warning "New extension value is same as existing one set in extensionAttribute$extensionId on device $deviceName. Skipping"
    } else {
        if ($extensionValue) {
            $verb = "Setting '$extensionValue' to"
        } else {
            $verb = "Emptying"
        }

        Write-Warning "$verb extensionAttribute$extensionId on device $deviceName (previous value was '$currentExtensionValue')"

        # prepare value hash
        $params = @{
            "extensionAttributes" = @{
                "extensionAttribute$extensionId" = $extensionValue
            }
        }

        Update-MgDevice -DeviceId $device.id -BodyParameter ($params | ConvertTo-Json)
    }
}

function Set-AzureRingGroup {
    <#
    .SYNOPSIS
    Function for dynamically setting members of specified "ring" groups based on the provided users list (members of the rootGroup) and the members per group percent ratio (ringGroupConfig).

    Useful if you want to deploy some feature gradually (ring by ring).

    "Ring" group concept is inspired by Intune Autopatch deployment rings.

    .DESCRIPTION
    Function for dynamically setting members of specified "ring" groups based on the provided users list (members of the rootGroup) and the members per group percent ratio (ringGroupConfig).

    Useful if you want to deploy some feature gradually (ring by ring).

    "Ring" group concept is inspired by Intune Autopatch deployment rings.

    With each function run, members and their ratio is checked and a rebalance of members is made if needed.

    Ring groups can contain only accounts that are members of the root group too!

    Ring groups description will be automatically updated with each run of this function. It will contain date of the last update and some generated text about how many percent of the root group this group contains.

    .PARAMETER rootGroup
    Id of the Azure group which members should be distributed across all ring groups based on the percent weight specified in the "ringGroupConfig".

    Members are searched recursively! Only users or devices accounts are used based on 'memberType'.

    .PARAMETER ringGroupConfig
    Ordered hashtable where keys are IDs of the Azure "ring" groups and values are integers representing percent of the "rootGroup" group members this "ring" group should contain.
    Sum of the values must be 100 at total.

    Example:
    [ordered]@{
        'bcf239e9-6a5e-4de0-baf4-c14bda4c0571' = 5 # ring_1
        '19fe5c4c-7568-43a3-bd21-f95cb5547366' = 15 # ring_2
        '0db6da9f-c224-4252-a7dc-c31d55b3acb3' = 80 # ring_3
    }

    .PARAMETER forceRecalculate
    Use if you want to force members check even though count of the root group members is the same as of all ring groups members (to overwrite manual edits etc)

    .PARAMETER firstRingGroupMembersSetManually
    Switch to specify that first group in ringGroupConfig is being manually set a.k.a skipped in re-balancing process.
    Therefore its value in ringGroupConfig must be set to 0 (because members are added manually).
    Percent weight (specified in ringGroupConfig) of the rest of the ring groups is used only for re-balancing users that are non-first-ring-group members.

    .PARAMETER skipUnderscoreInNameCheck
    Switch for skipping check that all "ring" groups that have dynamically set members have '_' prefix in their name (name convention).

    .PARAMETER includeDisabled
    Switch for including also disabled members of the root group, otherwise just enabled will be used to fill the "ring" groups.

    .PARAMETER skipDescriptionUpdate
    Switch for not modifying ring groups description.

    .PARAMETER memberType
    Type of the "rootGroup" you want to set on "ring" groups.

    Possible values: User, Device.

    By default 'User'.

    .EXAMPLE
    # group whose members will be distributed between ring groups
    $rootGroup = "330a6543-da12-4999-bf87-a0ae60g28bbc"
    # ring groups configuration
    $ringGroupConfig = [ordered]@{
        # manually set members
        '9e6be2e2-c050-4887-b14c-e612a1b4bb48' = 0 # ring_0
        # automatically set members
        'bcf239e9-6a5e-4de0-baf4-c14bda4c0a71' = 5 # ring_1
        '19fe5c4c-7568-43a3-bd21-f95cb5547766' = 15 # ring_2
        '0db6da9f-c224-4252-a7dc-c31d55b9acb3' = 80 # ring_3
    }

    Set-AzureRingGroup -rootGroup $rootGroup -ringGroupConfig $ringGroupConfig -firstRingGroupMembersSetManually

    Members of the root group (minus members of the first "ring" group) will be distributed across rest of the "ring" groups by percent ratio selected in the $ringGroupConfig.
    Members of the first "ring" group stay intact.
    In case current "ring" groups members count doesn't correspond to the percent specified in the $ringGroupConfig, members will be removed/added accordingly.

    .EXAMPLE
    # group whose members will be distributed between ring groups
    $rootGroup = "330a6543-da12-4999-bf87-a0ae60g28bbc"
    # ring groups configuration
    $ringGroupConfig = [ordered]@{
        'bcf239e9-6a5e-4de0-baf4-c14bda4c0a71' = 5 # ring_1
        '19fe5c4c-7568-43a3-bd21-f95cb5547766' = 15 # ring_2
        '0db6da9f-c224-4252-a7dc-c31d55b9acb3' = 80 # ring_3
    }

    Set-AzureRingGroup -rootGroup $rootGroup -ringGroupConfig $ringGroupConfig

    Members of the root group will be distributed across the "ring" groups by percent ratio selected in the $ringGroupConfig.
    In case current "ring" groups members count doesn't correspond to the percent specified in the $ringGroupConfig, members will be removed/added accordingly.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [guid] $rootGroup,

        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary] $ringGroupConfig,

        [switch] $forceRecalculate,

        [switch] $firstRingGroupMembersSetManually,

        [switch] $skipUnderscoreInNameCheck,

        [switch] $includeDisabled,

        [switch] $skipDescriptionUpdate,

        [ValidateSet('User', 'Device')]
        [string] $memberType = 'User'
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    #region functions
    function _getGroupName {
        param ($id)

        return (Get-MgGroup -GroupId $id -Property displayname).displayname
    }

    function _getMemberName {
        param ($id)

        return (Get-MgDirectoryObject -DirectoryObjectId $id).AdditionalProperties.displayName
    }

    function _setRingGroupsDescription {
        "Updating ring groups description"
        $ringGroupConfig.Keys | % {
            $groupId = $_

            $value = $ringGroupConfig.$groupId
            $ring0GroupId = $($ringGroupConfig.Keys)[0]

            if ($firstRingGroupMembersSetManually -and $groupId -eq $ring0GroupId) {
                $description = "Contains selected $($memberType.ToLower()) members of the $(_getGroupName $rootGroup) group. Members are assigned manually. Last processed at $(Get-Date -Format 'yyyy.MM.dd_HH:mm')"
            } else {
                $description = "Contains cca $value% $($memberType.ToLower()) members of the $(_getGroupName $rootGroup) group. Members are assigned programmatically. Last processed at $(Get-Date -Format 'yyyy.MM.dd_HH:mm')"
            }

            Update-MgGroup -GroupId $groupId -Description $description
        }
    }
    #endregion functions

    if ($firstRingGroupMembersSetManually) {
        # first ring group has manually set members
        # some exceptions in checks etc needs to be made
        $ring0GroupId = $($ringGroupConfig.Keys)[0]
    } else {
        # first ring group has automatically set members (as the rest of the ring groups)
        # no extra treatment is needed
        $ring0GroupId = $null
    }

    #region checks
    # all groups exists
    $allGroupId = @()
    $allGroupId += $rootGroup
    $ringGroupConfig.Keys | % { $allGroupId += $_ }
    $allGroupId | % {
        $groupId = $_

        try {
            $null = [guid] $groupId
        } catch {
            throw "$groupId isn't valid group ID"
        }

        try {
            $null = Get-MgGroup -GroupId $groupId -Property displayname -ErrorAction Stop
        } catch {
            throw "Group with ID $groupId that is defined in `$ringGroupConfig doesn't exist"
        }
    }

    # all automatically filled ring groups should have '_' prefix (naming convention)
    if (!$skipUnderscoreInNameCheck) {
        $ringGroupConfig.Keys | % {
            $groupId = $_

            if (!$firstRingGroupMembersSetManually -or $groupId -ne $ring0GroupId) {
                $groupName = _getGroupName $groupId

                if ($groupName -notlike "_*") {
                    throw "Group $groupName ($groupId) doesn't have prefix '_'. It has dynamically set members therefore it should!"
                }
            }
        }
    }

    # beta ring group has 0% set as assigned members count
    if ($firstRingGroupMembersSetManually -and $ringGroupConfig[0] -ne 0) {
        throw "First group in `$ringGroupConfig is manually filled a.k.a. value must be set to 0 (now $($ringGroupConfig[0]))"
    }

    # sum of all ring groups assigned members percent is 100% at total
    $ringGroupPercentSum = $ringGroupConfig.Values | Measure-Object -Sum | select -ExpandProperty Sum
    if ($ringGroupPercentSum -ne 100) {
        throw "Total sum of groups percent has to be 100 (now $ringGroupPercentSum)"
    }
    #endregion checks

    # make a note that group was processed, by updating its description
    if (!$skipDescriptionUpdate) {
        _setRingGroupsDescription
    }

    # get all users/devices that should be assigned to the "ring" groups
    $rootGroupMember = Get-AzureGroupMemberRecursive -Id $rootGroup -excludeDisabled:(!$includeDisabled) -allowedMemberType $memberType

    #region cleanup of members that are no longer in the root group or are placed in more than one group
    $memberOccurrence = @{}
    $ringGroupConfig.Keys | % {
        $groupId = $_
        Get-MgGroupMember -GroupId $groupId -All -Property Id | % {
            $memberId = $_.Id
            if ($memberId -notin $rootGroupMember.Id) {
                Write-Warning "Removing group's $(_getGroupName $groupId) member $(_getMemberName $memberId) (not in the root group)"
                Remove-MgGroupMemberByRef -GroupId $groupId -DirectoryObjectId $memberId
            } else {
                if ($memberOccurrence.$memberId) {
                    Write-Warning "Removing group's $(_getGroupName $groupId) member $(_getMemberName $memberId) (already member of the group $(_getGroupName $memberOccurrence.$memberId))"
                    Remove-MgGroupMemberByRef -GroupId $groupId -DirectoryObjectId $memberId
                } else {
                    $memberOccurrence.$memberId = $groupId
                }
            }
        }
    }
    #endregion cleanup of members that are no longer in the root group or are placed in more than one group

    $ringGroupsMember = $ringGroupConfig.Keys | % { Get-MgGroupMember -GroupId $_ -All -Property Id }

    $rootGroupMemberCount = $rootGroupMember.count
    $ringGroupsMemberCount = $ringGroupsMember.count
    if ($firstRingGroupMembersSetManually) {
        # set percent weight is calculated from all available members except the manually set members of the test (ring0) group
        $ring0GroupMember = Get-MgGroupMember -GroupId $ring0GroupId -All -Property Id
        $assignableRingGroupsMemberCount = $rootGroupMemberCount - $ring0GroupMember.count
    } else {
        $assignableRingGroupsMemberCount = $rootGroupMemberCount
    }

    if ($rootGroupMemberCount -eq $ringGroupsMemberCount -and !$forceRecalculate) {
        return "No change in members count detected. Exiting"
    }

    # contains users/devices that are members of the root group, but not of any ring group
    # plus users/devices that were removed from any ring group for redundancy a.k.a. should be relocate to another ring group
    $memberToRelocateList = New-Object System.Collections.ArrayList
    ($rootGroupMember).Id | % {
        if ($_ -notin $ringGroupsMember.Id) {
            $null = $memberToRelocateList.Add($_)
        }
    }

    # hashtable with group ids and number of members that should be added
    $groupWithMissingMember = @{}

    # remove obsolete/redundancy ring group members
    if ($assignableRingGroupsMemberCount -ne 0) {
        foreach ($groupId in $ringGroupConfig.Keys) {
            if ($firstRingGroupMembersSetManually -and $groupId -eq $ring0GroupId) {
                # ring0 group is manually filled, hence no checks on members count are needed
                continue
            }

            $groupMember = Get-MgGroupMember -GroupId $groupId -All -Property Id
            $groupCurrentMemberCount = $groupMember.count
            if ($groupCurrentMemberCount) {
                $groupCurrentWeight = [math]::round($groupCurrentMemberCount / $assignableRingGroupsMemberCount * 100)
            } else {
                $groupCurrentWeight = 0
            }

            $groupRequiredWeight = $ringGroupConfig.$groupId
            $groupRequiredMemberCount = [math]::round($assignableRingGroupsMemberCount / 100 * $groupRequiredWeight)
            if ($groupRequiredMemberCount -eq 0 -and $groupRequiredWeight -gt 0) {
                # assign at least one member
                $groupRequiredMemberCount = 1
            }

            if ($groupCurrentMemberCount -ne $groupRequiredMemberCount) {
                "Group $(_getGroupName $groupId) ($groupCurrentMemberCount member(s)) should contain $groupRequiredWeight% ($groupRequiredMemberCount member(s)) of all assignable ($assignableRingGroupsMemberCount) users/devices, but contains $groupCurrentWeight%"

                if ($groupCurrentMemberCount -gt $groupRequiredMemberCount) {
                    # remove some random users/devices
                    $memberToRelocate = Get-Random -InputObject $groupMember.Id -Count ($groupCurrentMemberCount - $groupRequiredMemberCount)

                    $memberToRelocate | % {
                        $memberId = $_

                        Write-Warning "Removing group's $(_getGroupName $groupId) member $(_getMemberName $memberId) (is over the set limit)"

                        Remove-MgGroupMemberByRef -GroupId $groupId -DirectoryObjectId $memberId

                        $null = $memberToRelocateList.Add($memberId)
                    }
                } else {
                    # make a note about how many members should be added (later, because at first I need to free up/remove them from their current groups)
                    $groupWithMissingMember.$groupId = $groupRequiredMemberCount - $groupCurrentMemberCount
                }
            }
        }
    }

    # add new members to ring groups that have less members than required
    if ($groupWithMissingMember.Keys) {
        # add some random users/devices from the pool of available users/devices
        # start with the group with least required members, because of the rounding there might not be enough of them for all groups and you want to have the testing groups filled
        foreach ($groupId in ($groupWithMissingMember.Keys | Sort-Object -Property { $ringGroupConfig.$_ })) {
            $memberToRelocateCount = $groupWithMissingMember.$groupId
            if ($memberToRelocateList.count -eq 0) {
                Write-Warning "There is not enough members left. Adding no members to the group $(_getGroupName $groupId) instead of $memberToRelocateCount"
            } else {
                if ($memberToRelocateList.count -lt $memberToRelocateCount) {
                    Write-Warning "There is not enough members left. Adding $($memberToRelocateList.count) instead of $memberToRelocateCount to the group $(_getGroupName $groupId)"
                    $memberToRelocateCount = $memberToRelocateList.count
                }

                $memberToAdd = Get-Random -InputObject $memberToRelocateList -Count $memberToRelocateCount

                $memberToAdd | % {
                    $memberId = $_

                    Write-Warning "Adding member $(_getMemberName $memberId) to the group $(_getGroupName $groupId)"

                    $params = @{
                        "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$memberId"
                    }
                    New-MgGroupMemberByRef -GroupId $groupId -BodyParameter $params

                    $null = $memberToRelocateList.Remove($memberId)
                }
            }
        }
    }

    if ($memberToRelocateList) {
        # this shouldn't happen?
        throw "There are still some unassigned users/devices left?!"
    }
}

function Start-AzureSync {
    <#
        .SYNOPSIS
        Invoke Azure AD sync cycle command (Start-ADSyncSyncCycle) on the server where 'Azure AD Connect' is installed.

        .DESCRIPTION
        Invoke Azure AD sync cycle command (Start-ADSyncSyncCycle) on the server where 'Azure AD Connect' is installed.

        .PARAMETER Type
        Type of sync.

        Initial (full) or just delta.

        Delta is default.

        .PARAMETER ADSynchServer
        Name of the server where 'Azure AD Connect' is installed

        .EXAMPLE
        Start-AzureSync -ADSynchServer ADSYNCSERVER
        Invokes synchronization between on-premises AD and AzureAD on server ADSYNCSERVER by running command Start-ADSyncSyncCycle there.
    #>

    [Alias("Sync-ADtoAzure", "Start-AzureADSync")]
    [cmdletbinding()]
    param (
        [ValidateSet('delta', 'initial')]
        [string] $type = 'delta',

        [ValidateNotNullOrEmpty()]
        [string] $ADSynchServer = $_ADSynchServer
    )

    $ErrState = $false
    do {
        try {
            Invoke-Command -ScriptBlock { Start-ADSyncSyncCycle -PolicyType $using:type } -ComputerName $ADSynchServer -ErrorAction Stop | Out-Null
            $ErrState = $false
        } catch {
            $ErrState = $true
            Write-Warning "Start-AzureSync: Error in Sync:`n$_`nRetrying..."
            Start-Sleep 5
        }
    } while ($ErrState -eq $true)
}

Export-ModuleMember -function Add-AzureAppUserConsent, Add-AzureGuest, Disable-AzureGuest, Get-AzureAccountOccurrence, Get-AzureAppConsentRequest, Get-AzureAppRegistration, Get-AzureAppVerificationStatus, Get-AzureAssessNotificationEmail, Get-AzureAuthenticatorLastUsedDate, Get-AzureCompletedMFAPrompt, Get-AzureDeviceWithoutBitlockerKey, Get-AzureEnterpriseApplication, Get-AzureGroupMemberRecursive, Get-AzureGroupSettings, Get-AzureManagedIdentity, Get-AzureResource, Get-AzureRoleAssignments, Get-AzureServiceAccount, Get-AzureServicePrincipalBySecurityAttribute, Get-AzureServicePrincipalOverview, Get-AzureServicePrincipalPermissions, Get-AzureServicePrincipalUsersAndGroups, Get-AzureSkuAssignment, Get-AzureSkuAssignmentError, Get-AzureUserAuthMethodChanges, Grant-AzureServicePrincipalPermission, New-AzureAutomationModule, Open-AzureAdminConsentPage, Remove-AzureAccountOccurrence, Remove-AzureAppUserConsent, Remove-AzureUserMemberOfDirectoryRole, Revoke-AzureServicePrincipalPermission, Set-AzureAppCertificate, Set-AzureDeviceExtensionAttribute, Set-AzureRingGroup, Start-AzureSync

Export-ModuleMember -alias Get-AzureADAccountOccurrence, Get-AzureIAMRoleAssignments, Get-AzureRBACRoleAssignments, Get-AzureSPPermissions, Get-MgGroupMemberRecursive, New-AzAutomationModule2, New-AzureADGuest, Remove-AzureADAccountOccurrence, Remove-AzureADGuest, Start-AzureADSync, Sync-ADtoAzure
