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

Export-ModuleMember -function Get-AzureRoleAssignments, Remove-AzureUserMemberOfDirectoryRole

Export-ModuleMember -alias Get-AzureIAMRoleAssignments, Get-AzureRBACRoleAssignments
