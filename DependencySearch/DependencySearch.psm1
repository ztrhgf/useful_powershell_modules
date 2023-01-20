function Get-AddPSSnapinFromAST {
    <#
    .SYNOPSIS
    Function finds calls of Add-PSSnapin command (including its alias asnp) in given AST and returns objects with used parameters and their values for each call.

    .DESCRIPTION
    Function finds calls of Add-PSSnapin command (including its alias asnp) in given AST and returns objects with used parameters and their values for each call.

    .PARAMETER AST
    AST object which will be searched.

    Can be retrieved like: $AST = [System.Management.Automation.Language.Parser]::ParseFile("C:\script.ps1", [ref] $null, [ref] $null)

    .EXAMPLE
    $AST = [System.Management.Automation.Language.Parser]::ParseFile("C:\script.ps1", [ref] $null, [ref] $null)

    Get-AddPSSnapinFromAST -AST $AST
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.Ast] $AST
    )

    $usedCommand = $AST.FindAll( { $args[0] -is [System.Management.Automation.Language.CommandAst ] }, $true)

    if (!$usedCommand) {
        Write-Verbose "No command detected in given AST"
        return
    }

    $addPSSnapinCommandList = $usedCommand | ? { $_.CommandElements[0].Value -in "Add-PSSnapin", "asnp" }

    if (!$addPSSnapinCommandList) {
        Write-Verbose "No 'Add-PSSnapin' or its alias 'asnp' detected"
        return
    }

    foreach ($addPSSnapinCommand in $addPSSnapinCommandList) {
        $addPSSnapinCommandElement = $addPSSnapinCommand.CommandElements
        $addPSSnapinCommandElement = $addPSSnapinCommandElement | select -Skip 1 # skip Add-PSSnapin command itself

        Write-Verbose "Getting Add-PSSnapin parameters from: '$($addPSSnapinCommand.extent.text)' (file: $($addPSSnapinCommand.extent.File))"

        #region get parameter name and value for NAMED parameters
        $param = @{}
        $paramName = ''
        foreach ($element in $addPSSnapinCommandElement) {
            if ($paramName) {
                # variable is set true when parameter was found
                # this foreach cycle therefore contains parameter value
                if ($element.StaticType.Name -eq "String") {
                    # one module was specified
                    $param.$paramName = $element.Extent.Text -replace "`"|'"
                } elseif ($element.Elements) {
                    # multiple modules were specified
                    $param.$paramName = ($element.Elements | ? { $_.StaticType.Name -eq "String" } | select -ExpandProperty Value) -replace "`"|'"
                } else {
                    # value passed from pipeline etc probably
                    Write-Verbose "Unknown Add-PSSnapin '$paramName' parameter value"
                    $param.$paramName = '<unknown>'
                }

                $paramName = ''
                continue
            }

            if ($element.ParameterName) {
                $paramName = $element.ParameterName

                # transform param. name shortcuts to their full name if necessary
                switch ($paramName) {
                    { $_ -match "^n" } { $paramName = "Name" }
                }
            }
        }
        #endregion get parameter name and value for NAMED parameters

        if (!$param.Name) {
            Write-Verbose "PSSnapins are imported using positional parameter"
            # 'Name' parameter wasn't specified by name, but by position, search for entered values
            # 'Name' parameter is on first position
            $firstAddPSSnapinCommandElement = $addPSSnapinCommandElement | select -First 1

            if ($firstAddPSSnapinCommandElement.Elements) {
                # multiple PSSnapin values were specified
                $param.Name = ($firstAddPSSnapinCommandElement.Elements | ? { $_.StaticType.Name -eq "String" } | select -ExpandProperty Value) -replace "`"|'"
            } elseif ($firstAddPSSnapinCommandElement.StaticType.Name -eq "String") {
                # one PSSnapin value was specified
                $param.Name = ($firstAddPSSnapinCommandElement | ? { $_.StaticType.Name -eq "String" } | select -ExpandProperty Value) -replace "`"|'"
            } else {
                Write-Verbose "Unknown Add-PSSnapin 'Name' parameter value"
            }
        }

        if (!$param.Name -or $param.Name -eq '<unknown>') {
            Write-Warning "Unable to detect PSSnapins added through Add-PSSnapin command: '$($addPSSnapinCommand.extent.text)' (file: $($addPSSnapinCommand.extent.File))"

            continue
        }

        # output object for each added PSSnapin
        $param.Name | % {
            [PSCustomObject]@{
                Command       = $addPSSnapinCommand.extent.text
                File          = $addPSSnapinCommand.extent.File
                AddedPSSnapin = $_
            }
        }
    }
}

function Get-CodeDependency {
    <#
    .SYNOPSIS
    Function finds dependencies/requirements for given PSH code/script/module.

    .DESCRIPTION
    Function finds dependencies/requirements for given PSH code/script/module.

    a) When code/script is given:
    - code #requires statement is searched for required modules and their dependencies are gathered using option b)
    - all commands used in the code are searched and:
        -if command is known (Get-Command founds it):
            - dependencies for command source module are searched using option b)
            - if command definition exists, it is searched too using option a) recursively
        - else it is skipped

    b) When module is given:
    - module is searched in locally available modules (using name and optionally version)
        - if not found, it is searched again online in PowerShell Gallery
    - #requires statements is checked and option b) is called upon for every required module recursively
    - (if 'processDefinedCommand' switch is used) text definition of every command in module is searched for dependencies using option a) recursively

    TIP: Built-in modules and corresponding commands are skipped during search (because everyone have them).

    .PARAMETER scriptPath
    Path to PSH script whose dependencies should be searched.

    .PARAMETER scriptContent
    PSH code whose dependencies should be searched.

    .PARAMETER moduleName
    PSH module name whose dependencies should be searched.

    .PARAMETER moduleVersion
    (optional) PSH module version whose dependencies should be searched.

    .PARAMETER checkModuleFunctionsDependencies
    Switch for searching dependencies for all commands defined in processed modules.

    By default just '#requires -module' statements is used for getting module dependencies.

    .PARAMETER availableModules
    To speed up repeated function runs, save all available modules into variable and use it as value for this parameter.

    By default this function caches all available modules before each run which can take several seconds.

    .EXAMPLE
    Get-CodeDependency -scriptPath "C:\scripts\Get-AzureADServicePrincipalOverview.ps1" -Verbose

    .EXAMPLE
    Get-CodeDependency -moduleName scripts -checkModuleFunctionsDependencies

    .EXAMPLE
    Get-CodeDependency -moduleName scripts -checkModuleFunctionsDependencies

    .EXAMPLE
    Get-CodeDependency -scriptContent 'Connect-MsolService' -Verbose

    .EXAMPLE
    $availableModules = @(Get-Module -ListAvailable)

    Get-CodeDependency -scriptContent 'Connect-MsolService' -availableModules $availableModules -Verbose
    #>

    [CmdletBinding()]
    [Alias("Get-Dependency", "Get-PSHCodeDependency")]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "scriptPath")]
        [ValidateScript( {
                if ((Test-Path -Path $_ -PathType leaf) -and $_ -match "\.ps1$") {
                    $true
                } else {
                    throw "$_ is not a ps1 file or it doesn't exist"
                }
            })]
        [string] $scriptPath,

        [Parameter(Mandatory = $true, ParameterSetName = "scriptContent")]
        [string] $scriptContent,

        [Parameter(Mandatory = $true, ParameterSetName = "moduleName")]
        [string] $moduleName,

        [Parameter(Mandatory = $false, ParameterSetName = "moduleName")]
        [string] $moduleVersion,

        [Parameter(Mandatory = $true, ParameterSetName = "moduleBasePath")]
        [ValidateScript( {
                if (Test-Path -Path $_ -PathType Container) {
                    $true
                } else {
                    throw "$_ is not a path to folder where module is stored. For example 'C:\modules\AWS.Tools.Common' or 'C:\modules\AWS.Tools.Common\4.1.233'"
                }
            })]
        [string] $moduleBasePath,

        [switch] $checkModuleFunctionsDependencies,

        [System.Collections.ArrayList] $availableModules = @(),

        [switch] $noReccursion
    )

    # modules available by default, will be therefore skipped
    $builtInModule = 'AppBackgroundTask', 'AppLocker', 'AppvClient', 'Appx', 'AssignedAccess', 'BitLocker', 'BitsTransfer', 'BranchCache', 'CimCmdlets', 'ConfigCI', 'Defender', 'DeliveryOptimization', 'DirectAccessClientComponents', 'Dism', 'DnsClient', 'EventTracingManagement', 'International', 'iSCSI', 'ISE', 'Kds', 'LanguagePackManagement', 'Microsoft.PowerShell.Archive', 'Microsoft.PowerShell.Diagnostics', 'Microsoft.PowerShell.Host', 'Microsoft.PowerShell.LocalAccounts', 'Microsoft.PowerShell.Management', 'Microsoft.PowerShell.ODataUtils', 'Microsoft.PowerShell.Security', 'Microsoft.PowerShell.Utility', 'Microsoft.WSMan.Management', 'MMAgent', 'MsDtc', 'NetAdapter', 'NetConnection', 'NetEventPacketCapture', 'NetLbfo', 'NetNat', 'NetQos', 'NetSecurity', 'NetSwitchTeam', 'NetTCPIP', 'NetworkConnectivityStatus', 'NetworkSwitchManager', 'NetworkTransition', 'PcsvDevice', 'PersistentMemory', 'PKI', 'PnpDevice', 'PrintManagement', 'ProcessMitigations', 'Provisioning', 'PSDesiredStateConfiguration', 'PSDiagnostics', 'PSScheduledJob', 'PSWorkflow', 'PSWorkflowUtility', 'ScheduledTasks', 'SecureBoot', 'SmbShare', 'SmbWitness', 'StartLayout', 'Storage', 'StorageBusCache', 'TLS', 'TroubleshootingPack', 'TrustedPlatformModule', 'UEV', 'VpnClient', 'Wdac', 'Whea', 'WindowsDeveloperLicense', 'WindowsErrorReporting', 'WindowsSearch', 'WindowsUpdate', 'Microsoft.PowerShell.Operation.Validation', 'PackageManagement', 'Pester', 'PowerShellGet', 'PSReadline'

    # here will be saved downloaded modules from PowerShell Gallery
    $moduleTmpPath = "$env:TEMP\PSHModules"

    #region set default parameters
    $PSDefaultParameterValuesBkp = $PSDefaultParameterValues.Clone()
    if (!$PSDefaultParameterValues) {
        $PSDefaultParameterValues = @{}
    }

    # to minimize clutter in verbose output
    $PSDefaultParameterValues.'Import-Module:Verbose' = $false
    $PSDefaultParameterValues.'Get-Module:Verbose' = $false

    $PSDefaultParameterValues.'Get-ScriptDependency:ignoreModule' = $builtInModule

    $PSDefaultParameterValues.'Get-ModuleDependency:ignoreModule' = $builtInModule
    $PSDefaultParameterValues.'Get-ModuleDependency:moduleTmpPath' = $moduleTmpPath
    if ($checkModuleFunctionsDependencies) {
        $PSDefaultParameterValues.'Get-ModuleDependency:processDefinedCommand' = $true
    } else {
        $PSDefaultParameterValues.Remove('Get-ModuleDependency:processDefinedCommand')
    }
    if ($noReccursion) {
        $PSDefaultParameterValues.'Get-ModuleDependency:noReccursion' = $true
        $PSDefaultParameterValues.'Get-ScriptDependency:noReccursion' = $true
    } else {
        $PSDefaultParameterValues.Remove('Get-ModuleDependency:noReccursion')
        $PSDefaultParameterValues.Remove('Get-ScriptDependency:noReccursion')
    }
    #endregion set default parameters

    #region cache
    if ($availableModules) {
        Write-Verbose "Using given 'availableModules' as list of available modules"
        [System.Collections.ArrayList] $global:availableModules = $availableModules
    } else {
        Write-Warning "Caching locally available modules. To skip this step, use parameter 'availableModules'"
        [System.Collections.ArrayList] $global:availableModules = @(Get-Module -ListAvailable)
    }
    # array of already processed modules saved as psobjects where each object contains module name and (optionally) its version
    $global:processedModules = @()
    # array of already processed commands
    $global:processedCommands = @()
    # array of already processed PSSnapins saved as psobjects where each object contains snapin name and (optionally) its version
    $global:processedPSSnapins = @()
    # if the code or some of its dependencies requires elevation
    $global:isElevationRequired = $false
    # hash where key is module BasePath and value are module private functions
    $global:modulePrivateFunction = @{}
    #endregion cache

    #region helper functions
    function _getModulePrivateFunction {
        # get & cache module private functions
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string] $moduleBasePath
        )

        if ($global:modulePrivateFunction.keys -contains $moduleBasePath) {
            return $global:modulePrivateFunction.$moduleBasePath
        }

        $result = Get-ModulePrivateFunction -moduleBasePath $moduleBasePath

        $global:modulePrivateFunction.$moduleBasePath = $result

        return $result
    }

    function Get-ModulePrivateFunction {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string] $moduleBasePath
        )

        $moduleObj = Get-Module -FullyQualifiedName $moduleBasePath -ListAvailable -Verbose:$false

        if (!$moduleObj) {
            Write-Error "Module in path '$moduleBasePath' doesn't exist"
        }

        $exportedCommand = $moduleObj.ExportedCommands.keys

        $modulePsm1 = Get-ChildItem (Join-Path $moduleBasePath "*") -Include "*.psm1" -Recurse | select -ExpandProperty FullName

        foreach ($psm1 in $modulePsm1) {
            # get AST
            $errors = [System.Management.Automation.Language.ParseError[]]@()
            $tokens = [System.Management.Automation.Language.Token[]]@()
            $AST = [System.Management.Automation.Language.Parser]::ParseFile($psm1, [ref] $tokens, [ref] $errors)

            # get functions defined in the code, so I can ignore them when searching for dependencies (their content is checked though)
            $definedFunction = $AST.FindAll( {
                    param([System.Management.Automation.Language.Ast] $AST)

                    $AST -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    # Class methods have a FunctionDefinitionAst under them as well, but we don't want them.
                        ($PSVersionTable.PSVersion.Major -lt 5 -or
                    $AST.Parent -isnot [System.Management.Automation.Language.FunctionMemberAst])
                }, $false)

            $privateFunction = $definedFunction.name | ? { $_ -notin $exportedCommand }

            $privateFunction
        }
    }

    function Get-ModuleDependency {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true, ParameterSetName = "moduleObj")]
            [System.Management.Automation.PSModuleInfo] $module,

            [Parameter(Mandatory = $true, ParameterSetName = "moduleName")]
            [string] $moduleName,

            [Parameter(ParameterSetName = "moduleName")]
            [version] $moduleVersion,

            [switch] $processDefinedCommand,

            [switch] $processBuiltinModule,

            [int] $indent = 1,

            [switch] $firstRun,

            [string] $source,

            [string] $command,

            [string[]] $ignoreModule,

            [string] $moduleTmpPath = "$env:TEMP\PSHModules",

            [switch] $noReccursion
        )

        #region helper functions
        function _getModule {
            [CmdletBinding()]
            param ([string] $moduleName, $moduleVersion, [int] $indent)

            Write-Verbose ("`t`t`t`t" * $indent + "- Searching for '$moduleName' (ver. $moduleVersion) in available modules")

            $module = $global:availableModules | ? Name -EQ $moduleName
            if ($moduleVersion) {
                $module = $module | ? Version -EQ $moduleVersion
            }

            #TODO muze byt vic se stejnym jmenem
            $module | select -First 1
        }

        function _moduleIsProcessed {
            param ($moduleName, $moduleVersion)

            if (($moduleVersion -and ($global:processedModules | ? { $_.ModuleName -eq $moduleName -and $_.ModuleVersion -eq $moduleVersion })) -or (!$moduleVersion -and ($moduleName -in $global:processedModules.ModuleName))) {
                $true
            } else {
                $false
            }
        }

        # function Get-ExtModule {
        #     # Get-Module for modules outside $env:PSModulePath

        #     param (
        #         [string] $moduleBasePath,
        #         [string] $moduleRootPath
        #     )

        #     $PSModulePathBkp = $env:PSModulePath
        #     if (($env:PSModulePath -split ";") -notcontains $moduleRootPath) {
        #         # required because using Get-Module for modules outside $env:PSModulePath isn't possible
        #         # Write-Verbose ("`t`t`t`t`t" * $indent + "- Making source module available for search $moduleRootPath")
        #         $env:PSModulePath += ";$moduleRootPath"
        #     }
        #     $module = Get-Module -FullyQualifiedName $moduleBasePath -ListAvailable -ErrorAction SilentlyContinue
        #     # restore original data
        #     $env:PSModulePath = $PSModulePathBkp

        #     return $module
        # }
        #endregion helper functions

        #region check
        if ($module) {
            $mName = $module.name
            $mVersion = $module.Version
        } else {
            $mName = $moduleName
            $mVersion = $moduleVersion
        }

        Write-Verbose ("`t`t`t" * $indent + "- Processing module '$mName' (ver. $mVersion)")

        if (_moduleIsProcessed -moduleName $mName -moduleVersion $mVersion) {
            Write-Verbose ("`t`t`t`t" * $indent + "- Module '$mName' (ver. $mVersion) was already processed. Skipping")
            return
        }

        if ($mName -in $ignoreModule -and !$processBuiltinModule) {
            Write-Verbose ("`t`t`t`t" * $indent + "- Module '$mName' (ver. $mVersion) is built-in. Skipping")
            return
        }

        # OUTPUT module that is being processed
        if (!$firstRun) {
            [PSCustomObject]@{
                Type    = 'Module'
                Name    = $mName
                Version = $mVersion
                Source  = $source
                Command = $command
            }

            if ($noReccursion) { return }
        }

        # make a note
        $global:processedModules += [PSCustomObject]@{
            ModuleName    = $mName
            ModuleVersion = $mVersion
        }
        #endregion check

        if ($moduleName) {
            # searching using module name (and version)
            $module = _getModule -moduleName $moduleName -moduleVersion $moduleVersion -indent $indent

            #region get module data from PSH Gallery
            if (!$module) {
                Write-Warning ("`t`t`t`t" * $indent + "- Module '$moduleName' (ver. $moduleVersion) isn't present on this machine. Trying to find it in online PowerShell Gallery")

                # if ('Trusted' -ne ($Policy = (Get-PSRepository PSGallery).InstallationPolicy)) {
                #     Set-PSRepository PSGallery -InstallationPolicy Trusted
                # }

                # get dependencies for every command this module defines
                # officially defined requirements don't have to be 100% correct
                if ($processDefinedCommand) {
                    # module commands should be processed, therefore I try to download the module locally
                    # if successful I will process the module as any other local module

                    # define module path
                    $modulePath = Join-Path $moduleTmpPath $moduleName # C:\modules\AWS.Tools.Common
                    if ($moduleVersion) {
                        $modulePath = Join-Path $modulePath $moduleVersion # C:\modules\AWS.Tools.Common\4.1.233
                    }

                    # $module = Get-ExtModule -moduleBasePath $modulePath -moduleRootPath $moduleTmpPath
                    $module = Get-Module -FullyQualifiedName $modulePath -ListAvailable -ErrorAction SilentlyContinue

                    if ($module) {
                        # module is already downloaded
                    } else {
                        # download missing module from PowerShell Gallery
                        $param = @{
                            Name        = $moduleName
                            Path        = $moduleTmpPath
                            ErrorAction = 'Stop'
                            Verbose     = $false
                        }
                        if ($moduleVersion) {
                            $param.RequiredVersion = $moduleVersion
                        }

                        try {
                            Write-Verbose ("`t`t`t`t" * $indent + "- Downloading module from the PowerShell Gallery to the '$moduleTmpPath'")

                            [Void][System.IO.Directory]::CreateDirectory($moduleTmpPath)

                            Save-Module @param

                            # $module = Get-ExtModule -moduleBasePath $modulePath -moduleRootPath $moduleTmpPath
                            $module = Get-Module -FullyQualifiedName $modulePath -ListAvailable -ErrorAction SilentlyContinue

                            # cache the result
                            $null = $global:availableModules.add($module)
                        } catch {
                            if ($_ -like "*No match was found for the specified search criteria*") {
                                Write-Warning ("`t`t`t`t" * $indent + "- Module isn't available in the PowerShell Gallery either")
                            } else {
                                Write-Error $_
                            }

                            return
                        }
                    }
                } else {
                    # commands defined in the module shouldn't be processed, just officially defined dependencies
                    # therefore module won't be downloaded locally, information will be gathered from Gallery instead
                    $param = @{
                        Name        = $moduleName
                        ErrorAction = 'Stop'
                        Verbose     = $false
                    }
                    if ($moduleVersion) {
                        $param.RequiredVersion = $moduleVersion
                    }

                    try {
                        Write-Verbose ("`t`t`t`t" * $indent + "- Searching for module in the PowerShell Gallery")
                        $pshgModule = Find-Module @param
                    } catch {
                        if ($_ -like "*No match was found for the specified search criteria*") {
                            Write-Warning ("`t`t`t`t" * $indent + "- Module isn't available in the PowerShell Gallery either")
                        } else {
                            Write-Error $_
                        }

                        return
                    }

                    #region get dependencies for every required module
                    $moduleDependency = $pshgModule.Dependencies

                    if ($moduleDependency) {
                        $moduleDependency | % {
                            $dependency = $_.getenumerator()
                            if ($dependency.gettype().name -eq 'SZArrayEnumerator') {
                                # multiple dependencies defined, expand once more
                                $dependency = $dependency.getenumerator()
                            }

                            foreach ($moduleUrl in ($dependency | ? key -EQ 'CanonicalId' | select -exp Value)) {
                                # CanonicalId looks like: powershellget:Microsoft.Graph.Authentication/[1.19.0]#https://www.powershellgallery.com/api/v2
                                $reqModuleName = ($moduleUrl -split "/")[0] -replace "powershellget:"
                                $reqModuleVersion = ([regex]"\d+\.\d+\.\d+").Match($moduleUrl).value

                                Write-Verbose ("`t`t`t`t" * $indent + "- Module '$moduleName' (ver. $moduleVersion) requires module $reqModuleName (ver. $reqModuleVersion)")

                                # get dependencies of dependency :)
                                $param = @{
                                    moduleName = $reqModuleName
                                    indent     = $indent + 1
                                    Source     = $moduleName
                                    Command    = "<module manifest>"
                                }
                                if ($reqModuleVersion) {
                                    $param.version = $reqModuleVersion
                                }

                                Get-ModuleDependency @param
                            }
                        }
                    } else {
                        Write-Verbose "`t- Didn't find any dependency"
                    }
                    #endregion get dependencies for every required module

                    return
                }
            } # module was searched in PowerShell Gallery
            #endregion get module data from PSH Gallery
        } # module was searched using its name

        #region get dependencies for every command this module defines
        # officially defined requirements don't have to be 100% correct
        if ($processDefinedCommand) {
            # get private functions so I can ignore them later
            $modulePrivateFunction = _getModulePrivateFunction -moduleBasePath $module.ModuleBase

            Write-Verbose ("`t`t`t`t" * $indent + "- Getting commands defined in module '$mName'")
            $module.ExportedCommands.keys | ? { $_ -notin $module.ExportedAliases.keys } | % {
                $cmdName = $_
                Write-Verbose ("`t`t`t`t`t" * $indent + "- Processing command '$cmdName'")
                # skip errors, because some module exports commands that doesn't exist

                $cmdData = Get-Command $cmdName -Module $module -Verbose:$false -ErrorAction SilentlyContinue | ? Name -EQ $cmdName # just exact matches (name can contain wildcard)
                $cmdDefinition = $cmdData.ScriptBlock # command body

                if ($cmdDefinition) {
                    Write-Verbose ("`t`t`t`t`t" * $indent + "- Getting command '$cmdName' dependencies from its definition")
                    Get-ScriptDependency -scriptContent $cmdDefinition -indent ($indent + 1) -source $mName -ignoreCommand $modulePrivateFunction
                } else {
                    Write-Verbose ("`t`t`t`t`t" * $indent + "- Unable to get command '$cmdName' definition")
                }
            }
        }
        #endregion get dependencies for every command this module defines

        #region get dependencies for every required module
        $requiredModules = $module.RequiredModules

        if ($requiredModules) {
            $requiredModules | % {
                Write-Verbose ("`t`t`t`t" * $indent + "- Module '$($module.name)' (ver. $($module.version)) requires module $($_.name) (ver. $($_.version))")
                # required modules definition doesn't contain requirements for required modules :)
                # get dependencies of dependency :)
                Get-ModuleDependency -moduleName $_.name -moduleVersion $_.version -indent ($indent + 1) -source $module.name -command "<module manifest>"
            }
        } else {
            Write-Verbose ("`t`t`t`t" * $indent + "- Module $($module.name) (ver. $($module.version)) doesn't require any modules")
        }

        #TODO vytahnout i dalsi DotNetFrameworkVersion, PowerShellVersion, RequiredAssemblies
        #endregion get dependencies for every required module
    }

    function Get-ScriptDependency {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true, ParameterSetName = "scriptPath")]
            [ValidateScript( {
                    if ((Test-Path -Path $_ -PathType leaf) -and $_ -match "\.ps1$") {
                        $true
                    } else {
                        throw "$_ is not a ps1 file or it doesn't exist"
                    }
                })]
            $scriptPath,

            [Parameter(Mandatory = $true, ParameterSetName = "scriptContent")]
            $scriptContent,

            [int] $indent = 1,

            [string] $source,

            [string[]] $ignoreCommand,

            [string[]] $ignoreModule,

            [switch] $noReccursion
        )

        # get AST
        $errors = [System.Management.Automation.Language.ParseError[]]@()
        $tokens = [System.Management.Automation.Language.Token[]]@()
        if ($scriptPath) {
            $AST = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $scriptPath), [ref] $tokens, [ref] $errors)
        } else {
            $AST = [System.Management.Automation.Language.Parser]::ParseInput($scriptContent, [ref] $tokens, [ref] $errors)
        }

        # get functions defined inside the code, so I can ignore them when searching for dependencies (their content is checked though)
        $definedFunction = $AST.FindAll( {
                param([System.Management.Automation.Language.Ast] $AST)

                $AST -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                # Class methods have a FunctionDefinitionAst under them as well, but we don't want them.
                        ($PSVersionTable.PSVersion.Major -lt 5 -or
                $AST.Parent -isnot [System.Management.Automation.Language.FunctionMemberAst])
            }, $true)

        $usedCommand = $AST.FindAll( { $args[0] -is [System.Management.Automation.Language.CommandAst ] }, $true)

        #region get&add used PSSnapins
        #region added using requires statement
        $requiresPSSnapIns = $AST.ScriptRequirements.RequiresPSSnapIns
        foreach ($PSSnapin in $requiresPSSnapIns) {
            Write-Verbose "PSSnapin '$($PSSnapin.Name)' is required"

            if ($PSSnapin.Name -in $global:processedPSSnapins.Name) {
                Write-Verbose "PSSnapin was already processed. Skipping"
            } else {
                # take a note
                $global:processedPSSnapins += [PSCustomObject]@{
                    Name    = $PSSnapin.Name
                    Version = $PSSnapin.Version
                }

                # OUTPUT processing pssnapin
                [PSCustomObject]@{
                    Type    = 'PSSnapin'
                    Name    = $PSSnapin.Name
                    Version = $PSSnapin.Version
                    Source  = $source
                    Command = "<requires statement>"
                }

                # add pssnapin
                Write-Verbose "Importing used PSSnapin '$($PSSnapin.Name)' (to be able to get details using Get-Command later)"
                try {
                    Add-PSSnapin -Name $($PSSnapin.Name) -ErrorAction Stop
                } catch {
                    Write-Warning "Unable to add PSSnapin '$($PSSnapin.Name)'. Some used commands won't be processed probably. Error was $_"
                }
            }
        }
        #endregion added using requires statement

        #region added using Add-PSSnapin
        $addedPSSnapin = Get-AddPSSnapinFromAST $AST
        foreach ($PSSnapin in $addedPSSnapin) {
            $PSSnapinName = $PSSnapin.AddedPSSnapin
            Write-Verbose "PSSnapin '$PSSnapinName' is required"

            if ($PSSnapinName -in $global:processedPSSnapins.Name) {
                Write-Verbose "PSSnapin was already processed. Skipping"
            } else {
                # take a note
                $global:processedPSSnapins += [PSCustomObject]@{
                    Name    = $PSSnapinName
                    Version = $null
                }

                # OUTPUT processing pssnapin
                [PSCustomObject]@{
                    Type    = 'PSSnapin'
                    Name    = $PSSnapinName
                    Version = $null
                    Source  = $source
                    Command = $PSSnapin.Command
                }

                # add pssnapin
                Write-Verbose "Importing used PSSnapin '$PSSnapinName' (to be able to get details using Get-Command later)"
                try {
                    Add-PSSnapin -Name $PSSnapinName -ErrorAction Stop
                } catch {
                    Write-Warning "Unable to add PSSnapin '$PSSnapinName'. Some used commands won't be processed probably. Error was $_"
                }
            }
        }
        #endregion added using Add-PSSnapin
        #endregion get&add used PSSnapins

        #region required modules
        #TODO detekovat pouziti using

        Write-Verbose ("`t`t`t`t" * $indent + "- Getting dependencies (for used MODULES)")
        # get all required modules defined in requires statement
        if ($AST.ScriptRequirements.RequiredModules) {
            Write-Verbose ("`t`t`t`t`t" * $indent + "- Processing modules from #requires statement")
            $AST.ScriptRequirements.RequiredModules | ? { $_ } | % {
                $minimumVersion = $_.version
                $maximumVersion = $_.MaximumVersion
                $requiredVersion = $_.RequiredVersion
                Get-ModuleDependency -moduleName $_.Name -moduleVersion $requiredVersion -indent ($indent + 1) -source $source -command "<requires statement>"
            }
        }

        #region get all modules imported using Import-Module or ipmo alias
        # ma smysl jen kvuli modulum ktere definuji promenne, typy atp a zjisteni konkretni verze modulu..jinak najdu moduly pres pouzite prikazy v kodu
        $importModuleCommandList = Get-ImportModuleFromAST $AST

        if ($importModuleCommandList) {
            Write-Verbose ("`t`t`t`t`t" * $indent + "- Processing modules from Import-Module command calls")

            $importModuleCommandList | % {
                $importedModule = $_.ImportedModule
                # Write-Verbose "Module '$($importedModule -join ', ')' is imported via command: $($_.Command)"

                foreach ($module in $importedModule) {
                    #TODO resit i minimum/maximum verzi?
                    Get-ModuleDependency -moduleName $module -moduleVersion $_.RequiredVersion -indent ($indent + 1) -source $source -command $_.Command
                }
            }
        }
        #endregion get all modules imported using Import-Module
        #endregion required modules

        #TODO hledat i pres promenne ( i v param bloku!)? pokud pouziva takove ktere jsou nekde exportovane...

        #region used functions/cmdlets/aliases
        #TODO prikazy s prefixem z naimportovaneho modulu (ziskat explicitne importovane moduly a pouzity prefix)

        # skip internal functions of the module where processed command is defined a.k.a. omit unnecessary warnings about unknown(private) commands
        if ($source) {
            # WARNING: I cannot be sure if I select correct command/module if there are multiple matches!
            $gcmData = Get-Command $source -Verbose:$false -ErrorAction SilentlyContinue | select -First 1
            if ($gcmData.Module.ModuleBase) {
                $modulePrivateFunction = _getModulePrivateFunction -moduleBasePath $gcmData.Module.ModuleBase
                $ignoreCommand += @($modulePrivateFunction)
            }
        }

        Write-Verbose ("`t`t`t`t" * $indent + "- Getting dependencies (for used COMMANDS)")
        # list of prefixes added to commands imported from modules
        $importModulePrefix = $importModuleCommandList.Prefix
        foreach ($cmd in $usedCommand) {
            $cmdName = $cmd.CommandElements[0].Value
            $cmdCommand = $cmd.Extent.Text

            # remove command prefix added when importing command source module
            if ($importModulePrefix) {
                foreach ($prefix in $importModulePrefix) {
                    $regPrefix = [regex]::escape($prefix)
                    if ($cmdName -match "-$regPrefix") {
                        $cmdNewName = $cmdName -replace "-$regPrefix", "-"
                        Write-Verbose ("`t`t`t`t`t" * $indent + "- Replacing command to process '$cmdName' for '$cmdNewName'. Because name matches module prefix '$prefix'")
                        $cmdName = $cmdNewName
                        break
                    }
                }
            }

            Write-Verbose ("`t`t`t`t`t" * $indent + "- Processing command '$cmdName'")

            if ($cmdName -in $definedFunction.name) {
                Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Locally defined function. Skipping")
            } elseif ($cmdName -in $ignoreCommand) {
                Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Ignored function. Skipping")
            } elseif ($cmdName -match "\.exe$") {
                Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Native or 3rd party binary. Skipping")
            } elseif ($cmdName -in $global:processedCommands) {
                # ignore (but what about same named functions in different modules?)
                Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Already processed. Skipping")
            } else {
                # make a note
                $global:processedCommands += $cmdName

                # zavislosti z kodu dane fce
                $cmdData = Get-Command $cmdName -All -Verbose:$false -ErrorAction SilentlyContinue | ? { ($_.ModuleName -or $_.CommandType -eq "Alias") -and $_.Name -EQ $cmdName } # just exact matches (name can contain wildcard) and defined in module

                if ($cmdData.count -gt 1) {
                    # try to limit the data just to module of the "source"
                    if ($source) {
                        $sourceCmdData = $cmdData | ? ModuleName -EQ $source

                        if ($sourceCmdData) {
                            # limit the command to the source module, but its just guessing!
                            $cmdData = $sourceCmdData
                        } else {
                            # source isn't module probably, try to search it as command instead
                            $sourceCmdData = Get-Command $source -All -Verbose:$false -ErrorAction SilentlyContinue | ? { ($_.ModuleName -or $_.CommandType -eq "Alias") -and $_.Name -eq $cmdName } # just exact matches (name can contain wildcard) and defined in module
                            if ($sourceCmdData) {
                                $sourceCmdData = $cmdData | ? ModuleName -In $sourceCmdData.ModuleName
                                if ($sourceCmdData) {
                                    # limit the command to the source module (where source command is defined), but its just guessing!
                                    $cmdData = $sourceCmdData
                                }
                            }
                        }
                    }

                    if ($cmdData.count -gt 1) {
                        Write-Warning "Command '$cmdName' is defined multiple times ($($cmdData.ModuleName -join ', '))"
                    }
                }

                if ($cmdData) {
                    # Get-Command found the command
                    foreach ($data in $cmdData) {
                        if ($data.commandType -eq "alias") {
                            Write-Verbose ("`t`t`t`t`t`t" * $indent + "- '$cmdName' is alias for '$($data.ResolvedCommandName)'")
                            $data = Get-Command $data.ResolvedCommandName -Verbose:$false
                        }

                        $cmdDefinition = $data.ScriptBlock # command body
                        $cmdModule = $data.module # module that contains/defines this command
                        $cmdSource = $data.source

                        if ($cmdSource -eq "Microsoft.PowerShell.Core" -or $cmdModule.Name -in $ignoreModule) {
                            # built-in command, ignore
                            Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Skipping. Its built-in command.")
                            continue
                        }

                        if ($cmdModule) {
                            Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Searching for dependencies in the command's source module '$($cmdModule.Name)'")

                            # searching just using name, because I can't say for sure that specific version is needed
                            # because it was found using Get-Command
                            Get-ModuleDependency -moduleName $cmdModule.Name -indent ($indent + 1) -source $cmdName -command $cmdCommand
                        }

                        if ($cmdDefinition -and !$noReccursion) {
                            Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Searching for dependencies in the command's '$cmdName' body")
                            Get-ScriptDependency -scriptContent $cmdDefinition.ToString() -indent ($indent + 1) -source $cmdName
                        }

                        if (!$cmdModule -and !$cmdDefinition) {
                            Write-Warning "Command $cmdName isn't defined in any module nor its definition was found. Skip getting its dependencies"
                        }
                    }
                } else {
                    # Get-Command didn't find the command
                    Write-Warning "Unable to find command '$cmdName' details using Get-Command. Skip getting its dependencies"
                }
            }
        }
        #endregion used functions/cmdlets/aliases

        #TODO vypisovat i ostatni requires
        if ($AST.ScriptRequirements.IsElevationRequired) {
            # code requires elevation
            Write-Verbose ("`t`t`t`t`t" * $indent + "- Code requires elevation through #requires statement")
            if ($global:isElevationRequired) {
                Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Elevation is already required. Skipping")
            } else {
                # take a note
                $global:isElevationRequired = $true

                # OUTPUT requirement
                [PSCustomObject]@{
                    Type    = 'Requirement'
                    Name    = 'ElevationIsRequired'
                    Version = $null # jen abych vracel stejny objekt jako u ostatnich requirementu
                    Source  = $source
                    Command = "<requires statement>"
                }
            }
        }
    }
    #endregion helper functions

    if ($scriptPath -or $scriptContent) {
        # get code dependencies
        $param = @{}
        if ($scriptPath) {
            $param.source = $scriptPath
            $param.scriptPath = $scriptPath
        }
        if ($scriptContent) {
            $param.source = "*scriptContent*"
            $param.scriptContent = $scriptContent
        }

        Get-ScriptDependency @param
    } elseif ($moduleName) {
        # get module dependencies
        $param = @{
            firstRun   = $true
            moduleName = $moduleName
            source     = $moduleName
        }
        if ($moduleVersion) { $param.moduleVersion = $moduleVersion }

        Get-ModuleDependency @param
    } elseif ($moduleBasePath) {
        # get module dependencies
        $param = @{
            firstRun = $true
            module   = (Get-Module -FullyQualifiedName $moduleBasePath -ListAvailable -ErrorAction Stop)
            source   = $moduleBasePath
        }

        Get-ModuleDependency @param
    } else {
        throw "undefined option"
    }

    # restore previous default parameter values
    $PSDefaultParameterValues = $PSDefaultParameterValuesBkp

    # cleanup downloaded modules
    Remove-Item $moduleTmpPath -Recurse -Force -ErrorAction SilentlyContinue
}

function Get-CodeDependencyStatus {
    <#
    .SYNOPSIS
    Function gets (module) dependencies of given script/module and warns you about possible problems.

    .DESCRIPTION
    Function gets (module) dependencies of given script/module and warns you about possible problems.
    What problems are checked:
     - given code uses command from module that is not explicitly required or imported
     - there is version mismatch between used and required modules
     - there is explicit requirement for module that is not being used
     - there is explicit import of a module that is not being used

    Beware that dependencies are not (on purpose) searched recursively. A.k.a dependencies of found dependencies are not checked :).

    .PARAMETER scriptPath
    Path to the ps1 script that should be checked.

    .PARAMETER moduleName
    Name of the module that should be checked.

    .PARAMETER moduleVersion
    (optional) version of the module that should be checked.

    .PARAMETER moduleBasePath
    Base path of the module that should be checked.

    .PARAMETER availableModules
    To speed up repeated function runs, save all available modules into variable and use it as value for this parameter.

    By default this function caches all available modules before each run which can take several seconds.

    .PARAMETER asObject
    Switch for returning psobjects instead of warning messages.

    .EXAMPLE
    $availableModules = Get-Module -ListAvailable

    Get-CodeDependencyStatus -scriptPath C:\scripts\myScript.ps1 -availableModules $availableModules

    Get dependencies of given script and warns about possible problems.

    .EXAMPLE
    $availableModules = Get-Module -ListAvailable

    Get-CodeDependencyStatus -scriptPath C:\scripts\myScript.ps1 -availableModules $availableModules -resultAsObject

    Get dependencies of given script and warns about possible problems. Instead of warning messages, objects will be returned.

    .EXAMPLE
    $availableModules = Get-Module -ListAvailable

    Get-CodeDependencyStatus -moduleName MyModule -availableModules $availableModules

    Get dependencies of given module and warns about possible problems. Such module has to be available in $env:PSModulePath or in PowerShell Gallery.

    .EXAMPLE
    $availableModules = Get-Module -ListAvailable

    Get-CodeDependencyStatus -moduleBasePath 'C:\modules\AWS.Tools.Common\4.1.233' -availableModules $availableModules

    Get dependencies of given module and warns about possible problems.

    .NOTES
    Requires function Get-CodeDependency.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "scriptPath")]
        [ValidateScript( {
                if ((Test-Path -Path $_ -PathType leaf) -and $_ -match "\.ps1$") {
                    $true
                } else {
                    throw "$_ is not a ps1 file or it doesn't exist"
                }
            })]
        [string] $scriptPath,

        [Parameter(Mandatory = $true, ParameterSetName = "moduleName")]
        [string] $moduleName,

        [Parameter(Mandatory = $false, ParameterSetName = "moduleName")]
        [string] $moduleVersion,

        [Parameter(Mandatory = $true, ParameterSetName = "moduleBasePath")]
        [ValidateScript( {
                if (Test-Path -Path $_ -PathType Container) {
                    $true
                } else {
                    throw "$_ is not a path to folder where module is stored. For example 'C:\modules\AWS.Tools.Common' or 'C:\modules\AWS.Tools.Common\4.1.233'"
                }
            })]
        [string] $moduleBasePath,

        [System.Collections.ArrayList] $availableModules = @(),

        [switch] $asObject
    )

    #region get dependencies
    $param = @{
        noReccursion                     = $true
        checkModuleFunctionsDependencies = $true
    }
    if ($availableModules) {
        $param.availableModules = $availableModules
    }
    if ($scriptPath) {
        $param.scriptPath = $scriptPath
    } elseif ($moduleName) {
        $param.moduleName = $moduleName
        if ($moduleVersion) {
            $param.moduleVersion = $moduleVersion
        }
    } elseif ($moduleBasePath) {
        $param.moduleBasePath = $moduleBasePath
    } else {
        throw "undefined option"
    }

    $dependency = Get-CodeDependency @param
    #endregion get dependencies

    $usedModule = $dependency | ? { $_.Type -EQ "Module" -and $_.Source -NE $scriptPath }

    $explicitlyImportedModule = $dependency | ? { $_.Type -EQ "Module" -and $_.Command -Match "^(Import-Module|ipmo) " }

    if ($scriptPath) {
        $explicitlyRequiredModule = $dependency | ? { $_.Type -EQ "Module" -and $_.Command -EQ "<requires statement>" }
    } else {
        $explicitlyRequiredModule = $dependency | ? { $_.Type -EQ "Module" -and $_.Command -EQ "<module manifest>" }
    }

    if ($scriptPath) {
        # script check
        $suffixTxt = "(through #requires statement)"
    } else {
        # module check
        $suffixTxt = "(through module manifest)"
    }

    #region missing explicit module requirement
    if ($usedModule) {
        $usedModule | % {
            $mName = $_.Name
            if ($mName -notin $explicitlyImportedModule.Name -and $mName -notin $explicitlyRequiredModule.Name) {
                $msg = "Module '$mName' (thanks to command: '$($_.Command)') is used, but not explicitly imported or required $suffixTxt"

                if ($asObject) {
                    [PSCustomObject]@{
                        Module  = $mName
                        Problem = "ModuleUsedButNotRequired"
                        Message = $msg
                    }
                } else {
                    Write-Warning $msg
                }
            }
        }
    }
    #endregion missing explicit module requirement

    #region version mismatch
    if ($usedModule) {
        $usedModule | % {
            $mName = $_.Name
            $mVersion = $_.Version
            $explicitlyRequiredModuleVersion = ($explicitlyRequiredModule | ? name -EQ $mName).version
            if ($mVersion -and $mVersion -notin $explicitlyRequiredModuleVersion) {
                $msg = "Module '$mName' (thanks to command: '$($_.Command)') that is used, has different version ($mVersion) then explicitly required one ($($explicitlyRequiredModuleVersion -join ', ')) $suffixTxt"

                if ($asObject) {
                    [PSCustomObject]@{
                        Module  = $mName
                        Problem = "ModuleVersionConflict"
                        Message = $msg
                    }
                } else {
                    Write-Warning $msg
                }
            }
        }
    }

    if ($explicitlyImportedModule) {
        $explicitlyImportedModule | % {
            $mName = $_.Name
            $mVersion = $_.Version
            $explicitlyRequiredModuleVersion = ($explicitlyRequiredModule | ? name -EQ $mName).version
            if ($mVersion -and $mVersion -notin $explicitlyRequiredModuleVersion) {
                $msg = "Module '$mName' that is explicitly imported, has different version ($mVersion) then explicitly required one ($($explicitlyRequiredModuleVersion -join ', ')) $suffixTxt"

                if ($asObject) {
                    [PSCustomObject]@{
                        Module  = $mName
                        Problem = "ModuleVersionConflict"
                        Message = $msg
                    }
                } else {
                    Write-Warning $msg
                }
            }
        }
    }
    #endregion version mismatch

    #region unnecessary module requirement
    if ($explicitlyImportedModule) {
        $explicitlyImportedModule | % {
            $mName = $_.Name
            if ($mName -notin $usedModule.Name) {
                $msg = "Module '$mName' is explicitly imported, but not used"

                if ($asObject) {
                    [PSCustomObject]@{
                        Module  = $mName
                        Problem = "ModuleImportedNotUsed"
                        Message = $msg
                    }
                } else {
                    Write-Warning $msg
                }
            }
        }
    }

    if ($explicitlyRequiredModule) {
        $explicitlyRequiredModule | % {
            $mName = $_.Name
            if ($mName -notin $usedModule.Name) {
                $msg = "Module '$mName' is explicitly required, but not used"

                if ($asObject) {
                    [PSCustomObject]@{
                        Module  = $mName
                        Problem = "ModuleRequiredNotUsed"
                        Message = $msg
                    }
                } else {
                    Write-Warning $msg
                }
            }
        }
    }
    #endregion unnecessary module requirement
}

function Get-ImportModuleFromAST {
    <#
    .SYNOPSIS
    Function finds calls of Import-Module command (including its alias ipmo) in given AST and returns objects with used parameters and their values for each call.

    .DESCRIPTION
    Function finds calls of Import-Module command (including its alias ipmo) in given AST and returns objects with used parameters and their values for each call.

    .PARAMETER AST
    AST object which will be searched.

    Can be retrieved like: $AST = [System.Management.Automation.Language.Parser]::ParseFile("C:\script.ps1", [ref] $null, [ref] $null)

    .EXAMPLE
    $AST = [System.Management.Automation.Language.Parser]::ParseFile("C:\script.ps1", [ref] $null, [ref] $null)

    Get-ImportModuleFromAST -AST $AST
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.Ast] $AST
    )

    $usedCommand = $AST.FindAll( { $args[0] -is [System.Management.Automation.Language.CommandAst ] }, $true)

    if (!$usedCommand) {
        Write-Verbose "No command detected in given AST"
        return
    }

    $importModuleCommandList = $usedCommand | ? { $_.CommandElements[0].Value -in "Import-Module", "ipmo" }

    if (!$importModuleCommandList) {
        Write-Verbose "No 'Import-Module' or its alias 'ipmo' detected"
        return
    }

    foreach ($importModuleCommand in $importModuleCommandList) {
        $importModuleCommandElement = $importModuleCommand.CommandElements
        $importModuleCommandElement = $importModuleCommandElement | select -Skip 1 # skip Import-Module command itself

        Write-Verbose "Getting Import-Module parameters from: '$($importModuleCommand.extent.text)' (file: $($importModuleCommand.extent.File))"

        #region get parameter name and value for NAMED parameters
        $param = @{}
        $paramName = ''
        foreach ($element in $importModuleCommandElement) {
            if ($paramName) {
                # variable is set true when parameter was found
                # this foreach cycle therefore contains parameter value
                if ($paramName -eq "FullyQualifiedName" -and $element.StaticType.Name -eq "String") {
                    # module name or path was specified
                    $param.Name = $element.Extent.Text -replace "`"|'"
                } elseif ($paramName -eq "FullyQualifiedName" -and $element.StaticType.Name -eq "Hashtable") {
                    # hashtable for 'FullyQualifiedName' parameter was specified
                    $param.Name = ($element.KeyValuePairs | ? { $_.Item1.Value -eq "ModuleName" }).Item2.Extent.Text -replace "`"|'"
                    $param.MinimumVersion = ($element.KeyValuePairs | ? { $_.Item1.Value -eq "ModuleVersion" }).Item2.Extent.Text -replace "`"|'"
                    $param.MaximumVersion = ($element.KeyValuePairs | ? { $_.Item1.Value -eq "MaximumVersion" }).Item2.Extent.Text -replace "`"|'"
                    $param.RequiredVersion = ($element.KeyValuePairs | ? { $_.Item1.Value -eq "RequiredVersion" }).Item2.Extent.Text -replace "`"|'"
                } elseif ($element.StaticType.Name -eq "String") {
                    # one module was specified
                    $param.$paramName = $element.Extent.Text -replace "`"|'"
                } elseif ($element.Elements) {
                    # multiple modules were specified
                    $param.$paramName = ($element.Elements | ? { $_.StaticType.Name -eq "String" } | select -ExpandProperty Value) -replace "`"|'"
                } else {
                    # value passed from pipeline etc probably
                    Write-Verbose "Unknown Import-Module '$paramName' parameter value"
                    $param.$paramName = '<unknown>'
                }

                $paramName = ''
                continue
            }

            if ($element.ParameterName) {
                $paramName = $element.ParameterName

                # transform param. name shortcuts to their full name if necessary
                switch ($paramName) {
                    { $_ -match "^f" } { $paramName = "FullyQualifiedName" }
                    { $_ -match "^n" } { $paramName = "Name" }
                    { $_ -match "^ma" } { $paramName = "MaximumVersion" }
                    { $_ -match "^mi" } { $paramName = "MinimumVersion" }
                    { $_ -match "^p" } { $paramName = "Prefix" }
                    { $_ -match "^r" } { $paramName = "RequiredVersion" }
                }
            }
        }
        #endregion get parameter name and value for NAMED parameters

        if (!$param.Name) {
            Write-Verbose "Modules are imported using positional parameter"
            # 'Name' parameter wasn't specified by name, but by position, search for entered values
            # Name parameter is on first position
            $firstImportModuleCommandElement = $importModuleCommandElement | select -First 1

            if ($firstImportModuleCommandElement.Elements) {
                # multiple module values were specified
                $param.Name = ($firstImportModuleCommandElement.Elements | ? { $_.StaticType.Name -eq "String" } | select -ExpandProperty Value) -replace "`"|'"
            } elseif ($firstImportModuleCommandElement.StaticType.Name -eq "String") {
                # one module value was specified
                $param.Name = ($firstImportModuleCommandElement | ? { $_.StaticType.Name -eq "String" } | select -ExpandProperty Value) -replace "`"|'"
            } else {
                Write-Verbose "Unknown Import-Module 'Name' parameter value"
            }
        }

        if (!$param.Name -or $param.Name -eq '<unknown>') {
            Write-Warning "Unable to detect module imported through Import-Module command: '$($importModuleCommand.extent.text)' (file: $($importModuleCommand.extent.File))"

            continue
        }

        # output object for each added module
        $param.Name | % {
            # I output separate object for each imported module, because in case path is used instead of name, different version for different modules can be specified
            # Import-Module "C:\DATA\repo\Pilot_PowerShell\modules\AutoItX\AutoItX.psd1", "C:\DATA\repo\Pilot_PowerShell\modules\AWS.Tools.Common\4.1.233\AWS.Tools.Common.psd1"
            $name = $_
            Write-Verbose "Processing module '$name'"

            $itIsPath = $name -like "*\*"

            # get module version
            # INFO version can be from two part to four part a.k.a. from 0.0 to 0.0.0.0
            $reqModuleVersion = $null
            $nameContainsVersion = $name -match "\\\d+(\.\d+){0,2}\.\d+"
            if ($param.RequiredVersion) {
                # RequiredVersion parameter overrides version specified in the module path
                Write-Verbose "Getting module version from RequiredVersion parameter"
                $reqModuleVersion = $param.RequiredVersion
            } elseif ($nameContainsVersion) {
                # path contain module version
                Write-Verbose "Getting module version from its path"
                $reqModuleVersion = ([regex]"\d+(\.\d+){0,2}\.\d+").Match($name).value
            }

            if ($itIsPath) {
                # replace path for name only
                if (Test-Path $name -PathType Leaf) {
                    # path looks like C:\modules\AWS.Tools.Common\AWS.Tools.Common.psd1
                    $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($name)
                } else {
                    if ($nameContainsVersion) {
                        # path looks like C:\modules\AWS.Tools.Common\4.1.233\...
                        $moduleName = Split-Path ($name -replace "\\\d+(\.\d+){0,2}\.\d+\\.*") -Leaf
                    } else {
                        # path looks like C:\modules\AWS.Tools.Common
                        $moduleName = ($name -split "\\")[-1]
                    }
                }
            } else {
                $moduleName = $name
            }

            [PSCustomObject]@{
                Command         = $importModuleCommand.extent.text
                File            = $importModuleCommand.extent.File
                ImportedModule  = $moduleName
                MaximumVersion  = $param.MaximumVersion
                MinimumVersion  = $param.MinimumVersion
                Prefix          = $param.Prefix
                RequiredVersion = $reqModuleVersion
            }
        }
    }
}

Export-ModuleMember -function Get-AddPSSnapinFromAST, Get-CodeDependency, Get-CodeDependencyStatus, Get-ImportModuleFromAST

Export-ModuleMember -alias Get-Dependency, Get-PSHCodeDependency
