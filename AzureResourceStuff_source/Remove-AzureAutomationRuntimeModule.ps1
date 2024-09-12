function Remove-AzureAutomationRuntimeModule {
    <#
    .SYNOPSIS
    Function remove selected module from specified Azure Automation runtime.

    .DESCRIPTION
    Function remove selected module from specified Azure Automation runtime.

    .PARAMETER runtimeName
    Name of the runtime environment you want to retrieve.

    If not provided, all runtimes will be returned.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER moduleName
    Name of the module(s) you want to remove.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Remove-AzureAutomationRuntimeModule

    Remove selected module(s) from the specified Automation runtime.
    Missing function arguments like $resourceGroupName or $moduleName will be interactively gathered through Out-GridView GUI.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Remove-AzureAutomationRuntimeModule -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging" -runtimeName Custom_PSH_51 -moduleName CommonStuff

    Remove module CommonStuff from the specified Automation runtime.
    #>

    [CmdletBinding()]
    param (
        [string] $runtimeName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [string[]] $moduleName,

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

    while (!$runtimeName) {
        $runtimeName = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -programmingLanguage PowerShell -runtimeSource Custom | select -ExpandProperty Name | Out-GridView -OutputMode Single -Title "Select runtime you want to process"
    }

    if (!$moduleName) {
        while (!$moduleName) {
            $moduleName = Get-AzureAutomationRuntimeCustomModule -runtimeName $runtimeName -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -moduleName $moduleName -header $header | select -ExpandProperty Name | Out-GridView -OutputMode Multiple -Title "Select module(s) you want to remove"
        }
    } else {
        $moduleExists = Get-AzureAutomationRuntimeCustomModule -runtimeName $runtimeName -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -moduleName $moduleName -header $header
        if (!$moduleExists) {
            throw "Module $moduleName doesn't exist in specified Automation environment"
        }
    }
    #endregion get missing arguments

    foreach ($modName in $moduleName) {
        Write-Verbose "Removing module $modName"

        Invoke-RestMethod2 -method Delete -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runtimeEnvironments/$runtimeName/packages/$modName`?api-version=2023-05-15-preview" -headers $header
    }
}