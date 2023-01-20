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