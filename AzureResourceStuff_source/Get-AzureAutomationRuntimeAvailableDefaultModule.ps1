function Get-AzureAutomationRuntimeAvailableDefaultModule {
    <#
    .SYNOPSIS
    Function returns default modules (Az) available to select in selected/all PSH runtime(s).

    .DESCRIPTION
    Function returns default modules (Az) available to select in selected/all PSH runtime(s).

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER runtimeName
    (optional) runtime name you want to get default modules for.

    If not provided, all default modules for all PSH runtimes in given automation account will be outputted.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRuntimeAvailableDefaultModule

    You will get list of all resource groups and automation accounts (in current subscription) to pick the one you are interested in.
    And the output will be all default modules (Az) that are available to select there.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Get-AzureAutomationRuntimeAvailableDefaultModule -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging" -runtimeName "PSH51_Custom"

    And the output will be default modules (Az) that are available to select in given Runtime Environment.
    #>

    [CmdletBinding()]
    param (
        [string] $resourceGroupName,

        [string] $automationAccountName,

        [string] $runtimeName,

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
    #endregion get missing arguments

    if ($runtimeName) {
        # get available default modules for this specific runtime
        # for this we need to get used PowerShell version
        $runtime = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -runtimeName $runtimeName -programmingLanguage PowerShell -ErrorAction Stop

        if (!$runtime) {
            throw "Runtime Environment wasn't found. Name is misspelled or it is not a PSH runtime"
        }

        $runtimeVersion = $runtime.properties.runtime.version

        if ($runtimeVersion -eq '5.1') {
            $runtimeLanguageVersion = 'powershell'
        } elseif ($runtimeVersion -eq '7.1') {
            $runtimeLanguageVersion = 'powershell7'
        } else {
            # hopefully MS will stick with this format
            $runtimeLanguageVersion = ('powershell' + ($runtimeVersion -replace '\.'))
        }

        Write-Verbose "Available default modules will be limited to $runtimeLanguageVersion runtime language"
    } else {
        $runtimeLanguageVersion = '*'
    }

    $result = Invoke-RestMethod2 -method Post -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/listbuiltinmodules?api-version=2023-05-15-preview" -headers $header

    if ($result) {
        # instead of one object containing all runtimes return one object per runtime
        $result | Get-Member -MemberType NoteProperty | select -ExpandProperty Name | ? { $_ -like $runtimeLanguageVersion } | % {
            $runtimeLanguage = $_
            $result.$runtimeLanguage | select @{n = 'RuntimeLanguage'; e = { $runtimeLanguage } }, *
        }
    }
}