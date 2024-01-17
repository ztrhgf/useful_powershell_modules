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