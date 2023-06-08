function Publish-Module2 {
    <#
    .SYNOPSIS
    Proxy function for original Publish-Module that fixes error: "Test-ModuleManifest : The specified RequiredModules entry 'xxx' In the module manifest 'xxx.psd1' is invalid. Try again after updating this entry with valid values" by creating temporary dummy modules for the missing ones that causes this error.

    .DESCRIPTION
    Proxy function for original Publish-Module that fixes error: "Test-ModuleManifest : The specified RequiredModules entry 'xxx' In the module manifest 'xxx.psd1' is invalid. Try again after updating this entry with valid values" by creating temporary dummy modules for the missing ones that causes this error.

    The thing is that Test-ModuleManifest that is called behind the scenes checks that each required module defined in published module manifest exists in $env:PSModulePath and if not, throws an error.

    .PARAMETER path
    Path to the module directory.

    .PARAMETER nugetApiKey
    Your nugetApiKey for PowerShell gallery.

    .EXAMPLE
    Publish-Module2 -Path "C:\repo\useful_powershell_modules\IntuneStuff" -NuGetApiKey oyjidshdnsdksjkdsqz2al4bu3ihkevj2qmxu3ksflmy -Verbose

    Creates dummy modules for each required module defined in IntuneStuff manifest file that is missing, then calls original Publish-Module and returns environment to the default state again.

    #>

    [CmdletBinding()]
    param (
        [string] $path,

        [string] $nugetApiKey
    )

    $manifestFile = (Get-ChildItem (Join-Path $path "*.psd1") -File).FullName

    if ($manifestFile) {
        if ($manifestFile.count -eq 1) {
            try {
                Write-Verbose "Processing '$manifestFile' manifest file"
                $manifestDataHash = Import-PowerShellDataFile $manifestFile -ErrorAction Stop
            } catch {
                Write-Error "Unable to process manifest file '$manifestFile'.`n`n$_"
            }

            if ($manifestDataHash) {
                # fix for Microsoft.PowerShell.Core\Test-ModuleManifest : The specified RequiredModules entry 'xxx' In the module manifest 'xxx.psd1' is invalid. Try again after updating this entry with valid values.
                # because every required module defined in the manifest file have to be in local available module list
                # so I temporarily create dummy one if necessary
                if ($manifestDataHash.RequiredModules) {
                    # make a backup of $env:PSModulePath
                    $bkpPSModulePath = $env:PSModulePath

                    $tempModulePath = Join-Path $env:TEMP (Get-Random)
                    # add temp module folder
                    $env:PSModulePath = "$env:PSModulePath;$tempModulePath"

                    $manifestDataHash.RequiredModules | % {
                        $mName = $_

                        if (!(Get-Module $mName -ListAvailable)) {
                            Write-Warning "Generating temporary dummy required module $mName. It's mentioned in manifest file but missing from this PC available modules list"
                            [Void][System.IO.Directory]::CreateDirectory("$tempModulePath\$mName")
                            'function dummy {}' > "$tempModulePath\$mName\$mName.psm1"
                        }
                    }
                }
            }
        } else {
            Write-Warning "Module manifest file won't be processed because more then one were found."
        }
    } else {
        Write-Verbose "No module manifest file found"
    }

    try {
        Publish-Module -Path $path -NuGetApiKey $nugetApiKey
    } catch {
        throw $_
    } finally {
        if ($bkpPSModulePath) {
            # restore $env:PSModulePath from the backup
            $env:PSModulePath = $bkpPSModulePath
        }
        if ($tempModulePath -and (Test-Path $tempModulePath)) {
            Write-Verbose "Removing temporary folder '$tempModulePath'"
            Remove-Item $tempModulePath -Recurse -Force
        }
    }
}