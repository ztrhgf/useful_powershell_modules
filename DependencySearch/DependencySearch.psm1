function Get-AddPSSnapinFromAST {
    <#
    .SYNOPSIS
    Function finds calls of Add-PSSnapin command (including its alias asnp) in given AST and returns objects with used parameters and their values for each call.

    .DESCRIPTION
    Function finds calls of Add-PSSnapin command (including its alias asnp) in given AST and returns objects with used parameters and their values for each call.

    .PARAMETER AST
    AST object which will be searched.

    Can be retrieved like: $AST = [System.Management.Automation.Language.Parser]::ParseFile("C:\script.ps1", [ref] $null, [ref] $null)

    .PARAMETER source
    For internal use only.

    .EXAMPLE
    $AST = [System.Management.Automation.Language.Parser]::ParseFile("C:\script.ps1", [ref] $null, [ref] $null)

    Get-AddPSSnapinFromAST -AST $AST
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.Ast] $AST,

        [array] $source
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
            if ($source) {
                $sourceTxt = "source: " + @($source)[-1]
            } else {
                $sourceTxt = "file: " + $addPSSnapinCommand.extent.File
            }
            Write-Warning "Unable to detect PSSnapins added through Add-PSSnapin command: '$($addPSSnapinCommand.extent.text)' ($sourceTxt)"

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
    Function finds dependencies for given PSH code/script/module.

    By dependencies, different kind of requirements are meant like:
    - PSH modules such code explicitly imports OR requires (using statement) OR requires, because uses commands defined in such module
    - PSSnapins
    - admin rights (using statement)

    .DESCRIPTION
    Function finds dependencies/requirements for given PSH code/script/module.

    a) When code/script is given:
    - code '#requires' statement is searched for required modules and their dependencies are gathered using option b)
    - code explicit module imports (calls of Import-Module) are searched and their dependencies are gathered using option b)
    - all commands used in the code are searched and:
        - if command is private, ignored or already processed it is skipped
        - if command is "known" (Get-Command founds it OR it's noun begin with 'Mg' and 'Find-MgGraphCommand' command founds it in Microsoft Graph commands OR Find-Command founds it in PSGallery):
            - dependencies for command "source" module are searched using option b)
            - if command text definition exists, it is searched too using option a) recursively

    b) When module is given:
    - module is searched in locally available modules ($env:PSModulePath) using name and optionally version
        - if not found, it is searched again online in PowerShell Gallery
    - 'dependencies' in module manifest is checked and option b) is called upon for every required module recursively
    - (if 'checkModuleFunctionsDependencies' switch is used) text definition of every command in module is searched for dependencies using option a) recursively (and module is downloaded from PSGallery if not found locally)

    TIP: Built-in modules and corresponding commands are skipped during search (because everyone have them).

    By default only given code dependencies are returned and no recursion to get also dependencies of dependencies is made :)

    .PARAMETER scriptPath
    Path to PSH script whose dependencies should be searched.

    .PARAMETER scriptContent
    PSH code whose dependencies should be searched.

    .PARAMETER moduleName
    PSH module name whose dependencies should be searched.

    .PARAMETER moduleVersion
    (optional) PSH module version whose dependencies should be searched.

    .PARAMETER moduleBasePath
    Base path of the module that should be checked.

    .PARAMETER checkModuleFunctionsDependencies
    Switch for searching dependencies also for all commands defined in processed modules. Such command cannot be binary a.k.a. plaintext definition has to be available so it is possible to process it using AST.

    This can significantly increase searching time! If command is not found in locally available modules, but in PSGallery, its source module will be downloaded from the PSGallery, to get the command text definition.

    By default just required modules defined in module manifest are used for getting module dependencies. This switch can help detect whether these officially defined modules match the real required ones.

    .PARAMETER availableModules
    Helpful only when 'goDeep' parameter is used!

    To speed up repeated function invocations, save all locally available modules into variable and use it as value for this parameter.

    By default this function caches all locally available modules before each run which can take several seconds. This cache is then used when searching for modules.

    .PARAMETER goDeep
    Switch to check for dependencies not just in the given code, but even in its dependencies (recursively). A.k.a. get the whole dependency tree.

    To really get all dependencies and not just the ones for running analyzed code, use parameter 'getDependencyOfRequiredModule'.

    .PARAMETER dontSearchCommandInPSGallery
    Switch to skip searching unknown commands in PowerShell Gallery.
    Drawback of using PowerShell Gallery is that it is just guessing. Even though some module defines our command doesn't mean it is real source of it.
    Moreover command with the same name can be defined in multiple modules.

    .PARAMETER getDependencyOfRequiredModule
    By default modules that are required (because in code #requires statement or explicitly imported using 'Import-Module') or source module of processed command are outputted, but not searched for their dependencies. This parameter can change that.

    Possible values:
        - scriptRequires
            - search dependencies of the module(s) from #requires statement
        - scriptImportedModules
            - search dependencies of explicitly imported modules
        - scriptSourceModule
            - search dependencies of command's source module (module where processed command is hosted)

    Using this parameter you can get all dependencies, even the ones that are not necessarily needed to run the analyzed code

    .PARAMETER allOccurrences
    Switch to output dependant module each time it was found to be required in the code.
    Useful if you want to get all commands that require some module and not just the first one found.

    .PARAMETER nonInteractive
    Switch to run the function without any user interruptions like if:
     - function finds unknown command in multiple PSGallery modules, it won't asks which one to search and uses all of them
     - function finds command definition in multiple local modules, it won't asks which one to search and uses all of them

    .PARAMETER unknownDependencyAsObject
    Switch to return dependency object with empty module 'name' property for commands whose dependencies cannot be retrieved (because command is unknown etc).
    Instead of just outputting the warning message.

    .PARAMETER processJustMSGraphSDK
    Switch for skipping all non-MSGraphSDK modules/commands except commands that can call Graph API directly ("Invoke-MsGraphRequest", "Invoke-RestMethod", "irm", "Invoke-WebRequest", "curl", "iwr", "wget").
    Used internally when called by Get-CodeGraphPermissionRequirement to speed up the processing.
    Works only if 'goDeep' parameter is not used, because you cannot skip any module/command, because it might use some Graph commands inside.

    Moreover to be able to analyze the built-in commands ("Invoke-RestMethod", "irm", "Invoke-WebRequest", "curl", "iwr", "wget") by Get-CodeGraphPermissionRequirement, they will be outputted to the console instead of ignoring them.

    .PARAMETER processEveryTime
    List of commands that should be processed every time.
    Used in Get-CodeGraphPermissionRequirement function to get all Invoke-MGGraphRequest etc commands to be able to process each of them.

    This doesn't make sense from dependency perspective! So kind of for internal use only.

    .PARAMETER installNuget
    Switch for installing NuGet package provider in case it is missing.
    NuGet is required to be able to search for missing modules/commands in PSGallery (enables use of Find-Module and Find-Command)

    .EXAMPLE
    Get-CodeDependency -scriptPath "C:\scripts\Get-AzureServicePrincipalOverview.ps1" -Verbose

    Get dependencies just for given script. No recursion.

    .EXAMPLE
    # cache available modules to speed up repeated 'Get-CodeDependency' function invocations
    $availableModules = Get-Module -ListAvailable

    Get-CodeDependency -scriptPath "C:\scripts\Get-AzureServicePrincipalOverview.ps1" -goDeep -availableModules $availableModules -Verbose

    Get dependencies for given script and also for all its dependencies.

    Next time you call 'Get-CodeDependency', you can use $availableModules to speed up the invocation.

    .EXAMPLE
    $code = @'
        Import-Module AzureAD

        Connect-MsolService

        ...
    '@

    Get-CodeDependency -scriptContent $code -Verbose

    Get dependencies of given code. No recursion.

    .EXAMPLE
    Get-CodeDependency -moduleName MyModule

    Get dependencies of module MyModule. Such module has to be placed in any folder mentioned in $env:PSModulePath or must exist in PowerShell Gallery.
    Only dependencies defined in module manifest will be processed.

    .EXAMPLE
    Get-CodeDependency -moduleName MyModule -checkModuleFunctionsDependencies

    Get dependencies of module MyModule. Such module has to be placed in any folder mentioned in $env:PSModulePath or must exist in PowerShell Gallery.
    Dependencies defined in module manifest AND all commands such module defines will be processed. Therefore you will get all really required dependencies. because module official manifest doesn't have to exist, or have required modules defined at all (or just partially correct)!

    .EXAMPLE
    Get-CodeDependency -moduleBasePath 'C:\modules\AWS.Tools.Common\4.1.233' -Verbose

    Get dependencies of module AWS.Tools.Common version 4.1.233 (such module does NOT have to be placed in folder from $env:PSModulePath).
    Only dependencies defined in module manifest will be processed.

    .EXAMPLE
    #save current variable content, so it can be restored later
    $PSModulePathBkp = $env:PSModulePath

    # path to the folder where all my custom made modules are stored (and that is outside module auto-discovery paths)
    # this folder contains module 'MyCustomModule' and some other dependant modules which I want to use when searching for code dependencies (to avoid unnecessary error that such modules doesn't exist)
    $myPrivateModules = "C:\useful_powershell_modules"

    # add modules path if necessary
    if ($myPrivateModules -notin ($env:PSModulePath -split ";")) {
        $env:PSModulePath = $env:PSModulePath + ";$myPrivateModules"
    }

    # cache available modules including the extra ones
    $availableModules = Get-Module -ListAvailable

    Get-CodeDependency -moduleName MyCustomModule -availableModules $availableModules

    # restore previous version of $env:PSModulePath
    $env:PSModulePath = $PSModulePathBkp

    Get dependencies of MyCustomModule module that is placed in folder not listed in $env:PSModulePath that uses some other modules from such folder.
    Only dependencies defined in module manifest will be processed.

    .EXAMPLE
    Get-CodeDependency -scriptPath "C:\scripts\Get-AzureServicePrincipalOverview.ps1" -allOccurrences -nonInteractive -installNuget -unknownDependencyAsObject

    Get dependencies of given script.

    Redundancy dependencies will be outputted (for example in case multiple used commands are defined in the same module).
    In case command/module isn't found locally but is found in PSGallery, all such findings will be searched without asking the user to choose the "right one".
    In case NuGet is not installed, it will be, so the PSGallery can be searched.
    In case unknown command is found it will be outputted instead of just warning message.
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

        [Alias("recurse")]
        [switch] $goDeep,

        [switch] $dontSearchCommandInPSGallery,

        [ValidateSet('scriptRequires', 'scriptImportedModules', 'scriptSourceModule')]
        [string[]] $getDependencyOfRequiredModule,

        [switch] $allOccurrences,

        [switch] $nonInteractive,

        [switch] $unknownDependencyAsObject,

        [switch] $processJustMSGraphSDK,

        [string[]] $processEveryTime,

        [switch] $installNuget
    )

    if ($availableModules -and !$goDeep) {
        Write-Warning "'availableModules' parameter doesn't have to be specified when 'goDeep' is being skipped"
    }

    # check whether PSGallery can be used to retrieve commands/modules information
    if (!(Get-PackageProvider | ? Name -EQ "NuGet") -and $installNuget) {
        Write-Warning "Installing NuGet package manager"
        $null = Install-PackageProvider -Name "NuGet" -Force -ForceBootstrap
    }

    # modules available by default, will be therefore skipped
    $ignoredModule = 'AppBackgroundTask', 'AppLocker', 'AppvClient', 'Appx', 'AssignedAccess', 'BitLocker', 'BitsTransfer', 'BranchCache', 'CimCmdlets', 'ConfigCI', 'Defender', 'DeliveryOptimization', 'DirectAccessClientComponents', 'Dism', 'DnsClient', 'EventTracingManagement', 'International', 'iSCSI', 'ISE', 'Kds', 'LanguagePackManagement', 'Microsoft.PowerShell.Archive', 'Microsoft.PowerShell.Diagnostics', 'Microsoft.PowerShell.Host', 'Microsoft.PowerShell.LocalAccounts', 'Microsoft.PowerShell.Management', 'Microsoft.PowerShell.ODataUtils', 'Microsoft.PowerShell.Security', 'Microsoft.PowerShell.Utility', 'Microsoft.WSMan.Management', 'MMAgent', 'MsDtc', 'NetAdapter', 'NetConnection', 'NetEventPacketCapture', 'NetLbfo', 'NetNat', 'NetQos', 'NetSecurity', 'NetSwitchTeam', 'NetTCPIP', 'NetworkConnectivityStatus', 'NetworkSwitchManager', 'NetworkTransition', 'PcsvDevice', 'PersistentMemory', 'PKI', 'PnpDevice', 'PrintManagement', 'ProcessMitigations', 'Provisioning', 'PSDesiredStateConfiguration', 'PSDiagnostics', 'PSScheduledJob', 'PSWorkflow', 'PSWorkflowUtility', 'ScheduledTasks', 'SecureBoot', 'SmbShare', 'SmbWitness', 'StartLayout', 'Storage', 'StorageBusCache', 'TLS', 'TroubleshootingPack', 'TrustedPlatformModule', 'UEV', 'VpnClient', 'Wdac', 'Whea', 'WindowsDeveloperLicense', 'WindowsErrorReporting', 'WindowsSearch', 'WindowsUpdate', 'Microsoft.PowerShell.Operation.Validation', 'PackageManagement', 'Pester', 'PowerShellGet', 'PSReadline'

    # here will be saved downloaded modules from PowerShell Gallery
    $moduleTmpPath = "$env:TEMP\PSHModules"

    #region set functions default parameters
    $PSDefaultParameterValuesBkp = $PSDefaultParameterValues.Clone()
    if (!$PSDefaultParameterValues) {
        $PSDefaultParameterValues = @{}
    }

    # to minimize clutter in verbose output
    $PSDefaultParameterValues.'Import-Module:Verbose' = $false
    $PSDefaultParameterValues.'Get-Module:Verbose' = $false
    #endregion set functions default parameters

    #region create cache variables
    if ($availableModules) {
        Write-Verbose "Using given 'availableModules' as list of available modules"
        [System.Collections.ArrayList] $global:availableModules = $availableModules
        # } elseif ($PSBoundParameters.ContainsKey("availableModules")) {
        #TODO prikazy se stejne budou hledat lokalne prec get-command, tzn dava tohle vubec smysl?
        #     Write-Warning "You choose to not provide 'availableModules'. All modules will be searched directly in the PSGallery instead of searching locally first"
        #     [System.Collections.ArrayList] $global:availableModules = @()
    } elseif (!$goDeep) {
        # no need to cache modules, won't be needed when searching for dependencies
        [System.Collections.ArrayList] $global:availableModules = @()
    } else {
        Write-Warning "Caching locally available modules. To skip this step, use parameter 'availableModules'"
        [System.Collections.ArrayList] $global:availableModules = @(Get-Module -ListAvailable)
    }
    # array of already processed modules saved as psobjects where each object contains module name and (optionally) its version
    $global:processedModules = @()
    # array of already outputted modules saved as psobjects where each object contains module name and (optionally) its version
    $global:outputtedModules = @()
    # array of already processed commands
    $global:processedCommands = @()
    # array of already processed PSSnapins saved as psobjects where each object contains snapin name and (optionally) its version
    $global:processedPSSnapins = @()
    # if the code or some of its dependencies requires elevation
    $global:isElevationRequired = $false
    # hash where key is module BasePath and value is module private functions
    $global:modulePrivateFunction = @{}
    # hash where key is module BasePath and value is list of all module function definitions
    $global:moduleFunctionDefinition = @{}
    #endregion create cache variables

    #region helper functions
    function ConvertTo-FlatArray {
        # flattens input in case, that string and arrays are entered at the same time
        param (
            [array] $inputArray
        )

        foreach ($item in $inputArray) {
            if ($item -ne $null) {
                # recurse for arrays
                if ($item.gettype().BaseType -eq [System.Array]) {
                    ConvertTo-FlatArray $item
                } else {
                    # output non-arrays
                    $item
                }
            }
        }
    }

    function Get-FunctionDefinitionFromAST {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            $AST,

            [switch] $recurse
        )

        $AST.FindAll( {
                param([System.Management.Automation.Language.Ast] $AST)

                $AST -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                # Class methods have a FunctionDefinitionAst under them as well, but we don't want them.
                        ($PSVersionTable.PSVersion.Major -lt 5 -or
                $AST.Parent -isnot [System.Management.Automation.Language.FunctionMemberAst])
            }, [bool]$recurse)
    }

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
            return
        }

        $exportedCommand = $moduleObj.ExportedCommands.keys

        $scriptFile = Get-ChildItem (Join-Path $moduleBasePath "*") -Include "*.psm1", "*.ps1" -Recurse | select -ExpandProperty FullName

        foreach ($script in $scriptFile) {
            # get AST
            $errors = [System.Management.Automation.Language.ParseError[]]@()
            $tokens = [System.Management.Automation.Language.Token[]]@()
            $AST = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref] $tokens, [ref] $errors)

            # get functions defined in the code, so I can ignore them when searching for dependencies (their content is checked though)
            $definedFunction = Get-FunctionDefinitionFromAST $AST

            $definedFunction.name | ? { $_ -notin $exportedCommand }
        }
    }

    function _getModuleFunctionDefinition {
        # get & cache module function definitions
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string] $moduleBasePath,

            [Parameter(Mandatory = $true)]
            [string] $commandName
        )

        if ($global:moduleFunctionDefinition.keys -contains $moduleBasePath) {
            return ($global:moduleFunctionDefinition.$moduleBasePath | ? Name -EQ $commandName | select -First 1 -ExpandProperty Body)
        }

        $result = Get-ModuleFunctionDefinition -moduleBasePath $moduleBasePath

        $global:moduleFunctionDefinition.$moduleBasePath = $result

        return ($result | ? Name -EQ $commandName | select -First 1 -ExpandProperty Body)
    }

    function Get-ModuleFunctionDefinition {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [ValidateScript( {
                    if (Test-Path -Path $_ -PathType Container) {
                        $true
                    } else {
                        throw "$_ is not a folder"
                    }
                })]
            [string] $moduleBasePath,

            [string] $commandName
        )

        $moduleObj = Get-Module -FullyQualifiedName $moduleBasePath -ListAvailable -Verbose:$false

        if (!$moduleObj) {
            Write-Error "Module in path '$moduleBasePath' doesn't exist"
            return
        }

        $scriptFile = Get-ChildItem (Join-Path $moduleBasePath "*") -Include "*.psm1", "*.ps1" -Recurse | select -ExpandProperty FullName

        foreach ($script in $scriptFile) {
            # get AST
            $errors = [System.Management.Automation.Language.ParseError[]]@()
            $tokens = [System.Management.Automation.Language.Token[]]@()
            $AST = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref] $tokens, [ref] $errors)

            # get functions defined in the code, so I can ignore them when searching for dependencies (their content is checked though)
            $definedFunction = Get-FunctionDefinitionFromAST $AST

            if ($commandName) {
                $definedFunction | ? { $_.Name -eq $commandName }
            } else {
                $definedFunction
            }
        }
    }

    function _getModuleDependency {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true, ParameterSetName = "moduleObj")]
            [System.Management.Automation.PSModuleInfo] $module,

            [Parameter(Mandatory = $true, ParameterSetName = "moduleName")]
            [string] $moduleName,

            [Parameter(ParameterSetName = "moduleName")]
            [version] $moduleVersion,

            [switch] $processBuiltinModule,

            [int] $indent = 1,

            [switch] $dontOutputTheModuleItself,

            [array] $source,

            [string] $command,

            [switch] $dontSearchForDependencies
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

        function _moduleIsOutputted {
            param ($moduleName, $moduleVersion)

            if (($moduleVersion -and ($global:outputtedModules | ? { $_.ModuleName -eq $moduleName -and $_.ModuleVersion -eq $moduleVersion })) -or (!$moduleVersion -and ($moduleName -in $global:outputtedModules.ModuleName))) {
                $true
            } else {
                $false
            }
        }
        #endregion helper functions

        #region checks & output before start of the module processing
        if ($module) {
            $mName = $module.name
            $mVersion = $module.Version
        } else {
            $mName = $moduleName
            $mVersion = $moduleVersion
        }

        Write-Verbose ("`t`t`t" * $indent + "- Processing module '$mName' (ver. $mVersion)")

        if ($processJustMSGraphSDK -and !$goDeep -and !$checkModuleFunctionsDependencies -and $mName -notlike "Microsoft.Graph.*" ) {
            Write-Verbose ("`t`t`t`t" * $indent + "- Module '$mName' (ver. $mVersion) isn't Graph SDK module. Skipping")
            return
        }

        if ($mName -in $ignoredModule -and !$processBuiltinModule) {
            Write-Verbose ("`t`t`t`t" * $indent + "- Module '$mName' (ver. $mVersion) is built-in. Skipping")
            return
        }

        $moduleWasProcessed = _moduleIsProcessed -moduleName $mName -moduleVersion $mVersion
        $moduleWasOutputted = _moduleIsOutputted -moduleName $mName -moduleVersion $mVersion

        if (!$dontOutputTheModuleItself -and ($allOccurrences -or (!$moduleWasProcessed -and !$moduleWasOutputted))) {
            # OUTPUT module that is being processed
            [PSCustomObject]@{
                Type           = 'Module'
                Name           = $mName
                Version        = $mVersion
                RequiredBy     = $command
                DependencyPath = ConvertTo-FlatArray $source
            }

            # make a note that module was outputted
            $global:outputtedModules += [PSCustomObject]@{
                ModuleName    = $mName
                ModuleVersion = $mVersion
            }
        }

        if ($dontSearchForDependencies) {
            Write-Verbose ("`t`t`t`t" * $indent + "- Searching for module '$mName' dependencies is skipped")
            return
        }

        # make a note that module was processed
        $global:processedModules += [PSCustomObject]@{
            ModuleName    = $mName
            ModuleVersion = $mVersion
        }

        if (!$dontOutputTheModuleItself -and !$goDeep) {
            return
        }

        if ($moduleWasProcessed) {
            Write-Verbose ("`t`t`t`t" * $indent + "- Module '$mName' (ver. $mVersion) was already processed. Skipping")
            return
        }
        #endregion checks & output before start of the module processing

        #region get module object if necessary
        if ($moduleName) {
            # module is defined by its name (and optionally version)
            # search must be made to get an actual module object with all relevant data
            $module = _getModule -moduleName $moduleName -moduleVersion $moduleVersion -indent $indent

            #region get module data from PSH Gallery if not found locally
            if (!$module) {
                if ($moduleVersion) {
                    $moduleVersionTxt = "(ver. $moduleVersion) "
                } else {
                    $moduleVersionTxt = $null
                }
                Write-Warning "- Module '$moduleName' $moduleVersionTxt`isn't present on this machine. Trying to find it in online PowerShell Gallery"

                # if ('Trusted' -ne ($Policy = (Get-PSRepository PSGallery).InstallationPolicy)) {
                #     Set-PSRepository PSGallery -InstallationPolicy Trusted
                # }

                # get dependencies for every command this module defines
                # officially defined requirements don't have to be 100% correct
                if ($checkModuleFunctionsDependencies) {
                    # module commands should be processed, therefore I try to download the module locally
                    # if successful I will process the module as any other local module

                    # define module path
                    $modulePath = Join-Path $moduleTmpPath $moduleName # C:\modules\AWS.Tools.Common
                    if ($moduleVersion) {
                        $modulePath = Join-Path $modulePath $moduleVersion # C:\modules\AWS.Tools.Common\4.1.233
                    }

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
                            [Void][System.IO.Directory]::CreateDirectory($moduleTmpPath)

                            Write-Verbose ("`t`t`t`t" * $indent + "- Downloading module from the PowerShell Gallery to the '$moduleTmpPath'")
                            Save-Module @param

                            $module = Get-Module -FullyQualifiedName $modulePath -ListAvailable -ErrorAction SilentlyContinue

                            # cache the result
                            $null = $global:availableModules.add($module)
                        } catch {
                            if ($_ -like "*No match was found for the specified search criteria*") {
                                Write-Warning "- Module isn't available in the PowerShell Gallery either"
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
                        if (Get-PackageProvider | ? Name -EQ "NuGet") {
                            $pshgModule = Find-Module @param
                        } else {
                            Write-Warning ("`t`t`t`t`t" * $indent + "- PSGallery cannot be used to search for '$moduleName' module. NuGet is missing. Use 'installNuget' parameter to solve this.")
                            return
                        }
                    } catch {
                        if ($_ -like "*No match was found for the specified search criteria*") {
                            Write-Warning "- Module isn't available in the PowerShell Gallery either"
                        } else {
                            Write-Error $_
                        }

                        return
                    }

                    #region get dependencies for every required module (specified in the manifest)
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
                                    $param.moduleVersion = $reqModuleVersion
                                }

                                _getModuleDependency @param
                            }
                        }
                    } else {
                        Write-Verbose "`t- Didn't find any dependency"
                    }
                    #endregion get dependencies for every required module  (specified in the manifest)

                    return
                }
            } # module was searched in PowerShell Gallery
            #endregion get module data from PSH Gallery if not found locally
        } else {
            # module was passed as an object, no search is necessary
        }
        #endregion get module object if necessary

        #region get dependencies for every module, module in question requires through manifest
        $requiredModules = $module.RequiredModules

        if ($requiredModules) {
            $requiredModules | % {
                Write-Verbose ("`t`t`t`t" * $indent + "- Module '$($module.name)' (ver. $($module.version)) requires module $($_.name) (ver. $($_.version))")
                # required modules definition doesn't contain requirements for required modules :)
                # get dependencies of dependency :)
                _getModuleDependency -moduleName $_.name -moduleVersion $_.version -indent ($indent + 1) -source ($source, $module.name) -command "<module manifest>"
            }
        } else {
            Write-Verbose ("`t`t`t`t" * $indent + "- Module $($module.name) (ver. $($module.version)) doesn't require any modules")
        }

        #TODO vytahnout i dalsi DotNetFrameworkVersion, PowerShellVersion, RequiredAssemblies
        #endregion get dependencies for every module, module in question requires through manifest

        #region get dependencies for every command, module in question defines
        # officially defined requirements don't have to be 100% correct
        if ($checkModuleFunctionsDependencies) {
            # get private functions so I can ignore them later
            Write-Verbose ("`t`t`t`t" * $indent + "- Getting private functions defined in module '$mName'")
            $modulePrivateFunction = _getModulePrivateFunction -moduleBasePath $module.ModuleBase

            Write-Verbose ("`t`t`t`t" * $indent + "- Getting commands defined in module '$mName'")
            # cmdlets are binary, hence no text definition will be available
            $module.ExportedCommands.keys | ? { $_ -notin $module.ExportedAliases.keys -and $_ -notin $module.ExportedCmdlets.Keys } | % {
                $cmdName = $_
                Write-Verbose ("`t`t`t`t`t" * $indent + "- Processing command '$cmdName'")
                # skip errors, because some module exports commands that doesn't exist

                $cmdData = Get-Command $cmdName -Module $module -Verbose:$false -ErrorAction SilentlyContinue | ? Name -EQ $cmdName # just exact matches (name can contain wildcard)
                $cmdDefinition = $cmdData.ScriptBlock # command body
                if (!$cmdDefinition) {
                    # sometimes module details doesn't contain commands definition (even though its not binary module)
                    Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Unable to get command definition using Get-Command, trying to get it from AST of the '$mName' module")
                    $cmdDefinition = _getModuleFunctionDefinition -moduleBasePath $module.ModuleBase -commandName $cmdName
                }

                if ($cmdDefinition) {
                    Write-Verbose ("`t`t`t`t`t" * $indent + "- Getting command '$cmdName' dependencies from its definition")
                    #TODO tim ze taham dependency z definition, tak nikdy neuvidim obsah #requires! (neni soucast tela funkce v modulech), proto muze byt kontrola per ps1 file lepsi
                    _getScriptDependency -scriptContent $cmdDefinition -indent ($indent + 1) -source ($source, $mName, $cmdName) -ignoreCommand $modulePrivateFunction
                } else {
                    Write-Warning ("`t`t`t`t`t" * $indent + "- Unable to get command '$cmdName' definition")

                    if ($unknownDependencyAsObject) {
                        [PSCustomObject]@{
                            Type           = 'Module'
                            Name           = ''
                            Version        = ''
                            RequiredBy     = $cmdName
                            DependencyPath = ConvertTo-FlatArray $source
                        }
                    }
                }
            }
        }
        #endregion get dependencies for every command, module in question defines
    } # end of _getModuleDependency function

    function _getScriptDependency {
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

            [array] $source,

            [string[]] $ignoreCommand
        )

        #region get commands used in the given code
        # get AST
        $errors = [System.Management.Automation.Language.ParseError[]]@()
        $tokens = [System.Management.Automation.Language.Token[]]@()
        if ($scriptPath) {
            $AST = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $scriptPath), [ref] $tokens, [ref] $errors)
        } else {
            $AST = [System.Management.Automation.Language.Parser]::ParseInput($scriptContent, [ref] $tokens, [ref] $errors)
        }

        # get functions defined inside the code, so I can ignore them when searching for dependencies (their content is checked though)
        $definedFunction = Get-FunctionDefinitionFromAST $AST -recurse

        $usedCommand = $AST.FindAll( { $args[0] -is [System.Management.Automation.Language.CommandAst ] }, $true)

        # filter out items that are with 99% probability not a real commands
        $usedCommand = $usedCommand | ? { $_.CommandElements[0].Value -notmatch "\\|/|\.ps1$|\.exe$" }
        #endregion get commands used in the given code

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
                    Type           = 'PSSnapin'
                    Name           = $PSSnapin.Name
                    Version        = $PSSnapin.Version
                    RequiredBy     = "<requires statement>"
                    DependencyPath = ConvertTo-FlatArray $source
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
        $addedPSSnapin = Get-AddPSSnapinFromAST $AST $source
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
                    Type           = 'PSSnapin'
                    Name           = $PSSnapinName
                    Version        = $null
                    RequiredBy     = $PSSnapin.Command
                    DependencyPath = ConvertTo-FlatArray $source
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

        #region get dependencies for every module, command in question requires
        #region get dependencies for every module, command in question has in requires statement
        #TODO detekovat pouziti using

        Write-Verbose ("`t`t`t`t" * $indent + "- Getting code dependencies for every required MODULE")
        # get all required modules defined in requires statement
        $requiresModuleList = $AST.ScriptRequirements.RequiredModules
        if ($requiresModuleList) {
            Write-Verbose ("`t`t`t`t`t" * $indent + "- Processing modules from #requires statement")
            $requiresModuleList | ? { $_ } | % {
                $minimumVersion = $_.version
                $maximumVersion = $_.MaximumVersion
                $requiredVersion = $_.RequiredVersion

                $param = @{
                    moduleName                = $_.Name
                    moduleVersion             = $requiredVersion
                    indent                    = ($indent + 1)
                    source                    = $source
                    command                   = "<requires statement>"
                    dontSearchForDependencies = $true
                }
                if ($getDependencyOfRequiredModule -contains "scriptRequires") {
                    $param.dontSearchForDependencies = $false
                }

                _getModuleDependency @param
            }
        }
        #endregion get dependencies for every module, command in question has in requires statement

        #region get dependencies for every module imported using Import-Module (or ipmo alias)
        # ma smysl jen kvuli modulum ktere definuji promenne, typy atp a zjisteni konkretni verze modulu..jinak najdu moduly pres pouzite prikazy v kodu
        $importModuleCommandList = Get-ImportModuleFromAST $AST $source

        if ($importModuleCommandList) {
            Write-Verbose ("`t`t`t`t`t" * $indent + "- Processing modules from Import-Module command calls")

            $importModuleCommandList | % {
                # Write-Verbose "Module '$($_.ImportedModule)' is imported via command: $($_.Command)"

                #TODO resit i minimum/maximum verzi?
                $param = @{
                    moduleName                = $_.ImportedModule
                    moduleVersion             = $_.RequiredVersion
                    indent                    = ($indent + 1)
                    source                    = $source
                    command                   = $_.Command
                    dontSearchForDependencies = $true
                }
                if ($getDependencyOfRequiredModule -contains "scriptImportedModules") {
                    $param.dontSearchForDependencies = $false
                }

                _getModuleDependency @param
            }
        }
        #endregion get dependencies for every module imported using Import-Module (or ipmo alias)
        #endregion get dependencies for every module, command in question requires

        #TODO hledat i pres promenne ( i v param bloku!)? pokud pouziva takove ktere jsou nekde exportovane...

        #region get dependencies for every used function/cmdlet/alias
        #TODO prikazy s prefixem z naimportovaneho modulu (ziskat explicitne importovane moduly a pouzity prefix)

        # skip internal functions of the module where command in question is defined a.k.a. omit unnecessary warnings about unknown (private) commands
        if ($source) {
            # WARNING: I cannot be sure if I select correct command/module if there are multiple matches!
            #TODO source[-2] by asi mel obsahovat modul, ze ktereho prikaz pochazi, tzn bych ho mohl rovnou pouzit?
            $gcmData = Get-Command $source[-1] -Verbose:$false -ErrorAction SilentlyContinue | select -First 1
            if ($gcmData.Module.ModuleBase) {
                Write-Verbose ("`t`t`t`t" * $indent + "- Getting private functions defined in command's source module '$($gcmData.ModuleName)' to ignore them")
                $modulePrivateFunction = _getModulePrivateFunction -moduleBasePath $gcmData.Module.ModuleBase
                $ignoreCommand += @($modulePrivateFunction)
            }
        }

        Write-Verbose ("`t`t`t`t" * $indent + "- Getting code dependencies for every used COMMAND")
        # list of prefixes added to commands imported from modules
        $importModulePrefix = $importModuleCommandList.Prefix | ? { $_ }
        # get dependencies of every used command
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

            if ($processJustMSGraphSDK -and $cmdName -in "Invoke-RestMethod", "irm", "Invoke-WebRequest", "curl", "iwr", "wget") {
                # HACK
                # these commands are built-in so they would be skipped anyway, because I don't output dependencies for built-in commands (they are built-in == don't have dependencies)
                # but I need to output these commands, so I can analyze them in Get-CodeGraphPermissionRequirement (thats why 'processJustMSGraphSDK' parameter was used)
                # to be more specific, check whether requested URI was Graph API call, and if so, get required permission(s)
                [PSCustomObject]@{
                    Type           = 'Module'
                    Name           = ''
                    Version        = ''
                    RequiredBy     = $cmdCommand
                    DependencyPath = ConvertTo-FlatArray ($source, $cmdName)
                }
                Write-Verbose ("`t`t`t`t`t`t" * $indent + "- HACK: Built-in command, but processJustMSGraphSDK was used. Output before skipping.")
            } elseif ($processJustMSGraphSDK -and !$goDeep -and $cmdName -notlike "*-Mg*" -and $cmdName -ne "Invoke-MsGraphRequest") {
                # skip to speed things up
                Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Not a Graph SDK function nor function that can do direct Graph API calls. Skipping")
            } elseif ($cmdName -in $definedFunction.name) {
                Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Locally defined function. Skipping")
            } elseif ($cmdName -in $ignoreCommand) {
                Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Ignored function. Skipping")
            } elseif ($cmdName -in $global:processedCommands -and $cmdName -notin $processEveryTime) {
                # ignore (but what about same named functions defined in different modules?!)
                Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Already processed. Skipping")
            } else {
                # it is externally defined command, hence should be processed
                # make a note that it was processed
                $global:processedCommands += $cmdName

                # get the command noun
                $cmdNoun = ""
                if ($cmdName -match "-") {
                    $cmdNoun = $cmdName.split("-", 2)[1]
                }

                # get command details
                $cmdData = Get-Command $cmdName -All -Verbose:$false -ErrorAction SilentlyContinue | ? { ($_.ModuleName -or $_.CommandType -eq "Alias") -and $_.Name -EQ $cmdName } # just exact matches (name can contain wildcard) and defined in module

                if ($cmdData.count -gt 1) {
                    #region try to guess the command real source
                    Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Defined in multiple modules. Trying to guess the right one")

                    # try to limit the data just to module of the "source"
                    if ($source) {
                        Write-Verbose ("`t`t`t`t`t`t`t" * $indent + "- Trying 'source' $($source[-1])")

                        $sourceCmdData = $cmdData | ? ModuleName -EQ $source[-1]

                        if ($sourceCmdData) {
                            # limit the command to the source module, but its just guessing!
                            $cmdData = $sourceCmdData
                        } else {
                            # source isn't module probably, try to search it as command instead
                            $sourceCmdData = Get-Command $source[-1] -All -Verbose:$false -ErrorAction SilentlyContinue | ? { ($_.ModuleName -or $_.CommandType -eq "Alias") -and $_.Name -eq $cmdName } # just exact matches (name can contain wildcard) and defined in module
                            if ($sourceCmdData) {
                                $sourceCmdData = $cmdData | ? ModuleName -In $sourceCmdData.ModuleName
                                if ($sourceCmdData) {
                                    # limit the command to the source module (where source command is defined), but its just guessing!
                                    $cmdData = $sourceCmdData
                                }
                            }
                        }
                    }

                    # try to limit the data to the explicitly imported module, but its just guessing!
                    if ($cmdData.count -gt 1 -and $importModuleCommandList) {
                        # if one of the modules from explicitly imported modules matches the command source module, its probably the right one
                        Write-Verbose ("`t`t`t`t`t`t`t" * $indent + "- Trying imported modules")
                        $sourceCmdData = $cmdData | ? ModuleName -In $importModuleCommandList.ImportedModule
                        if ($sourceCmdData) {
                            $cmdData = $sourceCmdData
                        }
                    }

                    # try to limit the data to the module from requires list, but its just guessing!
                    if ($cmdData.count -gt 1 -and $requiresModuleList) {
                        # if one of the modules from requires list matches the command source module, its probably the right one
                        Write-Verbose ("`t`t`t`t`t`t`t" * $indent + "- Trying required modules")
                        $sourceCmdData = $cmdData | ? ModuleName -In $requiresModuleList.Name
                        if ($sourceCmdData) {
                            $cmdData = $sourceCmdData
                        }
                    }
                    #endregion try to guess the command real source

                    if ($cmdData.count -gt 1) {
                        if ($nonInteractive) {
                            Write-Warning "Command '$cmdName' is defined multiple times ($($cmdData.ModuleName -join ', ')). Searching for dependencies in all of them which is 100% not-correct :)"
                        } else {
                            # let the user pick which (if any) modules should be searched for dependencies
                            $cmdData = $cmdData | Out-GridView -Title "Command '$cmdName' was found in multiple modules, select which to use for dependency retrieval" -OutputMode Multiple
                        }
                    }
                }

                #region get command dependencies
                if ($cmdData) {
                    # Get-Command found the command
                    Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Command is available locally")
                    foreach ($data in $cmdData) {
                        # transform alias'es data to the original command's data
                        if ($data.commandType -eq "alias") {
                            Write-Verbose ("`t`t`t`t`t`t" * $indent + "- '$cmdName' is alias for '$($data.ResolvedCommandName)'")
                            $data = Get-Command $data.ResolvedCommandName -Verbose:$false
                        }

                        $cmdSource = $data.source
                        $cmdModule = $data.module # module that contains/defines this command
                        $cmdDefinition = $data.ScriptBlock # command body

                        if ($cmdSource -eq "Microsoft.PowerShell.Core" -or $cmdModule.Name -in $ignoredModule) {
                            # built-in command, ignore
                            Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Skipping. Its built-in command.")
                            continue
                        }

                        if ($cmdModule) {
                            Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Searching for dependencies in the command's source module '$($cmdModule.Name)'")

                            # searching just using name, because I can't say for sure that specific version is needed
                            # because it was found using Get-Command
                            $param = @{
                                moduleName                = $cmdModule.Name
                                indent                    = ($indent + 1)
                                source                    = ($source, $cmdName)
                                command                   = $cmdCommand
                                dontSearchForDependencies = $true
                            }
                            if ($getDependencyOfRequiredModule -contains "scriptSourceModule") {
                                $param.dontSearchForDependencies = $false
                            }

                            _getModuleDependency @param
                        }

                        if ($cmdDefinition -and $goDeep) {
                            Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Searching for dependencies in the command's '$cmdName' body")
                            _getScriptDependency -scriptContent $cmdDefinition.ToString() -indent ($indent + 1) -source ($source, $cmdName)
                        }

                        # if (!$cmdModule -and !$cmdDefinition) {
                        #     Write-Warning "Command $cmdName isn't defined in any module nor its definition was found. Skip getting its dependencies"
                        # }

                        if (!$cmdDefinition -and $goDeep) {
                            Write-Warning "Command's $cmdName definition is missing. Skip getting its dependencies"
                        }
                    }
                } else {
                    # Get-Command didn't find the command, try other options
                    Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Command isn't available locally")
                    #region is it Microsoft Graph SDK command?
                    if ($cmdNoun -cmatch "^Mg[A-Z]") {
                        # it might be Microsoft Graph SDK command
                        Write-Verbose ("`t`t`t`t`t`t`t" * $indent + "- Trying Microsoft Graph SDK")
                        if (Get-Command "Find-MgGraphCommand" -ErrorAction SilentlyContinue) {
                            $cmdData = @(Find-MgGraphCommand -Command $cmdName -ErrorAction SilentlyContinue)
                            $data = $cmdData[0]

                            if ($data) {
                                $cmdModule = "Microsoft.Graph." + $data.module # module that contains/defines this command

                                # Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Searching for dependencies in the command's source module '$cmdModule'")
                                Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Command was found in module '$cmdModule'")
                                if ($goDeep) {
                                    Write-Warning "Command's $cmdName definition is missing. Skip getting its dependencies"
                                }

                                # searching just using name, because I can't say for sure that specific version is needed
                                # because it was found using Find-MgGraphCommand
                                $param = @{
                                    moduleName                = $cmdModule
                                    indent                    = ($indent + 1)
                                    source                    = ($source, $cmdName)
                                    command                   = $cmdCommand
                                    dontSearchForDependencies = $true
                                }
                                if ($getDependencyOfRequiredModule -contains "scriptSourceModule") {
                                    $param.dontSearchForDependencies = $false
                                }

                                _getModuleDependency @param
                            } else {
                                # Find-MgGraphCommand didn't find the command
                                Write-Warning "Unable to find command '$cmdName' (source: $((ConvertTo-FlatArray $source) -join ' >> ')) details using Get-Command (locally) nor Find-MgGraphCommand (in PSGallery)"
                            }
                        } else {
                            Write-Warning "Unable to find command '$cmdName' (source: $((ConvertTo-FlatArray $source) -join ' >> ')) details using Get-Command. Because of 'Mg' prefix, it might be some Microsoft Graph SDK command, but Find-MgGraphCommand is missing to test it (get it by installing 'Microsoft.Graph.Authentication' module)"
                        }
                    }
                    #endregion is it Microsoft Graph SDK command?

                    #region is it in PSGallery?
                    if (!$cmdData) {
                        # it wasn't Graph SDK command either, trying to find it in registered repositories (PSGallery)
                        if ($dontSearchCommandInPSGallery) {
                            Write-Warning "Unable to find command '$cmdName' (source: $((ConvertTo-FlatArray $source) -join ' >> ')) details. Skip getting its dependencies"
                            if ($unknownDependencyAsObject) {
                                [PSCustomObject]@{
                                    Type           = 'Module'
                                    Name           = ''
                                    Version        = ''
                                    RequiredBy     = $cmdName
                                    DependencyPath = ConvertTo-FlatArray $source
                                }
                            }
                        } else {
                            Write-Verbose ("`t`t`t`t`t`t`t" * $indent + "- Trying PSGallery")
                            if (Get-PackageProvider | ? Name -EQ "NuGet") {
                                $cmdData = Find-Command -Name $cmdName
                            } else {
                                Write-Warning ("`t`t`t`t`t" * $indent + "- PSGallery cannot be used to search for '$cmdName' command. NuGet is missing. Use 'installNuget' parameter to solve this.")
                            }

                            if ($cmdData) {
                                if ($cmdData.count -gt 1) {
                                    #region try to guess the command real source
                                    Write-Verbose ("`t`t`t`t`t`t`t" * $indent + "- Defined in multiple modules. Trying to guess the right one")
                                    # try to limit the data to the explicitly imported module, but its just guessing!
                                    if ($cmdData.count -gt 1 -and $importModuleCommandList) {
                                        # if one of the modules from explicitly imported modules matches the command source module, its probably the right one
                                        Write-Verbose ("`t`t`t`t`t`t`t" * $indent + "- Trying imported modules")
                                        $sourceCmdData = $cmdData | ? ModuleName -In $importModuleCommandList.ImportedModule
                                        if ($sourceCmdData) {
                                            $cmdData = $sourceCmdData
                                        }
                                    }

                                    # try to limit the data to the module from requires list, but its just guessing!
                                    if ($cmdData.count -gt 1 -and $requiresModuleList) {
                                        # if one of the modules from requires list matches the command source module, its probably the right one
                                        Write-Verbose ("`t`t`t`t`t`t`t" * $indent + "- Trying required modules")
                                        $sourceCmdData = $cmdData | ? ModuleName -In $requiresModuleList.Name
                                        if ($sourceCmdData) {
                                            $cmdData = $sourceCmdData
                                        }
                                    }
                                    #endregion try to guess the command real source

                                    if ($cmdData.count -gt 1) {
                                        if ($nonInteractive) {
                                            Write-Warning "Found multiple modules ($($cmdData.ModuleName -join ', ')) in PSGallery that contains command '$cmdName'. Searching for dependencies in all of them which is 100% not-correct :)"
                                        } else {
                                            # let the user pick which (if any) modules should be searched for dependencies
                                            $cmdData = $cmdData | Out-GridView -Title "Command '$cmdName' was found in multiple modules in PSGallery, select which to use for dependency retrieval" -OutputMode Multiple
                                        }
                                    }
                                }

                                foreach ($data in $cmdData) {
                                    $cmdModule = $data.ModuleName

                                    # Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Searching for dependencies in the command's PSGallery source module '$cmdModule'")
                                    Write-Verbose ("`t`t`t`t`t`t" * $indent + "- Command was found in PSGallery module '$cmdModule'")
                                    if ($goDeep) {
                                        Write-Warning "Command's $cmdName definition is missing. Skip getting its dependencies"
                                    }

                                    # searching just using name, because I can't say for sure that specific version is needed
                                    # because it was found using Find-Command
                                    #TODO novy atribut, ktery rekne, ze jen hadam?
                                    $param = @{
                                        moduleName                = $cmdModule
                                        indent                    = ($indent + 1)
                                        source                    = ($source, $cmdName)
                                        command                   = $cmdCommand
                                        dontSearchForDependencies = $true
                                    }
                                    if ($getDependencyOfRequiredModule -contains "scriptSourceModule") {
                                        $param.dontSearchForDependencies = $false
                                    }

                                    _getModuleDependency @param
                                }
                            } else {
                                Write-Warning "Unable to find command '$cmdName' (source: $((ConvertTo-FlatArray $source) -join ' >> ')) details using Get-Command (locally) nor Find-Command (in PSGallery). Skip getting its dependencies"

                                if ($unknownDependencyAsObject) {
                                    [PSCustomObject]@{
                                        Type           = 'Module'
                                        Name           = ''
                                        Version        = ''
                                        RequiredBy     = $cmdName
                                        DependencyPath = ConvertTo-FlatArray $source
                                    }
                                }
                            }
                        }
                    }
                    #endregion is it in PSGallery?
                }
                #endregion get command dependencies
            }
        }
        #endregion get dependencies for every used function/cmdlet/alias

        #region output various requirements from requires statement
        #TODO output other requirements too
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
                    Type           = 'Requirement'
                    Name           = 'ElevationIsRequired'
                    Version        = $null # jen abych vracel stejny objekt jako u ostatnich requirementu
                    RequiredBy     = "<requires statement>"
                    DependencyPath = ConvertTo-FlatArray $source
                }
            }
        }
        #endregion output various requirements from requires statement
    } # end of _getScriptDependency function
    #endregion helper functions

    #region start searching for dependencies
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

        _getScriptDependency @param
    } elseif ($moduleName) {
        # get module dependencies
        $param = @{
            dontOutputTheModuleItself = $true
            moduleName                = $moduleName
            source                    = $moduleName
        }
        if ($moduleVersion) { $param.moduleVersion = $moduleVersion }

        _getModuleDependency @param
    } elseif ($moduleBasePath) {
        # get module dependencies (by module path)
        $param = @{
            dontOutputTheModuleItself = $true
            module                    = (Get-Module -FullyQualifiedName $moduleBasePath -ListAvailable -ErrorAction Stop)
            source                    = $moduleBasePath
        }

        _getModuleDependency @param
    } else {
        throw "undefined option"
    }
    #endregion start searching for dependencies

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

    .PARAMETER allOccurrences
    Switch to output even all problems including duplicities. For example one missing module can be used by several commands, so with this switch used, warning about such module will be outputted for each command.

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

        [switch] $asObject,

        [switch] $allOccurrences
    )

    #region get dependencies
    $param = @{
        noRecursion                      = $true
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

    $usedModule = $dependency | ? { $_.Type -EQ "Module" -and $_.DependencyPath -NE $scriptPath }

    $explicitlyImportedModule = $dependency | ? { $_.Type -EQ "Module" -and $_.RequiredBy -Match "^(Import-Module|ipmo) " }

    if ($scriptPath) {
        $explicitlyRequiredModule = $dependency | ? { $_.Type -EQ "Module" -and $_.RequiredBy -EQ "<requires statement>" }
    } else {
        $explicitlyRequiredModule = $dependency | ? { $_.Type -EQ "Module" -and $_.RequiredBy -EQ "<module manifest>" }
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
        $processedModule = @()

        foreach ($module in $usedModule) {
            $mName = $module.Name

            if (!$allOccurrences -and $mName -in $processedModule) { continue }

            if ($mName -in $explicitlyImportedModule.Name -and $mName -notin $explicitlyRequiredModule.Name) {
                $msg = "Module '$mName' is explicitly imported, but not required $suffixTxt. Reason: '$($module.RequiredBy)'"
                $problem = "ModuleImportedButMissingRequirement"
            } elseif ($mName -notin $explicitlyImportedModule.Name -and $mName -notin $explicitlyRequiredModule.Name) {
                $msg = "Module '$mName' is used, but not required $suffixTxt. Reason: '$($module.RequiredBy)'"
                $problem = "ModuleUsedButMissingRequirement"
            } else {
                # module is required, no action needed
                continue
            }

            if ($asObject) {
                [PSCustomObject]@{
                    Module  = $mName
                    Problem = $problem
                    Message = $msg
                }
            } else {
                Write-Warning $msg
            }

            $processedModule += $mName
        }
    }
    #endregion missing explicit module requirement

    #region version mismatch
    if ($usedModule) {
        $processedModule = @{}

        foreach ($module in $usedModule) {
            $mName = $module.Name
            $mVersion = $module.Version
            $explicitlyRequiredModuleVersion = ($explicitlyRequiredModule | ? name -EQ $mName).version

            if ($mVersion -and $mVersion -notin $explicitlyRequiredModuleVersion) {
                if (!$allOccurrences -and $mVersion -eq $processedModule.$mName) { continue }

                $msg = "Module '$mName' (thanks to command: '$($module.RequiredBy)') that is used, has different version ($mVersion) then explicitly required one ($($explicitlyRequiredModuleVersion -join ', ')) $suffixTxt"

                if ($asObject) {
                    [PSCustomObject]@{
                        Module  = $mName
                        Problem = "ModuleVersionConflict"
                        Message = $msg
                    }
                } else {
                    Write-Warning $msg
                }

                $processedModule.$mName = $mVersion
            }
        }
    }

    if ($explicitlyImportedModule) {
        $processedModule = @{}

        foreach ($module in $explicitlyImportedModule) {
            $mName = $module.Name
            $mVersion = $module.Version
            $explicitlyRequiredModuleVersion = ($explicitlyRequiredModule | ? name -EQ $mName).version

            if ($mVersion -and $mVersion -notin $explicitlyRequiredModuleVersion) {
                if (!$allOccurrences -and $mVersion -eq $processedModule.$mName) { continue }

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

                $processedModule.$mName = $mVersion
            }
        }
    }
    #endregion version mismatch

    #region unnecessary module requirement
    if ($explicitlyImportedModule) {
        $processedModule = @()

        foreach ($module in $explicitlyImportedModule) {
            $mName = $module.Name

            if (!$allOccurrences -and $mName -in $processedModule) { continue }

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

                $processedModule += $mName
            }
        }
    }

    if ($explicitlyRequiredModule) {
        $processedModule = @()

        foreach ($module in $explicitlyRequiredModule) {
            $mName = $module.Name

            if (!$allOccurrences -and $mName -in $processedModule) { continue }

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

                $processedModule += $mName
            }
        }
    }
    #endregion unnecessary module requirement
}

function Get-CorrespondingGraphCommand {
    <#
    .SYNOPSIS
    Function finds corresponding Graph command for MSOnline and AzureAD commands.

    .DESCRIPTION
    Function finds corresponding Graph command for MSOnline and AzureAD commands.

    .PARAMETER commandName
    MSOnline or AzureAD command name.

    .EXAMPLE
    Get-CorrespondingGraphCommand Get-MsolUser

    Finds corresponding Graph command for Get-MsolUser command. A.k.a. Get-MgUser.

    .EXAMPLE
    $scripts = Get-ChildItem C:\scripts -Recurse -Filter "*.ps1" -file | ? name -Match "\.ps1$" | select -exp FullName

    $moduleList = @()
    "AzureAD", "AzureADPreview", "MSOnline", "AzureRM" | % {
        $module = Get-Module $_ -ListAvailable
        if ($module) {
            $moduleList += $module
        } else {
            Write-Warning "Module $_ isn't available on you system. Add it to `$env:PSModulePath or install using Install-Module?"
        }
    }

    $scripts | % {
        Get-ModuleCommandUsedInCode -scriptPath $_ -module $moduleList | Select-Object *, @{n = 'GraphCommand'; e = { (Get-CorrespondingGraphCommand $_.command).GraphCommand } } | Format-Table -AutoSize
    }

    Search all ps1 scripts in C:\scripts folder for commands defined in modules "AzureAD", "AzureADPreview", "MSOnline", "AzureRM". Show where they are used and if possible also equivalent Graph command.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $commandName
    )

    $cacheFile = "$env:TEMP\graphcommandmap.xml"

    if ((Test-Path $cacheFile -ea SilentlyContinue) -and ((Get-Item $cacheFile).LastWriteTime -gt [datetime]::Today.AddDays(-30))) {
        Write-Verbose "Using $cacheFile"
        $table = Import-Clixml $cacheFile
    } else {
        Write-Verbose "Getting command map"
        $uri = "https://learn.microsoft.com/en-au/powershell/microsoftgraph/azuread-msoline-cmdlet-map?view=graph-powershell-beta"
        $pageContent = (Invoke-WebRequest -Method GET -Uri $uri -UseBasicParsing).content
        $table = ConvertFrom-HTMLTable $pageContent -useHTMLAgilityPack -asArrayOfTables -all
        $table | Export-Clixml $cacheFile -Force
    }

    $table | % { $_ | select @{n = "Command"; e = { if ($_."Azure AD cmdlet") { $_."Azure AD cmdlet" } elseif ($_."MSOnline cmdlet") { $_."MSOnline cmdlet" } else { $_."Azure AD Preview cmdlet" } } }, @{n = "GraphCommand"; e = { $_."Microsoft Graph PowerShell cmdlet" } } } | select *, @{n = 'Note'; e = { if ($_.Command -like "* 1") { "This cmdlet has more than one cmdlet mapping in Microsoft Graph PowerShell" } elseif ($_.Command -like "* 2") { "Privileged Identity Management (PIM) iteration 3 APIs (https://learn.microsoft.com/en-us/graph/api/resources/privilegedidentitymanagementv3-overview?view=graph-rest-1.0) should be used. Check this guidance (https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-apis) for more details." } } } | select @{n = "Command"; e = { $_.Command -replace " \d+$" } }, GraphCommand, Note | ? Command -EQ $commandName
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

    .PARAMETER source
    "Path" to provided AST that will be shown as a source instead of AST file path property.
    Used by Get-CodeDependency.

    .EXAMPLE
    $AST = [System.Management.Automation.Language.Parser]::ParseFile("C:\script.ps1", [ref] $null, [ref] $null)

    Get-ImportModuleFromAST -AST $AST
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.Ast] $AST,

        [array] $source
    )

    $usedCommand = $AST.FindAll( { $args[0] -is [System.Management.Automation.Language.CommandAst ] }, $true)

    if (!$usedCommand) {
        Write-Verbose "No command detected in given AST"
        return
    }

    #region functions
    function ConvertTo-FlatArray {
        # flattens input in case, that string and arrays are entered at the same time
        param (
            [array] $inputArray
        )

        foreach ($item in $inputArray) {
            if ($item -ne $null) {
                # recurse for arrays
                if ($item.gettype().BaseType -eq [System.Array]) {
                    ConvertTo-FlatArray $item
                } else {
                    # output non-arrays
                    $item
                }
            }
        }
    }

    function _source {
        if ($source) {
            "(source: $((ConvertTo-FlatArray $source) -join ' >> '))"
        } else {
            if ($importModuleCommand.extent.File) {
                "(source: $($importModuleCommand.extent.File))"
            }
        }
    }
    #endregion functions

    $importModuleCommandList = $usedCommand | ? { $_.CommandElements[0].Value -in "Import-Module", "ipmo" }

    if (!$importModuleCommandList) {
        Write-Verbose "No 'Import-Module' or its alias 'ipmo' detected"
        return
    }

    foreach ($importModuleCommand in $importModuleCommandList) {
        $importModuleCommandElement = $importModuleCommand.CommandElements
        $importModuleCommandElement = $importModuleCommandElement | select -Skip 1 # skip Import-Module command itself

        Write-Verbose "Getting Import-Module parameters from: '$($importModuleCommand.extent.text)' $(_source)"

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
            Write-Warning "Unable to detect module imported through command: '$($importModuleCommand.extent.text)' $(_source)"

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

function Get-ModuleCommandUsedInCode {
    <#
    .SYNOPSIS
    Function for getting commands (defined in given module) that are used in given script.

    .DESCRIPTION
    Function for getting commands (defined in given module) that are used in given script.

    .PARAMETER scriptPath
    Path to the ps1 script that should be searched for used commands.

    .PARAMETER module
    Module(s) object whose commands/aliases will be searched in given script.

    Should be retrieved using Get-Module command a.k.a. has to exist on local system!

    .EXAMPLE
    $module = Get-Module MSOnline -ListAvailable | select -last 1

    Get-ModuleCommandUsedInCode -scriptPath "C:\repo\AzureAD_monitoring\AzureAD_user_APS.ps1" -module $module

    Get all commands used in "AzureAD_user_APS.ps1" script that are defined in the module MSOnline.

    .EXAMPLE
    $scripts = Get-ChildItem C:\scripts -Recurse -Filter "*.ps1" -file | ? name -Match "\.ps1$" | select -exp FullName

    $moduleList = @()
    "AzureAD", "AzureADPreview", "MSOnline", "AzureRM" | % {
        $module = Get-Module $_ -ListAvailable
        if ($module) {
            $moduleList += $module
        } else {
            Write-Warning "Module $_ isn't available on you system. Add it to `$env:PSModulePath or install using Install-Module?"
        }
    }

    $scripts | % {
        Get-ModuleCommandUsedInCode -scriptPath $_ -module $moduleList
    }

    Search all ps1 scripts in C:\scripts folder for commands defined in modules "AzureAD", "AzureADPreview", "MSOnline", "AzureRM".
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript( {
                if ((Test-Path -Path $_ -PathType leaf) -and $_ -match "\.ps1$") {
                    $true
                } else {
                    throw "$_ is not a ps1 file or it doesn't exist"
                }
            })]
        [string] $scriptPath,

        [Parameter(Mandatory = $true)]
        [PSModuleInfo[]] $module
    )

    #TODO if module has default prefix, add it to each exported commands
    # $modulePrefix = $module.Prefix

    #region get commands & aliases defined in the module
    # hash with where keys are function names defined in given module(s) and value is name of module where it is defined
    $definedCommand = @{}

    # fill the $definedCommand hash
    $module | % {
        $moduleObj = $_
        $moduleObj.ExportedCommands.keys | % { $definedCommand.$_ = $moduleObj.Name }
        $moduleObj.ExportedAliases.keys | % { $definedCommand.$_ = $moduleObj.Name }

        if (($moduleObj.ExportedCommands.keys).count -eq 0 -and ($moduleObj.ExportedAliases.keys).count -eq 0) {
            Write-Warning "Module $($_.Name) doesn't contain any commands"
        }
    }
    #endregion get commands & aliases defined in the module

    #region get commands & aliases used in the script
    $AST = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $scriptPath), [ref] $null, [ref] $null)

    $usedCommand = $AST.FindAll( { $args[0] -is [System.Management.Automation.Language.CommandAst ] }, $true)

    if (!$usedCommand) {
        Write-Warning "Script '$scriptPath' doesn't contain any commands"
        return
    }
    #endregion get commands & aliases used in the script

    #region output the results
    [System.Collections.ArrayList] $result = @()

    $usedCommand | % {
        $commandName = $_.CommandElements[0].Value
        $commandLine = $_.Extent.StartLineNumber
        if ($commandName -in $definedCommand.Keys) {
            $null = $result.add([PSCustomObject]@{
                    Command = $commandName
                    Line    = $commandLine
                    Module  = $definedCommand.$commandName
                    Script  = $scriptPath
                })
        }
    }

    $result | Sort-Object -Property Command
    #endregion output the results
}

Export-ModuleMember -function Get-AddPSSnapinFromAST, Get-CodeDependency, Get-CodeDependencyStatus, Get-CorrespondingGraphCommand, Get-ImportModuleFromAST, Get-ModuleCommandUsedInCode

Export-ModuleMember -alias Get-Dependency, Get-PSHCodeDependency
