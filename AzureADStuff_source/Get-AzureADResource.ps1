function Get-AzureADResource {
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
    Get-AzureADResource

    Returns resources for all subscriptions.

    .EXAMPLE
    Get-AzureADResource -subscriptionId 1234-1234-1234-1234

    Returns resources for subscription with ID 1234-1234-1234-1234.

    .EXAMPLE
    Get-AzureADResource -selectCurrentSubscription

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