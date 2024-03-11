function Get-CodeGraphModuleDependency {
    <#
    .SYNOPSIS
    Function for getting Graph SDK modules required to run given code.

    .DESCRIPTION
    Function for getting Graph SDK modules required to run given code.
    It extracts all Graph commands using 'Get-CodeDependency' function (DependencySearch module).
    Modules that hosts found commands are retrieved using official 'Find-MgGraphCommand' command then.

    .PARAMETER scriptPath
    Path to ps1 script that should be analyzed.

    .PARAMETER availableModules
    To speed up repeated function invocations, save all available modules into variable and use it as value for this parameter.

    By default this function caches all locally available modules before each run which can take several seconds.

    .PARAMETER allOccurrences
    Switch to return all found Mg* commands and not just the first one for each PowerShell SDK module.

    .PARAMETER goDeep
    Switch to check for direct dependencies not just in the given code, but even indirect ones in its dependencies (recursively) == gets the whole dependency tree.

    By default ONLY the code in the 'scriptPath' is analyzed, but not the called commands/modules definitions!

    .EXAMPLE
    # cache available modules to speed up repeated 'Get-CodeGraphModuleDependency' function invocations
    $availableModules = @(Get-Module -ListAvailable)

    Get-CodeGraphModuleDependency -scriptPath C:\scripts\someGraphRelatedCode.ps1 -availableModules $availableModules

    Returns Graph SDK modules required by selected code.
    In case there are some indirect dependencies (like there is a function that has some Graph module dependency in its code), they won't be returned!

    .EXAMPLE
    Get-CodeGraphModuleDependency -scriptPath C:\scripts\someGraphRelatedCode.ps1 -goDeep

    Returns ALL Graph SDK modules required to run selected code (direct and indirect).

    .NOTES
    Requires module 'Microsoft.Graph.Authentication' because of 'Find-MgGraphCommand' command.
    #>

    [CmdletBinding()]
    [Alias("Get-GraphAPICodeModuleDependency")]
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

        [System.Collections.ArrayList] $availableModules = @(),

        [switch] $allOccurrences,

        [switch] $goDeep
    )

    if (!(Get-Command "Find-MgGraphCommand" -ErrorAction SilentlyContinue)) {
        throw "'Find-MgGraphCommand' command is missing. Install 'Microsoft.Graph.Authentication' module and run again"
    }

    if (!(Get-Command "Get-CodeDependency" -ErrorAction SilentlyContinue)) {
        throw "'Get-CodeDependency' command is missing. Install 'DependencyStuff' module and run again"
    }

    $param = @{
        scriptPath                   = $scriptPath
        processJustMSGraphSDK        = $true
        dontSearchCommandInPSGallery = $true
    }
    if ($availableModules) {
        $param.availableModules = $availableModules
    }
    if ($goDeep) {
        $param.goDeep = $true
    }
    if ($allOccurrences) {
        $param.allOccurrences = $true
    }
    if ($PSBoundParameters.Verbose) {
        $param.Verbose = $true
    }

    Get-CodeDependency @param | ? { $_.Type -eq "Module" -and $_.Name -like "Microsoft.Graph.*" }
}