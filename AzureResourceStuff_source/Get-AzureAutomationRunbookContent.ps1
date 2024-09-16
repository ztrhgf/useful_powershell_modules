function Get-AzureAutomationRunbookContent {
    <#
    .SYNOPSIS
    Function gets Automation Runbook code content.

    .DESCRIPTION
    Function gets Automation Runbook code content.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER runbookName
    Runbook name.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Get-AzureAutomationRunbookContent -runbookName someRunbook -ResourceGroupName Automations -AutomationAccountName someAutomationAccount

    Gets code set in the specified runbook.
    #>

    [CmdletBinding()]
    param (
        [string] $resourceGroupName,

        [string] $automationAccountName,

        [string] $runbookName,

        [hashtable] $header
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    #region get missing arguments
    $subscriptionId = (Get-AzContext).Subscription.Id

    # create auth token
    $accessToken = Get-AzAccessToken -ResourceTypeName "Arm"
    if ($accessToken.Token) {
        $header = @{
            'Content-Type'  = 'application/json'
            'Authorization' = "Bearer {0}" -f $accessToken.Token
        }
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

    Write-Verbose "Getting runbook code content"

    try {
        Invoke-RestMethod "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runbooks/$runbookName/content?api-version=2015-10-31" -Method GET -Headers $header
    } catch {
        if ($_.Exception.StatusCode -eq 'NotFound') {
            Write-Verbose "There is no code set in the runbook"
        } else {
            throw $_
        }
    }
}