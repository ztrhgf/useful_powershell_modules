function Get-AzureAutomationRuntime {
    <#
    .SYNOPSIS
    Function returns selected/all Azure Automation runtime environment/s.

    .DESCRIPTION
    Function returns selected/all Azure Automation runtime environment/s.

    .PARAMETER runtimeName
    Name of the runtime environment you want to retrieve.

    If not provided, all runtimes will be returned.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER programmingLanguage
    Filter runtimes to just ones using selected language.

    Possible values: All, PowerShell, Python.

    By default: All

    .PARAMETER runtimeSource
    Filter runtimes by source of creation.

    Possible values: All, Default, Custom.

    By default: All

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRuntime -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging"

    Get all Automation Runtimes in given Automation Account.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRuntime -programmingLanguage PowerShell -runtimeSource Custom

    Get just PowerShell based manually created Automation Runtimes in given Automation Account.

    Missing function arguments like $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.

    .NOTES
    https://learn.microsoft.com/en-us/rest/api/automation/runtime-environments/get?view=rest-automation-2023-05-15-preview&tabs=HTTP
    #>

    [CmdletBinding()]
    param (
        [string] $runtimeName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [ValidateSet('PowerShell', 'Python', 'All')]
        [string] $programmingLanguage = 'All',

        [ValidateSet('Default', 'Custom', 'All')]
        [string] $runtimeSource = 'All',

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
    #endregion get missing arguments

    $result = Invoke-RestMethod2 -method Get -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runtimeEnvironments/$runtimeName/?api-version=2023-05-15-preview" -headers $header -ErrorAction $ErrorActionPreference

    #region filter results
    if ($result -and $programmingLanguage -ne 'All') {
        $result = $result | ? { $_.Properties.Runtime.language -eq $programmingLanguage }
    }

    if ($result -and $runtimeSource -ne 'All') {
        switch ($runtimeSource) {
            'Default' {
                $result = $result | ? { $_.Properties.Description -like "System-generated Runtime Environment for your Automation account with Runtime language:*" }
            }

            'Custom' {
                $result = $result | ? { $_.Properties.Description -notlike "System-generated Runtime Environment for your Automation account with Runtime language:*" }
            }

            default {
                throw "Undefined runtimeSource ($runtimeSource)"
            }
        }
    }
    #endregion filter results

    $result
}