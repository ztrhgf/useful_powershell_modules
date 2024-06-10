function Set-AzureAutomationRuntimeDescription {
    <#
    .SYNOPSIS
    Function set Azure Automation Account Runtime description.

    .DESCRIPTION
    Function set Azure Automation Account Runtime description.

    .PARAMETER runtimeName
    Name of the runtime environment you want to update.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER description
    Runtime description.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Set-AzureAutomationRuntimeDescription -description "testing runtime"

    Set given description in given Automation Runtime.
    Missing function arguments like $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Set-AzureAutomationRuntimeDescription -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging" -description "testing runtime"

    Set given description in given Automation Runtime.
    #>

    [CmdletBinding()]
    param (
        [string] $runtimeName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [Parameter(Mandatory = $true)]
        [string] $description,

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

    #region send web request
    $body = @{
        "properties" = @{
            "description" = $description
        }
    }
    $body = $body | ConvertTo-Json

    Write-Verbose $body

    Invoke-RestMethod2 -method Patch -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runtimeEnvironments/$runtimeName`?api-version=2023-05-15-preview" -body $body -headers $header
    #endregion send web request
}