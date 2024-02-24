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

    #TODO podpora URI skrze invoke-webrequest (curl, iwr, wget), Invoke-MsGraphRequest, invoke-restmethod (irm)
    # commands that can be used to directly call Graph API
    $webCommandList = "Invoke-MgGraphRequest", "Invoke-MsGraphRequest", "Invoke-RestMethod", "irm", "Invoke-WebRequest", "curl", "iwr", "wget"

    $param = @{
        scriptPath                   = $scriptPath
        processJustMSGraphSDK        = $true
        allOccurrences               = $true
        dontSearchCommandInPSGallery = $true
        processEveryTime             = $webCommandList
    }
    if ($availableModules) {
        $param.availableModules = $availableModules
    }
    if ($goDeep) {
        $param.goDeep = $true
    }

    $usedGraphCommand = Get-CodeDependency @param | ? { ($_.Type -eq "Module" -and $_.Name -like "Microsoft.Graph.*") -or $_.DependencyPath[-1] -in $webCommandList }

    $processedGraphCommand = @()


    if ($usedGraphCommand) {
        foreach ($mgCommandData in $usedGraphCommand) {
            $mgCommand = $mgCommandData.DependencyPath[-1]
            $dependencyPath = $mgCommandData.DependencyPath
            $invocationText = $mgCommandData.RequiredBy

            Write-Verbose "Processing: $invocationText"

            if ($mgCommand -eq "Connect-MgGraph") {
                # no permission needed
                continue
            }

            if ($mgCommand -in $processedGraphCommand) {
                continue
            }

            if ($mgCommand -in $webCommandList) {
                # some web command

                $uri = $invocationText -split " " | ? { $_ -like "*graph.microsoft.com*" -or $_ -like "*v1.0*" -or $_ -Like "*beta*" }
                if (!$uri) {
                    Write-Warning "Unable to obtain URI from '$invocationText' or it is not a Graph URI. Skipping."
                    if ($invocationText -like "Invoke-MgGraphRequest *" -or $invocationText -like "Invoke-MsGraphRequest *") {
                        # Invoke-MgGraphRequest and Invoke-MsGraphRequest commands for sure uses Graph Api, hence output empty object to highlight I was unable to extract it
                        '' | select @{n = 'Command'; e = { $mgCommand } }, Name, Description, FullDescription, @{n = 'Type'; e = { $permType } }, @{n = 'InvokedAs'; e = { $invocationText } }, @{n = 'DependencyPath'; e = { $dependencyPath } }
                    }
                    continue
                } else {
                    # standardize found URI

                    # get rid of quotes
                    $uri = $uri -replace "`"|'"
                    # get rid of filter section
                    $uri = ($uri -split "\?")[0]
                    # replace variables for {id} placeholder
                    $uri = $uri -replace "\$[^/]+", "{id}"
                }

                $method = $invocationText -split " " | ? { $_ -in "GET", "POST", "PUT", "PATCH", "DELETE" }
                if (!$method) {
                    # select the default method
                    $method = "GET"
                }

                if ($uri -like "*beta*") {
                    $apiVersion = "beta"
                } else {
                    $apiVersion = "v1.0"
                }

                try {
                    Write-Verbose "Get permissions for URI: '$uri', Method: $method, ApiVersion: $apiVersion"
                    $mgCommandPerm = Find-MgGraphCommand -Uri $uri -Method $method -ApiVersion $apiVersion -ErrorAction Stop | ? Permissions | select -First 1 -ExpandProperty Permissions

                    if (!$mgCommandPerm) {
                        # try again with shorter uri (higher chance it will find some permission)
                        $uriSplitted = $uri.split("/")
                        $uri = $uriSplitted[0..($uriSplitted.count - 2)] -join "/"
                        $mgCommandPerm = Find-MgGraphCommand -Uri $uri -Method $method -ApiVersion $apiVersion -ErrorAction Stop | ? Permissions | select -First 1 -ExpandProperty Permissions
                    }
                } catch {
                    Write-Warning "'Find-MgGraphCommand' was unable to find permissions for URI: '$uri', Method: $method, ApiVersion: $apiVersion"
                    continue
                }

                if ($mgCommandPerm) {
                    if ($permType -eq "application") {
                        $mgCommandPerm = $mgCommandPerm | ? IsAdmin -EQ $true
                    } else {
                        $mgCommandPerm = $mgCommandPerm | ? IsAdmin -EQ $false
                    }

                    if ($mgCommandPerm) {
                        $mgCommandPerm | select @{n = 'Command'; e = { $mgCommand } }, Name, Description, FullDescription, @{n = 'Type'; e = { $permType } }, @{n = 'InvokedAs'; e = { $invocationText } }, @{n = 'DependencyPath'; e = { $dependencyPath } }
                    } else {
                        Write-Warning "$mgCommand requires some permissions, but not of '$permType' type"
                    }
                } else {
                    Write-Verbose "'$invocationText' doesn't need any permissions?!"
                    '' | select @{n = 'Command'; e = { $mgCommand } }, Name, Description, FullDescription, @{n = 'Type'; e = { $permType } }, @{n = 'InvokedAs'; e = { $invocationText } }, @{n = 'DependencyPath'; e = { $dependencyPath } }
                }
            } else {
                # built-in graph sdk command
                $processedGraphCommand += $mgCommand

                try {
                    $mgCommandPerm = Find-MgGraphCommand -Command $mgCommand -ErrorAction Stop | ? Permissions | select -First 1 -ExpandProperty Permissions
                } catch {
                    Write-Warning "'Find-MgGraphCommand' was unable to find command '$mgCommand'?!"
                    continue
                }

                if ($mgCommandPerm) {
                    if ($permType -eq "application") {
                        $mgCommandPerm = $mgCommandPerm | ? IsAdmin -EQ $true
                    } else {
                        $mgCommandPerm = $mgCommandPerm | ? IsAdmin -EQ $false
                    }

                    if ($mgCommandPerm) {
                        $mgCommandPerm | select @{n = 'Command'; e = { $mgCommand } }, Name, Description, FullDescription, @{n = 'Type'; e = { $permType } }, @{n = 'InvokedAs'; e = { $invocationText } }, @{n = 'DependencyPath'; e = { $dependencyPath } }
                    } else {
                        Write-Warning "$mgCommand requires some permissions, but not of '$permType' type"
                    }
                } else {
                    Write-Verbose "$mgCommand doesn't need any permissions?!"
                    '' | select @{n = 'Command'; e = { $mgCommand } }, Name, Description, FullDescription, @{n = 'Type'; e = { $permType } }, @{n = 'InvokedAs'; e = { $invocationText } }, @{n = 'DependencyPath'; e = { $dependencyPath } }
                }
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