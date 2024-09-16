function Start-AzureAutomationRunbookTestJob {
    <#
    .SYNOPSIS
    Start selected Runbook test job using selected Runtime.

    .DESCRIPTION
    Start selected Runbook test job using selected Runtime.

    Runtime will be used only for this test job, no permanent change to the Runbook will be made.

    To get the test job results use Get-AzureAutomationRunbookTestJobOutput, to get overall status use Get-AzureAutomationRunbookTestJobStatus.

    .PARAMETER runbookName
    Runbook name you want to run.

    .PARAMETER runtimeName
    Runtime name you want to use for a test job.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER wait
    Switch for waiting the Runbook test job to end and returning the job status.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Start-AzureAutomationRunbookTestJob

    Start selected Runbook test job using selected Runtime.

    Missing function arguments like $runbookName, $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.

    To get the test job results use Get-AzureAutomationRunbookTestJobOutput, to get overall status use Get-AzureAutomationRunbookTestJobStatus.
    #>

    [CmdletBinding()]
    [Alias("Invoke-AzureAutomationRunbookTestJob")]
    param (
        [string] $runbookName,

        [string] $runtimeName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [switch] $wait,

        [hashtable] $header
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
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
        $runbookName = Get-AzAutomationRunbook -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroupName | select -ExpandProperty Name | Out-GridView -OutputMode Single -Title "Select runbook you want to start"
    }

    #region get runbook language
    $runbook = Get-AzAutomationRunbook -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroupName -Name $runbookName -ErrorAction Stop

    $runbookType = $runbook.RunbookType
    if ($runbookType -eq 'python2') {
        $programmingLanguage = 'Python'
    } else {
        $programmingLanguage = $runbookType
    }
    #endregion get runbook language

    $currentRuntimeName = Get-AzureAutomationRunbookRuntime -automationAccountName $automationAccountName -resourceGroupName $resourceGroupName -runbookName $runbookName -header $header -ErrorAction Stop

    while (!$runtimeName) {
        $runtimeName = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -programmingLanguage $programmingLanguage -header $header | select -ExpandProperty Name | Out-GridView -OutputMode Single -Title "Select environment you want to test (currently used '$currentRuntimeName')"
    }
    #endregion get missing arguments

    #region send web request
    $body = @{
        properties = @{
            "runtimeEnvironment" = $runtimeName
            "runOn"              = ""
            "parameters"         = @{}
        }
    }

    $body = $body | ConvertTo-Json

    Write-Verbose $body

    Write-Information "Starting Runbook '$runbookName' test job using Runtime '$runtimeName'"

    try {
        $null = Invoke-RestMethod2 -method Put -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runbooks/$runbookName/draft/testJob?api-version=2023-05-15-preview" -headers $header -body $body -ErrorAction Stop
    } catch {
        if ($_.ErrorDetails.Message -like "*Test job is already running.*") {
            throw "Test job is currently running. Unable to start a new one."
        } else {
            throw $_
        }
    }
    #endregion send web request

    Write-Verbose "To get the test job results use Get-AzureAutomationRunbookTestJobOutput, to get overall status use Get-AzureAutomationRunbookTestJobStatus."

    if ($wait) {
        Write-Information "Waiting for the Runbook '$runbookName' to finish"
        Write-Information "Job status:"

        $processedStatus = @()

        do {
            $testRunStatus = Get-AzureAutomationRunbookTestJobStatus -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -runbookName $runbookName -header $header

            if ($testRunStatus.Status -notin $processedStatus) {
                $processedStatus += $testRunStatus.Status
                Write-Information "`t$($testRunStatus.Status)"
            }

            Start-Sleep 2
        } while ($testRunStatus.Status -notin "Stopped", "Completed", "Failed")

        $testRunStatus
    }
}