function Uninstall-ApplicationViaUninstallString {
    <#
    .SYNOPSIS
    Function for uninstalling applications using uninstall string (command) that is saved in registry for each application.

    .DESCRIPTION
    Function for uninstalling applications using uninstall string (command) that is saved in registry for each application.
    This functions cannot guarantee that uninstall process will be unattended!

    .PARAMETER name
    Name of the application(s) to uninstall.
    Can be retrieved using function Get-InstalledSoftware.

    .PARAMETER addArgument
    Argument that should be added to those from uninstall string.
    Can be helpful if you need to do unattended uninstall and know the right parameter for it.

    .EXAMPLE
    Uninstall-ApplicationViaUninstallString -name "7-Zip 22.01 (x64)"

    Uninstall 7zip application.

    .EXAMPLE
    Get-InstalledSoftware -appName Dell | Uninstall-ApplicationViaUninstallString

    Uninstall every application that has 'Dell' in its name.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias("displayName")]
        [string[]] $name,

        [string] $addArgument
    )

    # without admin rights msiexec uninstall fails without any error
    if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        throw "Run with administrator rights"
    }

    if (!(Get-Command Get-InstalledSoftware)) {
        throw "Function Get-InstalledSoftware is missing"
    }

    $appList = Get-InstalledSoftware -property DisplayName, UninstallString, QuietUninstallString | ? DisplayName -In $name

    if ($appList) {
        foreach ($app in $appList) {
            if ($app.QuietUninstallString) {
                $uninstallCommand = $app.QuietUninstallString
            } else {
                $uninstallCommand = $app.UninstallString
            }
            $name = $app.DisplayName

            if (!$uninstallCommand) {
                Write-Warning "Uninstall command is not defined for app '$name'"
                continue
            }

            if ($uninstallCommand -like "msiexec.exe*") {
                # it is MSI
                $uninstallMSIArgument = $uninstallCommand -replace "MsiExec.exe"
                # sometimes there is /I (install) instead of /X (uninstall) parameter
                $uninstallMSIArgument = $uninstallMSIArgument -replace "/I", "/X"
                # add silent and norestart switches
                $uninstallMSIArgument = "$uninstallMSIArgument /QN"
                if ($addArgument) {
                    $uninstallMSIArgument = $uninstallMSIArgument + " " + $addArgument
                }
                Write-Warning "Uninstalling app '$name'"
                Write-Verbose "Uninstall command is: msiexec.exe $uninstallMSIArgument"
                Start-Process "msiexec.exe" -ArgumentList $uninstallMSIArgument -Wait
            } else {
                # it is EXE
                # add silent and norestart switches
                $match = ([regex]'("[^"]+")(.*)').Matches($uninstallCommand)
                $uninstallExe = $match.captures.groups[1].value
                if (!$uninstallExe) {
                    Write-Error "Unable to extract EXE path from '$uninstallCommand'"
                    continue
                }
                $uninstallExeArgument = $match.captures.groups[2].value
                if ($addArgument) {
                    $uninstallExeArgument = $uninstallExeArgument + " " + $addArgument
                }
                Write-Warning "Uninstalling app '$name'"
                Write-Verbose "Uninstall command is: $uninstallCommand"

                $param = @{
                    FilePath = $uninstallExe
                    Wait     = $true
                }
                if ($uninstallExeArgument) {
                    $param.ArgumentList = $uninstallExeArgument
                }
                Start-Process @param
            }
        }
    } else {
        Write-Warning "No software with name $($name -join ', ') was found. Get the correct name by running 'Get-InstalledSoftware' function."
    }
}