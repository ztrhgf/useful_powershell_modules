#requires -modules Az.Accounts, Az.Automation
function New-AzureAutomationModule {
    <#
    .SYNOPSIS
    Function for importing new (or updating existing) Azure Automation PSH module.

    Any module dependencies will be automatically installed too.

    .DESCRIPTION
    Function for importing new (or updating existing) Azure Automation PSH module.

    Any module dependencies will be automatically installed too.

    By default newest supported version is imported (if 'moduleVersion' is not set). If module exists, but with different version, it will be replaced (including its dependencies).

    According the dependencies. If version that can be used exist, it is not updated to the newest possible one, but is used at it is. Reason for this is to avoid unnecessary updates that can lead to unstable/untested environment.

    Supported version means, version that support given runtime ('runtimeVersion' parameter).

    .PARAMETER moduleName
    Name of the PSH module.

    .PARAMETER moduleVersion
    (optional) version of the PSH module.
    If not specified, newest supported version for given runtime will be gathered from PSGallery.

    .PARAMETER resourceGroupName
    Name of the Azure Resource Group.

    .PARAMETER automationAccountName
    Name of the Azure Automation Account.

    .PARAMETER runtimeVersion
    PSH runtime version.

    Possible values: 5.1, 7.1, 7.2.

    By default 5.1.

    .PARAMETER overridePSGalleryModuleVersion
    Hashtable of hashtables where you can specify what module version should be used for given runtime if no specific version is required.

    This is needed in cases, where module newest available PSGallery version isn't compatible with your runtime because of incorrect manifest.

    By default:

    $overridePSGalleryModuleVersion = @{
        # 2.x.x PnP.PowerShell versions (2.1.1, 2.2.0) requires PSH 7.2 even though manifest doesn't say it
        # so the wrong module version would be picked up which would cause an error when trying to import
        "PnP.PowerShell" = @{
            "5.1" = "1.12.0"
        }
    }

    .EXAMPLE
    Connect-AzAccount -Tenant "contoso.onmicrosoft.com" -SubscriptionName "AutomationSubscription"

    New-AzureAutomationModule -resourceGroupName test -automationAccountName test -moduleName "Microsoft.Graph.Groups"

    Imports newest supported version (for given runtime) of the "Microsoft.Graph.Groups" module including all its dependencies.
    In case module "Microsoft.Graph.Groups" with such version is already imported, nothing will happens.
    Otherwise module will be imported/replaced (including all dependencies that are required for this specific version).

    .EXAMPLE
    Connect-AzAccount -Tenant "contoso.onmicrosoft.com" -SubscriptionName "AutomationSubscription"

    New-AzureAutomationModule -resourceGroupName test -automationAccountName test -moduleName "Microsoft.Graph.Groups" -moduleVersion "2.11.1"

    Imports "2.11.1" version of the "Microsoft.Graph.Groups" module including all its dependencies.
    In case module "Microsoft.Graph.Groups" with version "2.11.1" is already imported, nothing will happens.
    Otherwise module will be imported/replaced (including all dependencies that are required for this specific version).
    #>

    [CmdletBinding()]
    [Alias("New-AzAutomationModule2")]
    param (
        [Parameter(Mandatory = $true)]
        [string] $moduleName,

        [string] $moduleVersion,

        [Parameter(Mandatory = $true)]
        [string] $resourceGroupName,

        [Parameter(Mandatory = $true)]
        [string] $automationAccountName,

        [ValidateSet('5.1', '7.1', '7.2')]
        [string] $runtimeVersion = '5.1',

        [int] $indent = 0,

        [hashtable[]] $overridePSGalleryModuleVersion = @{
            # 2.x.x PnP.PowerShell versions (2.1.1, 2.2.0) requires PSH 7.2 even though manifest doesn't say it
            # so the wrong module version would be picked up which would cause an error when trying to import
            "PnP.PowerShell" = @{
                "5.1" = "1.12.0"
            }
        }
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    $indentString = "     " * $indent

    function _write {
        param ($string, $color, [switch] $noNewLine, [switch] $noIndent)

        $param = @{}
        if ($noIndent) {
            $param.Object = $string
        } else {
            $param.Object = ($indentString + $string)
        }
        if ($color) {
            $param.ForegroundColor = $color
        }
        if ($noNewLine) {
            $param.noNewLine = $true
        }

        Write-Host @param
    }

    if ($moduleVersion) {
        $moduleVersionString = "($moduleVersion)"
    } else {
        $moduleVersionString = ""
    }

    _write "Processing module $moduleName $moduleVersionString" "Magenta"

    #region get PSGallery module data
    $param = @{
        # IncludeDependencies = $true # cannot be used, because always returns newest usable module version, I want to use existing modules if possible (to minimize the runtime & risk that something will stop working)
        Name        = $moduleName
        ErrorAction = "Stop"
    }
    if ($moduleVersion) {
        $param.RequiredVersion = $moduleVersion
    } elseif ($runtimeVersion -eq '5.1') {
        $param.AllVersions = $true
    }

    $moduleGalleryInfo = Find-Module @param
    #endregion get PSGallery module data

    # get newest usable module version for given runtime
    if (!$moduleVersion -and $runtimeVersion -eq '5.1') {
        # no specific version was selected and older PSH version is used, make sure module that supports it, will be found
        # for example (currently newest) pnp.powershell 2.3.0 supports only PSH 7.2
        $moduleGalleryInfo = $moduleGalleryInfo | ? { $_.AdditionalMetadata.PowerShellVersion -le $runtimeVersion } | select -First 1
    }

    if (!$moduleGalleryInfo) {
        Write-Error "No supported $moduleName module was found in PSGallery"
        return
    }

    # override module version
    if (!$moduleVersion -and $moduleName -in $overridePSGalleryModuleVersion.Keys -and $overridePSGalleryModuleVersion.$moduleName.$runtimeVersion) {
        $overriddenModule = $overridePSGalleryModuleVersion.$moduleName
        $overriddenModuleVersion = $overriddenModule.$runtimeVersion
        if ($overriddenModuleVersion) {
            _write " (no version specified and override for version exists, hence will be used ($overriddenModuleVersion))"
            $moduleVersion = $overriddenModuleVersion
        }
    }

    if (!$moduleVersion) {
        $moduleVersion = $moduleGalleryInfo.Version
        _write " (no version specified, newest supported version from PSGallery will be used ($moduleVersion))"
    }

    Write-Verbose "Getting current Automation modules"
    $currentAutomationModules = Get-AzAutomationModule -AutomationAccountName $automationAccountName -ResourceGroup $resourceGroupName -RuntimeVersion $runtimeVersion -ErrorAction Stop

    # check whether required module is present
    # there can be module in Failed state, just because update of such module failed, but if it has SizeInBytes set, it means its in working state
    $moduleExists = $currentAutomationModules | ? { $_.Name -eq $moduleName -and $_.SizeInBytes }
    if ($moduleVersion) {
        $moduleExists = $moduleExists | ? Version -EQ $moduleVersion
    }

    if ($moduleExists) {
        return ($indentString + "Module $moduleName ($($moduleExists.Version)) is already present")
    }

    _write " - Getting module $moduleName dependencies"
    $moduleDependency = $moduleGalleryInfo.Dependencies | Sort-Object { $_.name }

    # dependency must be installed first
    if ($moduleDependency) {
        #TODO znacit si jake moduly jsou required (at uz tam jsou nebo musim doinstalovat) a kontrolovat, ze jeden neni required s ruznymi verzemi == konflikt protoze nainstalovana muze byt jen jedna
        _write "  - Depends on: $($moduleDependency.Name -join ', ')"
        foreach ($module in $moduleDependency) {
            $requiredModuleName = $module.Name
            [version]$requiredModuleMinVersion = $module.MinimumVersion
            [version]$requiredModuleMaxVersion = $module.MaximumVersion
            [version]$requiredModuleReqVersion = $module.RequiredVersion
            $notInCorrectVersion = $false

            _write "   - Checking module $requiredModuleName (minVer: $requiredModuleMinVersion maxVer: $requiredModuleMaxVersion reqVer: $requiredModuleReqVersion)"

            # there can be module in Failed state, just because update of such module failed, but if it has SizeInBytes set, it means its in working state
            $existingRequiredModule = $currentAutomationModules | ? { $_.Name -eq $requiredModuleName -and ($_.ProvisioningState -eq "Succeeded" -or $_.SizeInBytes) }
            [version]$existingRequiredModuleVersion = $existingRequiredModule.Version

            # check that existing module version fits
            if ($existingRequiredModule -and ($requiredModuleMinVersion -or $requiredModuleMaxVersion -or $requiredModuleReqVersion)) {

                #TODO pokud nahrazuji existujici modul, tak bych se mel podivat, jestli jsou vsechny ostatni ok s jeho novou verzi
                if ($requiredModuleReqVersion -and $requiredModuleReqVersion -ne $existingRequiredModuleVersion) {
                    $notInCorrectVersion = $true
                    _write "     - module exists, but not in the correct version (has: $existingRequiredModuleVersion, should be: $requiredModuleReqVersion). Will be replaced" "Yellow"
                } elseif ($requiredModuleMinVersion -and $requiredModuleMaxVersion -and ($existingRequiredModuleVersion -lt $requiredModuleMinVersion -or $existingRequiredModuleVersion -gt $requiredModuleMaxVersion)) {
                    $notInCorrectVersion = $true
                    _write "     - module exists, but not in the correct version (has: $existingRequiredModuleVersion, should be: $requiredModuleMinVersion .. $requiredModuleMaxVersion). Will be replaced" "Yellow"
                } elseif ($requiredModuleMinVersion -and $existingRequiredModuleVersion -lt $requiredModuleMinVersion) {
                    $notInCorrectVersion = $true
                    _write "     - module exists, but not in the correct version (has: $existingRequiredModuleVersion, should be > $requiredModuleMinVersion). Will be replaced" "Yellow"
                } elseif ($requiredModuleMaxVersion -and $existingRequiredModuleVersion -gt $requiredModuleMaxVersion) {
                    $notInCorrectVersion = $true
                    _write "     - module exists, but not in the correct version (has: $existingRequiredModuleVersion, should be < $requiredModuleMaxVersion). Will be replaced" "Yellow"
                }
            }

            if (!$existingRequiredModule -or $notInCorrectVersion) {
                if (!$existingRequiredModule) {
                    _write "     - module is missing" "Yellow"
                }

                if ($notInCorrectVersion) {
                    #TODO kontrola, ze jina verze modulu nerozbije zavislost nejakeho jineho existujiciho modulu
                }

                #region install required module first
                $param = @{
                    moduleName            = $requiredModuleName
                    resourceGroupName     = $resourceGroupName
                    automationAccountName = $automationAccountName
                    runtimeVersion        = $runtimeVersion
                    indent                = $indent + 1
                }
                if ($requiredModuleMinVersion) {
                    $param.moduleVersion = $requiredModuleMinVersion
                }
                if ($requiredModuleMaxVersion) {
                    $param.moduleVersion = $requiredModuleMaxVersion
                }
                if ($requiredModuleReqVersion) {
                    $param.moduleVersion = $requiredModuleReqVersion
                }

                New-AzureAutomationModule @param
                #endregion install required module first
            } else {
                if ($existingRequiredModuleVersion) {
                    _write "     - module (ver. $existingRequiredModuleVersion) is already present"
                } else {
                    _write "     - module is already present"
                }
            }
        }
    } else {
        _write "  - No dependency found"
    }

    $uri = "https://www.powershellgallery.com/api/v2/package/$moduleName/$moduleVersion"
    _write " - Uploading module $moduleName ($moduleVersion)" "Yellow"
    $status = New-AzAutomationModule -AutomationAccountName $automationAccountName -ResourceGroup $resourceGroupName -Name $moduleName -ContentLinkUri $uri -RuntimeVersion $runtimeVersion

    #region output dots while waiting on import to finish
    $i = 0
    _write "    ." -noNewLine
    do {
        Start-Sleep 5

        if ($i % 3 -eq 0) {
            _write "." -noNewLine -noIndent
        }

        ++$i
    } while (!($requiredModule = Get-AzAutomationModule -AutomationAccountName $automationAccountName -ResourceGroup $resourceGroupName -RuntimeVersion $runtimeVersion -ErrorAction Stop | ? { $_.Name -eq $moduleName -and $_.ProvisioningState -in "Succeeded", "Failed" }))

    ""
    #endregion output dots while waiting on import to finish

    if ($requiredModule.ProvisioningState -ne "Succeeded") {
        Write-Error "Import failed. Check Azure Portal >> Automation Account >> Modules >> $moduleName details to get the reason."
    } else {
        _write " - Success" "Green"
    }
}