function Get-CMAutopilotHash {
    <#
    .SYNOPSIS
    Function for getting Autopilot hash from SCCM database.

    .DESCRIPTION
    Function for getting Autopilot hash from SCCM database.
    Hash is by default gathered during Hardware inventory cycle.

    .PARAMETER computerName
    Name of the computer you want to get the hash for.
    If omitted, hashes for all computers will be returned.

    .PARAMETER SCCMServer
    Name of the SCCM server.

    .PARAMETER SCCMSiteCode
    SCCM site code

    .EXAMPLE
    Get-CMAutopilotHash -computerName "PC-01" -SCCMServer "CMServer" -SCCMSiteCode "XXX"

    Get Autopilot hash for PC-01 computer from SCCM server.

    .EXAMPLE
    Get-CMAutopilotHash -SCCMServer "CMServer" -SCCMSiteCode "XXX"

    Get Autopilot hash for all computers from SCCM server.

    .NOTES
    Requires function Invoke-SQL and permission to read data from SCCM database.
    #>

    [CmdletBinding()]
    param (
        [string[]] $computerName,

        [ValidateNotNullOrEmpty()]
        $SCCMServer = $_SCCMServer,

        [ValidateNotNullOrEmpty()]
        $SCCMSiteCode = $_SCCMSiteCode
    )

    $sql = @'
SELECT
distinct(bios.SerialNumber0) as "SerialNumber",
System.Name0 as "Hostname",
User_Name0 as "Owner",
(osinfo.SerialNumber0) as "WindowsProductID",
mdminfo.DeviceHardwareData0 as "HardwareHash"
FROM v_R_System System
Inner Join v_GS_PC_BIOS bios on System.ResourceID=bios.ResourceID
Inner Join v_GS_OPERATING_SYSTEM osinfo on System.ResourceID=osinfo.ResourceID
Inner Join v_GS_MDM_DEVDETAIL_EXT01 mdminfo on System.ResourceID=mdminfo.ResourceID
'@

    if ($computerName) {
        $sql = "$sql WHERE System.Name0 IN ($(($computerName | % {"'"+$_+"'"}) -join ", "))"
        Write-Verbose $sql
    }

    Invoke-SQL -dataSource $SCCMServer -database "CM_$SCCMSiteCode" -sqlCommand $sql
}