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