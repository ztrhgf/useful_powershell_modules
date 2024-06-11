# TODO upload WHL souboru pro PYTHON a zip pro PSH
function New-AzureAutomationRuntimeModule {
    <#
    .SYNOPSIS
    Function add/replace selected module in specified Azure Automation runtime by importing it from the PowerShell Gallery.
    If module has some dependencies, that are currently missing (or have incorrect version), they will be imported automatically.

    .DESCRIPTION
    Function add/replace selected module in specified Azure Automation runtime by importing it from the PowerShell Gallery.

    If module exists, it will be replaced by selected version, if it is not, it will be added.

    If module has some dependencies, that are currently missing (or have incorrect version), they will be imported automatically.

    .PARAMETER runtimeName
    Name of the runtime environment you want to retrieve.

    If not provided, all runtimes will be returned.

    .PARAMETER resourceGroupName
    Resource group name.

    .PARAMETER automationAccountName
    Automation account name.

    .PARAMETER moduleName
    Name of the module you want to add/(replace by other version).

    .PARAMETER moduleVersion
    Module version.
    If not specified, newest supported version for given runtime will be gathered from PSGallery.

    .PARAMETER header
    Authentication header that can be created via New-AzureAutomationGraphToken.

    .PARAMETER overridePSGalleryModuleVersion
    Hashtable of hashtables where you can specify what module version should be used for given runtime if no specific version is required.

    This is needed in cases, where newest module version available in PSGallery isn't compatible with your runtime because of incorrect module manifest.

    By default:

    $overridePSGalleryModuleVersion = @{
        # 2.x.x PnP.PowerShell versions (2.1.1, 2.2.0) requires PSH 7.2 even though manifest doesn't say it
        # so the wrong module version would be picked up which would cause an error when trying to import
        "PnP.PowerShell" = @{
            "5.1" = "1.12.0"
        }
    }

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    New-AzureAutomationRuntimeModule -moduleName CommonStuff -moduleVersion 1.0.18

    Add module CommonStuff 1.0.18 to the specified Automation runtime.
    If module exists, it will be replaced by selected version, if it is not, it will be added.
    If module has some dependencies, that are currently missing (or have incorrect version), they will be imported automatically.

    Missing function arguments like $resourceGroupName or $automationAccountName will be interactively gathered through Out-GridView GUI.

    .EXAMPLE
    Connect-AzAccount

    Set-AzContext -Subscription "IT_Testing"

    New-AzureAutomationRuntimeModule -resourceGroupName "AdvancedLoggingRG" -automationAccountName "EnableO365AdvancedLogging" -runtimeName Custom_PSH_51 -moduleName CommonStuff -moduleVersion 1.0.18

    Add module CommonStuff 1.0.18 to specified Automation runtime.
    If module exists, it will be replaced by selected version, if it is not, it will be added.
    #>

    [CmdletBinding()]
    [Alias("Set-AzureAutomationRuntimeModule")]
    param (
        [string] $runtimeName,

        [string] $resourceGroupName,

        [string] $automationAccountName,

        [Parameter(Mandatory = $true)]
        [string] $moduleName,

        [string] $moduleVersion,

        [hashtable] $header,

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

    try {
        $runtime = Get-AzureAutomationRuntime -automationAccountName $automationAccountName -ResourceGroup $resourceGroupName -runtimeName $runtimeName -programmingLanguage PowerShell -runtimeSource Custom -header $header -ErrorAction Stop
    } catch {
        throw "Runtime '$runtimeName' doesn't exist or it isn't custom created PowerShell Runtime"
    }
    $runtimeVersion = $runtime.properties.runtime.version

    $indentString = "     " * $indent

    #region helper functions
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

    function Compare-VersionString {
        # module version can be like "1.0.0", but also like "2.0.0-preview8", "2.0.0-rc3"
        # hence this comparison function
        param (
            [Parameter(Mandatory = $true)]
            $version1,

            [Parameter(Mandatory = $true)]
            $version2,

            [Parameter(Mandatory = $true)]
            [ValidateSet('equal', 'notEqual', 'greaterThan', 'lessThan')]
            $operator
        )

        function _convertResultToBoolean {
            # function that converts 0,1,-1 to true/false based on comparison operator
            param (
                [ValidateSet('equal', 'notEqual', 'greaterThan', 'lessThan')]
                $operator,

                $result
            )

            switch ($operator) {
                "equal" {
                    if ($result -eq 0) {
                        return $true
                    }
                }

                "notEqual" {
                    if ($result -ne 0) {
                        return $true
                    }
                }

                "greaterThan" {
                    if ($result -eq 1) {
                        return $true
                    }
                }

                "lessThan" {
                    if ($result -eq -1) {
                        return $true
                    }
                }

                default { throw "Undefined operator" }
            }

            return $false
        }

        # Split version and suffix
        $v1, $suffix1 = $version1 -split '-', 2
        $v2, $suffix2 = $version2 -split '-', 2

        # Compare versions
        $versionComparison = ([version]$v1).CompareTo([version]$v2)
        if ($versionComparison -ne 0) {
            return (_convertResultToBoolean -operator $operator -result $versionComparison)
        }

        # If versions are equal, compare suffixes
        if ($suffix1 -and !$suffix2) {
            return (_convertResultToBoolean -operator $operator -result -1)
        } elseif (!$suffix1 -and $suffix2) {
            return (_convertResultToBoolean -operator $operator -result 1)
        } elseif (!$suffix1 -and !$suffix2) {
            return (_convertResultToBoolean -operator $operator -result 0)
        } else {
            return (_convertResultToBoolean -operator $operator -result ([string]::Compare($suffix1, $suffix2)))
        }
    }
    #endregion helper functions

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
        if (!($moduleVersion -as [version])) {
            # version is something like "2.2.0.rc4" a.k.a. pre-release version
            $param.AllowPrerelease = $true
        }
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
    $currentAutomationModules = Get-AzureAutomationRuntimeCustomModule -automationAccountName $automationAccountName -ResourceGroup $resourceGroupName -runtimeName $runtimeName -header $header -ErrorAction Stop

    # check whether required module is present
    # there can be module in Failed state, just because update of such module failed, but if it has SizeInBytes set, it means its in working state
    $moduleExists = $currentAutomationModules | ? { $_.Name -eq $moduleName -and ($_.Properties.ProvisioningState -eq "Succeeded" -or $_.Properties.SizeInBytes) }
    if ($moduleExists) {
        $moduleExistsVersion = $moduleExists.Properties.Version
        if ($moduleVersion -and $moduleVersion -ne $moduleExistsVersion) {
            $moduleExists = $null
        }

        if ($moduleExists) {
            return ($indentString + "Module $moduleName ($moduleExistsVersion) is already present")
        } elseif (!$moduleExists -and $indent -eq 0) {
            # some module with that name exists, but not in the correct version and this is not a recursive call (because of dependency processing) hence user was not yet warned about replacing the module
            _write " - Existing module $moduleName ($moduleExistsVersion) will be replaced" "Yellow"
        }
    }

    _write " - Getting module $moduleName dependencies"
    $moduleDependency = $moduleGalleryInfo.Dependencies | Sort-Object { $_.name }

    # dependency must be installed first
    if ($moduleDependency) {
        #TODO znacit si jake moduly jsou required (at uz tam jsou nebo musim doinstalovat) a kontrolovat, ze jeden neni required s ruznymi verzemi == konflikt protoze nainstalovana muze byt jen jedna
        _write "  - Depends on: $($moduleDependency.Name -join ', ')"
        foreach ($module in $moduleDependency) {
            $requiredModuleName = $module.Name
            $requiredModuleMinVersion = $module.MinimumVersion -replace "\[|]" # for some reason version can be like '[2.0.0-preview6]'
            $requiredModuleMaxVersion = $module.MaximumVersion -replace "\[|]"
            $requiredModuleReqVersion = $module.RequiredVersion -replace "\[|]"
            $notInCorrectVersion = $false

            _write "   - Checking module $requiredModuleName (minVer: $requiredModuleMinVersion maxVer: $requiredModuleMaxVersion reqVer: $requiredModuleReqVersion)"

            # there can be module in Failed state, just because update of such module failed, but if it has SizeInBytes set, it means its in working state
            $existingRequiredModule = $currentAutomationModules | ? { $_.Name -eq $requiredModuleName -and ($_.Properties.ProvisioningState -eq "Succeeded" -or $_.Properties.SizeInBytes) }
            $existingRequiredModuleVersion = $existingRequiredModule.Properties.Version # version always looks like n.n.n. suffixes like rc, beta etc are always cut off!

            # check that existing module version fits
            if ($existingRequiredModule -and ($requiredModuleMinVersion -or $requiredModuleMaxVersion -or $requiredModuleReqVersion)) {
                #TODO pokud nahrazuji existujici modul, tak bych se mel podivat, jestli jsou vsechny ostatni ok s jeho novou verzi
                if ($requiredModuleReqVersion -and (Compare-VersionString $requiredModuleReqVersion $existingRequiredModuleVersion "notEqual")) {
                    $notInCorrectVersion = $true
                    _write "     - module exists, but not in the correct version (has: $existingRequiredModuleVersion, should be: $requiredModuleReqVersion). Will be replaced" "Yellow"
                } elseif ($requiredModuleMinVersion -and $requiredModuleMaxVersion -and ((Compare-VersionString $existingRequiredModuleVersion $requiredModuleMinVersion "lessThan") -or (Compare-VersionString $existingRequiredModuleVersion $requiredModuleMaxVersion "greaterThan"))) {
                    $notInCorrectVersion = $true
                    _write "     - module exists, but not in the correct version (has: $existingRequiredModuleVersion, should be: $requiredModuleMinVersion .. $requiredModuleMaxVersion). Will be replaced" "Yellow"
                } elseif ($requiredModuleMinVersion -and (Compare-VersionString $existingRequiredModuleVersion $requiredModuleMinVersion "lessThan")) {
                    $notInCorrectVersion = $true
                    _write "     - module exists, but not in the correct version (has: $existingRequiredModuleVersion, should be > $requiredModuleMinVersion). Will be replaced" "Yellow"
                } elseif ($requiredModuleMaxVersion -and (Compare-VersionString $existingRequiredModuleVersion $requiredModuleMaxVersion "greaterThan")) {
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
                    runtimeName           = $runtimeName
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

                New-AzureAutomationRuntimeModule @param
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

    _write " - Uploading module $moduleName ($moduleVersion)" "Yellow"
    $modulePkgUri = "https://devopsgallerystorage.blob.core.windows.net/packages/$($moduleName.ToLower()).$moduleVersion.nupkg"

    $pkgStatus = Invoke-WebRequest -Uri $modulePkgUri -SkipHttpErrorCheck
    if ($pkgStatus.StatusCode -ne 200) {
        throw "Module $moduleName (version $moduleVersion) doesn't exist in PSGallery. Error was $($pkgStatus.StatusDescription)"
    }

    #region send web request
    $body = @{
        "properties" = @{
            "contentLink" = @{
                "uri" = $modulePkgUri
            }
            "version"     = $moduleVersion
        }
    }

    $body = $body | ConvertTo-Json

    Write-Verbose $body

    $null = Invoke-RestMethod2 -method Put -uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runtimeEnvironments/$runtimeName/packages/$moduleName`?api-version=2023-05-15-preview" -body $body -headers $header
    #endregion send web request

    #region output dots while waiting on import to finish
    $i = 0
    _write "    ." -noNewLine
    do {
        Start-Sleep 5

        if ($i % 3 -eq 0) {
            _write "." -noNewLine -noIndent
        }

        ++$i
    } while (!($requiredModule = Get-AzureAutomationRuntimeCustomModule -automationAccountName $automationAccountName -ResourceGroup $resourceGroupName -runtimeName $runtimeName -moduleName $moduleName -header $header -ErrorAction Stop | ? { $_.Properties.ProvisioningState -in "Succeeded", "Failed" }))

    ""
    #endregion output dots while waiting on import to finish

    if ($requiredModule.Properties.ProvisioningState -ne "Succeeded") {
        Write-Error "Import failed. Check Azure Portal >> Automation Account >> Runtime Environments >> $runtimeName >> $moduleName details to get the reason."
    } else {
        _write " - Success" "Green"
    }
}