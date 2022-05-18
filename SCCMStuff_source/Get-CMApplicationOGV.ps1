function Get-CMApplicationOGV {
    param (
        [ValidateNotNullOrEmpty()]
        $sccmServer = $_SCCMServer
        ,
        [ValidateNotNullOrEmpty()]
        $siteCode = $_SCCMSiteCode
        ,
        $title = "Vyber aplikaci"
    )

    Get-WmiObject -ComputerName $sccmServer -Namespace "root\sms\site_$siteCode" -Query 'SELECT * FROM SMS_Application WHERE isexpired="false" AND isenabled="true"' |
    select LocalizedDisplayName, LocalizedDescription, SoftwareVersion, NumberOfDeployments, NumberOfDevicesWithApp, NumberOfDevicesWithFailure |
    sort LocalizedDisplayName | ogv -OutputMode Multiple -Title $title | select -exp LocalizedDisplayName
}