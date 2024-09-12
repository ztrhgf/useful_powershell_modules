function Get-AzureAutomationRunbookRuntime {
    <#
    .SYNOPSIS
    Get Runtime Environment name of the selected Azure Automation Account Runbook.

    .DESCRIPTION
    Get Runtime Environment name of the selected Azure Automation Account Runbook.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER runbookName
    Runbook name.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRunbookRuntime

    Get name of the Runtime Environment used in selected Runbook.
    Missing function arguments like $resourceGroupName, $automationAccountName or $runbookName will be interactively gathered through Out-GridView GUI.
    #>

    [CmdletBinding()]
    param (
        [string] $resourceGroupName,

        [string] $automationAccountName,

        [string] $runbookName,

        [hashtable] $header
    )

    if (!(Get-Command 'Get-AzAccessToken -AsSecureString' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -AsSecureString -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    #region get missing arguments
    if (!$header) {
        $header = New-AzureAutomationGraphToken
    }

    $subscriptionId = (Get-AzContext).Subscription.Id

    while (!$resourceGroupName) {
        $resourceGroupName = Get-AzResourceGroup | select -ExpandProperty ResourceGroupName | Out-GridView -OutputMode Single -Title "Select resource group you want to process"
    }

    while (!$automationAccountName) {
        $automationAccountName = Get-AzAutomationAccount -ResourceGroupName $resourceGroupName | select -ExpandProperty AutomationAccountName | Out-GridView -OutputMode Single -Title "Select automation account you want to process"
    }

    while (!$runbookName) {
        $runbookName = Get-AzAutomationRunbook -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroupName | select -ExpandProperty Name | Out-GridView -OutputMode Single -Title "Select runbook you want to process"
    }
    #endregion get missing arguments

    Invoke-RestMethod2 "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runbooks/$runbookName`?api-version=2023-05-15-preview" -headers $header | select -ExpandProperty properties | select -ExpandProperty runtimeEnvironment
}