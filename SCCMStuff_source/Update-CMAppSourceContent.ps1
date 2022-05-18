Function Update-CMAppSourceContent {
    <#
    .SYNOPSIS
    Spusti aktualizaci zdrojovych souboru vybranych aplikaci na SCCM serveru.

    .DESCRIPTION
    Spusti aktualizaci zdrojovych souboru vybranych aplikaci na SCCM serveru.
    (nahraje je znovu ze zdroje na DP)

    .PARAMETER appName
    Jmeno aplikace, jejiz zdrojove soubory se maji updatovat na DP.
    Pokud se nezada, zobrazi se tabulka s dostupnymi aplikacemi.

    .PARAMETER sccmServer
    Jmeno sccm serveru.

    .PARAMETER siteCode
    Jmeno SCCM site.

    .EXAMPLE
    Update-CMAppSourceContent -appName "7-zip x64"

    Updatuje zdrojove soubory aplikace 7zip na SCCM serveru.

    .EXAMPLE
    Update-CMAppSourceContent

    Zobrazi tabulku s dostupnymi aplikacemi, po vybrani a potvrzeni, provede update jejich zdrojovych souboru.
    #>

    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string[]] $appName
        ,
        [ValidateNotNullOrEmpty()]
        $sccmServer = $_SCCMServer
        ,
        [ValidateNotNullOrEmpty()]
        $siteCode = $_SCCMSiteCode
    )

    process {
        # Get-CMApplication nejde pouzit s OGV (fce se ukonci), proto skrze WMI
        $application = @()
        if (!$appName) {
            $appName = Get-WmiObject -ComputerName $sccmServer -Namespace "root\sms\site_$siteCode" -Query 'SELECT * FROM SMS_Application WHERE isexpired="false" AND isenabled="true"' |
            select LocalizedDisplayName | sort LocalizedDisplayName | Out-GridView -OutputMode Multiple | select -exp LocalizedDisplayName
        }

        $appName | % {
            "Ziskavam informace o $_"
            $name = $_
            $app = Get-WmiObject -Namespace "Root\SMS\Site_$siteCode" -Class SMS_ApplicationLatest -ComputerName $sccmServer -Filter "LocalizedDisplayName='$name'"
            $packageID = Get-WmiObject -Namespace "Root\SMS\Site_$siteCode" -Class SMS_ContentPackage -ComputerName $sccmServer -Filter "SecurityKey='$($app.ModelName)'" | select -exp PackageID
            if ($packageID) {
                $application += New-Object PSObject -Property @{ LocalizedDisplayName = $name; PackageId = $packageID }
            } else {
                Write-Warning "U aplikace $name se nepodarilo ziskat packageID, updatujte rucne v SCCM konzoli"
            }

        }

        foreach ($app in $application) {
            "Updatuji zdrojaky $($app.LocalizedDisplayName)"
            $WmiObjectParam = @{
                'Namespace'    = "root\SMS\Site_$siteCode";
                'Class'        = 'SMS_ContentPackage';
                'computername' = $sccmServer;
                'Filter'       = "PackageID='$($app.PackageId)'";
            }
            (Get-WmiObject @WmiObjectParam).Commit() | Out-Null
        }
    }
}