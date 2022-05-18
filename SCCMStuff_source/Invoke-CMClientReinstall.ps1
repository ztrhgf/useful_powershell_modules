function Invoke-CMClientReinstall {
    [cmdletbinding()]
    param (
        [string] $computerName = $env:COMPUTERNAME
    )

    $ErrorActionPreference = "Stop"

    $oSCCM = [wmiclass] "\\$computerName\root\ccm:sms_client"
    $oSCCM.RepairClient()

    "Repair on $computerName has started"

    Write-Warning "Installation can take from 5 to 30 minutes! Check current status using: Get-CMLog -computerName $computerName -problem CMClientInstallation"
}