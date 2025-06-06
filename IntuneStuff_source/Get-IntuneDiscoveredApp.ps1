function Get-IntuneDiscoveredApp {
    <#
    .SYNOPSIS
    Function to retrieve discovered apps on specified/all Intune devices.

    .DESCRIPTION
    Function to retrieve discovered apps on specified/all Intune devices.

    .PARAMETER deviceName
    Name of the device you want to process.

    .PARAMETER deviceId
    Id(s) of the devices you want to process.

    .PARAMETER appName
    Filtering to return just devices where app with given name (matched using: -like '*appName*') was found.

    If not set, all processed devices will be returned.

    .EXAMPLE
    Get-IntuneDiscoveredApp -deviceName pc-01

    Return apps discovered on pc-01

    .EXAMPLE
    Get-IntuneDiscoveredApp -appName node.js

    Return all devices where node.js app was discovered.
    #>

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "DeviceName")]
        [string] $deviceName,

        [Parameter(Mandatory = $true, ParameterSetName = "DeviceId")]
        [string[]] $deviceId,

        [string] $appName = "*"
    )

    if ($deviceName) {
        $deviceId = (Get-MgBetaDeviceManagementManagedDevice -Filter "DeviceName eq '$deviceName'" -Property Id).Id

        if (!$deviceId) {
            throw "No device was found matching '$deviceName' name"
        }
    }

    if (!$deviceId) {
        Write-Warning "Getting detected apps for all devices!"
        $deviceId = (Get-MgBetaDeviceManagementManagedDevice -Property id -All).Id

        if (!$deviceId) {
            throw "No device was found"
        }
    }

    New-GraphBatchRequest -urlWithPlaceholder "/deviceManagement/managedDevices/<placeholder>?`$select=id,devicename&`$expand=DetectedApps" -inputObject $deviceId | Invoke-GraphBatchRequest -graphVersion beta | ? { $_.DetectedApps.DisplayName -like "*$appName*" }
}