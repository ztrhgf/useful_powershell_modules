function Get-IntuneDeviceHardware {
    <#
    .SYNOPSIS
    Function returns data similar to Intune device Hardware tab.

    .DESCRIPTION
    Function returns data similar to Intune device Hardware tab.

    .PARAMETER deviceId
    Intune device ID(s).

    If not provided, all Windows devices will be processed.

    .EXAMPLE
    Connect-MgGraph

    Get-IntuneDeviceHardware -deviceId cc924194-f2c8-496c-9943-e6e74278ace5, 7f70a48e-cf9f-4d11-8a12-04c1e436dc1e

    Returns hardware data for selected devices.
    #>

    [CmdletBinding()]
    param (
        [guid[]]$deviceId
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    # get general info
    $generalProperty = "Id", "DeviceName", "operatingSystem" , "osVersion"

    # Get list of devices
    $deviceList = @()

    if (!$deviceId) {
        Write-Warning "Processing all Windows Intune devices!"
        $deviceList = Get-MgDeviceManagementManagedDevice -All -Filter "OperatingSystem eq 'Windows'" -Property $generalProperty
    } else {
        $deviceId | % {
            Get-MgDeviceManagementManagedDevice -ManagedDeviceId $_ -Property $generalProperty | % {
                $deviceList += $_
            }
        }
    }

    # get hardware info (must be gathered device by device otherwise returned values are null!)
    Write-Verbose "Get devices ($($deviceList.count)) HW data"
    $deviceListHardwareInfo = New-GraphBatchRequest -urlWithPlaceholder "/deviceManagement/manageddevices('<placeholder>')?`$select=id,devicename,hardwareinformation,activationLockBypassCode,iccid,udid,roleScopeTagIds,ethernetMacAddress,processorArchitecture,physicalMemoryInBytes,bootstrapTokenEscrowed" -placeholder $deviceList.Id | Invoke-GraphBatchRequest -graphVersion beta

    foreach ($device in $deviceList) {
        $deviceId = $device.Id
        $deviceName = $device.DeviceName

        Write-Verbose "Processing $deviceName ($deviceId)"

        $hardwareInfo = $deviceListHardwareInfo | ? Id -EQ $deviceId

        # make sure only required properties are returned
        $device = $device | select $generalProperty

        # add top-level HW properties
        'ethernetMacAddress', 'processorArchitecture', 'physicalMemoryInBytes' | % {
            $device | Add-Member -MemberType NoteProperty -Name $_ -Value $hardwareInfo.$_
        }

        # add nested HW properties
        $hardwareInfo.hardwareInformation | gm -MemberType NoteProperty | select -ExpandProperty Name | % {
            $device | Add-Member -MemberType NoteProperty -Name $_ -Value $hardwareInfo.hardwareInformation.$_
        }

        $device
    }
}