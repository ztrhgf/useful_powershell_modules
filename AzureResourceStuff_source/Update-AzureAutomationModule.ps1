#requires -modules Az.Accounts, Az.Automation
function Update-AzureAutomationModule {
    [CmdletBinding()]
    param (
        [string[]] $moduleName,

        [string] $moduleVersion,

        [switch] $allModule,

        [switch] $allCustomModule,

        [Parameter(Mandatory = $true)]
        [string] $resourceGroupName,

        [string[]] $automationAccountName,

        [ValidateSet('5.1', '7.2')]
        [string] $runtimeVersion = '5.1'
    )

    if ($allCustomModule -and $moduleName) {
        throw "Choose moduleName or allCustomModule"
    }
    if ($allCustomModule -and $allModule) {
        throw "Choose allModule or allCustomModule"
    }

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    $subscription = $((Get-AzContext).Subscription.Name)

    $automationAccount = Get-AzAutomationAccount -ResourceGroupName $resourceGroupName

    if (!$automationAccount) {
        throw "No Automation account found in the current Subscription '$subscription' and Resource group '$resourceGroupName'"
    }

    if ($automationAccountName) {
        $automationAccount = $automationAccount | ? AutomationAccountName -EQ $automationAccountName
    }

    if (!$automationAccount) {
        throw "No Automation account match the selected criteria"
    }

    foreach ($atmAccount in $automationAccount) {
        $atmAccountName = $atmAccount.AutomationAccountName
        $atmAccountResourceGroup = $atmAccount.ResourceGroupName

        "Processing Automation account '$atmAccountName' (ResourceGroup: '$atmAccountResourceGroup' Subscription: '$subscription')"

        $currentAutomationModules = Get-AzAutomationModule -AutomationAccountName $atmAccountName -ResourceGroup $atmAccountResourceGroup -RuntimeVersion $runtimeVersion

        if ($allCustomModule) {
            $automationModulesToUpdate = $currentAutomationModules | ? IsGlobal -EQ $false
        } elseif ($moduleName) {
            $automationModulesToUpdate = $currentAutomationModules | ? Name -In $moduleName
            if ($moduleVersion -and $automationModulesToUpdate) {
                Write-Verbose "Selecting only module(s) with version $moduleVersion or lower"
                $automationModulesToUpdate = $automationModulesToUpdate | ? { [version]$_.Version -lt [version] $moduleVersion }
            }
        } elseif ($allModule) {
            $automationModulesToUpdate = $currentAutomationModules
        } else {
            $automationModulesToUpdate = $currentAutomationModules | Out-GridView -PassThru
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
                $requiredModuleVersion = $moduleGalleryInfo.Version | select -First 1

                if ($requiredModuleVersion -eq $module.Version) {
                    Write-Warning "Module $moduleName already has newest available version $requiredModuleVersion. Skipping"
                    continue
                }
            }

            $param = @{
                resourceGroupName     = $module.ResourceGroupName
                automationAccountName = $module.AutomationAccountName
                moduleName            = $module.Name
                runtimeVersion        = $runtimeVersion
                moduleVersion         = $requiredModuleVersion
            }

            "Updating module $($module.Name) $($module.Version) >> $requiredModuleVersion"
            New-AzureAutomationModule @param
        }
    }
}