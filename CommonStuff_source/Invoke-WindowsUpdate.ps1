function Invoke-WindowsUpdate {
    <#
    .SYNOPSIS
    Function for invoking Windows Update.
    Updates will be searched, downloaded and installed.

    .DESCRIPTION
    Function for invoking Windows Update.
    Updates will be searched (only updates that would be automatically selected in WU are searched), downloaded and installed (by default only the critical ones).

    Supports only Server 2016 and 2019 and partially 2012!

    .PARAMETER computerName
    Name of computer(s) where WU should be started.

    .PARAMETER allUpdates
    Switch for installing all available updates, not just critical ones.
    But in either case, just updates that would be automatically selected in WU are searched (because of AutoSelectOnWebSites=1 filter).

    .PARAMETER restartIfRequired
    Switch for restarting the computer if reboot is pending after updates installation.
    If not used and restart is needed, warning will be outputted.

    .EXAMPLE
    Invoke-WindowsUpdate app-15

    On server app-15 will be downloaded and installed all critical updates.

    .EXAMPLE
    Invoke-WindowsUpdate app-15 -restartIfRequired

    On server app-15 will be downloaded and installed all critical updates.
    Restart will be invoked in needed.

    .EXAMPLE
    Invoke-WindowsUpdate app-15 -restartIfRequired -allUpdates

    On server app-15 will be downloaded and installed all updates.
    Restart will be invoked in needed.

    .NOTES
    Inspired by https://github.com/microsoft/WSLab/tree/master/Scenarios/Windows%20Update#apply-updates-on-2016-and-2019
    #>

    [CmdletBinding()]
    [Alias("Invoke-WU", "Install-WindowsUpdate")]
    param (
        [string[]] $computerName
        ,
        [switch] $allUpdates
        ,
        [switch] $restartIfRequired
    )

    Invoke-Command -ComputerName $computerName {
        param ($allUpdates, $restartIfRequired)

        $os = (Get-CimInstance -Class Win32_OperatingSystem).Caption
        $result = @()

        switch ($os) {
            "2012" {
                if (!$allUpdates) {
                    Write-Warning "On Server 2012 are always installed all updates"
                }

                # find & apply all updates
                wuauclt /detectnow /updatenow
            }

            "2016" {
                # find updates
                $Instance = New-CimInstance -Namespace "root/Microsoft/Windows/WindowsUpdate" -ClassName MSFT_WUOperationsSession
                $ScanResult = $instance | Invoke-CimMethod -MethodName ScanForUpdates -Arguments @{SearchCriteria = "IsInstalled=0 AND AutoSelectOnWebSites=1"; OnlineScan = $true }

                # filter just critical ones
                if (!$allUpdates) {
                    $ScanResult = $ScanResult | ? { $_.updates.MsrcSeverity -eq "Critical" }
                }

                # apply updates
                if ($ScanResult.Updates) {
                    $null = $instance | Invoke-CimMethod -MethodName DownloadUpdates -Arguments @{Updates = [ciminstance[]]$ScanResult.Updates }
                    $result = $instance | Invoke-CimMethod -MethodName InstallUpdates -Arguments @{Updates = [ciminstance[]]$ScanResult.Updates }
                }
            }

            "2019" {
                # find updates
                try {
                    $ScanResult = Invoke-CimMethod -Namespace "root/Microsoft/Windows/WindowsUpdate" -ClassName "MSFT_WUOperations" -MethodName ScanForUpdates -Arguments @{SearchCriteria = "IsInstalled=0" } -ErrorAction Stop
                } catch {
                    try {
                        $ScanResult = Invoke-CimMethod -Namespace "root/Microsoft/Windows/WindowsUpdate" -ClassName "MSFT_WUOperations" -MethodName ScanForUpdates -Arguments @{SearchCriteria = "IsInstalled=0 AND AutoSelectOnWebSites=1" }-ErrorAction Stop
                    } catch {
                        # this should work for Core server
                        $ScanResult = Invoke-CimMethod -Namespace "root/Microsoft/Windows/WindowsUpdate" -ClassName "MSFT_WUOperations" -MethodName ScanForUpdates -Arguments @{SearchCriteria = "IsInstalled=0 AND Type='Software'" } -ErrorAction Stop
                    }
                }

                # filter just critical ones
                if (!$allUpdates) {
                    $ScanResult = $ScanResult | ? { $_.updates.MsrcSeverity -eq "Critical" }
                }

                # apply updates
                if ($ScanResult.Updates) {
                    $result = Invoke-CimMethod -Namespace "root/Microsoft/Windows/WindowsUpdate" -ClassName "MSFT_WUOperations" -MethodName InstallUpdates -Arguments @{Updates = $ScanResult.Updates }
                }
            }

            default {
                throw "$os is not defined"
            }
        }

        #region inform about results
        if ($failed = $result | ? { $_.returnValue -ne 0 }) {
            $failed = " ($($failed.count) failed"
        }

        if (@($result).count) {
            "Installed $(@($result).count) updates$failed on $env:COMPUTERNAME"
        } else {
            if ($os -match "2012") {
                "You have to check manually if some updates were installed (because it's Server 2012)"
            } else {
                "No updates found on $env:COMPUTERNAME"
            }
        }
        #endregion inform about results

        #region restart system
        if ($os -notmatch "2012") {
            $pendingReboot = Invoke-CimMethod -Namespace "root/Microsoft/Windows/WindowsUpdate" -ClassName "MSFT_WUSettings" -MethodName IsPendingReboot | select -exp pendingReboot
        } else {
            "Unable to detect if restart is required (because it's Server 2012)"
        }

        if ($restartIfRequired -and $pendingReboot -eq $true) {
            Write-Warning "Restarting $env:COMPUTERNAME"
            shutdown /r /t 30 /c "restarting because of newly installed updates"
        }
        if (!$restartIfRequired -and $pendingReboot -eq $true) {
            Write-Warning "Restart is required on $env:COMPUTERNAME!"
        }
        #endregion restart system
    } -ArgumentList $allUpdates, $restartIfRequired
}