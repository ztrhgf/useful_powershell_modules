function Set-AzureAutomationRunbookContent {
    <#
    .SYNOPSIS
    Function sets Automation Runbook code content.

    .DESCRIPTION
    Function sets Automation Runbook code content.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER runbookName
    Runbook name.

    .PARAMETER content
    String that should be set as a new runbook code.

    .PARAMETER publish
    Switch to publish the newly set content.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    $content = @'
        Get-process notepad
        restart-service spooler
    '@

    Set-AzureAutomationRunbookContent -runbookName someRunbook -ResourceGroupName Automations -AutomationAccountName someAutomationAccount -content $content

    Sets given code as the new runbook content.
    #>

    [CmdletBinding()]
    param (
        [string] $resourceGroupName,

        [string] $automationAccountName,

        [string] $runbookName,

        [Parameter(Mandatory = $true)]
        [string] $content,

        [switch] $publish,

        [hashtable] $header
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    #region get missing arguments
    $subscriptionId = (Get-AzContext).Subscription.Id

    # create auth token
    if (!$header) {
        $header = New-AzureAutomationGraphToken
    }

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

    Write-Verbose "Setting new runbook code content"
    Invoke-RestMethod2 "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runbooks/$runbookName/draft/content?api-version=2015-10-31" -method PUT -headers $header -body $content

    if ($publish) {
        Write-Verbose "Publishing"
        $null = Publish-AzAutomationRunbook -Name $runbookName -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName
    }
}