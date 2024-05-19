function New-CMAppDeployment {
    <#
		.SYNOPSIS
			Fce pro nasazeni aplikace/i na vybranou kolekci/e.

		.DESCRIPTION
			Fce pro nasazeni aplikace/i na vybranou kolekci/e.
			Po spusteni funkce bez parametru se zobrazi okno pro vyber baliku a nasledne kolekce, na kterou se ma nainstalovat.
			Baliky se nasazuji jako required, bez zobrazeni notifikace v liste, vcetne zobrazeni alertu v SCCM konzoli pri nejake neuspesne instalaci.

            Navic dojde k dotazu, zdali je aplikace licencovana. Pokud bude odpoved kladna, tak se u ni nastavi priznak,
			ze vyzaduje pred zapocetim instalace schvaleni SCCM spravcem.

		.PARAMETER  AppName
			Nazev aplikace.
			Pokud se nezada, zobrazi se GUI se seznamem dostupnych aplikaci.

		.PARAMETER  CollectionName
			Nazev kolekce, na kterou budeme instalovat.
			Pokud se nezada, zobrazi se GUI se seznamem dostupnych kolekci.

        .PARAMETER Purpose
            Type of deployment.
            Required or Available.

            Default is Required.

        .PARAMETER DeployAction
            Type of deployment.
            Install or Uninstall.

            Default is Install.

		.PARAMETER  SiteCode
			Nepovinny parametr udavajici kod SCCM site.

		.PARAMETER  SccmServer
			Nepovinny parametr udavajici jmeno SCCM serveru.

        .PARAMETER DPGroupName
            Name of DP group.

            Default is "DP Group"

		.PARAMETER  force_install
			Switch rikajici jestli se ma provest na klientech update SCCM politik = uspisit nainstalovani aplikace.
            Vyzaduje fci Update-CMClientPolicy.

        .EXAMPLE
            New-CMAppDeployment

            Shows GUI for selecting application and collection and deploy it as required.

        .EXAMPLE
            New-CMAppDeployment -Purpose Available

            Shows GUI for selecting application and collection and deploy it as Available.

		.NOTES
			Fce pouziva fci connect-sccm pro pripojeni do SCCM, ale funguje i bez ni.
			Pouziva i Add-CMDeploymentTypeGlobalCondition, ktera vyzaduje, aby byla lokalne nainstalovana SCCM konzole!
	#>

    [CmdletBinding()]
    [Alias("Invoke-CMAppDeployment")]
    param(
        $AppName
        ,
        [array] $CollectionName
        ,
        [ValidateSet('Required', 'Available')]
        [string] $Purpose = "Required"
        ,
        [ValidateSet('Install', 'Uninstall')]
        [string] $DeployAction = "Install"
        ,
        $siteCode = $_SCCMSiteCode
        ,
        $sccmServer = $_SCCMServer
        ,
        $DPGroupName = "DP group"
        ,
        [switch] $force_install
    )

    $ConnectParameters = @{
        sccmServer  = $sccmServer
        commandName = "New-CMApplicationDeployment", "Get-CMCollection", "Start-CMContentDistribution", "Set-CMApplicationDeployment", "Get-CMCategory", "New-CMCategory", "Set-CMApplication", "Get-CMDeployment", "Get-CMApplication", "Get-CMDeploymentType"
        ErrorAction = "stop"
    }
    if ($VerbosePreference -eq 'continue') {
        $ConnectParameters.Add("verbose", $true)
    }

    Write-Output "Connecting to $sccmServer"
    Connect-SCCM @ConnectParameters

    if (!$AppName) {
        $AppName = Get-CMApplicationOGV -title "Choose application(s) to deploy"
    }
    if (!$AppName) { throw "No application was chosen!" }

    if (!$CollectionName) {
        $CollectionName = Get-CMCollectionOGV -title "Choose target collection(s)"
    }
    if (!$CollectionName) { throw "No collection was chosen!" }

    if ($DeployAction -eq "Uninstall" -and $Purpose -ne "Required") {
        Write-Warning "Purpose was set to Required, which is mandatory for uninstall action"
        $Purpose = "Required"
    }

    #
    # distribuce na DP pokud tam uz neni
    #
    foreach ($App in $AppName) {
        $AppID = Get-CimInstance -ComputerName $sccmServer -Namespace root\SMS\Site_$siteCode -Class SMS_PackageBaseclass -Filter "Name='$App'" | select -exp PackageID
        $distributed = Get-CimInstance -ComputerName $sccmServer -Namespace root\SMS\Site_$siteCode -Class SMS_DistributionStatus | where { $_.packageid -eq $AppID }
        if (!$distributed) {
            Write-Verbose "Application $App isn't on any DP, distributing"
            Start-CMContentDistribution -ApplicationName $App -DistributionPointGroupName $DPGroupName
        }
    }

    #
    # nasazeni na vybrane kolekce
    #
    foreach ($collection in $CollectionName) {
        # zjistim jestli je tato kolekce typu user collection
        $isUserCollection = Get-CimInstance -ComputerName $sccmServer -Namespace "root\sms\site_$siteCode" -Query "SELECT * FROM SMS_Collection where name=`"$collection`" and collectiontype = 1"

        try {
            foreach ($App in $AppName) {
                $deployed = Get-CMDeployment -SoftwareName $App -CollectionName $collection | ? {
                    if (($DeployAction -eq "Install" -and $_.DesiredConfigType -eq 1) -or ($DeployAction -eq "Uninstall" -and $_.DesiredConfigType -eq 2)) { $true } else { $false } }
                if ($deployed) {
                    Write-Warning "Application $App is already deployed to $collection collection. Skipping"
                    continue
                }

                if (!$isUserCollection) {
                    [System.Collections.ArrayList] $appCategory = @(Get-CimInstance -ComputerName $sccmServer -Namespace "root\sms\site_$siteCode" -Query "SELECT LocalizedCategoryInstanceNames FROM SMS_Application WHERE LocalizedDisplayName = `'$App`' AND IsLatest = 1" | select -exp LocalizedCategoryInstanceNames)
                }

                Write-Output "Deploy: $App to: $collection as: $Purpose"

                #
                # NASAZENI DEPLOYMENTU
                #

                # vytvorim hash s parametry, ktere se pouziji pro nasazeni deploymentu
                $params = @{
                    Name                  = $App
                    CollectionName        = $collection
                    DeployAction          = $DeployAction
                    DeployPurpose         = $Purpose
                    UserNotification      = 'DisplaySoftwareCenterOnly' #'DisplayAll'
                    TimeBaseOn            = 'LocalTime'
                    OverrideServiceWindow = $true
                    PostponeDateTime      = (Get-Date).AddDays(+7)
                    FailParameterValue    = 0
                    SuccessParameterValue = 100
                    ErrorAction           = 'stop'
                }

                # nasazuji na uzivatelskou kolekci
                if ($isUserCollection) {
                    # od kdy bude aplikace dostupna
                    $params.AvailableDateTime = Get-Date
                    # a tyto parametry jsou u uzivatelu zbytecne
                    # $params.Remove('SuccessParameterValue')
                    # $params.Remove('PostponeDateTime')
                    # $params.Remove('OverrideServiceWindow')

                    # nazev kategorie urcujici, ze jde o placeny SW
                    $licensedCategory = 'Licensed SW'
                    # aktualne nastaven SW kategorie
                    [System.Collections.ArrayList] $appCategory = @(Get-CimInstance -ComputerName $sccmServer -Namespace "root\sms\site_$siteCode" -Query "SELECT LocalizedCategoryInstanceNames FROM SMS_Application WHERE LocalizedDisplayName = `'$App`' AND IsLatest = 1" | select -exp LocalizedCategoryInstanceNames)

                    # zjistim jestli jde o placeny SW
                    $licensedApp = ''
                    if ($appCategory -contains $licensedCategory) {
                        $licensedApp = 'Y' #Get-CimInstance -computername $sccmServer -Namespace "root\sms\site_$siteCode" -query "SELECT LocalizedDisplayName FROM SMS_Application WHERE LocalizedDisplayName = `'$App`' AND LocalizedCategoryInstanceNames = `'$licensedCategory`'"
                    }

                    $usedToBeFreeApp = 0
                    # aktualne neni oznacen jako placeny
                    if (!$licensedApp) {
                        # poznacim si, ze nemel nastavenou kategorii (ze je placeny)
                        ++$usedToBeFreeApp
                        # zjistim, jestli ma byt oznacen jako placeny
                        while ($licensedApp -notin ("Y", "N")) {
                            $licensedApp = Read-Host "Is admin approval necessary to deploy this app? Y|N (Default is N)"
                            if (!$licensedApp) { $licensedApp = 'N' }
                        }
                    }

                    # SW je placeny/Licencovany
                    if ($licensedApp -eq 'Y') {
                        <# instalace neslo spustit i kdyz dany uzuivatel byl na svem primary device...
						# zjistim jestli jiz obsahuje omezeni na instalaci pouze na Primary Device uzivatele
						$jenNaPrimaryDevice = Get-CMApplication $App | select sdmpackagexml | where {$_.sdmpackagexml -like "*Primarydevice*"}
						# omezeni instalace neni nastaveno
						if (!$jenNaPrimaryDevice) {
							# omezim moznost instalace pouze na primary device uzivatele
							Write-Verbose "Nastavuji requirement, aby sla instalovat pouze na Primary Device daneho uzivatele (nemohl ji instalovat kdekoli)"
							$pouzivanyDeployment = Get-CMDeploymentType -ApplicationName $App | where {$_.PriorityInLatestApp -eq 1} | select -exp localizeddisplayname
							try {
								Add-CMDeploymentTypeGlobalCondition -ApplicationName $App -DeploymentTypeName $pouzivanyDeployment -sdkserver $sccmServer -sitecode $siteCode -GlobalCondition "PrimaryDevice" -Operator "IsEquals" -Value "True" -ea stop
							} catch {
								throw "Pri nastavovani podminky, aby sla aplikace instalovat pouze na Primary Device uzivatele se vyskytl problem:`n$_"
							}
						} else {
							Write-Verbose "Uz ma nastaveno omezeni instalace pouze na Primary Device uzivatele"
						}
						#>

                        # nastavim nutnost schvaleni instalace adminem
                        Write-Verbose "Set approval for this app"
                        $params.add('approvalRequired', $true)

                        # nastavim kategorii 'Licencovany SW'
                        if ($usedToBeFreeApp) {
                            Write-Verbose "Set SW category to mark $App as paid/licensed"
                            [System.Collections.ArrayList] $appCategory = @(Get-CimInstance -ComputerName $sccmServer -Namespace "root\sms\site_$siteCode" -Query "SELECT LocalizedCategoryInstanceNames FROM SMS_Application WHERE LocalizedDisplayName = `'$App`' AND IsLatest = 1" | select -exp LocalizedCategoryInstanceNames)

                            $appCategory.Add($licensedCategory) | Out-Null

                            Set-CMApplication -ApplicationName $App -AppCategories $appCategory
                            if (!$?) {
                                # try catch u tohoto cmdletu nefungoval
                                throw "When setting SW category there was an error. Make sure, that noone has this app opened in SCCM console."
                            }
                        } else {
                            Write-Output "Application $App was set as licensed, users will need admin approval before installation occurs."
                        }
                    } # konec licencovana app
                } # konec isUserCollection

                #
                # vytvorim novy deployment aplikace na vybranou kolekci
                #
                New-CMApplicationDeployment @params | Out-Null

                # umozneni instalace SW mimo maintenance windows. Skrze -OverrideServiceWindow nefunguje.
                Write-Verbose "allow installation outside the maintenance window"
                $apps = Get-CimInstance -Namespace "root\sms\site_$siteCode" -ComputerName $sccmServer -Query "SELECT * FROM SMS_ApplicationAssignment WHERE CollectionName = `'$collection`' and ApplicationName = `'$App`'"
                $apps.OverrideServiceWindows = $true
                $null = $apps.put()
            } # konec foreach cyklu resiciho instalace jednotlivych aplikaci
        } catch {
            throw $_
        }
    } # konec foreach cyklu resiciho jednotlive kolekce

    if (!$error) {
        Write-Output "OK"

        if ($force_install) {
            if (gcm Update-CMClientPolicy -ErrorAction silentlycontinue) {
                Write-Output "`nIn about 2 minutes, update of SCCM policy on computer in $($CollectionName -join ', ') begins"
                # zpozdeni je kvuli tomu, ze i na SCCM chvili trva, nez se zmeny v deploymentu projevi, tak aby klienti politiky kontrolovaly az budou updatovave
                Start-Job { sleep 120; Update-CMClientPolicy -CollectionName $CollectionName } | Out-Null
            } else {
                Write-Error "Function Update-CMClientPolicy ins't available, -force switch won't be used"
            }
        }
    }
}