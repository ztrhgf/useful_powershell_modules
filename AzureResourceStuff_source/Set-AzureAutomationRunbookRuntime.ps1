function Set-AzureAutomationRunbookRuntime {
    <#
    .SYNOPSIS
    Set Runtime Environment in the selected Azure Automation Account Runbook.

    .DESCRIPTION
    Set Runtime Environment in the selected Azure Automation Account Runbook.

    .PARAMETER runtimeName
    Runtime name you want to use.

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

    Set-AzureAutomationRunbookRuntime

    Set selected Runtime Environment in selected Runbook.
    Missing function arguments like $runtimeName, $resourceGroupName, $automationAccountName or $runbookName will be interactively gathered through Out-GridView GUI.
    #>

    [CmdletBinding()]
    param (
        [string] $runtimeName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [string] $runbookName,

        [hashtable] $header
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
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
        $runbookName = Get-AzAutomationRunbook -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroupName | select -ExpandProperty Name | Out-GridView -OutputMode Single -Title "Select runbook you want to change"
    }
    #endregion get missing arguments

    $runbookType = Get-AzAutomationRunbook -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroupName -Name $runbookName | select -ExpandProperty RunbookType

    if ($runbookType -eq 'python2') {
        $programmingLanguage = 'Python'
    } else {
        $programmingLanguage = $runbookType
    }

    $currentRuntimeName = Get-AzureAutomationRunbookRuntime -automationAccountName $automationAccountName -resourceGroupName $resourceGroupName -runbookName $runbookName -header $header

    if ($runtimeName -and $runtimeName -eq $currentRuntimeName) {
        Write-Warning "Runtime '$runtimeName' is already set. Skipping."
        return
    } else {
        while (!$runtimeName) {
            $runtimeName = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -programmingLanguage $programmingLanguage | select -ExpandProperty Name | ? { $_ -notin $currentRuntimeName } | Out-GridView -OutputMode Single -Title "Select runtime you want to set (current is '$currentRuntimeName')"
        }
    }

    #region send web request
    $body = @{
        "properties" = @{
            runtimeEnvironment = $runtimeName
        }
    }
    if ($programmingLanguage -eq 'Python') {
        # fix for bug? "The property runtimeEnvironment cannot be configured for runbookType Python2. Either use runbookType Python or remove runtimeEnvironment from input."
        $body.properties.runbookType = 'Python'
    }
    $body = $body | ConvertTo-Json

    Write-Verbose $body

    Invoke-RestMethod2 -method PATCH -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runbooks/$runbookName`?api-version=2023-05-15-preview" -body $body -headers $header
    #endregion send web request
}