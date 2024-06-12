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

    .PARAMETER moduleVersionType
    Type of the specified module version.

    Possible values are: 'RequiredVersion', 'MinimumVersion', 'MaximumVersion'.

    By default 'RequiredVersion'.

    .PARAMETER resourceGroupName
    Name of the Azure Resource Group.

    .PARAMETER automationAccountName
    Name of the Azure Automation Account.

    .PARAMETER runtimeVersion
    PSH runtime version.

    Possible values: 5.1, 7.2.

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

    .NOTES
    1. Because this function depends on Find-Module command heavily, it needs to have communication with the PSGallery enabled. To automate this, you can use following code:

    "Install a package manager"
    $null = Install-PackageProvider -Name nuget -Force -ForceBootstrap -Scope allusers

    "Set PSGallery as a trusted repository"
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

    'PackageManagement', 'PowerShellGet', 'PSReadline', 'PSScriptAnalyzer' | % {
        "Install module $_"
        Install-Module $_ -Repository PSGallery -Force -AllowClobber
    }

    "Uninstall old version of PowerShellGet"
    Get-Module PowerShellGet -ListAvailable | ? version -lt 2.0.0 | select -exp ModuleBase | % { Remove-Item -Path $_ -Recurse -Force }

    2. Modules saved in Azure Automation Account have only "main" version saved and suffixes like "beta", "rc" etc are always cut off!
    A.k.a. if you import module with version "1.0.0-rc4". Version that will be shown in the GUI will be just "1.0.0" hence if you try to import such module again, it won't be correctly detected hence will be imported once again.
    #>

    [CmdletBinding()]
    [Alias("New-AzAutomationModule2", "Set-AzureAutomationModule")]
    param (
        [Parameter(Mandatory = $true)]
        [string] $moduleName,

        [string] $moduleVersion,

        [ValidateSet('RequiredVersion', 'MinimumVersion', 'MaximumVersion')]
        [string] $moduleVersionType = 'RequiredVersion',

        [Parameter(Mandatory = $true)]
        [string] $resourceGroupName,

        [Parameter(Mandatory = $true)]
        [string] $automationAccountName,

        [ValidateSet('5.1', '7.2')]
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
        $param.$moduleVersionType = $moduleVersion
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

    #region override module version
    # range instead of specific module version was specified
    if ($moduleVersion -and $moduleVersionType -ne 'RequiredVersion' -and $moduleVersion -ne $moduleGalleryInfo.Version) {
        _write " (version $($moduleGalleryInfo.Version) will be used instead of $moduleVersionType $moduleVersion)"
        $moduleVersion = $moduleGalleryInfo.Version
    }

    # no version was specified and module is in override list
    if (!$moduleVersion -and $moduleName -in $overridePSGalleryModuleVersion.Keys -and $overridePSGalleryModuleVersion.$moduleName.$runtimeVersion) {
        $overriddenModule = $overridePSGalleryModuleVersion.$moduleName
        $overriddenModuleVersion = $overriddenModule.$runtimeVersion
        if ($overriddenModuleVersion) {
            _write " (no version specified and override for version exists, hence will be used ($overriddenModuleVersion))"
            $moduleVersion = $overriddenModuleVersion
        }
    }

    # no version was specified, use the newest one
    if (!$moduleVersion) {
        $moduleVersion = $moduleGalleryInfo.Version
        _write " (no version specified, newest supported version from PSGallery will be used ($moduleVersion))"
    }
    #endregion override module version

    Write-Verbose "Getting current Automation modules"
    $currentAutomationModules = Get-AzAutomationModule -AutomationAccountName $automationAccountName -ResourceGroup $resourceGroupName -RuntimeVersion $runtimeVersion -ErrorAction Stop

    # check whether required module is present
    # there can be module in Failed state, just because update of such module failed, but if it has SizeInBytes set, it means its in working state
    $moduleExists = $currentAutomationModules | ? { $_.Name -eq $moduleName -and ($_.ProvisioningState -eq "Succeeded" -or $_.SizeInBytes) }
    if ($moduleExists) {
        $moduleExistsVersion = $moduleExists.Version
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
            $existingRequiredModule = $currentAutomationModules | ? { $_.Name -eq $requiredModuleName -and ($_.ProvisioningState -eq "Succeeded" -or $_.SizeInBytes) }
            $existingRequiredModuleVersion = $existingRequiredModule.Version # version always looks like n.n.n. suffixes like rc, beta etc are always cut off!

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
                    runtimeVersion        = $runtimeVersion
                    indent                = $indent + 1
                }
                if ($requiredModuleMinVersion) {
                    $param.moduleVersion = $requiredModuleMinVersion
                    $param.moduleVersionType = 'MinimumVersion'
                }
                if ($requiredModuleMaxVersion) {
                    $param.moduleVersion = $requiredModuleMaxVersion
                    $param.moduleVersionType = 'MaximumVersion'
                }
                if ($requiredModuleReqVersion) {
                    $param.moduleVersion = $requiredModuleReqVersion
                    $param.moduleVersionType = 'RequiredVersion'
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