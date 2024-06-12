function Update-AzureAutomationRunbookModule {
    <#
    .SYNOPSIS
    Function updates all/selected custom modules in given Azure Automation Account Environment Runtime.

    Custom module means module you have to explicitly import (not 'Az' or 'azure cli').

    .DESCRIPTION
    Function updates all/selected custom modules in given Azure Automation Account Environment Runtime.

    Custom module means module you have to explicitly import (not 'Az' or 'azure cli').

    .PARAMETER moduleName
    Name of the module you want to add/(replace by other version).

    .PARAMETER moduleVersion
    Target module version you want to update to.

    Applies to all updated modules!

    If not specified, newest supported version for used runtime language version will be gathered from PSGallery.

    .PARAMETER allCustomModule
    Parameter description

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER runtimeName
    Name of the runtime environment you want to retrieve.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Update-AzureAutomationRunbookModule -moduleName CommonStuff -moduleVersion 1.0.18

    Updates module CommonStuff to the version 1.0.18 in the specified Automation runtime(s).
    If module has some dependencies, that are currently missing (or have incorrect version), they will be imported automatically.

    Missing function arguments like $runtimeName, $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Update-AzureAutomationRunbookModule -moduleName CommonStuff

    Updates module CommonStuff to the newest available version in the specified Automation runtime(s).
    If module has some dependencies, that are currently missing (or have incorrect version), they will be imported automatically.

    Missing function arguments like $runtimeName, $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    Update-AzureAutomationRunbookModule -allCustomModule

    Updates all custom modules to the newest available version in the specified Automation runtime(s).
    If module(s) have some dependencies, that are currently missing (or have incorrect version), they will be imported automatically.

    Missing function arguments like $runtimeName, $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.
    #>

    [CmdletBinding()]
    param (
        [string[]] $moduleName,

        [string] $moduleVersion,

        [switch] $allCustomModule,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [string[]] $runtimeName,

        [hashtable] $header
    )

    if ($allCustomModule -and $moduleName) {
        throw "Choose moduleName or allCustomModule"
    }

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    #region get missing arguments
    if (!$header) {
        $header = New-AzureAutomationGraphToken
    }

    $subscriptionId = (Get-AzContext).Subscription.Id
    $subscription = $((Get-AzContext).Subscription.Name)

    $automationAccount = Get-AzAutomationAccount -ResourceGroupName $resourceGroupName

    while (!$resourceGroupName) {
        $resourceGroupName = Get-AzResourceGroup | select -ExpandProperty ResourceGroupName | Out-GridView -OutputMode Single -Title "Select resource group you want to process"
    }

    while (!$automationAccountName) {
        $automationAccountName = Get-AzAutomationAccount -ResourceGroupName $resourceGroupName | select -ExpandProperty AutomationAccountName | Out-GridView -OutputMode Single -Title "Select automation account you want to process"
    }

    while (!$runtimeName) {
        $runtimeName = Get-AzureAutomationRuntime -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -programmingLanguage PowerShell -runtimeSource Custom -header $header | select -ExpandProperty Name | Out-GridView -OutputMode Multiple -Title "Select environment you want to process"
    }

    $runtimeVersion = $runtime.properties.runtime.version
    #endregion get missing arguments

    foreach ($runtName in $runtimeName) {
        "Processing Runtime '$runtName' (ResourceGroup: '$resourceGroupName' Subscription: '$subscription')"

        $currentAutomationCustomModules = Get-AzureAutomationRuntimeCustomModule -automationAccountName $atmAccountName -ResourceGroup $atmAccountResourceGroup -runtimeName $runtName -header $header

        if ($allCustomModule) {
            $automationModulesToUpdate = $currentAutomationCustomModules
        } elseif ($moduleName) {
            $automationModulesToUpdate = $currentAutomationCustomModules | ? Name -In $moduleName

            if ($moduleVersion -and $automationModulesToUpdate) {
                Write-Verbose "Selecting only module(s) with version $moduleVersion or lower"
                $automationModulesToUpdate = $automationModulesToUpdate | ? { [version]$_.Version -lt [version] $moduleVersion }
            }
        } else {
            $automationModulesToUpdate = $currentAutomationCustomModules | Out-GridView -PassThru -Title "Select module(s) to update"

            if ($moduleVersion -and $automationModulesToUpdate) {
                Write-Verbose "Selecting only module(s) with version $moduleVersion or lower"
                $automationModulesToUpdate = $automationModulesToUpdate | ? { [version]$_.Version -lt [version] $moduleVersion }
            }
        }

        if (!$automationModulesToUpdate) {
            Write-Warning "No module match the selected update criteria. Skipping"
            continue
        }

        foreach ($module in $automationModulesToUpdate) {
            $moduleName = $module.Name
            $requiredModuleVersion = $moduleVersion

            #region get PSGallery module data
            $param = @{
                # IncludeDependencies = $true # cannot be used, because always returns newest available modules, I want to use existing modules if possible (to minimize risk that something will stop working)
                Name        = $moduleName
                ErrorAction = "Stop"
            }
            if ($requiredModuleVersion) {
                $param.RequiredVersion = $requiredModuleVersion
            } else {
                $param.AllVersions = $true
            }

            $moduleGalleryInfo = Find-Module @param
            #endregion get PSGallery module data

            # get newest usable module version for given runtime
            if (!$requiredModuleVersion -and $runtimeVersion -eq '5.1') {
                # no specific version was selected and older PSH version is used, make sure module that supports it, will be found
                # for example (currently newest) pnp.powershell 2.3.0 supports only PSH 7.2
                $moduleGalleryInfo = $moduleGalleryInfo | ? { $_.AdditionalMetadata.PowerShellVersion -le $runtimeVersion } | select -First 1
            }

            if (!$moduleGalleryInfo) {
                Write-Error "No supported $moduleName module was found in PSGallery"
                continue
            }

            if (!$requiredModuleVersion) {
                # no version specified, newest version from PSGallery will be used"
                $requiredModuleVersion = $moduleGalleryInfo.Version

                if ($requiredModuleVersion -eq $module.Version) {
                    Write-Warning "Module $moduleName already has newest available version $requiredModuleVersion. Skipping"
                    continue
                }
            }

            $param = @{
                resourceGroupName     = $module.ResourceGroupName
                automationAccountName = $module.AutomationAccountName
                runtimeName           = $runtimeName
                moduleName            = $module.Name
                runtimeVersion        = $runtimeVersion
                moduleVersion         = $requiredModuleVersion
                header                = $header
            }

            "Updating module $($module.Name) $($module.Version) >> $requiredModuleVersion"
            New-AzureAutomationRuntimeModule @param
        }
    }
}