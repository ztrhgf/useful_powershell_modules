function Get-InstalledSoftware {
    <#
    .SYNOPSIS
    Function returns installed applications.

    .DESCRIPTION
    Function returns installed applications.
    Such information is retrieved from registry keys 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\', 'SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\'.

    .PARAMETER ComputerName
    Name of the remote computer where you want to run this function.

    .PARAMETER AppName
    (optional) Name of the application(s) to look for.
    It can be just part of the app name.

    .PARAMETER DontIgnoreUpdates
    Switch for getting Windows Updates too.

    .PARAMETER Property
    What properties of the registry key should be returned.

    Default is 'DisplayVersion', 'UninstallString'.

    DisplayName will be always returned no matter what.

    .PARAMETER Ogv
    Switch for getting results in Out-GridView.

    .EXAMPLE
    Get-InstalledSoftware

    Show all installed applications on local computer

    .EXAMPLE
    Get-InstalledSoftware -DisplayName 7zip

    Check whether application with name 7zip is installed on local computer.

    .EXAMPLE
    Get-InstalledSoftware -DisplayName 7zip -Property Publisher, Contact, VersionMajor -Ogv

    Check whether application with name 7zip is installed on local computer and output results to Out-GridView with just selected properties.

    .EXAMPLE
    Get-InstalledSoftware -ComputerName PC01

    Show all installed applications on computer PC01.
    #>

    [CmdletBinding()]
    param(
        [string[]] $appName,

        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]] $computerName,

        [switch] $dontIgnoreUpdates,

        [ValidateNotNullOrEmpty()]
        [ValidateSet('AuthorizedCDFPrefix', 'Comments', 'Contact', 'DisplayName', 'DisplayVersion', 'EstimatedSize', 'HelpLink', 'HelpTelephone', 'InstallDate', 'InstallLocation', 'InstallSource', 'Language', 'ModifyPath', 'NoModify', 'NoRepair', 'Publisher', 'QuietUninstallString', 'UninstallString', 'URLInfoAbout', 'URLUpdateInfo', 'Version', 'VersionMajor', 'VersionMinor', 'WindowsInstaller')]
        [string[]] $property = ('DisplayName', 'DisplayVersion', 'UninstallString'),

        [switch] $ogv
    )

    PROCESS {
        $scriptBlock = {
            param ($Property, $DontIgnoreUpdates, $appName)

            # where to search for applications
            $RegistryLocation = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\', 'SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\'

            # define what properties should be outputted
            $SelectProperty = @('DisplayName') # DisplayName will be always outputted
            if ($Property) {
                $SelectProperty += $Property
            }
            $SelectProperty = $SelectProperty | select -Unique

            $RegBase = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $env:COMPUTERNAME)
            if (!$RegBase) {
                Write-Error "Unable to open registry on $env:COMPUTERNAME"
                return
            }

            foreach ($RegKey in $RegistryLocation) {
                Write-Verbose "Checking '$RegKey'"
                foreach ($appKeyName in $RegBase.OpenSubKey($RegKey).GetSubKeyNames()) {
                    Write-Verbose "`t'$appKeyName'"
                    $ObjectProperty = [ordered]@{}
                    foreach ($CurrentProperty in $SelectProperty) {
                        Write-Verbose "`t`tGetting value of '$CurrentProperty' in '$RegKey$appKeyName'"
                        $ObjectProperty.$CurrentProperty = ($RegBase.OpenSubKey("$RegKey$appKeyName")).GetValue($CurrentProperty)
                    }

                    if (!$ObjectProperty.DisplayName) {
                        # Skipping. There are some weird records in registry key that are not related to any app"
                        continue
                    }

                    $ObjectProperty.ComputerName = $env:COMPUTERNAME

                    # create final object
                    $appObj = New-Object -TypeName PSCustomObject -Property $ObjectProperty

                    if ($appName) {
                        $appNameRegex = $appName | % {
                            [regex]::Escape($_)
                        }
                        $appNameRegex = $appNameRegex -join "|"
                        $appObj = $appObj | ? { $_.DisplayName -match $appNameRegex }
                    }

                    if (!$DontIgnoreUpdates) {
                        $appObj = $appObj | ? { $_.DisplayName -notlike "*Update for Microsoft*" -and $_.DisplayName -notlike "Security Update*" }
                    }

                    $appObj
                }
            }
        }

        $param = @{
            scriptBlock  = $scriptBlock
            ArgumentList = $property, $dontIgnoreUpdates, $appName
        }
        if ($computerName) {
            $param.computerName = $computerName
            $param.HideComputerName = $true
        }

        $result = Invoke-Command @param

        if ($computerName) {
            $result = $result | select * -ExcludeProperty RunspaceId
        }
    }

    END {
        if ($ogv) {
            $comp = $env:COMPUTERNAME
            if ($computerName) { $comp = $computerName }
            $result | Out-GridView -PassThru -Title "Installed software on $comp"
        } else {
            $result
        }
    }
}