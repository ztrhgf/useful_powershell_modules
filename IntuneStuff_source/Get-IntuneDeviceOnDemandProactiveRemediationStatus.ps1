function Get-IntuneDeviceOnDemandProactiveRemediationStatus {
    [CmdletBinding(DefaultParameterSetName = 'DeviceName')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "DeviceName")]
        [string[]] $deviceName,

        [Parameter(Mandatory = $true, ParameterSetName = "DeviceId")]
        [string[]] $deviceId
    )

    #region get device ids
    $deviceName = $deviceName | select -Unique

    $deviceIdList = @()

    if ($deviceName) {
        $deviceName | % {
            $device = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$_'" -Property Id, OperatingSystem, ManagementAgent
            if ($device.count -gt 1) {
                Write-Warning "There are multiple devices with name '$_'. Use ID instead. Skipping"
            } elseif ($device.count -eq 1) {
                if ($device.OperatingSystem -eq "Windows" -and $device.ManagementAgent -in "mdm", "configurationManagerClientMdm") {
                    $deviceList.($device.Id) = $_
                } else {
                    Write-Warning "Device '$_' isn't Windows client or isn't managed by Intune"
                }
            } else {
                Write-Warning "Device '$_' doesn't exist"
            }
        }
    } else {
        #TODO kontrola ze jde o windows device
        $deviceIdList = $deviceId
    }
    #endregion get device ids

    if (!$deviceIdList) {
        Write-Warning "No clients to check left"
        return
    }

    foreach ($devId in $deviceIdList) {
        $deviceDetails = Get-MgDeviceManagementManagedDevice -ManagedDeviceId $devId -Property DeviceName, Id, DeviceActionResults, LastSyncDateTime
        $onDemandRemediationData = $deviceDetails.DeviceActionResults | ? ActionName -EQ 'initiateOnDemandProactiveRemediation'

        $deviceDetails | select DeviceName, Id, @{n = 'ActionState'; e = { $onDemandRemediationData.ActionState } }, @{n = 'StartDateTimeUTC'; e = { $onDemandRemediationData.StartDateTime } }, @{n = 'LastUpdatedDateTimeUTC'; e = { $onDemandRemediationData.LastUpdatedDateTime } }, @{n = 'LastSyncDateTimeUTC'; e = { $_.LastSyncDateTime } }
    }
}