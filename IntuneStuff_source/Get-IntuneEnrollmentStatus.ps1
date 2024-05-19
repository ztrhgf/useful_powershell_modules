#requires -modules Microsoft.Graph.DeviceManagement
function Get-IntuneEnrollmentStatus {
    <#
    .SYNOPSIS
    Function for checking whether computer is managed by Intune (fulfill all requirements).

    .DESCRIPTION
    Function for checking whether computer is managed by Intune (fulfill all requirements).
    What is checked:
     - device is AAD joined
     - device is joined to Intune
     - device has valid Intune certificate
     - device has Intune sched. tasks
     - device has Intune registry keys
     - Intune service exists

    Returns true or false.

    .PARAMETER computerName
    (optional) name of the computer to check.

    .PARAMETER checkIntuneToo
    Switch for checking Intune part too (if device is listed there).

    .PARAMETER wait
    Number of seconds function should wait when checking Intune certificate existence.

    Default is 0.

    .EXAMPLE
    Get-IntuneEnrollmentStatus

    Check Intune status on local computer.

    .EXAMPLE
    Get-IntuneEnrollmentStatus -computerName ae-50-pc

    Check Intune status on computer ae-50-pc.

    .EXAMPLE
    Get-IntuneEnrollmentStatus -computerName ae-50-pc -checkIntuneToo

    Check Intune status on computer ae-50-pc, plus connects to Intune and check whether ae-50-pc exists there.
    #>

    [CmdletBinding()]
    [Alias("Get-IntuneJoinStatus")]
    param (
        [string] $computerName,

        [switch] $checkIntuneToo,

        [int] $wait = 0
    )

    if (!$computerName) { $computerName = $env:COMPUTERNAME }

    #region get Intune data
    if ($checkIntuneToo) {
        $ErrActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Stop"

        if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
            throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
        }

        try {
            if (Get-Command Get-ADComputer -ErrorAction SilentlyContinue) {
                $ADObj = Get-ADComputer -Filter "Name -eq '$computerName'" -Properties Name, ObjectGUID
            } else {
                Write-Verbose "Get-ADComputer command is missing, unable to get device GUID"
            }

            $intuneObj = @()

            $intuneObj += Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$computerName'"

            if ($ADObj.ObjectGUID) {
                # because of bug? computer can be listed under guid_date name in cloud
                $intuneObj += Get-MgDeviceManagementManagedDevice -Filter "azureADDeviceId eq '$($ADObj.ObjectGUID)'" | ? DeviceName -NE $computerName
            }
        } catch {
            Write-Warning "Unable to get information from Intune. $_"

            # to avoid errors that device is missing from Intune
            $intuneObj = 1
        }

        $ErrorActionPreference = $ErrActionPreference
    }
    #endregion get Intune data

    $scriptBlock = {
        param ($checkIntuneToo, $intuneObj, $wait)

        $intuneNotJoined = 0

        #region Intune checks
        if ($checkIntuneToo) {
            if (!$intuneObj) {
                ++$intuneNotJoined
                Write-Warning "Device is missing from Intune!"
            }

            if ($intuneObj.count -gt 1) {
                Write-Warning "Device is listed $($intuneObj.count) times in Intune"
            }

            $wrongIntuneName = $intuneObj.DeviceName | ? { $_ -ne $env:COMPUTERNAME }
            if ($wrongIntuneName) {
                Write-Warning "Device is named as $wrongIntuneName in Intune"
            }

            $correctIntuneName = $intuneObj.DeviceName | ? { $_ -eq $env:COMPUTERNAME }
            if ($intuneObj -and !$correctIntuneName) {
                ++$intuneNotJoined
                Write-Warning "Device has no record in Intune with correct device name"
            }
        }
        #endregion Intune checks

        #region dsregcmd checks
        $dsregcmd = dsregcmd.exe /status
        $azureAdJoined = $dsregcmd | Select-String "AzureAdJoined : YES"
        if (!$azureAdJoined) {
            ++$intuneNotJoined
            Write-Warning "Device is NOT AAD joined"
        }

        $tenantName = $dsregcmd | Select-String "TenantName : .+"
        if (!$tenantName) {
            Write-Verbose "TenantName is missing in 'dsregcmd.exe /status' output"
        }
        $MDMUrl = $dsregcmd | Select-String "MdmUrl : .+"
        if (!$MDMUrl) {
            ++$intuneNotJoined
            Write-Warning "Device is NOT Intune joined"
        }
        #endregion dsregcmd checks

        #region certificate checks
        while (!($MDMCert = Get-ChildItem 'Cert:\LocalMachine\My\' | ? Issuer -EQ "CN=Microsoft Intune MDM Device CA") -and $wait -gt 0) {
            Start-Sleep 1
            --$wait
            Write-Verbose $wait
        }
        if (!$MDMCert) {
            ++$intuneNotJoined
            Write-Warning "Intune certificate is missing"
        } elseif ($MDMCert.NotAfter -lt (Get-Date) -or $MDMCert.NotBefore -gt (Get-Date)) {
            ++$intuneNotJoined
            Write-Warning "Intune certificate isn't valid"
        }
        #endregion certificate checks

        #region sched. task checks
        $MDMSchedTask = Get-ScheduledTask | ? { $_.TaskPath -like "*Microsoft*Windows*EnterpriseMgmt\*" -and $_.TaskName -eq "PushLaunch" }
        $enrollmentGUID = $MDMSchedTask | Select-Object -ExpandProperty TaskPath -Unique | ? { $_ -like "*-*-*" } | Split-Path -Leaf
        if (!$enrollmentGUID) {
            ++$intuneNotJoined
            Write-Warning "Synchronization sched. task is missing"
        }
        #endregion sched. task checks

        #region registry checks
        if ($enrollmentGUID) {
            $missingRegKey = @()
            $registryKeys = "HKLM:\SOFTWARE\Microsoft\Enrollments", "HKLM:\SOFTWARE\Microsoft\Enrollments\Status", "HKLM:\SOFTWARE\Microsoft\EnterpriseResourceManager\Tracked", "HKLM:\SOFTWARE\Microsoft\PolicyManager\AdmxInstalled", "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers", "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts", "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Logger", "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Sessions"
            foreach ($key in $registryKeys) {
                if (!(Get-ChildItem -Path $key -ea SilentlyContinue | Where-Object { $_.Name -match $enrollmentGUID })) {
                    Write-Warning "Registry key $key is missing"
                    ++$intuneNotJoined
                }
            }
        }
        #endregion registry checks

        #region service checks
        $MDMService = Get-Service -Name IntuneManagementExtension -ErrorAction SilentlyContinue
        if (!$MDMService) {
            ++$intuneNotJoined
            Write-Warning "Intune service IntuneManagementExtension is missing"
        }
        if ($MDMService -and $MDMService.Status -ne "Running") {
            Write-Warning "Intune service IntuneManagementExtension is not running"
        }
        #endregion service checks

        if ($intuneNotJoined) {
            return $false
        } else {
            return $true
        }
    }

    $param = @{
        scriptBlock  = $scriptBlock
        argumentList = $checkIntuneToo, $intuneObj, $wait
    }
    if ($computerName -and $computerName -notin "localhost", $env:COMPUTERNAME) {
        $param.computerName = $computerName
    }

    Invoke-Command @param
}