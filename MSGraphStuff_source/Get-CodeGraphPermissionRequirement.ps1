function Get-CodeGraphPermissionRequirement {
    <#
    .SYNOPSIS
    Function for analyzing required Graph API permissions that are needed tu run selected code.

    .DESCRIPTION
    Function for analyzing required Graph API permissions that are needed tu run selected code.
    All Graph (Mg*) commands are retrieved using custom 'Get-CodeDependency' function and their permissions are retrieved using official 'Find-MgGraphCommand' command.

    .PARAMETER scriptPath
    Path to ps1 script that should be analyzed.

    .PARAMETER permType
    What type of permissions you want to retrieve.

    Possible values: application, delegated.

    By default 'application'.

    .PARAMETER availableModules
    To speed up repeated function invocations, save all available modules into variable and use it as value for this parameter.

    By default this function caches all locally available modules before each run which can take several seconds.

    .PARAMETER goDeep
    Switch to check for dependencies not just in the given code, but even in its dependencies (recursively). A.k.a. get the whole dependency tree.

    .EXAMPLE
    $availableModules = @(Get-Module -ListAvailable)
    Get-CodeGraphPermissionRequirement -scriptPath C:\temp\SensitiveAppBlock.ps1 -availableModules $availableModules | ogv
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

        [ValidateSet('application', 'delegated')]
        [string] $permType = "application",

        [System.Collections.ArrayList] $availableModules = @(),

        [switch] $goDeep
    )

    if (!(Get-Command "Find-MgGraphCommand" -ErrorAction SilentlyContinue)) {
        throw "'Find-MgGraphCommand' command is missing. Install 'Microsoft.Graph.Authentication' module and run again"
    }

    $param = @{
        scriptPath                   = $scriptPath
        processJustMSGraphSDK        = $true
        allOccurrences               = $true
        dontSearchCommandInPSGallery = $true
    }
    if ($availableModules) {
        $param.availableModules = $availableModules
    }
    if ($goDeep) {
        $param.goDeep = $true
    }

    $processedGraphCommand = @()

    $usedGraphCommand = Get-CodeDependency @param | ? { $_.Type -eq "Module" -and $_.Name -like "Microsoft.Graph.*" }

    if ($usedGraphCommand) {
        foreach ($mgCommandData in $usedGraphCommand) {
            $mgCommand = $mgCommandData.DependencyPath[-1]
            $dependencyPath = $mgCommandData.DependencyPath

            if ($mgCommand -in "Connect-MgGraph", "Invoke-MgGraphRequest") {
                continue
            }

            if ($mgCommand -in $processedGraphCommand) {
                continue
            }

            $processedGraphCommand += $mgCommand

            try {
                $mgCommandPerm = Find-MgGraphCommand -Command $mgCommand -ErrorAction Stop | ? Permissions | select -First 1 -ExpandProperty Permissions
            } catch {
                Write-Warning "'Find-MgGraphCommand' was unable to find command '$mgCommand'?!"
            }

            if ($mgCommandPerm) {
                if ($permType -eq "application") {
                    $mgCommandPerm = $mgCommandPerm | ? IsAdmin -EQ $true
                } else {
                    $mgCommandPerm = $mgCommandPerm | ? IsAdmin -EQ $false
                }

                if ($mgCommandPerm) {
                    $mgCommandPerm | select @{n = 'Command'; e = { $mgCommand } }, Name, Description, FullDescription, @{n = 'Type'; e = { $permType } }, @{n = 'DependencyPath'; e = { $dependencyPath } }
                } else {
                    Write-Warning "$mgCommand requires some permissions, but not of '$permType' type"
                }
            } else {
                Write-Verbose "$mgCommand doesn't need any permissions?!"
                '' | select @{n = 'Command'; e = { $mgCommand } }, Name, Description, FullDescription, @{n = 'Type'; e = { $permType } }, @{n = 'DependencyPath'; e = { $dependencyPath } }
            }
        }

        Write-Warning "Be noted that it is impossible to tell whether found permissions for some command are all required, or just some subset of them (for least-privileged access). Consult the Microsoft Graph Permissions Reference documentation to identify the least-privileged permission for your use case :("
    } else {
        if ($goDeep) {
            Write-Warning "No Graph commands were found in '$scriptPath' or it's dependency tree"
        } else {
            Write-Warning "No Graph commands were found in '$scriptPath'"
        }
    }
}