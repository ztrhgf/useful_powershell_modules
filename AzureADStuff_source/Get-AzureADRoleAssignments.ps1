#Requires -Module Az.Accounts
#Requires -Module Az.Resources
function Get-AzureADRoleAssignments {
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
    Get-AzureADRoleAssignments

    Returns RBAC role assignments for all subscriptions.

    .EXAMPLE
    Get-AzureADRoleAssignments -subscriptionId 1234-1234-1234-1234

    Returns RBAC role assignments for subscription with ID 1234-1234-1234-1234.

    .EXAMPLE
    Get-AzureADRoleAssignments -selectCurrentSubscription

    Returns RBAC role assignments just for current subscription.

    .EXAMPLE
    Get-AzureADRoleAssignments -selectCurrentSubscription -userPrincipalName john@contoso.com

    Returns RBAC role assignments of the user john@contoso.com just for current subscription.

    .NOTES
    Required Azure permissions:
    - Global reader
    - Security Reader assigned at 'Tenant Root Group'

    https://m365internals.com/2021/11/30/lateral-movement-with-managed-identities-of-azure-virtual-machines/?s=09
    https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
    #>

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [Alias("Get-AzureADRBACRoleAssignments", "Get-AzureADIAMRoleAssignments")]
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
                ErrorAction   = 'Stop'
                WarningAction = "SilentlyContinue" # to avoid: WARNING: We have migrated the API calls for this cmdlet from Azure Active Directory Graph to Microsoft Graph.Visit https://go.microsoft.com/fwlink/?linkid=2181475 for any permission issues.
            }
            if ($objectId) {
                $param.objectId = $objectId
            } elseif ($userPrincipalName) {
                # -ExpandPrincipalGroups for also assignments based on group membership
                $param.SignInName = $userPrincipalName
            }

            Get-AzRoleAssignment @param | Select-Object RoleDefinitionName, DisplayName, SignInName, ObjectType, ObjectId, @{n = 'AssignmentScope'; e = { $_.Scope } }, @{n = "SubscriptionId"; e = { $Subscription.SubscriptionId } }, @{n = 'ScopeType'; e = { _scopeType  $_.scope } }, @{n = 'CustomRole'; e = { ($roleDefinition | ? { $_.Name -eq $_.RoleDefinitionName }).IsCustom } }, @{n = "SubscriptionName"; e = { $Subscription.Name } }
        } catch {
            if ($_ -match "The current subscription type is not permitted to perform operations on any provider namespace. Please use a different subscription") {
                Write-Warning "At subscription $($Subscription.Name) there is no resource provider registered"
            } else {
                Write-Error $_
            }
        }
    }
}