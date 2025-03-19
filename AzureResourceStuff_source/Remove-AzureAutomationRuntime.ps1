function Remove-AzureAutomationRuntime {
    <#
    .SYNOPSIS
    Removes selected Azure Automation Account Runtime(s).

    .DESCRIPTION
    Removes selected Azure Automation Account Runtime(s).

    .PARAMETER runtimeName
    Name of the runtime environment you want to remove.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Remove-AzureAutomationRuntime

    Removes selected Automation Runtime.

    Missing function arguments like $runtimeName, $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Remove-AzureAutomationRuntime -runtimeName "PSH51Custom" -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging"

    Removes "PSH51Custom" Automation Runtime from given Automation Account.
    #>

    [CmdletBinding()]
    param (
        [string[]] $runtimeName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [hashtable] $header
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
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

    if ($runtimeName) {
        foreach ($runtName in $runtimeName) {
            Write-Verbose "Checking existence of $runtName runtime"
            try {
                $runtime = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -runtimeName $runtName -ErrorAction Stop
            } catch {
                if ($_.exception.StatusCode -eq 'NotFound') {
                    throw "Runtime '$runtName' doesn't exist"
                } else {
                    throw $_
                }
            }
        }
    } else {
        while (!$runtimeName) {
            $runtimeName = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -programmingLanguage PowerShell -runtimeSource Custom | select -ExpandProperty Name | Out-GridView -OutputMode Multiple -Title "Select runtime you want to process"
        }
    }
    #endregion get missing arguments

    foreach ($runtName in $runtimeName) {
        Write-Verbose "Removing $runtName runtime"

        Invoke-RestMethod2 -method delete -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runtimeEnvironments/$runtName`?api-version=2023-05-15-preview" -body $body -headers $header
    }
}