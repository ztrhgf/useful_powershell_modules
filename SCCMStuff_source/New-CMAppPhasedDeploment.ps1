function New-CMAppPhasedDeploment {
    <#
    .SYNOPSIS
    Function for creation of phased application deployment.

    .DESCRIPTION
    Function for creation of phased application deployment.

    .PARAMETER AppName
    Name of the deployed application.

    .PARAMETER phs1Collection
    Name of the test collection (phase 1 collection).

    .PARAMETER phs2Collection
    Name of the target collection (phase 2 collection).

    .PARAMETER DPGroupName
    Name of the distribution group.
    This will be used, if application is not distributed yet.

    .PARAMETER siteCode
    Name of the SCCM site.

    .PARAMETER sccmServer
    Name of the SCCM server.

    .EXAMPLE
    New-CMAppPhasedDeploment

    GUI for selecting application, phase 1 collection and phase 2 collection will let you choose, what you want to do.
    #>

    [CmdletBinding()]
    [Alias("Invoke-CMAppPhasedDeployment")]
    param(
        $AppName
        ,
        [string] $phs1Collection
        ,
        [string] $phs2Collection
        ,
        $DPGroupName = "DP group"
        ,
        $siteCode = $_SCCMSiteCode
        ,
        $sccmServer = $_SCCMServer
    )

    #region connect to SCCM server
    $ConnectParameters = @{
        sccmServer  = $sccmServer
        commandName = "New-CMApplicationAutoPhasedDeployment", "Start-CMContentDistribution"
        ErrorAction = "stop"
    }
    if ($VerbosePreference -eq 'continue') {
        $ConnectParameters.Add("verbose", $true)
    }

    Write-Output "Connecting to $sccmServer"
    Connect-SCCM @ConnectParameters
    #endregion connect to SCCM server

    #region get missing values
    if (!$AppName) {
        $AppName = Get-CMApplicationOGV -title "Choose application(s) to deploy"
    }
    if (!$AppName) { throw "No application was chosen!" }

    if (!$phs1Collection) {
        $phs1Collection = Get-CMCollectionOGV -title "Choose phase one collection"
    }
    if (!$phs1Collection) { throw "No collection was chosen!" }

    if (!$phs2Collection) {
        $phs2Collection = Get-CMCollectionOGV -title "Choose target collection"
    }
    if (!$phs2Collection) { throw "No collection was chosen!" }
    #endregion get missing values

    foreach ($App in $AppName) {
        # distribute app to DP if necessary
        $AppID = Get-CimInstance -ComputerName $sccmServer -Namespace root\SMS\Site_$siteCode -Class SMS_PackageBaseclass -Filter "Name='$App'" | select -exp PackageID
        $distributed = Get-CimInstance -ComputerName $sccmServer -Namespace root\SMS\Site_$siteCode -Class SMS_DistributionStatus | where { $_.packageid -eq $AppID }
        if (!$distributed) {
            Write-Warning "Application $App isn't on any DP, distributing to DP group '$DPGroupName'"
            Start-CMContentDistribution -ApplicationName $App -DistributionPointGroupName $DPGroupName
        }

        # create phased deployment
        $null = New-CMApplicationAutoPhasedDeployment -ApplicationName $App -Name "Phased Deployment - $App" `
            -FirstCollectionName $phs1Collection -SecondCollectionName $phs2Collection `
            -CriteriaOption Compliance -CriteriaValue 95 `
            -BeginCondition AfterPeriod -DaysAfterPreviousPhaseSuccess 7 `
            -ThrottlingDays 7 -InstallationChoice AfterPeriod `
            -DeadlineUnit Days -DeadlineValue 3 `
            -Description "$App pilot deployment"
    }
}