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