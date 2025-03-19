function Stop-AzureAutomationRunbookTestJob {
    <#
    .SYNOPSIS
    Invoke test run of the selected Runbook using selected Runtime.

    .DESCRIPTION
    Invoke test run of the selected Runbook using selected Runtime.

    Runtime will be used only for test run, no permanent change to the Runbook will be made.

    .PARAMETER runbookName
    Runbook name you want to run.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Stop-AzureAutomationRunbookTestJob

    Stop test run of the selected Runbook.

    Missing function arguments like $runbookName, $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.
    #>

    [CmdletBinding()]
    param (
        [string] $runbookName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [switch] $wait,

        [hashtable] $header
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    $InformationPreference = 'continue'

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
        $runbookName = Get-AzAutomationRunbook -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroupName | select -ExpandProperty Name | Out-GridView -OutputMode Single -Title "Select runbook you want to stop"
    }
    #endregion get missing arguments

    $testRunStatus = Get-AzureAutomationRunbookTestJobStatus -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -runbookName $runbookName -header $header

    if ($testRunStatus.Status -in "Stopped", "Completed", "Failed") {
        Write-Warning "Runbook '$runbookName' test job isn't running"
        return
    }

    Write-Information "Stopping Runbook '$runbookName' test job"

    Invoke-RestMethod2 -method Post -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runbooks/$runbookName/draft/testJob/stop?api-version=2019-06-01" -headers $header

    if ($wait) {
        Write-Information -MessageData "Waiting for the Runbook '$runbookName' test job to stop"

        do {
            $testRunStatus = Get-AzureAutomationRunbookTestJobStatus -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -runbookName $runbookName -header $header
            Start-Sleep 5
        } while ($testRunStatus.Status -ne "Stopped")

        Write-Information -MessageData "Runbook '$runbookName' test job was stopped"
    }
}