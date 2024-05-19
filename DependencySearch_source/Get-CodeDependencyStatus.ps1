#TODO add checks for pssnapins etc
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

    .PARAMETER dependencyParam
    Hashtable with parameters that will be passed to Get-CodeDependency function.

    By default:
    @{
        checkModuleFunctionsDependencies = $false
        dontSearchCommandInPSGallery     = $true
    }

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

        [switch] $allOccurrences,

        [hashtable] $dependencyParam = @{
            allOccurrences                   = $true
            checkModuleFunctionsDependencies = $false
            dontSearchCommandInPSGallery     = $true
        }
    )

    #region get dependencies
    $param = $dependencyParam
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

    if ($scriptPath) {
        # script check
        $source = $scriptPath
    } elseif ($moduleName) {
        # module check
        $source = $moduleName
    } elseif ($moduleBasePath) {
        $source = $moduleBasePath
    } else {
        throw "undefined option"
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
                    Source  = $source
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
                        Source  = $source
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
                        Source  = $source
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
                        Source  = $source
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
                        Source  = $source
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