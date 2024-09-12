function Get-AzureAutomationRunbookTestJobOutput {
    <#
    .SYNOPSIS
    Get output from last Runbook test run.

    .DESCRIPTION
    Get output from last Runbook test run.

    .PARAMETER runbookName
    Runbook name.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER justText
    Instead of object return just outputted messages of selected type(s).

    Possible values: 'Output', 'Warning', 'Error', 'Exception'

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRunbookTestJobOutput

    Get output of selected Runbook last test run. Output will be returned via array of objects where beside returned text also other properties like type of the output or output time are returned.

    Missing function arguments like $runbookName, $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRunbookTestJobOutput -justText Output

    Get just common (no warnings or errors) output of selected Runbook last test run. Output will be returned as array of strings.

    Missing function arguments like $runbookName, $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.
    #>

    [CmdletBinding()]
    param (
        [string] $resourceGroupName,

        [string] $automationAccountName,

        [string] $runbookName,

        [ValidateSet('Output', 'Warning', 'Error', 'Exception')]
        [string[]] $justText,

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
        $runbookName = Get-AzAutomationRunbook -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroupName | select -ExpandProperty Name | Out-GridView -OutputMode Single -Title "Select runbook you want to change"
    }
    #endregion get missing arguments

    # get ordinary output, warnings, errors
    $result = Invoke-RestMethod2 -method get -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runbooks/$runbookName/draft/testJob/streams?`$filter=properties/time ge 1899-12-30T23:00:00.001Z&api-version=2019-06-01" -headers $header | select -ExpandProperty properties

    # get exceptions
    $testJobStatus = Get-AzureAutomationRunbookTestJobStatus -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -runbookName $runbookName -header $header

    if ($justText) {
        # output specified type of messages (ordinary output, warnings and errors)
        $result | ? streamType -In $justText | select -ExpandProperty Summary

        # output exception message if requested
        if ($justText -contains 'Exception' -and $testJobStatus.exception) {
            $testJobStatus.exception
        }
    } else {
        # output ordinary output, warnings and errors
        $result

        # output exception message
        if ($testJobStatus.exception) {
            [PSCustomObject]@{
                jobStreamId = $null
                summary     = $testJobStatus.exception
                time        = $testJobStatus.endTime
                streamType  = 'Exception'
            }
        }
    }
}
