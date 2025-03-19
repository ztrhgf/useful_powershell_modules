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

    .PARAMETER safely
    Switch to create copy of the runtime before updating its modules.
    Such "copy" will be set as the new runtime for all affected runbooks before update process starts.
    After update process finishes, affected runbooks will be switched back to the updated runtime and runtime copy will be deleted.

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

        [switch] $safely,

        [hashtable] $header
    )

    if ($allCustomModule -and $moduleName) {
        throw "Choose moduleName or allCustomModule"
    }

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    #region get missing arguments
    if (!$header) {
        $header = New-AzureAutomationGraphToken
    }

    $subscriptionId = (Get-AzContext).Subscription.Id
    $subscription = $((Get-AzContext).Subscription.Name)

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
        "Processing Runtime '$runtName' (AutomationAccountName $automationAccountName ResourceGroup: '$resourceGroupName' Subscription: '$subscription')"

        $currentAutomationCustomModules = Get-AzureAutomationRuntimeCustomModule -automationAccountName $automationAccountName -ResourceGroup $resourceGroupName -runtimeName $runtName -header $header -ErrorAction Stop

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

        if ($safely) {
            $bkpRuntName = $runtName + "_" + (Get-Random)
            "Creating runtime '$runtName' backup named '$bkpRuntName'"
            $null = Copy-AzureAutomationRuntime -runtimeName $runtName -newRuntimeName $bkpRuntName -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header -ErrorAction Stop

            # get all existing runbooks
            $runbookList = Get-AzAutomationRunbook -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroupName | ? RunbookType -EQ "PowerShell" | select -ExpandProperty Name

            # find out which runbooks use runtime thats being updated
            $affectedRunbookList = $runbookList | ? { (Get-AzureAutomationRunbookRuntime -automationAccountName $automationAccountName -resourceGroupName $resourceGroupName -runbookName $_ -header $header).Name -eq $runtName }

            # change runtime to the backup (old one) before updating the modules for each affected runbook
            $affectedRunbookList | % {
                "Changing runtime used in '$_' runbook to '$bkpRuntName'"
                Set-AzureAutomationRunbookRuntime -runtimeName $bkpRuntName -runbookName $_ -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header
            }
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
                $requiredModuleVersion = $moduleGalleryInfo.Version | select -First 1

                if ($requiredModuleVersion -eq $module.Version) {
                    Write-Warning "Module $moduleName already has newest available version $requiredModuleVersion. Skipping"
                    continue
                }
            }

            $param = @{
                resourceGroupName     = $resourceGroupName
                automationAccountName = $automationAccountName
                runtimeName           = $runtName
                moduleName            = $module.Name
                moduleVersion         = $requiredModuleVersion
                header                = $header
            }

            "Updating module $($module.Name) $($module.Version) >> $requiredModuleVersion"
            New-AzureAutomationRuntimeModule @param
        }

        if ($safely) {
            # change runtime from the backup (old one) created before updating the modules, to the original one
            $affectedRunbookList | % {
                "Changing runtime used in '$_' runbook back to '$runtName'"
                $null = Set-AzureAutomationRunbookRuntime -runtimeName $runtName -runbookName $_ -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header
            }

            "Removing backup runtime '$bkpRuntName'"
            $null = Remove-AzureAutomationRuntime -runtimeName $bkpRuntName -resourceGroupName $resourceGroupName -automationAccountName $automationAccountName -header $header
        }
    }
}