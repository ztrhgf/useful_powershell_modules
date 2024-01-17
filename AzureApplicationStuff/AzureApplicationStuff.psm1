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

Export-ModuleMember -function Add-AzureAppUserConsent, Get-AzureAppConsentRequest, Get-AzureAppRegistration, Get-AzureAppVerificationStatus, Get-AzureEnterpriseApplication, Get-AzureManagedIdentity, Get-AzureServiceAccount, Get-AzureServicePrincipalBySecurityAttribute, Get-AzureServicePrincipalOverview, Get-AzureServicePrincipalPermissions, Get-AzureServicePrincipalUsersAndGroups, Grant-AzureServicePrincipalPermission, Remove-AzureAppUserConsent, Revoke-AzureServicePrincipalPermission, Set-AzureAppCertificate

Export-ModuleMember -alias Get-AzureSPPermissions
