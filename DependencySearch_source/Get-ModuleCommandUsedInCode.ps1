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