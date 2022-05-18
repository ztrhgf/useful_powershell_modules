function Set-CMDeviceSerialNumber {
    <#
    .SYNOPSIS
    Function for setting devices SerialNumber in SCCM database.

    .DESCRIPTION
    Function for setting devices SerialNumber in SCCM database.
    Can be used for new, not yet discovered devices or devices where hardware inventory hasn't been run yet.

    .PARAMETER computerName
    Name of SCCM device.

    .PARAMETER serialNumber
    Serial number (service tag) of the device.
    Should be numbers and letters and length should be 7 chars.

    .PARAMETER SCCMServer
    Name of SCCM server.

    .PARAMETER SCCMSiteCode
    Name of SCCM site.

    .EXAMPLE
    Set-CMDeviceSerialNumber -computerName nl-23-atb -serialNumber 123a123
    #>

    [Alias("Set-CMDeviceServiceTag")]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $computerName,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z0-9]{7}$')]
        [Alias("serviceTag", "srvTag")]
        [string] $serialNumber,

        [ValidateNotNullOrEmpty()]
        [string] $SCCMServer = $_SCCMServer,

        [ValidateNotNullOrEmpty()]
        [string] $SCCMSiteCode = $_SCCMSiteCode
    )

    $ErrorActionPreference = "Stop"

    $serialNumber = $serialNumber.ToUpper()

    $machineID = (Invoke-SQL -dataSource $SCCMServer -database "CM_$SCCMSiteCode" -sqlCommand "SELECT ItemKey FROM vSMS_R_System WHERE Name0 = '$computerName'").ItemKey

    if (!$machineID) { throw "$computerName wasn't found in SCCM database" }

    $machineSQLRecord = Invoke-SQL -dataSource $SCCMServer -database "CM_$SCCMSiteCode" -sqlCommand "SELECT MachineId FROM System_Enclosure_DATA WHERE MachineID = '$machineID'"
    if (!$machineSQLRecord.MachineId) { throw "$computerName doesn't have any record in SQL table System_Enclosure_DATA so there is nothing to update" }

    Invoke-SQL -dataSource $SCCMServer -database "CM_$SCCMSiteCode" -sqlCommand "UPDATE System_Enclosure_DATA SET SerialNumber00 = '$serialNumber' WHERE MachineID = '$machineID'" -force
}