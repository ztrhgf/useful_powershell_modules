function Get-AzureAutomationRuntimeSelectedDefaultModule {
    <#
    .SYNOPSIS
    Function get default module (Az) that is selected in the specified Azure Automation runtime.

    .DESCRIPTION
    Function get default module (Az) that is selected in the specified Azure Automation runtime.

    Custom modules are added by user, default ones are built-in (Az) and user just select version to use.

    .PARAMETER runtimeName
    Name of the runtime environment you want to retrieve.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRuntimeSelectedDefaultModule

    You will get list of all (in current subscription) resource groups, automation accounts and runtimes to pick the one you are interested in.
    And you will get default module name (AZ) and its version that is selected in the specified Automation runtime.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRuntimeSelectedDefaultModule -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging" -runtimeName Custom_PSH_51

    Get default module (Az) version in the specified Automation runtime.
    #>

    [CmdletBinding()]
    [Alias("Get-AzureAutomationRuntimeAzModule")]
    param (
        [string] $runtimeName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

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

    while (!$runtimeName) {
        $runtimeName = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -programmingLanguage PowerShell | select -ExpandProperty Name | Out-GridView -OutputMode Single -Title "Select environment you want to process"
    }
    #endregion get missing arguments

    Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -runtimeName $runtimeName -header $header | select -ExpandProperty properties | select -ExpandProperty defaultPackages | % {
        $module = $_
        $moduleName = $_ | Get-Member -MemberType NoteProperty | select -ExpandProperty Name
        $moduleVersion = $module.$moduleName

        [PSCustomObject]@{
            Name    = $moduleName
            Version = $moduleVersion
        }
    }
}