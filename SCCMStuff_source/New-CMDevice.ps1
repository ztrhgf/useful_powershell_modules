function New-CMDevice {
    <#
    .SYNOPSIS
    Function for creating new SCCM device in SCCM database.

    .DESCRIPTION
    Function for creating new SCCM device in SCCM database.

    .PARAMETER computerName
    Name of the device.

    .PARAMETER MACAddress
    MAC address of the device.

    .PARAMETER serialNumber
    (optional) Serial number (service tag) of the device.

    .PARAMETER collectionName
    (optional) Name of the SCCM collection this device should be member of.

    .EXAMPLE
    New-CMDevice -computerName nl-23-ntb -MACAddress 48:51:C5:20:44:2D -serialNumber 1234567
    #>

    param (
        [Parameter(Mandatory = $true)]
        [string] $computerName,

        [Parameter(Mandatory = $true)]
        [string] $MACAddress,

        [ValidatePattern('^[a-z0-9]{7}$')]
        [string] $serialNumber,

        [string[]] $collectionName
    )

    if (!$serialNumber) {
        $choice = ""
        while ($choice -notmatch "^[Y|N]$") {
            $choice = Read-Host "You haven't entered serialNumber. OSD won't work without it! Continue? (Y|N)"
        }
        if ($choice -eq "N") {
            break
        }
    }

    Connect-SCCM -commandName Import-CMComputerInformation -ErrorAction Stop

    $param = @{
        computerName = $computerName
        macAddress   = $MACAddress
    }

    if ($collectionName) { $param.collectionName = $collectionName }

    Import-CMComputerInformation @param

    if ($serialNumber) {
        Set-CMDeviceSerialNumber $computerName $serialNumber
    }
}