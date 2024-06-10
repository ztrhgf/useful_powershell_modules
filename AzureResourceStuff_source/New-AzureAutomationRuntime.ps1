function New-AzureAutomationRuntime {
    <#
    .SYNOPSIS
    Function creates a new custom Azure Automation Account Runtime.

    .DESCRIPTION
    Function creates a new custom Azure Automation Account Runtime.

    Both Powershell nad Python runtimes are supported. Powershell one supports specifying Az module version.

    .PARAMETER runtimeName
    Name of the created runtime.

    .PARAMETER runtimeLanguage
    Language that will be used in created runtime.

    Possible values are PowerShell, Python.

    .PARAMETER runtimeVersion
    Version of the runtimeLanguage.

    For Python it is 3.8, 3.10, for PowerShell '5.1', '7.1', '7.2', but this will likely change in the future.

    .PARAMETER defaultPackage
    Only use for PowerShell runtimeLanguage!

    Hashtable where keys are default module names ('az' (both PSHs), 'azure cli' (only in PSH Core)) and values are module versions.

    If no defaultPackage hashtable is provided, no default modules will be enabled in created runtime.

    .PARAMETER description
    Runtime description.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    $defaultPackage = @{
        az = '8.0.0'
    }

    New-AzureAutomationRuntime -runtimeName 'CustomPSH51' -runtimeLanguage 'PowerShell' -runtimeVersion 5.1 -defaultPackage $defaultPackage -description 'PSH 5.1 for testing purposes' -resourceGroupName 'AdvancedLoggingRG' -automationAccountName 'EnableO365AdvancedLogging'

    Create new custom Powershell 5.1 runtime with Az module 8.0.0 enabled.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    New-AzureAutomationRuntime -runtimeName 'CustomPSH51' -runtimeLanguage 'PowerShell' -runtimeVersion 5.1 -description 'PSH 5.1 for testing purposes' -resourceGroupName 'AdvancedLoggingRG' -automationAccountName 'EnableO365AdvancedLogging'

    Create a new custom Powershell 5.1 runtime without Az module enabled.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    $defaultPackage = @{
        'az' = '8.0.0'
        'azure cli' = '2.56.0'
    }

    New-AzureAutomationRuntime -runtimeName 'CustomPSH72' -runtimeLanguage 'PowerShell' -runtimeVersion 7.2 -defaultPackage $defaultPackage -description 'PSH 7.2 for testing purposes' -resourceGroupName 'AdvancedLoggingRG' -automationAccountName 'EnableO365AdvancedLogging'

    Create a new custom Powershell 7.2 runtime with 'Az module 8.0.0' and 'azure cli 2.56.0' enabled.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    New-AzureAutomationRuntime -runtimeName 'CustomPython310' -runtimeLanguage 'Python' -runtimeVersion 3.10 -description 'Python 3.10 for testing purposes' -resourceGroupName 'AdvancedLoggingRG' -automationAccountName 'EnableO365AdvancedLogging'

    Create a new custom Python 3.10 runtime.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $runtimeName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('PowerShell', 'Python')]
        [string] $runtimeLanguage,

        [ArgumentCompleter( {
                param ($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)

                if ($runtimeLanguage = $FakeBoundParams.runtimeLanguage) {
                    switch ($runtimeLanguage) {
                        'PowerShell' {
                            '5.1', '7.1', '7.2' | ? { $_ -like "*$WordToComplete*" }
                        }

                        'Python' {
                            '3.8', '3.10' | ? { $_ -like "*$WordToComplete*" }
                        }
                    }
                }
            })]
        [string] $runtimeVersion,

        [hashtable] $defaultPackage,

        [string] $description,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [hashtable] $header
    )

    #region checks
    if ($defaultPackage -and $runtimeLanguage -ne 'PowerShell') {
        Write-Warning "Parameter 'defaultModuleData' can be defined only for 'PowerShell' runtime language. Will be ignored."
        $defaultPackage = @{}
    }

    if (!$defaultPackage -and $runtimeLanguage -eq 'PowerShell') {
        $defaultPackage = @{}
    }
    #endregion checks

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
    #endregion get missing arguments

    #region checks
    try {
        $runtime = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -runtimeName $runtimeName -ErrorAction Stop
    } catch {
        if ($_.exception.StatusCode -ne 'NotFound') {
            throw $_
        }
    }

    if ($runtime) {
        # prevent accidental replacing of the existing runtime
        throw "Runtime with given name '$runtimeName' already exist"
    }
    #endregion checks

    #region send web request
    $body = @{
        properties = @{
            runtime         = @{
                language = $runtimeLanguage
                version  = $runtimeVersion
            }
            defaultPackages = $defaultPackage
            description     = $description
        }
    }

    $body = $body | ConvertTo-Json

    Write-Verbose $body

    Invoke-RestMethod2 -method Put -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runtimeEnvironments/$runtimeName`?api-version=2023-05-15-preview" -body $body -headers $header
    #endregion send web request
}