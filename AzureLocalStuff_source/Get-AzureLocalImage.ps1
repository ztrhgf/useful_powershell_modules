function Get-AzureLocalImage {
    <#
    .SYNOPSIS
    Retrieves existing Azure Local (HCI) VM images.

    .DESCRIPTION
    This function retrieves a list of VM images available in the specified Azure Local (HCI) environment.

    .PARAMETER SubscriptionId
    The subscription ID to filter the VM images.

    .PARAMETER ResourceGroupName
    The resource group name to filter the VM images.

    .EXAMPLE
    Get-AzureLocalImage -SubscriptionId "66cdebf5-fbaf-4040-b777-4507fe1ccb5e" -ResourceGroupName "ahci-main"

    .NOTES
    Requires Azure CLI with stack-hci-vm extension installed.
    #>

    [CmdletBinding()]
    param(
        [string]$SubscriptionId,

        [string]$ResourceGroupName
    )

    Write-Verbose "Retrieving existing Azure Local VM images..."

    # Get all VM images from Azure Local
    if ($SubscriptionId) {
        $SubscriptionIdText = " --subscription '$SubscriptionId'"
    } else {
        $SubscriptionIdText = $null
        Write-Verbose "No SubscriptionId provided, using default subscription"
    }

    if ($ResourceGroupName) {
        $ResourceGroupNameText = " --resource-group '$ResourceGroupName'"
    } else {
        $ResourceGroupNameText = $null
        Write-Verbose "No ResourceGroupName provided, using default resource group"
    }

    $azCommand = "az stack-hci-vm image list $SubscriptionIdText $ResourceGroupNameText --output json"
    $result = Invoke-Expression $azCommand

    $result | ConvertFrom-Json
}