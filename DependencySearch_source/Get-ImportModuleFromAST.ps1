#TODO muze importovat i pres ModuleInfo (module objekt)
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