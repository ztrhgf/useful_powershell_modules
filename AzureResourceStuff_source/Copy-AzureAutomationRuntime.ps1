function Copy-AzureAutomationRuntime {
    <#
    .SYNOPSIS
    Make a copy of existing Azure Automation Runtime Environment.

    .DESCRIPTION
    Make a copy of existing Azure Automation Runtime Environment.

    Copy will have:
    - same default and custom modules
    - same language, version and description

    Copy is by default created in the same Automation Account, but can be placed in different one too.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER runtimeName
    Name of the runtime to copy.

    .PARAMETER newResourceGroupName
    Destination Resource group name.
    If not specified, source one will be used.

    .PARAMETER newAutomationAccountName
    Destination Automation account name.

    If not specified, source one will be used.

    .PARAMETER newRuntimeName
    Name of the new runtime.

    If not specified, it will be "copy_<sourceRuntimeName>".

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Copy-AzureAutomationRuntime

    Creates a copy of the selected Runtime in the same Automation Account. It will be named like "copy_<sourceRuntimeName>".

    Missing function arguments like $runtimeName, $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Copy-AzureAutomationRuntime -runtimeName "Runtime51" -newRuntimeName "Runtime51_v2" -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging"

    Creates a copy of the selected Runtime in the same Automation Account.
    #>

    [CmdletBinding()]
    param (
        [string] $resourceGroupName,

        [string] $automationAccountName,

        [string] $runtimeName,

        [string] $newResourceGroupName,

        [string] $newAutomationAccountName,

        [string] $newRuntimeName,

        [hashtable] $header
    )

    if (!(Get-Command 'Get-AzAccessToken -AsSecureString' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -AsSecureString -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    if (($newResourceGroupName -and !$newAutomationAccountName) -or (!$newResourceGroupName -and $newAutomationAccountName)) {
        throw "Either both 'newResourceGroupName' and 'newAutomationAccountName' parameters have to be set or neither of them"
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
        $runtimeName = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -programmingLanguage PowerShell -runtimeSource Custom -header $header | select -ExpandProperty Name | Out-GridView -OutputMode Single -Title "Select environment you want to process"
    }
    #endregion get missing arguments

    # get all custom modules
    Write-Verbose "Get Runtime '$runtimeName' custom modules"
    $customModule = Get-AzureAutomationRuntimeCustomModule -runtimeName $runtimeName -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -ErrorAction Stop

    # get all default modules
    Write-Verbose "Get Runtime '$runtimeName' default modules"
    $defaultPackageObj = Get-AzureAutomationRuntimeSelectedDefaultModule -runtimeName $runtimeName -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -ErrorAction Stop

    # get runtime language, version, description
    Write-Verbose "Get Runtime '$runtimeName' information"
    $runtime = Get-AzureAutomationRuntime -runtimeName $runtimeName -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -ErrorAction Stop

    $runtimeLanguage = $runtime.properties.runtime.language
    $runtimeVersion = $runtime.properties.runtime.version
    $runtimeDescription = $runtime.properties.description

    #region create new runtime with language, version and default modules
    if (!$newResourceGroupName) {
        $newResourceGroupName = $resourceGroupName
    }
    if (!$newAutomationAccountName) {
        $newAutomationAccountName = $automationAccountName
    }
    if (!$newRuntimeName) {
        $newRuntimeName = "copy_$runtimeName"
    }

    if ($defaultPackageObj) {
        # transform $defaultPackageObj to hashtable
        $defaultPackage = @{}

        $moduleNameList = $defaultPackageObj | Get-Member -MemberType NoteProperty | select -ExpandProperty Name
        $moduleNameList | % {
            $defaultPackage.$_ = $defaultPackageObj.$_
        }
    } else {
        # no default modules needed
        $defaultPackage = @{}
    }

    "Creating new runtime '$newRuntimeName'"
    $null = New-AzureAutomationRuntime -runtimeName $newRuntimeName -resourceGroupName $newResourceGroupName -automationAccountName $newAutomationAccountName -runtimeLanguage $runtimeLanguage -runtimeVersion $runtimeVersion -defaultPackage $defaultPackage -description $runtimeDescription -header $header
    #region create new runtime with language, version and default modules

    # add custom modules
    foreach ($custModule in $customModule) {
        $name = $custModule.name
        $version = $custModule.properties.version
        $provisioningState = $custModule.properties.provisioningState

        if ($provisioningState -ne 'Succeeded') {
            Write-Verbose "Skipping adding custom module '$name', because it is in '$provisioningState' provisioning state"
            continue
        }

        "Adding custom module '$name' $version"
        New-AzureAutomationRuntimeModule -runtimeName $newRuntimeName -resourceGroupName $newResourceGroupName -automationAccountName $newAutomationAccountName -moduleName $name -moduleVersion $version -header $header
    }
}