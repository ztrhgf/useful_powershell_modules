function Get-AzureAutomationRuntimeCustomModule {
    <#
    .SYNOPSIS
    Function gets all (or just selected) custom modules (packages) that are imported in the specified PowerShell Azure Automation runtime.

    .DESCRIPTION
    Function gets all (or just selected) custom modules (packages) that are imported in the specified PowerShell Azure Automation runtime.

    Custom modules are added by user, default ones are built-in (Az) and user just select version to use.

    .PARAMETER runtimeName
    Name of the runtime environment you want to retrieve.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER moduleName
    Name of the custom module you want to get.

    If not provided, all custom modules will be returned.

    .PARAMETER simplified
    Switch to return only name and version of successfully imported modules.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRuntimeCustomModule

    You will get list of all (in current subscription) resource groups, automation accounts and runtimes to pick the one you are interested in.
    And the output will be all custom modules imported in the specified Automation runtime.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRuntimeCustomModule -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging" -runtimeName Custom_PSH_51 -moduleName CommonStuff

    Get custom module CommonStuff imported in the specified Automation runtime.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRuntimeCustomModule -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging" -runtimeName Custom_PSH_51

    Get all custom modules imported in the specified Automation runtime.
    #>

    [CmdletBinding()]
    param (
        [string] $runtimeName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [string] $moduleName,

        [switch] $simplified,

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

    while (!$runtimeName) {
        $runtimeName = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -programmingLanguage PowerShell | select -ExpandProperty Name | Out-GridView -OutputMode Single -Title "Select runtime you want to process"
    }
    #endregion get missing arguments

    $result = Invoke-RestMethod2 -method Get -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runtimeEnvironments/$runtimeName/packages/$moduleName`?api-version=2023-05-15-preview" -headers $header

    if ($simplified) {
        $result | ? { $_.properties.provisioningState -eq 'Succeeded' } | select @{n = 'Name'; e = { $_.Name } }, @{n = 'Version'; e = { $version = $_.properties.version; if ($version -eq 'Unknown') { $null } else { $version } } }
    } else {
        $result
    }
}