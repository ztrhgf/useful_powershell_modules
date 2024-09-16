function Get-CodeGraphPermissionRequirement {
    <#
    .SYNOPSIS
    Function for getting Graph API permissions (scopes) that are needed to run selected code.

    Official Graph SDK commands AND direct Graph API calls are both processed :)

    .DESCRIPTION
    Function for getting Graph API permissions (scopes) that are needed to run selected code.

    All official Graph SDK commands (*-Mg*) AND commands making direct Graph API calls (Invoke-MsGraphRequest, Invoke-RestMethod, Invoke-WebRequest and their aliases) are extracted using 'Get-CodeDependency' function (DependencySearch module).
    Permissions required to use these commands are retrieved using official 'Find-MgGraphCommand' command then.

    By default not all found permissions are returned, but just filtered subset, to make the output more readable and support principle of least privilege. Check parameter 'dontFilterPermissions' help for more details.

    .PARAMETER scriptPath
    Path to ps1 script that should be analyzed.

    .PARAMETER permType
    What type of permissions you want to retrieve.

    Possible values: Application, DelegatedWork, DelegatedPersonal.

    By default 'Application'.

    .PARAMETER availableModules
    To speed up repeated function invocations, save all available modules into variable and use it as value for this parameter.

    By default this function caches all locally available modules before each run which can take several seconds.

    .PARAMETER goDeep
    Switch to check for dependencies not just in the given code, but even in its dependencies (recursively). A.k.a. get the whole dependency tree.

    .PARAMETER dontFilterPermissions
    Switch to output all found permissions a.k.a. not to make any filtering.

    Otherwise just privileges marked as IsLeastPrivilege (if found) are returned or the ones guessed as the least ones (filtered by following internal logic).
    - if it is READ command (GET)
        - READWRITE permissions that have corresponding READ permission are ignored
        - directory.* permissions are ignored if any other permission is in place
    - if it is MODIFYING command (POST, PUT, PATCH, DELETE)
        - READ permissions that have corresponding READWRITE permission are ignored
        - directory.* permissions are ignored if any other permission is in place

    Beware that to read some sensitive data (like encrypted OMA Settings), you really need ReadWrite permission (because of security reasons)! In such cases, you need to select the 'dontFilterPermissions' parameter.

    .EXAMPLE
    Get-CodeGraphPermissionRequirement -scriptPath C:\scripts\someGraphRelatedCode.ps1 | Out-GridView

    Returns Graph permissions of 'Application' type required by selected script.
    In case there are some indirect dependencies (like there is used some external function that has some inner Graph calls in its code), they won't be analyzed/returned!
    Result will be showed in Out-GridView graphical window.

    .EXAMPLE
    # cache available modules to speed up repeated 'Get-CodeGraphPermissionRequirement' function invocations
    $availableModules = @(Get-Module -ListAvailable)

    Get-CodeGraphPermissionRequirement -scriptPath C:\scripts\someGraphRelatedCode.ps1 -goDeep -availableModules $availableModules -dontFilterPermissions | Out-GridView

    Returns ALL 'Application' type Graph permissions required to run selected code (direct and indirect).

    .NOTES
    Requires module 'Microsoft.Graph.Authentication' (at least version 2.18.0), because of 'Find-MgGraphCommand' command.

    Be noted that it is impossible to tell whether found permissions for some command are all required, or just some subset of them (for least-privileged access). Consult the Microsoft Graph Permissions Reference documentation to identify the least-privileged permission for your use case :(

    Direct API calls made via parameter splatting aren't detected. Its in my TODO list.
    #>

    [CmdletBinding()]
    [Alias("Get-CodeGraphPermission", "Get-CodeGraphScope", "Get-GraphAPICodePermission", "Get-GraphAPICodeScope")]
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

        [ValidateSet('Application', 'DelegatedWork', 'DelegatedPersonal')]
        [string] $permType = 'Application',

        [System.Collections.ArrayList] $availableModules = @(),

        [switch] $goDeep,

        [switch] $dontFilterPermissions
    )

    $commandData = Get-Command "Find-MgGraphCommand" -ErrorAction SilentlyContinue
    if (!$commandData) {
        throw "'Find-MgGraphCommand' command is missing. Install 'Microsoft.Graph.Authentication' module and run again"
    } elseif ($commandData.Version -lt "2.18.0") {
        # older versions returns different data
        throw "At least version '2.18.0' of the 'Microsoft.Graph.Authentication' module is required for 'Find-MgGraphCommand' command to work properly."
    }

    if (!(Get-Command "Get-CodeDependency" -ErrorAction SilentlyContinue)) {
        throw "'Get-CodeDependency' command is missing. Install 'DependencyStuff' module and run again"
    }

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

    # get all commands which belongs to Graph SDK modules or are web invocations
    $usedGraphCommand = Get-CodeDependency @param | ? { ($_.Type -eq "Module" -and $_.Name -like "Microsoft.Graph.*" -and $_.RequiredBy -ne '<requires statement>' -and $_.RequiredBy -notmatch "^Import-Module|^ipmo") -or $_.DependencyPath[-1] -in $webCommandList }

    $processedGraphCommand = @()

    if ($usedGraphCommand) {
        foreach ($mgCommandData in $usedGraphCommand) {
            $mgCommand = @($mgCommandData.DependencyPath)[-1]
            $dependencyPath = $mgCommandData.DependencyPath
            $invocationText = $mgCommandData.RequiredBy
            $method = $null
            $apiVersion = $null

            Write-Verbose "Processing: $invocationText"

            if ($mgCommand -in "Connect-MgGraph", "Get-MgContext") {
                # no permission needed
                continue
            }

            if ($mgCommand -in $processedGraphCommand) {
                continue
            }

            #region get required Graph permission
            if ($mgCommand -in $webCommandList) {
                # processing a "web" command (direct API call)

                #region get called URI
                if ($mgCommand -in "Invoke-MgGraphRequest", "Invoke-MsGraphRequest") {
                    # these commands should have call Graph API, hence more relaxed search for Graph URI
                    $uri = $invocationText -split " " | ? { $_ -like "*graph.microsoft.com/*" -or $_ -like "*v1.0/*" -or $_ -like "*beta/*" -or $_ -like "*/*" }
                } elseif ($mgCommand -in "Invoke-RestMethod", "irm", "Invoke-WebRequest", "curl", "iwr", "wget") {
                    # these commands can, but don't have to call Graph API, hence more restrictive search for Graph URI
                    $uri = $invocationText -split " " | ? { $_ -like "*graph.microsoft.com/*" -or $_ -like "*v1.0/*" -or $_ -like "*beta/*" }
                } else {
                    throw "$mgCommand is in `$webCommandList, but missing elseif statement in the function code. Fix it"
                }

                if (!$uri) {
                    if ($invocationText -like "Invoke-MgGraphRequest *" -or $invocationText -like "Invoke-MsGraphRequest *") {
                        # Invoke-MgGraphRequest and Invoke-MsGraphRequest commands for sure uses Graph Api, hence output empty object to highlight I was unable to extract it
                        Write-Warning "Unable to extract URI from '$invocationText'. Skipping."
                        '' | select @{n = 'Command'; e = { $mgCommand } }, Name, Description, FullDescription, @{n = 'Type'; e = { $null } }, @{n = 'InvokedAs'; e = { $invocationText } }, @{n = 'DependencyPath'; e = { $dependencyPath } }, @{n = 'ApiVersion'; e = { $null } }, @{n = 'Method'; e = { $null } }, @{n = 'IsAdmin'; e = { $null } }, @{n = 'ErrorMsg'; e = { "Unable to extract URI" } }
                    } else {
                        Write-Verbose "Unable to extract URI from '$invocationText' or it is not a Graph URI. Skipping."
                    }

                    continue
                }
                #endregion get called URI

                #region convert called URI to searchable form
                # get rid of quotes
                $uri = $uri -replace "`"|'"
                # get rid of filter section
                $uri = ($uri -split "\?")[0]
                # replace variables for {id} placeholder (it is just guessing that user put variable int he url instead of ID)
                $uri = $uri -replace "\$[^/]+", "{id}"
                #endregion convert called URI to searchable form

                # find requested method
                $method = $invocationText -split " " | ? { $_ -in "GET", "POST", "PUT", "PATCH", "DELETE" }
                if (!$method) {
                    # select the default method
                    $method = "GET"
                }

                # find requested api version
                if ($uri -like "*beta*") {
                    $apiVersion = "beta"
                } else {
                    $apiVersion = "v1.0"
                }

                # find graph command/permission(s) for called URI, Method and Api version
                try {
                    Write-Verbose "Get permissions for URI: '$uri', Method: $method, ApiVersion: $apiVersion"
                    $mgCommandPerm = Find-MgGraphCommand -Uri $uri -Method $method -ApiVersion $apiVersion -ErrorAction Stop | ? Permissions | select -First 1 -ExpandProperty Permissions

                    if (!$mgCommandPerm) {
                        # try again with not as specific uri (higher chance it will find some permission)
                        $uriSplitted = $uri.split("/")
                        $uri = $uriSplitted[0..($uriSplitted.count - 2)] -join "/"
                        $mgCommandPerm = Find-MgGraphCommand -Uri $uri -Method $method -ApiVersion $apiVersion -ErrorAction Stop | ? Permissions | select -First 1 -ExpandProperty Permissions
                    }
                } catch {
                    Write-Warning "'Find-MgGraphCommand' was unable to find permissions for URI: '$uri', Method: $method, ApiVersion: $apiVersion"
                    '' | select @{n = 'Command'; e = { $mgCommand } }, Name, Description, FullDescription, @{n = 'Type'; e = { $null } }, @{n = 'InvokedAs'; e = { $invocationText } }, @{n = 'DependencyPath'; e = { $dependencyPath } }, @{n = 'ApiVersion'; e = { $apiVersion } }, @{n = 'Method'; e = { $method } }, @{n = 'IsAdmin'; e = { $null } }, @{n = 'ErrorMsg'; e = { "'Find-MgGraphCommand' was unable to find permissions for given URI, Method and ApiVersion" } }
                    continue
                }
            } else {
                # processing a built-in graph sdk command
                $processedGraphCommand += $mgCommand

                # find graph permission(s) for called Graph SDK command
                try {
                    $mgCommandPerm = Find-MgGraphCommand -Command $mgCommand -ErrorAction Stop | ? Permissions | select -First 1 -ExpandProperty Permissions
                } catch {
                    Write-Warning "'Find-MgGraphCommand' was unable to find command '$mgCommand'?!"
                    continue
                }
            }
            #endregion get required Graph permission

            if ($mgCommandPerm) {
                # some Graph permissions are required

                $mgCommandPerm = $mgCommandPerm | ? PermissionType -EQ $permType

                #region helper functions
                function _apiVersion {
                    if ($apiVersion) {
                        # URI invocation
                        return $apiVersion
                    } else {
                        # Graph command invocation
                        return (Find-MgGraphCommand -Command $mgCommand).APIVersion | select -Unique
                    }
                }

                function _method {
                    if ($method) {
                        # URI invocation
                        return $method
                    } else {
                        # Graph command invocation
                        return (Find-MgGraphCommand -Command $mgCommand).Method | select -Unique
                    }
                }
                #endregion helper functions

                if ($mgCommandPerm) {
                    if ($dontFilterPermissions) {
                        Write-Verbose "Returning all found permissions of the '$permType' type: $($mgCommandPerm.Name)"

                        $mgCommandPerm | select @{n = 'Command'; e = { $mgCommand } }, Name, Description, FullDescription, @{n = 'Type'; e = { $_.PermissionType } }, @{n = 'InvokedAs'; e = { $invocationText } }, @{n = 'DependencyPath'; e = { $dependencyPath } }, @{n = 'ApiVersion'; e = { _apiVersion } }, @{n = 'Method'; e = { _method $mgCommand } }, IsAdmin, @{n = 'ErrorMsg'; e = { $null } }
                    } else {
                        $leastPrivilege = $mgCommandPerm | ? IsLeastPrivilege

                        if ($leastPrivilege) {
                            # there is some permission marked as least privileged, output just that

                            Write-Verbose "Returning just 'IsLeastPrivilege' marked permissions of the '$permType' type: $($leastPrivilege.Name)"

                            $leastPrivilege | select @{n = 'Command'; e = { $mgCommand } }, Name, Description, FullDescription, @{n = 'Type'; e = { $_.PermissionType } }, @{n = 'InvokedAs'; e = { $invocationText } }, @{n = 'DependencyPath'; e = { $dependencyPath } }, @{n = 'ApiVersion'; e = { _apiVersion } }, @{n = 'Method'; e = { _method $mgCommand } }, IsAdmin, @{n = 'ErrorMsg'; e = { $null } }
                        } else {
                            # there isn't any permission marked as least privileged, do some filtering magic

                            Write-Verbose "Returning just least-privilege-best-guess subset of permissions of the '$permType' type: $($mgCommandPerm.Name)"

                            if ((_method $mgCommand) -eq "GET") {
                                # the command just READs data

                                $mgCommandPerm = $mgCommandPerm | ? {
                                    $permission = $_.Name
                                    $isWritePermission = $permission -like "*.ReadWrite.*"

                                    if ($permission -like "Directory.*") {
                                        $someOtherPermission = $mgCommandPerm | ? { $_.Name -notlike "Directory.*" -and $_.Name -like "*.Read.*" }

                                        if ($someOtherPermission) {
                                            Write-Verbose "Skipping DIRECTORY permission $permission. There is some other least-priv permission in place ($($someOtherPermission.name))"
                                            return $false
                                        }
                                    } elseif ($isWritePermission) {
                                        $correspondingReadPermission = $mgCommandPerm | ? Name -EQ ($permission -replace "\.ReadWrite\.", ".Read.")

                                        if ($correspondingReadPermission) {
                                            # don't output, there is same but just READ permission in place
                                            Write-Verbose "Skipping READWRITE permission $permission. There is some other READ permission in place ($($correspondingReadPermission.name))"
                                            return $false
                                        }
                                    }

                                    return $true
                                }

                                $mgCommandPerm | select @{n = 'Command'; e = { $mgCommand } }, Name, Description, FullDescription, @{n = 'Type'; e = { $_.PermissionType } }, @{n = 'InvokedAs'; e = { $invocationText } }, @{n = 'DependencyPath'; e = { $dependencyPath } }, @{n = 'ApiVersion'; e = { _apiVersion } }, @{n = 'Method'; e = { _method $mgCommand } }, IsAdmin, @{n = 'ErrorMsg'; e = { $null } }
                            } else {
                                # the command MODIFIES data

                                $mgCommandPerm = $mgCommandPerm | ? {
                                    $permission = $_.Name
                                    $isReadPermission = $permission -like "*.Read.*"

                                    if ($permission -like "Directory.*") {
                                        $someOtherPermission = $mgCommandPerm | ? { $_.Name -notlike "Directory.*" -and $_.Name -like "*.ReadWrite.*" }

                                        if ($someOtherPermission) {
                                            Write-Verbose "Skipping DIRECTORY permission $permission. There is some other least-priv permission in place ($($someOtherPermission.name))"
                                            return $false
                                        }
                                    } elseif ($isReadPermission) {
                                        $correspondingWritePermission = $mgCommandPerm | ? Name -EQ ($permission -replace "\.Read\.", ".ReadWrite.")

                                        if ($correspondingWritePermission) {
                                            # don't output, there is same but READWRITE permission in place
                                            Write-Verbose "Skipping READ permission $permission. There is some other READWRITE permission in place ($($correspondingWritePermission.name))"
                                            return $false
                                        }
                                    }

                                    return $true
                                }

                                $mgCommandPerm | select @{n = 'Command'; e = { $mgCommand } }, Name, Description, FullDescription, @{n = 'Type'; e = { $_.PermissionType } }, @{n = 'InvokedAs'; e = { $invocationText } }, @{n = 'DependencyPath'; e = { $dependencyPath } }, @{n = 'ApiVersion'; e = { _apiVersion } }, @{n = 'Method'; e = { _method $mgCommand } }, IsAdmin, @{n = 'ErrorMsg'; e = { $null } }
                            }
                        }
                    }
                } else {
                    Write-Warning "$mgCommand requires some permissions, but not of '$permType' type"
                }
            } else {
                # no Graph permissions are required?!
                if ($mgCommand -in $webCommandList) {
                    $cmd = $invocationText
                } else {
                    $cmd = $mgCommand
                }
                Write-Verbose "'$cmd' doesn't need any permissions?!"
                '' | select @{n = 'Command'; e = { $mgCommand } }, Name, Description, FullDescription, @{n = 'Type'; e = { $null } }, @{n = 'InvokedAs'; e = { $invocationText } }, @{n = 'DependencyPath'; e = { $dependencyPath } }, @{n = 'ApiVersion'; e = { _apiVersion $mgCommand } }, @{n = 'Method'; e = { _method $mgCommand } }, IsAdmin, @{n = 'ErrorMsg'; e = { $null } }
            }
        }
    } else {
        if ($goDeep) {
            Write-Warning "No Graph commands nor direct Graph API calls were found in '$scriptPath' or it's dependency tree"
        } else {
            Write-Warning "No Graph commands nor direct Graph API calls were found in '$scriptPath'"
        }
    }
}