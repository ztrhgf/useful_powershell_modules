function Get-AzureLocalHealth {
    <#
    .SYNOPSIS
        Retrieves health alerts for an Azure Local (HCI) cluster using Azure Resource Graph.

    .DESCRIPTION
        The Get-AzureLocalHealth function queries Azure Resource Graph for active health alerts related to a specified Azure Local (HCI) cluster.
        It filters alerts by subscription, resource group, and cluster name, returning only alerts with a 'Fired' monitor condition.

    .PARAMETER SubscriptionId
        The Azure subscription ID containing the Azure Local (HCI) cluster.

    .PARAMETER ResourceGroupName
        The resource group name where the Azure Local (HCI) cluster resides.

    .PARAMETER ClusterName
        The name of the Azure Local (HCI) cluster.

    .EXAMPLE
        Get-AzureLocalHealth -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -ResourceGroupName "AHCI-MAIN" -ClusterName "AHCI-MAIN"

        Retrieves all active health alerts for the cluster 'AHCI-MAIN' in resource group 'AHCI-MAIN' within the specified subscription.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$subscriptionId,

        [Parameter(Mandatory = $true)]
        [string]$resourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]$clusterName
    )

    $query = @"
alertsmanagementresources | where type == 'microsoft.alertsmanagement/alerts' | extend severity = tostring(properties["essentials"]["severity"]) | where properties["essentials"]["targetResource"] =~ '/subscriptions/$subscriptionId/resourcegroups/$resourceGroupName/providers/microsoft.azurestackhci/clusters/$clusterName' or properties["essentials"]["targetResource"] startswith '/subscriptions/$subscriptionId/resourcegroups/$resourceGroupName/providers/microsoft.azurestackhci/clusters/$clusterName/'
| where properties["essentials"]["monitorCondition"] in~ ('Fired')
"@
    Search-AzGraph -Query $query
}