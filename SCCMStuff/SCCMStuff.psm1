function Add-CMDeviceToCollection {
    <#
    .SYNOPSIS
    Function for easy adding of device(s) to SCCM collection.

    .DESCRIPTION
    Function for easy adding of device(s) to SCCM collection.
    It can be added using static or query rule type.

    .PARAMETER computerName
    Computer name(s).

    .PARAMETER collectionName
    Name of the SCCM collection.

    .PARAMETER asQuery
    Switch for adding computer using query rule (instead of static).
    Query rule add computer even after it was deleted and re-added to SCCM database.

    .EXAMPLE
    Add-CMDeviceToCollection -computerName ae-79-pc -collectionName 'windows 10 deploy' -asQuery
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ArgumentCompleter( {
                param ($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)

                Get-ADComputer -Filter "name -like '*$WordToComplete*' -and enabled -eq 'true'" -property Name, Enabled | select -exp Name | sort
            })]
        [string[]] $computerName,

        [Parameter(Mandatory = $true)]
        [ArgumentCompleter( {
                param ($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)

                Get-CMCollection -Name "*$WordToComplete*" | select -exp Name | sort | % { "'$_'" }
            })]
        [string] $collectionName,

        [switch] $asQuery
    )

    Connect-SCCM -ea Stop

    if (!(Get-CMCollection -Name $collectionName)) {
        throw "Collection '$collectionName' doesn't exist"
    }

    # get computer resourceId
    $computerHash = @{}
    $computerName | % {
        if (Get-CMCollectionMember -CollectionName $collectionName -Name $_) {
            Write-Warning "$_ is already in collection '$collectionName'. Skipping"
        } else {
            $computerId = Get-CMDevice -Name $_ -Fast | select -exp ResourceId
            if ($computerId) {
                $computerHash.$_ = $computerId
            } else {
                Write-Warning "Computer $_ wasn't found in SCCM database"
            }
        }
    }

    if ($computerHash.Keys) {
        if ($asQuery) {
            # add query rule (will survive computers removal from SCCM database)
            $computerHash.GetEnumerator() | % {
                Add-CMDeviceCollectionQueryMembershipRule -CollectionName $collectionName -QueryExpression "select SMS_R_System.ResourceId from SMS_R_System where SMS_R_System.Name = `"$($_.key)`"" -RuleName ($_.key).toupper()
            }
        } else {
            # add static rule
            $computerHash.GetEnumerator() | % {
                Add-CMDeviceCollectionDirectMembershipRule -CollectionName $collectionName -ResourceId $_.value
            }
        }

        # update membership
        Invoke-CMCollectionUpdate -Name $collectionName -Confirm:$false
    } else {
        Write-Warning "No such computer was found in SCCM database"
    }
}

function Clear-CMClientCache {
    <#
    .SYNOPSIS
        vymaze cache SCCM klienta (persistentni balicky ponecha)
    .DESCRIPTION
        vymaze cache SCCM klienta (persistentni balicky ponecha)
        druha varianta https://gallery.technet.microsoft.com/scriptcenter/Deleting-the-SCCM-Cache-da03e4c7
    #>

    [cmdletbinding()]
    Param (
        [Parameter(ValueFromPipeline = $True, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = "localhost"
    )

    PROCESS {
        Invoke-Command2 -ComputerName $ComputerName -ScriptBlock {
            $Computer = $env:COMPUTERNAME

            if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
                throw "You don't have administrator rights"
            }

            Try {
                #Connect to Resource Manager COM Object
                $resman = New-Object -com "UIResource.UIResourceMgr"
                $cacheInfo = $resman.GetCacheInfo()

                #Enum Cache elements, compare date, and delete older than 60 days
                $cacheinfo.GetCacheElements() | foreach { $cacheInfo.DeleteCacheElement($_.CacheElementID) }
                if ($?) {
                    Write-Output "$computer hotovo"
                }

            } catch {
                Write-Output "$computer error"
            }
        }
    }
}

function Connect-SCCM {
    <#
    .SYNOPSIS
    Helper function for making session to SCCM server, to be able to call locally any available command from SCCM module there.

    .DESCRIPTION
    Helper function for making session to SCCM server, to be able to call locally any available command from SCCM module there.

    .PARAMETER sccmServer
    Name of your SCCM server.

    .PARAMETER commandName
    (Optional)

    Name of command(s) you want to import instead of all.

    .EXAMPLE
    Connect-SCCM -sccmServer SCCM-01
    #>

    [CmdletBinding()]
    param (
        [ValidateNotNullOrEmpty()]
        $sccmServer = $_SCCMServer
        ,
        [string[]]$commandName
    )

    $correctlyConfSession = ""
    $sessionExist = Get-PSSession | ? { $_.computername -eq $sccmServer -and $_.state -eq "opened" }

    # remove broken sessions
    Get-PSSession | ? { $_.computername -eq $sccmServer -and $_.state -eq "broken" } | Remove-PSSession

    if ($commandName) {
        # check that pssession already exists and contains given commands
        $commandExist = try {
            Get-Command $commandName -ErrorAction Stop
        } catch {}

        if ($sessionExist -and $commandExist) {
            $correctlyConfSession = 1
            Write-Verbose "Session to $sccmServer is already created and contains required commands"
        }
    } else {
        # check that pssession already exists and that number of commands there is more than 50 (it is highly probable, that session contains all available commands)
        if ($sessionExist -and ((Get-Command -ListImported | ? { $_.name -like "*-cm*" -and $_.source -like "tmp_*" }).count -gt 50)) {
            $correctlyConfSession = 1
            Write-Verbose "Session to $sccmServer is already created"
        }
    }

    if (!$correctlyConfSession) {
        if (Test-Connection $sccmServer -ErrorAction SilentlyContinue) {
            # pssession doesn't contain necessary commands
            try {
                Write-Verbose "Removing existing sessions that doesn't contain required commands"
                Get-PSSession | ? { $_.computername -eq $sccmServer } | Remove-PSSession
            } catch {}

            $sccmSession = New-PSSession -ComputerName $sccmServer -Name "SCCM"

            try {
                $ErrorActionPreference = "stop"
                Invoke-Command -Session $sccmSession -ScriptBlock {
                    $ErrorActionPreference = "stop"

                    try {
                        Import-Module "$(Split-Path $Env:SMS_ADMIN_UI_PATH)\ConfigurationManager.psd1"
                    } catch {
                        throw "Unable to import SCCM module on $env:COMPUTERNAME"
                    }

                    try {
                        $sccmSite = (Get-PSDrive -PSProvider CMSite).name
                        Set-Location -Path ($sccmSite + ":\")
                    } catch {
                        throw "Unable to retrieve SCCM Site Code"
                    }
                }

                $Params = @{
                    'session'      = $sccmSession
                    'Module'       = 'ConfigurationManager'
                    'AllowClobber' = $true
                    'ErrorAction'  = "Stop"
                }
                if ($commandName) {
                    $Params.Add("CommandName", $CommandName)
                }

                # import-module is used, so the commands will be available even if Connect-SCCM is called from module
                Import-Module (Import-PSSession @Params) -Global -Force
            } catch {
                "To be able to use SCCM commands remotely you have to:`n1. Connect to $sccmServer using RDP.`n2. Run SCCM console under account, that should use commands remotely.`n3. In SCCM console run PowerShell console (Connect via PowerShell).`n4. In such PowerShell console enable import of certificate by selecting choice '[A] Always run'"

                "Second option should be to:`n1. Open file properties of 'C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1'.`n2. On tab Digital Signatures > Details > View Certificate > Install Certificate > Install such certificate to Trusted Publishers store"

                "Error was: $($_.Exception.Message)"
            }
        } else {
            "$sccmServer is offline"
        }
    }
}

function Get-CMAppDeploymentStatus {
    <#
    .SYNOPSIS
        Skript vraci stav nainstalovanosti deploymentu aplikaci na zadanych strojich.
    .DESCRIPTION
        Skript vraci stav nainstalovanosti deploymentu aplikaci na zadanych strojich.
        Nevraci SW, ktery neni nainstalovan z duvodu nesplneni pozadavku na instalaci
    .PARAMETER Computername
        Jmeno stroje, ze ktereho chci vysledky.
    .PARAMETER ApplicationName
        Vyfiltrovani vysledku dle 'Localized Application DisplayName' nazvu aplikace (zjistim v konzoli u dane aplikace na zalozce Application Catalog).
    .PARAMETER NotInstalled
        Zobrazi pouze nenainstalovane aplikace
    .PARAMETER targeted
        Zobrazeni aplikaci cilenych per user/computer.
        Vychozi jsou i per user i per computer.
    .PARAMETER Install
        Spusti instalaci vsech nalezenych nenainstalovanych aplikaci.
    .PARAMETER SiteServer
        Your SCCM site server
    .PARAMETER SiteCode
        The 3 character SCCM site code
    .EXAMPLE
        PS> Get-CmAppDeploymentStatus -ApplicationName "BIOS Update"

        Vrati stav deploymentu aplikace "BIOS Update" na lokalnim klientovi.
    #>

    [CmdletBinding()]
    param (
        [string[]] $Computername = $env:COMPUTERNAME
        ,
        [string] $ApplicationName
        ,
        [switch] $NotInstalled
        ,
        [ValidateSet('perUser', 'perComputer')]
        [string[]] $targeted = ("perUser", "perComputer")
        ,
        [switch] $Install
        ,
        [ValidateNotNullOrEmpty()]
        [string] $SiteServer = $_SCCMServer
        ,
        [ValidateNotNullOrEmpty()]
        [string] $SiteCode = $_SCCMSiteCode
    )

    begin {
        if ($NotInstalled) {
            $status = "Installed"
        } else {
            $status = "fakefakefake"
        }

        $EvalStates = @{
            0  = 'No state information is available';
            1  = 'Application is enforced to desired/resolved state';
            2  = 'Application is not required on the client';
            3  = 'Application is available for enforcement (install or uninstall based on resolved state). Content may/may not have been downloaded';
            4  = 'Application last failed to enforce (install/uninstall)';
            5  = 'Application is currently waiting for content download to complete';
            6  = 'Application is currently waiting for content download to complete';
            7  = 'Application is currently waiting for its dependencies to download';
            8  = 'Application is currently waiting for a service (maintenance) window';
            9  = 'Application is currently waiting for a previously pending reboot';
            10 = 'Application is currently waiting for serialized enforcement';
            11 = 'Application is currently enforcing dependencies';
            12 = 'Application is currently enforcing';
            13 = 'Application install/uninstall enforced and soft reboot is pending';
            14 = 'Application installed/uninstalled and hard reboot is pending';
            15 = 'Update is available but pending installation';
            16 = 'Application failed to evaluate';
            17 = 'Application is currently waiting for an active user session to enforce';
            18 = 'Application is currently waiting for all users to logoff';
            19 = 'Application is currently waiting for a user logon';
            20 = 'Application in progress, waiting for retry';
            21 = 'Application is waiting for presentation mode to be switched off';
            22 = 'Application is pre-downloading content (downloading outside of install job)';
            23 = 'Application is pre-downloading dependent content (downloading outside of install job)';
            24 = 'Application download failed (downloading during install job)';
            25 = 'Application pre-downloading failed (downloading outside of install job)';
            26 = 'Download success (downloading during install job)';
            27 = 'Post-enforce evaluation';
            28 = 'Waiting for network connectivity';
        }

        # translate human readable state to its ID
        $wantedEvalState = @()
        if ($targeted -contains "perComputer") { $wantedEvalState += 1 }
        if ($targeted -contains "perUser") { $wantedEvalState += 2 }
    }

    process {
        foreach ($Computer in $Computername) {
            if ($targeted -contains "perUser" -and $Computer -eq $env:COMPUTERNAME) {
                Write-Warning "Per-User applications for only $env:username will be shown"
            } else {
                Write-Warning "Per-User applications won't be shown (I don't know how)"
            }

            $Params = @{
                'Computername' = $Computer
                'Namespace'    = 'root\ccm\clientsdk'
                'Class'        = 'CCM_Application'
            }

            if ($ApplicationName) {
                $Applications = Get-WmiObject @Params | Where-Object { $_.FullName -like "*$ApplicationName*" -and $_.InstallState -notlike $status -and $_.EvaluationState -in $wantedEvalState }
            } else {
                $Applications = Get-WmiObject @Params | Where-Object { $_.InstallState -notlike $status -and $_.EvaluationState -in $wantedEvalState }
            }

            if ($Applications) {
                $Applications | Select-Object PSComputerName, Name, InstallState, SoftwareVersion, ErrorCode, @{ n = 'EvalState'; e = { $EvalStates[[int]$_.EvaluationState] } }, @{ label = 'ApplicationMadeAvailable'; expression = { $_.ConvertToDateTime($_.StartTime) } }, @{ label = 'LastInstallDate'; expression = { $_.ConvertToDateTime($_.LastInstallTime) } }
            } elseif (!$NotInstalled) {
                "Application is not installed on $Computer."
            }

            if ($install) {
                $ApplicationClass = [WmiClass]"\\$Computer\root\ccm\clientSDK:CCM_Application"
                # vynutim spusteni instalace (jen u nenainstalovanych)
                $Applications | Where-Object { InstallState -NotLike "installed" } | % {
                    $Application = $_
                    $ApplicationID = $Application.Id
                    $ApplicationRevision = $Application.Revision
                    $ApplicationIsMachineTarget = $Application.ismachinetarget
                    $EnforcePreference = "Immediate"
                    $Priority = "high"
                    $IsRebootIfNeeded = $false

                    Write-Verbose "Starting installation of $($application.fullname)"
                    $null = $ApplicationClass.Install($ApplicationID, $ApplicationRevision, $ApplicationIsMachineTarget, 0, $Priority, $IsRebootIfNeeded)
                    # spravne poradi parametru ziskam pomoci $ApplicationClass.GetMethodParameters("install") | select -first 1 | select -exp properties
                    #Invoke-WmiMethod -ComputerName titan02 -Class $Params.Class -Namespace $Params.Namespace -Name install -ArgumentList 0,$ApplicationID,$ApplicationIsMachineTarget,$IsRebootIfNeeded,$Priority,$ApplicationRevision
                }
            }
        }
    }
}

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

function Get-CMCollectionComplianceStatus {
    [CmdletBinding()]
    param (
        [ArgumentCompleter( {
                param ($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)
                Get-WmiObject -Namespace "root\SMS\Site_$_SCCMSiteCode" -Query "select LocalizedDisplayName from SMS_ConfigurationBaselineInfo" -ComputerName $_SCCMServer | ? { $_.LocalizedDisplayName -like "*$WordToComplete*" } | % { '"' + $_.LocalizedDisplayName + '"' }
            })]
        [string[]] $confBaseline
        ,
        [ArgumentCompleter( {
                param ($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)
                Get-WmiObject -Namespace "root\SMS\Site_$_SCCMSiteCode" -Query "select Name from SMS_Collection" -ComputerName $_SCCMServer | ? { $_.Name -like "*$WordToComplete*" } | % { '"' + $_.Name + '"' }
            })]
        [string[]] $collection
        ,
        [string[]] $computerName
    )

    if ($computerName -and $collection) {
        Write-Warning "Collection will be ignored, because you have selected computerName"
    }
    if (!$confBaseline -and !$computerName -and !$collection) {
        throw "You have to specify confBaseline and/or collection and/or computer"
    }

    $filter = ""

    if ($confBaseline) {
        $list = @()
        $confBaseline | % {
            $name = $_
            $list += Get-WmiObject -Namespace "root\SMS\Site_$_SCCMSiteCode" -Query "select LocalizedDisplayName, CI_ID from SMS_ConfigurationBaselineInfo" -ComputerName $_SCCMServer | ? { $_.LocalizedDisplayName -eq $name } | select -exp CI_ID
        }

        if ($filter) {
            $and = " and"
        }
        $list = $list -join ', '
        $filter += "$and CI.CI_ID IN($list)"
    }

    if ($computerName) {
        if ($filter) {
            $and = " and"
        }
        $computerName = ($computerName | % { "'" + $_ + "'" }) -join ', '
        $filter += "$and VRS.Netbios_Name0 IN($computerName)"
    }

    if ($collection) {
        $list = @()
        $collection | % {
            $name = $_
            $list += Get-WmiObject -Namespace "root\SMS\Site_$_SCCMSiteCode" -Query "select Name, CollectionID from SMS_Collection" -ComputerName $_SCCMServer | ? { $_.Name -eq $name } | select -exp CollectionID
        }

        if ($filter) {
            $and = " and"
        }
        $list = ($list | % { "'" + $_ + "'" }) -join ', '
        $filter += "$and FM.CollectionID IN ($list)"
    }

    $sqlCommand = "
    select distinct VRS.Netbios_Name0 as ComputerName, CI.UserName, CI.DisplayName, CI.ComplianceStateName from v_R_System VRS
    right join v_FullCollectionMembership_Valid FM on VRS.ResourceID=FM.ResourceID
    right join fn_ListCI_ComplianceState(1033) CI on VRS.ResourceID=CI.ResourceID
    where $filter"

    Write-Verbose $sqlCommand

    $a = Invoke-SQL -dataSource $_SCCMServer -database "CM_$_SCCMSiteCode" -sqlCommand $sqlCommand
    $a | select ComputerName, UserName, DisplayName, ComplianceStateName | Sort-Object ComputerName
}

function Get-CMCollectionOGV {
    param (
        [ValidateNotNullOrEmpty()]
        [string] $sccmServer = $_SCCMServer
        ,
        [ValidateNotNullOrEmpty()]
        [string] $siteCode = $_SCCMSiteCode
        ,
        [string] $title = "Vyber kolekci"
        ,
        [ValidateSet('Multiple', 'Single')]
        [string] $outputMode = "Multiple"
        ,
        [ValidateSet('user', 'device', 'all')]
        [string[]] $type = "all"
        ,
        [switch] $returnAsObject
    )

    if ($type -eq "user") {
        $collectionType = 1
    } elseif ($type -eq "device") {
        $collectionType = 2
    } else {
        $collectionType = 1, 2
    }
    $collection = Get-WmiObject -ComputerName $sccmServer -Namespace "root\sms\site_$siteCode" -Query 'SELECT * FROM SMS_Collection' | ? { $_.CollectionType -in $collectionType } | select Name, Comment, MemberCount, RefreshType, CollectionID | sort Name | ogv -OutputMode $outputMode -Title $title
    if ($returnAsObject) {
        $collection
    } else {
        $collection | select -exp Name
    }
}

function Get-CMComputerCollection {
    <#
    .SYNOPSIS
    Function returns name of computer's collection(s).

    .DESCRIPTION
    Function returns name of computer's collection(s).

    .PARAMETER computerName
    Name of computer.

    .PARAMETER SCCMServer
    Name of the SCCM server.

    Default is $_SCCMServer.

    .EXAMPLE
    Get-CMComputerCollection ni-20-ntb
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $computerName,

        [ValidateNotNullOrEmpty()]
        [string] $SCCMServer = $_SCCMServer
    )

    if (!$SCCMServer) { throw "Undefined SCCMServer" }

    (Get-WmiObject -ComputerName $SCCMServer -Namespace root/SMS/site_$_SCCMSiteCode -Query "SELECT SMS_Collection.* FROM SMS_FullCollectionMembership, SMS_Collection where name = '$computerName' and SMS_FullCollectionMembership.CollectionID = SMS_Collection.CollectionID").Name
}

function Get-CMComputerComplianceStatus {
    <#
    .SYNOPSIS
    Function gets status of SCCM compliance baselines on given client.

    .DESCRIPTION
    Function gets status of SCCM compliance baselines on given client.
    Shows user and device compliances (thanks to Invoke-AsCurrentUser).

    If run locally, returns object with all user (which run this function) and device CB status.
    If run remotely, returns string with all (there logged) user and device CB status.

    .PARAMETER computerName
    Name of remote computer to connect.

    .PARAMETER onlyComputerCB
    Switch for showing just device targeted CB not user ones.
    But as advantage, object will be returned instead of string.

    .EXAMPLE
    Get-CMComputerComplianceStatus

    Returns configuration baselines status as object.
    User and device ones.

    .EXAMPLE
    Get-CMComputerComplianceStatus -computerName pc-01

    Returns configuration baselines status as string.
    User and device ones.

    .EXAMPLE
    Get-CMComputerComplianceStatus -computerName pc-01 -onlyComputerCB

    Returns configuration baselines status as object. Just device CB ones.
    #>

    [CmdletBinding()]
    param (
        [string] $computerName
        ,
        [switch] $onlyComputerCB
    )

    #region prepare param for Invoke-AsLoggedUser
    $param = @{ReturnTranscript = $true }

    if ($computerName -and $computerName -notmatch "localhost|$env:COMPUTERNAME") {
        $param.computerName = $computerName
    }
    #endregion prepare param for Invoke-AsLoggedUser

    $scriptBlockText = @'
$Baselines = Get-CimInstance -Namespace root\ccm\dcm -Class SMS_DesiredConfiguration
ForEach ($Baseline in $Baselines) {
    $bsDisplayName = $Baseline.DisplayName
    $name = $Baseline.Name
    $IsMachineTarget = $Baseline.IsMachineTarget
    $IsEnforced = $Baseline.IsEnforced
    $PolicyType = $Baseline.PolicyType
    $version = $Baseline.Version

    switch ($Baseline.LastComplianceStatus) {
        0 { $bsStatus = "Noncompliant" }
        1 { $bsStatus = "Compliant" }
        2 { $bsStatus = "NotApplicable" }
        3 { $bsStatus = "Unknown" }
        4 { $bsStatus = "Error" }
        5 { $bsStatus = "NotEvaluated" }
        default {$bsStatus = "*Unknown*"}
    }

    [xml]$ComplianceDetails = $baseline.ComplianceDetails

    [PSCustomObject]@{
        DisplayName = $bsDisplayName
        Status = $bsStatus
        LastEvaluated = $Baseline.LastEvalTime
        CI = $ComplianceDetails.ConfigurationItemReport.ReferencedConfigurationItems.ConfigurationItemReport | ? { $_ } | % {
            $property = [ordered]@{
                Name                = $_.CIProperties.name.'#text'
                State               = $_.CIComplianceState
            }
            $DiscoveryViolations = $_.DiscoveryViolations.DiscoveryViolation.SettingInformation.Errors.Error.ErrorDescription
            if ($DiscoveryViolations) {
                $property.DiscoveryViolations = $DiscoveryViolations
            }
            New-Object -TypeName PSObject -Property $property
        }
        IsMachineTarget = $IsMachineTarget
        Version = $version
    }
}
'@ # end of scriptBlock text


    $scriptBlock = [Scriptblock]::Create($scriptBlockText)

    if ($param.computerName) {
        if ($onlyComputerCB) {
            Invoke-Command -ComputerName $computerName -ScriptBlock $scriptBlock
        } else {
            Invoke-AsLoggedUser -ScriptBlock $scriptBlock @param
        }
    } else {
        Invoke-Command -ScriptBlock $scriptBlock
    }
}

function Get-CMDeploymentStatus {
    <#
    .SYNOPSIS
    Get SCCM (not just application) deployment status.

    .DESCRIPTION
    Get SCCM (not just application) deployment status.

    .PARAMETER name
    (optional) name of the deployment.

    .PARAMETER SCCMServer
    Name of the SCCM server.

    Default is $_SCCMServer.

    .PARAMETER SCCMSiteCode
    Name of the SCCM site.

    Default is $_SCCMSiteCode.

    .EXAMPLE
    Get-CMDeploymentStatus

    Returns deployment status of all deployments in SCCM.

    .EXAMPLE
    Get-CMDeploymentStatus -name CB_not_for_ConditionalAccess

    Returns deployment status of CB_not_for_ConditionalAccess compliance deployment.
    #>

    [CmdletBinding()]
    param (
        [string] $name,

        [ValidateNotNullOrEmpty()]
        [string] $SCCMServer = $_SCCMServer,

        [ValidateNotNullOrEmpty()]
        [string] $SCCMSiteCode = $_SCCMSiteCode
    )

    if ($name) {
        $nameFilter = "where SoftwareName = '$name'"
    }

    Get-WmiObject -ComputerName $SCCMServer -Namespace "root\SMS\site_$SCCMSiteCode" -Query "SELECT SoftwareName, CollectionName, NumberTargeted, NumberSuccess, NumberErrors, NumberInprogress, NumberOther, NumberUnknown FROM SMS_DeploymentSummary $nameFilter" | select SoftwareName, CollectionName, NumberTargeted, NumberSuccess, NumberErrors, NumberInprogress, NumberOther, NumberUnknown
}

function Get-CMLog {
    <#
    .SYNOPSIS
    Function for easy opening of SCCM logs.

    You have two options to define what log(s) you want to open:
     - by specifying AREA of your problem
     - by specifying NAME of the LOG(S)

    .DESCRIPTION
    Function for easy opening of SCCM logs.

    You have two options to define what log(s) you want to open:
     - by specifying AREA of your problem
     - by specifying NAME of the LOG(S)

    Benefits of using AREA approach:
     - you don't have to remember which logs are for which type of problem
     - you don't have to remember where such logs are stored

    Benefits of using LOG NAME approach:
     - you don't have to remember where such logs are stored

    General benefits of using this function:
     - description for each log is outputted
      - it is retrieved from https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/hierarchy/log-files#BKMK_ServerLogs and cached locally so ongoing runs will be much faster!
     - function supports opening of archived logs
     - best possible log viewer application will be used
      - Sorted by preference: 'Configuration Manager Support Center Log Viewer', 'Support Center OneTrace', CMTrace or as a last resort in default associated program

    How to get the log viewers:
    - 'Configuration Manager Support Center Log Viewer' and 'Support Center OneTrace' can be installed via 'C:\Program Files\Microsoft Configuration Manager\tools\SupportCenter\supportcenterinstaller.msi' (saved on your SCCM server) or by installing SCCM Administrator console.
    - CMTrace is installed by default with SCCM Client

    .PARAMETER computerName
    Name of computer where CLIENT logs should be obtained.
    In case the problem is related to SCCM server, this parameter will be ignored.

    .PARAMETER area
    What area (problem) you want to show logs from.

    Possible values:
    ApplicationDiscovery
    ApplicationDownload
    ApplicationInstallation
    ApplicationManagement
    ApplicationMetering
    AssetIntelligence
    BackupAndRecovery
    BootImageUpdate
    CertificateEnrollment
    ClientInstallation
    ClientNotification
    ClientPush
    CMG
    CMGClientTraffic
    CMGDeployments
    CMGHealth
    Co-Management
    Compliance
    ComplianceSettingsAndCompanyResourceAccess
    ConfigurationManagerConsole
    ContentDistribution
    ContentManagement
    DesktopAnalytics
    Discovery
    EndpointAnalytics
    EndpointProtection
    ExchangeServerConnector
    Extensions
    Inventory
    InventoryProcessing
    Metering
    Migration
    MobileDeviceLegacy
    MobileDevicesEnrollment
    NotificationClient
    NotificationServer
    NotificationServerInstall
    OSDeployment
    OSDeployment_clientPerspective
    PackagesAndPrograms
    PolicyProcessing
    PowerManagement
    PXE
    RemoteControl
    Reporting
    Role-basedAdministration
    SoftwareMetering
    SoftwareUpdates
    WindowsServicing
    WindowsUpdateAgent
    WOL
    WSUSServer

    .PARAMETER logName
    Name of the log(s) you want to open.
    Function itself knows where log(s) are stored, so just name is enough.

    Possible values:
    ADALOperationProvider, adctrl, ADForestDisc, adminservice, AdminUI.ExtensionInstaller, ADService, adsgdis, adsysdis, adusrdis, aikbmgr, AIUpdateSvc, AIUSMSI, AIUSSetup, AlternateHandler, AppDiscovery, AppEnforce, AppGroupHandler, AppIntentEval, AssetAdvisor, BgbHttpProxy, bgbisapiMSI, bgbmgr, BGBServer, BgbSetup, BitLockerManagementHandler, BusinessAppProcessWorker, CAS, CBS, ccm, CCM_STS, Ccm32BitLauncher, CCMAgent, CCMClient, CcmEval, CcmEvalTask, CcmExec, CcmIsapi, CcmMessaging, CcmNotificationAgent, CCMNotificationAgent, CCMNotifications, ccmperf, Ccmperf, CCMPrefPane, CcmRepair, CcmRestart, Ccmsdkprovider, CCMSDKProvider, ccmsetup, ccmsetup-ccmeval, ccmsqlce, CcmUsrCse, CCMVDIProvider, CertEnrollAgent, CertificateMaintenance, CertMgr, CIAgent, Cidm, CIDownloader, CIStateStore, CIStore, CITaskManager, CITaskMgr, client.msi, client.msi_uninstall, ClientAuth, ClientIDManagerStartup, ClientLocation, ClientServicing, CloudDP, CloudMgr, Cloudusersync, CMBITSManager, CMGContentService, CMGHttpHandler, CMGService, CMGSetup, CMHttpsReadiness, CmRcService, CMRcViewer, CollectionAADGroupSyncWorker, CollEval, colleval, CoManagementHandler, ComplRelayAgent, compmon, compsumm, ComRegSetup, ConfigMgrAdminUISetup, ConfigMgrPrereq, ConfigMgrSetup, ConfigMgrSetupWizard, ContentTransferManager, CreateTSMedia, Crp, Crpctrl, Crpmsi, Crpsetup, dataldr, Dataldr, DataTransferService, DCMAgent, DCMReporting, DcmWmiProvider, ddm, DeltaDownload, despool, Diagnostics, DISM, Dism, dism, distmgr, Distmgr, DmCertEnroll, DMCertResp.htm, DmClientHealth, DmClientRegistration, DmClientSetup, DmClientXfer, DmCommonInstaller, DmInstaller, DmpDatastore, DmpDiscovery, Dmpdownloader, DmpHardware, DmpIsapi, dmpmsi, DMPRP, DMPSetup, DmpSoftware, DmpStatus, dmpuploader, Dmpuploader, DmSvc, DriverCatalog, DWSSMSI, DWSSSetup, easdisc, EndpointConnectivityCheckWorker, EndpointProtectionAgent, enrollmentservice, enrollmentweb, EnrollSrv, enrollsrvMSI, EnrollWeb, enrollwebMSI, EPCtrlMgr, EPMgr, EPSetup, execmgr, ExpressionSolver, ExternalEventAgent, ExternalNotificationsWorker, FeatureExtensionInstaller, FileBITS, FileSystemFile, FspIsapi, fspmgr, fspMSI, FSPStateMessage, hman, Change, chmgr, Inboxast, inboxmgr, inboxmon, InternetProxy, InventoryAgent, InventoryProvider, invproc, loadstate, LocationCache, LocationServices, M365ADeploymentPlanWorker, M365ADeviceHealthWorker, M365AHandler, M365AUploadWorker, MaintenanceCoordinator, ManagedProvider, mcsexec, mcsisapi, mcsmgr, MCSMSI, Mcsperf, mcsprv, MCSSetup, Microsoft.ConfigMgrDataWarehouse, MicrosoftPolicyPlatformSetup.msi, Mifprovider, migmctrl, MP_ClientIDManager, MP_CliReg, MP_Ddr, MP_DriverManager, MP_Framework, MP_GetAuth, MP_GetPolicy, MP_Hinv, MP_Location, MP_OOBMgr, MP_Policy, MP_RegistrationManager, MP_Relay, MP_RelayMsgMgr, MP_Retry, MP_Sinv, MP_SinvCollFile, MP_Status, mpcontrol, mpfdm, mpMSI, MPSetup, mtrmgr, MVLSImport, NDESPlugin, netdisc, NotiCtrl, ntsvrdis, Objreplmgr, objreplmgr, offermgr, offersum, OfflineServicingMgr, outboxmon, outgoingcontentmanager, PatchDownloader, PatchRepair, PerfSetup, PkgXferMgr, PolicyAgent, PolicyAgentProvider, PolicyEvaluator, PolicyPlatformClient, policypv, PolicyPV, PolicySdk, PrestageContent, PullDP, Pwrmgmt, pwrmgmt, PwrProvider, rcmctrl, RebootCoordinator, replmgr, ResourceExplorer, RESTPROVIDERSetup, ruleengine, ScanAgent, scanstate, SCClient, SCNotify, Scripts, SdmAgent, sender, SensorEndpoint, SensorManagedProvider, SensorWmiProvider, ServiceConnectionTool, ServiceWindowManager, SettingsAgent, Setupact, setupact, Setupapi, Setuperr, setuppolicyevaluator, schedule, Scheduler, sinvproc, sitecomp, Sitecomp, sitectrl, sitestat, SleepAgent, smpisapi, Smpmgr, smpmsi, smpperf, SMS_AZUREAD_DISCOVERY_AGENT, SMS_BOOTSTRAP, SMS_BUSINESS_APP_PROCESS_MANAGER, SMS_Cloud_ProxyConnector, SMS_CLOUDCONNECTION, SMS_DataEngine, SMS_DM, SMS_ImplicitUninstall, SMS_ISVUPDATES_SYNCAGENT, SMS_MESSAGE_PROCESSING_ENGINE, SMS_OrchestrationGroup, SMS_PhasedDeployment, SMS_REST_PROVIDER, SmsAdminUI, smsbkup, Smsbkup, SmsClientMethodProvider, smscliui, smsdbmon, SMSdpmon, smsdpprov, smsdpusage, SMSENROLLSRVSetup, SMSENROLLWEBSetup, smsexec, SMSFSPSetup, Smsprov, SMSProv, smspxe, smssmpsetup, smssqlbkup, Smsts, smstsvc, Smswriter, SmsWusHandler, SoftwareCenterSystemTasks, SoftwareDistribution, SrcUpdateMgr, srsrp, srsrpMSI, srsrpsetup, SrvBoot, StateMessage, StateMessageProvider, statesys, Statesys, statmgr, StatusAgent, SUPSetup, swmproc, SWMTRReportGen, TaskSequenceProvider, TSAgent, TSDTHandler, UpdatesDeployment, UpdatesHandler, UpdatesStore, UserAffinity, UserAffinityProvider, UserService, UXAnalyticsUploadWorker, VCRedist_x64_Install, VCRedist_x86_Install, VirtualApp, wakeprxy-install, wakeprxy-uninstall, WCM, Wedmtrace, WindowsUpdate, wolcmgr, wolmgr, WsfbSyncWorker, WSUSCtrl, wsyncmgr, WUAHandler, WUSSyncXML


    .PARAMETER maxHistory
    How much archived logs you want to see.
    Default is 0.

    .PARAMETER SCCMServer
    Name of the SCCM server.
    Needed in case the opened log is stored on the SCCM server, not client.
    To open server side logs admin share (C$) is used, so this function has to be run with appropriate rights.

    Default is $_SCCMServer.

    .PARAMETER WSUSServer
    Name of the WSUS server.
    Needed in case the opened log is stored on the WSUS server, not client.

    If not specified value from SCCMServer parameter will be used.

    .PARAMETER serviceConnectionPointServer
    Name of the Service Connection Point server.
    Needed in case the opened log is stored on the Service Connection Point server, not client.

    If not specified value from SCCMServer parameter will be used.

    .EXAMPLE
    Get-CMLog -area ApplicationDiscovery

    Opens all logs on this computer related to application discovery.

    .EXAMPLE
    Get-CMLog -area ApplicationDiscovery -maxHistory 3

    Opens all logs on this computer related to application discovery. Including archived ones (but at maximum 3 latest for each log).

    .EXAMPLE
    Get-CMLog -computerName PC01 -area ApplicationInstallation

    Opens all logs on PC01 related to application installation.

    .EXAMPLE
    Get-CMLog -logName CcmEval, CcmExec

    Opens logs CcmEval, CcmExec.

    .EXAMPLE
    Get-CMLog -area PXE -SCCMServer SCCM01

    Opens all logs related to PXE. If such logs are stored on SCCM server they will be searched on 'SCCM01'.

    .NOTES
    To add new (problem) area:
        - add its name to ValidateSet of $area parameter
        - define what logs should be opened in $areaDetails
        - check $logDetails that it defines path where are these new logs saved

    List of all SCCM logs https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/hierarchy/log-files.
    #>

    [CmdletBinding(DefaultParameterSetName = 'area')]
    param (
        [Parameter(Position = 0)]
        [string] $computerName,

        [Parameter(Mandatory = $true, Position = 1, ParameterSetName = "area")]
        [ValidateSet('ApplicationDiscovery', 'ApplicationDownload', 'ApplicationInstallation', 'ApplicationManagement', 'ApplicationMetering', 'AssetIntelligence', 'BackupAndRecovery', 'BootImageUpdate', 'CertificateEnrollment', 'ClientInstallation', 'ClientNotification', 'ClientPush', 'CMG', 'CMGClientTraffic', 'CMGDeployments', 'CMGHealth', 'Co-Management', 'Compliance', 'ComplianceSettingsAndCompanyResourceAccess', 'ConfigurationManagerConsole', 'ContentDistribution', 'ContentManagement', 'DesktopAnalytics', 'Discovery', 'EndpointAnalytics', 'EndpointProtection', 'ExchangeServerConnector', 'Extensions', 'Inventory', 'InventoryProcessing', 'Metering', 'Migration', 'MobileDeviceLegacy', 'MobileDevicesEnrollment', 'NotificationClient', 'NotificationServer', 'NotificationServerInstall', 'OSDeployment', 'OSDeployment_clientPerspective', 'PackagesAndPrograms', 'PolicyProcessing', 'PowerManagement', 'PXE', 'RemoteControl', 'Reporting', 'Role-basedAdministration', 'SoftwareMetering', 'SoftwareUpdates', 'WindowsServicing', 'WindowsUpdateAgent', 'WOL', 'WSUSServer')]
        [Alias("problem")]
        [string] $area,

        [Parameter(Mandatory = $true, Position = 1, ParameterSetName = "logName")]
        [ValidateSet('ADALOperationProvider', 'adctrl', 'ADForestDisc', 'adminservice', 'AdminUI.ExtensionInstaller', 'ADService', 'adsgdis', 'adsysdis', 'adusrdis', 'aikbmgr', 'AIUpdateSvc', 'AIUSMSI', 'AIUSSetup', 'AlternateHandler', 'AppDiscovery', 'AppEnforce', 'AppGroupHandler', 'AppIntentEval', 'AssetAdvisor', 'BgbHttpProxy', 'bgbisapiMSI', 'bgbmgr', 'BGBServer', 'BgbSetup', 'BitLockerManagementHandler', 'BusinessAppProcessWorker', 'CAS', 'CBS', 'ccm', 'CCM_STS', 'Ccm32BitLauncher', 'CCMAgent', 'CCMClient', 'CcmEval', 'CcmEvalTask', 'CcmExec', 'CcmIsapi', 'CcmMessaging', 'CcmNotificationAgent', 'CCMNotificationAgent', 'CCMNotifications', 'ccmperf', 'Ccmperf', 'CCMPrefPane', 'CcmRepair', 'CcmRestart', 'Ccmsdkprovider', 'CCMSDKProvider', 'ccmsetup', 'ccmsetup-ccmeval', 'ccmsqlce', 'CcmUsrCse', 'CCMVDIProvider', 'CertEnrollAgent', 'CertificateMaintenance', 'CertMgr', 'CIAgent', 'Cidm', 'CIDownloader', 'CIStateStore', 'CIStore', 'CITaskManager', 'CITaskMgr', 'client.msi', 'client.msi_uninstall', 'ClientAuth', 'ClientIDManagerStartup', 'ClientLocation', 'ClientServicing', 'CloudDP', 'CloudMgr', 'Cloudusersync', 'CMBITSManager', 'CMGContentService', 'CMGHttpHandler', 'CMGService', 'CMGSetup', 'CMHttpsReadiness', 'CmRcService', 'CMRcViewer', 'CollectionAADGroupSyncWorker', 'CollEval', 'colleval', 'CoManagementHandler', 'ComplRelayAgent', 'compmon', 'compsumm', 'ComRegSetup', 'ConfigMgrAdminUISetup', 'ConfigMgrPrereq', 'ConfigMgrSetup', 'ConfigMgrSetupWizard', 'ContentTransferManager', 'CreateTSMedia', 'Crp', 'Crpctrl', 'Crpmsi', 'Crpsetup', 'dataldr', 'Dataldr', 'DataTransferService', 'DCMAgent', 'DCMReporting', 'DcmWmiProvider', 'ddm', 'DeltaDownload', 'despool', 'Diagnostics', 'DISM', 'Dism', 'dism', 'distmgr', 'Distmgr', 'DmCertEnroll', 'DMCertResp.htm', 'DmClientHealth', 'DmClientRegistration', 'DmClientSetup', 'DmClientXfer', 'DmCommonInstaller', 'DmInstaller', 'DmpDatastore', 'DmpDiscovery', 'Dmpdownloader', 'DmpHardware', 'DmpIsapi', 'dmpmsi', 'DMPRP', 'DMPSetup', 'DmpSoftware', 'DmpStatus', 'dmpuploader', 'Dmpuploader', 'DmSvc', 'DriverCatalog', 'DWSSMSI', 'DWSSSetup', 'easdisc', 'EndpointConnectivityCheckWorker', 'EndpointProtectionAgent', 'enrollmentservice', 'enrollmentweb', 'EnrollSrv', 'enrollsrvMSI', 'EnrollWeb', 'enrollwebMSI', 'EPCtrlMgr', 'EPMgr', 'EPSetup', 'execmgr', 'ExpressionSolver', 'ExternalEventAgent', 'ExternalNotificationsWorker', 'FeatureExtensionInstaller', 'FileBITS', 'FileSystemFile', 'FspIsapi', 'fspmgr', 'fspMSI', 'FSPStateMessage', 'hman', 'Change', 'chmgr', 'Inboxast', 'inboxmgr', 'inboxmon', 'InternetProxy', 'InventoryAgent', 'InventoryProvider', 'invproc', 'loadstate', 'LocationCache', 'LocationServices', 'M365ADeploymentPlanWorker', 'M365ADeviceHealthWorker', 'M365AHandler', 'M365AUploadWorker', 'MaintenanceCoordinator', 'ManagedProvider', 'mcsexec', 'mcsisapi', 'mcsmgr', 'MCSMSI', 'Mcsperf', 'mcsprv', 'MCSSetup', 'Microsoft.ConfigMgrDataWarehouse', 'MicrosoftPolicyPlatformSetup.msi', 'Mifprovider', 'migmctrl', 'MP_ClientIDManager', 'MP_CliReg', 'MP_Ddr', 'MP_DriverManager', 'MP_Framework', 'MP_GetAuth', 'MP_GetPolicy', 'MP_Hinv', 'MP_Location', 'MP_OOBMgr', 'MP_Policy', 'MP_RegistrationManager', 'MP_Relay', 'MP_RelayMsgMgr', 'MP_Retry', 'MP_Sinv', 'MP_SinvCollFile', 'MP_Status', 'mpcontrol', 'mpfdm', 'mpMSI', 'MPSetup', 'mtrmgr', 'MVLSImport', 'NDESPlugin', 'netdisc', 'NotiCtrl', 'ntsvrdis', 'Objreplmgr', 'objreplmgr', 'offermgr', 'offersum', 'OfflineServicingMgr', 'outboxmon', 'outgoingcontentmanager', 'PatchDownloader', 'PatchRepair', 'PerfSetup', 'PkgXferMgr', 'PolicyAgent', 'PolicyAgentProvider', 'PolicyEvaluator', 'PolicyPlatformClient', 'policypv', 'PolicyPV', 'PolicySdk', 'PrestageContent', 'PullDP', 'Pwrmgmt', 'pwrmgmt', 'PwrProvider', 'rcmctrl', 'RebootCoordinator', 'replmgr', 'ResourceExplorer', 'RESTPROVIDERSetup', 'ruleengine', 'ScanAgent', 'scanstate', 'SCClient', 'SCNotify', 'Scripts', 'SdmAgent', 'sender', 'SensorEndpoint', 'SensorManagedProvider', 'SensorWmiProvider', 'ServiceConnectionTool', 'ServiceWindowManager', 'SettingsAgent', 'Setupact', 'setupact', 'Setupapi', 'Setuperr', 'setuppolicyevaluator', 'schedule', 'Scheduler', 'sinvproc', 'sitecomp', 'Sitecomp', 'sitectrl', 'sitestat', 'SleepAgent', 'smpisapi', 'Smpmgr', 'smpmsi', 'smpperf', 'SMS_AZUREAD_DISCOVERY_AGENT', 'SMS_BOOTSTRAP', 'SMS_BUSINESS_APP_PROCESS_MANAGER', 'SMS_Cloud_ProxyConnector', 'SMS_CLOUDCONNECTION', 'SMS_DataEngine', 'SMS_DM', 'SMS_ImplicitUninstall', 'SMS_ISVUPDATES_SYNCAGENT', 'SMS_MESSAGE_PROCESSING_ENGINE', 'SMS_OrchestrationGroup', 'SMS_PhasedDeployment', 'SMS_REST_PROVIDER', 'SmsAdminUI', 'smsbkup', 'Smsbkup', 'SmsClientMethodProvider', 'smscliui', 'smsdbmon', 'SMSdpmon', 'smsdpprov', 'smsdpusage', 'SMSENROLLSRVSetup', 'SMSENROLLWEBSetup', 'smsexec', 'SMSFSPSetup', 'Smsprov', 'SMSProv', 'smspxe', 'smssmpsetup', 'smssqlbkup', 'Smsts', 'smstsvc', 'Smswriter', 'SmsWusHandler', 'SoftwareCenterSystemTasks', 'SoftwareDistribution', 'SrcUpdateMgr', 'srsrp', 'srsrpMSI', 'srsrpsetup', 'SrvBoot', 'StateMessage', 'StateMessageProvider', 'statesys', 'Statesys', 'statmgr', 'StatusAgent', 'SUPSetup', 'swmproc', 'SWMTRReportGen', 'TaskSequenceProvider', 'TSAgent', 'TSDTHandler', 'UpdatesDeployment', 'UpdatesHandler', 'UpdatesStore', 'UserAffinity', 'UserAffinityProvider', 'UserService', 'UXAnalyticsUploadWorker', 'VCRedist_x64_Install', 'VCRedist_x86_Install', 'VirtualApp', 'wakeprxy-install', 'wakeprxy-uninstall', 'WCM', 'Wedmtrace', 'WindowsUpdate', 'wolcmgr', 'wolmgr', 'WsfbSyncWorker', 'WSUSCtrl', 'wsyncmgr', 'WUAHandler', 'WUSSyncXML')]
        [ValidateScript( {
                If ($_ -match "\.log$") {
                    throw "Enter log name without extension (.log)"
                } else {
                    $true
                }
            })]
        [string[]] $logName,

        [ValidateRange(0, 100)]
        [int] $maxHistory = 0,

        [ValidateNotNullOrEmpty()]
        [string] $SCCMServer = $_SCCMServer,

        [string] $WSUSServer,

        [string] $serviceConnectionPointServer,

        [ValidateScript( {
                If ((Test-Path $_) -and ($_ -match "\.exe$")) {
                    $true
                } else {
                    throw "Enter path to log viewer binary (C:\apps\cmtrace.exe)"
                }
            })]
        [string] $viewer
    )

    #region prepare
    if (!$serviceConnectionPointServer -and $SCCMServer) {
        Write-Verbose "Setting serviceConnectionPointServer parameter to '$SCCMServer'"
        $serviceConnectionPointServer = $SCCMServer
    }

    if (!$WSUSServer -and $SCCMServer) {
        Write-Verbose "Setting WSUSServer parameter to '$SCCMServer'"
        $WSUSServer = $SCCMServer
    }

    #region define common folders where logs are stored
    # client's log location
    if ($computerName) {
        # client's log location
        $clientLog = "\\$computerName\C$\Windows\CCM\Logs"
        # client's setup log location
        $clientSetupLog = "\\$computerName\C$\Windows\ccmsetup\Logs"
        # Remote Control log location (stored on computer that runs Remote Control)
        $remoteControlLog = "\\$computerName\C$\Windows\Temp"
        # SCCM console log location (stored on computer that runs SCCM console)
        $sccmConsoleLog = "\\$computerName\C$\Program Files (x86)\Microsoft Endpoint Manager\AdminConsole\AdminUILog"
    } else {
        # client's log location
        $clientLog = "$env:windir\CCM\Logs"
        # client's setup log location
        $clientSetupLog = "$env:windir\ccmsetup\Logs"
        # Remote Control log location (stored on computer that runs Remote Control)
        $remoteControlLog = "$env:windir\Temp"
        # SCCM console log location (stored on computer that runs SCCM console)
        $sccmConsoleLog = "${env:ProgramFiles(x86)}\Microsoft Endpoint Manager\AdminConsole\AdminUILog"
    }
    # client's SMSTS log location
    $clientSMSTSLog = "$clientLog\SMSTSLog"


    # server's log locations
    $serverLog = "\\$SCCMServer\C$\Program Files\SMS_CCM\Logs"
    $serverLog2 = "\\$SCCMServer\C$\Program Files\Microsoft Configuration Manager\Logs"
    $serverDISMLog = "\\$SCCMServer\C$\Windows\Logs\DISM"
    $WSUSLog = "\\$WSUSServer\C$\Program Files\Update Services\LogFiles"

    # Service Connection Point location
    $serviceConnectionPointLog = "\\$serviceConnectionPointServer\C$\Program Files\Configuration Manager\Logs\M365A"
    #endregion define common folders where logs are stored

    #region define where specific logs are stored
    $logDetails = @(
        [PSCustomObject]@{
            logName   = @('AdminUI.ExtensionInstaller', 'ConfigMgrAdminUISetup', 'CreateTSMedia', 'FeatureExtensionInstaller', 'ResourceExplorer', 'SmsAdminUI')
            logFolder = $sccmConsoleLog
        },

        [PSCustomObject]@{
            logName   = @('CMRcViewer')
            logFolder = $remoteControlLog
        },

        [PSCustomObject]@{
            logName   = @('ccmsetup-ccmeval', 'ccmsetup', 'CcmRepair', 'client.msi', 'client.msi_uninstall', 'MicrosoftPolicyPlatformSetup.msi', 'PatchRepair', 'VCRedist_x64_Install', 'VCRedist_x86_Install')
            logFolder = $clientSetupLog
        },

        [PSCustomObject]@{
            logName   = @('ADALOperationProvider', 'BitLockerManagementHandler', 'CAS', 'Ccm32BitLauncher', 'CcmEval', 'CcmEvalTask', 'CcmExec', 'CcmMessaging', 'CCMNotificationAgent', 'Ccmperf', 'CcmRestart', 'CCMSDKProvider', 'ccmsqlce', 'CcmUsrCse', 'CCMVDIProvider', 'CertEnrollAgent', 'CertificateMaintenance', 'CIAgent', 'CIDownloader', 'CIStateStore', 'CIStore', 'CITaskMgr', 'ClientAuth', 'ClientIDManagerStartup', 'ClientLocation', 'ClientServicing', 'CMBITSManager', 'CMHttpsReadiness', 'CmRcService', 'CoManagementHandler', 'ComplRelayAgent', 'ContentTransferManager', 'DataTransferService', 'DCMAgent', 'DCMReporting', 'DcmWmiProvider', 'DeltaDownload', 'Diagnostics', 'EndpointProtectionAgent', 'execmgr', 'ExpressionSolver', 'ExternalEventAgent', 'FileBITS', 'FileSystemFile', 'FSPStateMessage', 'InternetProxy', 'InventoryAgent', 'InventoryProvider', 'LocationCache', 'LocationServices', 'M365AHandler', 'MaintenanceCoordinator', 'Mifprovider', 'mtrmgr', 'PolicyAgent', 'PolicyAgentProvider', 'PolicyEvaluator', 'PolicyPlatformClient', 'PolicySdk', 'Pwrmgmt', 'PwrProvider', 'SCClient', 'Scheduler', 'SCNotify', 'Scripts', 'SensorWmiProvider', 'SensorEndpoint', 'SensorManagedProvider', 'setuppolicyevaluator', 'SleepAgent', 'SmsClientMethodProvider', 'smscliui', 'SrcUpdateMgr', 'StateMessageProvider', 'StatusAgent', 'SWMTRReportGen', 'UserAffinity', 'UserAffinityProvider', 'VirtualApp', 'Wedmtrace', 'wakeprxy-install', 'wakeprxy-uninstall', 'ClientServicing', 'CCMClient', 'CCMAgent', 'CCMNotifications', 'CCMPrefPane', 'AppIntentEval', 'AppDiscovery', 'AppEnforce', 'AppGroupHandler', 'Ccmsdkprovider', 'SettingsAgent', 'SoftwareCenterSystemTasks', 'TSDTHandler', 'execmgr', 'AssetAdvisor', 'BgbHttpProxy', 'CcmNotificationAgent', 'CIAgent', 'CITaskManager', 'DCMAgent', 'DCMReporting', 'DcmWmiProvider', 'M365AHandler', 'InventoryAgent', 'SensorWmiProvider', 'SensorEndpoint', 'SensorManagedProvider', 'EndpointProtectionAgent', 'mtrmgr', 'SWMTRReportGen', 'DmCertEnroll', 'DMCertResp.htm', 'DmClientSetup', 'DmClientXfer', 'DmCommonInstaller', 'DmInstaller', 'DmSvc', 'CAS', 'ccmsetup', 'Setupact', 'Setupapi', 'Setuperr', 'smpisapi', 'TSAgent', 'loadstate', 'scanstate', 'pwrmgmt', 'AlternateHandler', 'ccmperf', 'DeltaDownload', 'PolicyEvaluator', 'RebootCoordinator', 'ScanAgent', 'SdmAgent', 'ServiceWindowManager', 'SmsWusHandler', 'StateMessage', 'UpdatesDeployment', 'UpdatesHandler', 'UpdatesStore', 'WUAHandler', 'CBS', 'DISM', 'setupact', 'WindowsUpdate')
            logFolder = $clientLog
        },

        [PSCustomObject]@{
            logName   = @('Smsts')
            logFolder = $clientSMSTSLog
        },

        [PSCustomObject]@{
            logName   = @('adctrl', 'ADForestDisc', 'adminservice', 'ADService', 'adsgdis', 'adsysdis', 'adusrdis', 'BusinessAppProcessWorker', 'ccm', 'CertMgr', 'chmgr', 'Cidm', 'CollectionAADGroupSyncWorker', 'colleval', 'compmon', 'compsumm', 'ComRegSetup', 'dataldr', 'ddm', 'despool', 'distmgr', 'EPCtrlMgr', 'EPMgr', 'EPSetup', 'EnrollSrv', 'EnrollWeb', 'ExternalNotificationsWorker', 'fspmgr', 'hman', 'Inboxast', 'inboxmgr', 'inboxmon', 'invproc', 'migmctrl', 'mpcontrol', 'mpfdm', 'mpMSI', 'MPSetup', 'netdisc', 'NotiCtrl', 'ntsvrdis', 'Objreplmgr', 'offermgr', 'offersum', 'OfflineServicingMgr', 'outboxmon', 'PerfSetup', 'PkgXferMgr', 'policypv', 'rcmctrl', 'replmgr', 'RESTPROVIDERSetup', 'ruleengine', 'schedule', 'sender', 'sinvproc', 'sitecomp', 'sitectrl', 'sitestat', 'SMS_AZUREAD_DISCOVERY_AGENT', 'SMS_BUSINESS_APP_PROCESS_MANAGER', 'SMS_DataEngine', 'SMS_ISVUPDATES_SYNCAGENT', 'SMS_MESSAGE_PROCESSING_ENGINE', 'SMS_OrchestrationGroup', 'SMS_PhasedDeployment', 'SMS_REST_PROVIDER', 'smsbkup', 'smsdbmon', 'SMSENROLLSRVSetup', 'SMSENROLLWEBSetup', 'smsexec', 'SMSFSPSetup', 'SMSProv', 'srsrpMSI', 'srsrpsetup', 'statesys', 'statmgr', 'swmproc', 'UXAnalyticsUploadWorker', 'ConfigMgrPrereq', 'ConfigMgrSetup', 'ConfigMgrSetupWizard', 'SMS_BOOTSTRAP', 'smstsvc', 'DWSSMSI', 'DWSSSetup', 'Microsoft.ConfigMgrDataWarehouse', 'FspIsapi', 'fspMSI', 'CcmIsapi', 'CCM_STS', 'ClientAuth', 'MP_CliReg', 'MP_Ddr', 'MP_Framework', 'MP_GetAuth', 'MP_GetPolicy', 'MP_Hinv', 'MP_Location', 'MP_OOBMgr', 'MP_Policy', 'MP_RegistrationManager', 'MP_Relay', 'MP_RelayMsgMgr', 'MP_Retry', 'MP_Sinv', 'MP_SinvCollFile', 'MP_Status', 'UserService', 'CollEval', 'Cloudusersync', 'Dataldr', 'Distmgr', 'Dmpdownloader', 'Dmpuploader', 'EndpointConnectivityCheckWorker', 'WsfbSyncWorker', 'objreplmgr', 'PolicyPV', 'outgoingcontentmanager', 'ServiceConnectionTool', 'Sitecomp', 'SMS_CLOUDCONNECTION', 'Smsprov', 'SrvBoot', 'Statesys', 'PatchDownloader', 'SUPSetup', 'WCM', 'WSUSCtrl', 'wsyncmgr', 'WUSSyncXML', 'PrestageContent', 'SMS_ImplicitUninstall', 'SMSdpmon', 'aikbmgr', 'AIUpdateSvc', 'AIUSMSI', 'AIUSSetup', 'ManagedProvider', 'MVLSImport', 'Smsbkup', 'smssqlbkup', 'Smswriter', 'Crp', 'Crpctrl', 'Crpsetup', 'Crpmsi', 'NDESPlugin', 'bgbmgr', 'BGBServer', 'BgbSetup', 'bgbisapiMSI', 'CloudMgr', 'CMGSetup', 'CMGService', 'SMS_Cloud_ProxyConnector', 'CMGContentService', 'CMGHttpHandler', 'CloudDP', 'DataTransferService', 'PullDP', 'smsdpprov', 'smsdpusage', 'M365ADeploymentPlanWorker', 'M365ADeviceHealthWorker', 'M365AUploadWorker', 'DMPRP', 'dmpmsi', 'DMPSetup', 'enrollsrvMSI', 'enrollmentweb', 'enrollwebMSI', 'enrollmentservice', 'SMS_DM', 'easdisc', 'DmClientHealth', 'DmClientRegistration', 'DmpDatastore', 'DmpDiscovery', 'DmpHardware', 'DmpIsapi', 'DmpSoftware', 'DmpStatus', 'Dism', 'DriverCatalog', 'mcsisapi', 'mcsexec', 'mcsmgr', 'mcsprv', 'MCSSetup', 'MCSMSI', 'Mcsperf', 'MP_ClientIDManager', 'MP_DriverManager', 'Smpmgr', 'smpmsi', 'smpperf', 'smspxe', 'smssmpsetup', 'TaskSequenceProvider', 'srsrp', 'mtrmgr', 'wolcmgr', 'wolmgr', 'Change', 'SoftwareDistribution')
            logFolder = $serverLog, $serverLog2
        },

        [PSCustomObject]@{
            logName   = @('dism')
            logFolder = $serverDISMLog
        },

        [PSCustomObject]@{
            logName   = @('Change', 'SoftwareDistribution')
            logFolder = $WSUSLog
        },

        [PSCustomObject]@{
            logName   = @('Cloudusersync', 'Dmpdownloader', 'dmpuploader', 'EndpointConnectivityCheckWorker', 'M365ADeploymentPlanWorker', 'M365ADeviceHealthWorker', 'M365AUploadWorker', 'outgoingcontentmanager', 'SMS_CLOUDCONNECTION', 'SmsAdminUI', 'SrvBoot', 'WsfbSyncWorker')
            logFolder = $serviceConnectionPointLog
        }
    )
    #endregion define where specific logs are stored

    #region get best possible log viewer
    if (!$viewer) {
        $CMLogViewer = "${env:ProgramFiles(x86)}\Microsoft Endpoint Manager\AdminConsole\bin\CMLogViewer.exe"
        $CMLogViewer2 = "${env:ProgramFiles(x86)}\Configuration Manager Support Center\CMLogViewer.exe"
        $CMPowerLogViewer = "${env:ProgramFiles(x86)}\Microsoft Endpoint Manager\AdminConsole\bin\CMPowerLogViewer.exe"
        $CMPowerLogViewer2 = "${env:ProgramFiles(x86)}\Configuration Manager Support Center\CMPowerLogViewer.exe"
        $CMTrace = "$env:windir\CCM\CMTrace.exe"

        if (Test-Path $CMLogViewer) {
            $viewer = $CMLogViewer
        } elseif (Test-Path $CMLogViewer2) {
            $viewer = $CMLogViewer2
        } elseif (Test-Path $CMPowerLogViewer) {
            $viewer = $CMPowerLogViewer
        } elseif (Test-Path $CMPowerLogViewer2) {
            $viewer = $CMPowerLogViewer2
        } elseif (Test-Path $CMTrace) {
            $viewer = $CMTrace
        }
    }
    #endregion get best possible log viewer

    #region helper functions
    function _getAndCacheLogDescription {
        $uri = "https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/hierarchy/log-files"
        Write-Verbose "Getting logs info from $uri"
        try {
            $pageContent = Invoke-WebRequest -Method GET -Uri $uri -ErrorAction Stop
        } catch {
            Write-Warning "Unable to get data from $uri. Description for the logs will not be shown."
            return
        }

        # on page some tables have 'Log Name' as column name and others have just 'Log'
        # also some logs are defined multiple times so remove duplicities
        $script:logDescription = $pageContent.ParsedHtml.getElementsByTagName('table') | % { ConvertFrom-HTMLTable $_ } | select @{n = 'LogName'; e = { if ($_.'Log Name') { ($_.'Log Name' -split "\s+")[0] } else { ($_.'Log' -split "\s+")[0] } } }, @{n = 'Description'; e = { $_.Description } } | sort -Unique -Property LogName

        # cache the results
        Write-Verbose "Caching data to '$cachedLogDescription'"
        $script:logDescription | Export-Clixml -Path $cachedLogDescription -Force
    }

    function _getLogDescription {
        param (
            [Parameter(Mandatory = $true)]
            [string[]] $logName,

            [switch] $secondRun
        )

        $logWithoutDescription = 'CMGHttpHandler', 'client.msi_uninstall'

        if ($script:logDescription) {
            if (!$secondRun) {
                Write-Host "Log(s) description #####################`n" -ForegroundColor Green
            }

            $logName | % {
                $lName = $_.trim()

                # log names on web page can be in these forms too
                # CCMAgent-<date_time>.log
                # SCClient_<domain>@<username>_1.log
                # SleepAgent_<domain>@SYSTEM_0.log
                $wantedLogDescription = $script:logDescription | ? LogName -Match "^$lName\.log$|^$lName[-_].+\.log$"

                if ($wantedLogDescription) {
                    # for better readibility output as string
                    $wantedLogDescription | % {
                        $_.LogName
                        " - " + $_.Description
                        ""
                    }
                } else {
                    if ($secondRun) {
                        Write-Warning "Unable to get description for $lName log."
                    } else {
                        if ($lName -in $logWithoutDescription) {
                            Write-Warning "For $lName there is no description."
                        } else {
                            Write-Warning "Unable to get description for $lName log. Trying to get newest data from Microsoft site"

                            _getAndCacheLogDescription

                            # try again
                            _getLogDescription $lName -secondRun # secondRun parameter to avoid infinite loop
                        }
                    }
                }
            }

            if (!$secondRun) {
                Write-Host "########################################" -ForegroundColor Green
            }
        }
    }

    function _openLog {
        param (
            [string[]] $logName
        )

        $logPath = @()

        $inaccessibleLogFolder = @()

        #region get log path
        foreach ($lName in $logName) {
            # most logs have static name but some are dynamic:
            # - CloudDP-<guid>.log
            # - SCClient_<domain>@<username>_1.log
            # - SCNotify_<domain>@<username>_1-<date_time>.log
            # - SleepAgent_<domain>@SYSTEM_0.log
            # - CCMClient-<date_time>.log
            # - CCMAgent-<date_time>.log
            # - CCMNotifications-<date_time>.log
            # - CCMPrefPane-<date_time>.log
            # - CMG-zzzxxxyyy-ProxyService_IN_0-CMGxxx.log

            Write-Verbose "Processing '$lName' log"

            if ($lName -eq 'CMRcViewer') {
                Write-Warning "Log 'CMRcViewer' is saved on the computer that runs the remote control viewer, in the %temp% folder. For sake of this function it is searched on computer defined in computerName parameter (a.k.a. $computerName)"
            }

            $logFolder = $logDetails | ? logName -Contains $lName | select -ExpandProperty logFolder
            if (!$logFolder) { throw "Undefined destination folder for log $lName. Define it inside this function in `$logDetails" }

            $wantedLog = $null

            # some logs are in multiple locations (therefore foreach)
            foreach ($lFolder in $logFolder) {
                if ($lFolder -in $inaccessibleLogFolder) {
                    Write-Verbose "Skipping inaccessible '$lFolder'"
                    continue
                }

                #region checks
                if (!$SCCMServer -and ($lFolder -in $serverLog, $serverDISMLog)) {
                    throw "You haven't specified SCCMServer parameter but log '$lName' is saved on SCCM server."
                }

                if (!$WSUSServer -and ($lFolder -in $WSUSLog)) {
                    throw "You haven't specified WSUSServer parameter but log '$lName' is saved on WSUS server."
                }

                if (!$serviceConnectionPointServer -and ($lFolder -in $serviceConnectionPointLog)) {
                    throw "You haven't specified serviceConnectionPointServer parameter but log '$lName' is saved on Service Connection Point server."
                }
                #endregion checks

                # get all possible log
                try {
                    # <log> OR <log>-<guid> OR <log>_<domain>@<username> OR <log>-<date_time> OR CMG-<tenantdata><log>
                    $regEscLog = [regex]::Escape($lName)
                    $availableLogs = Get-ChildItem $lFolder -Force -File -ErrorAction Stop | ? Name -Match "$regEscLog\.log?$|$regEscLog-[A-Z0-9-]+\.log?$|$regEscLog`_.+@.+\.log?$|$regEscLog-[0-9-]+\.log?$|CMG-.+$regEscLog" | Sort-Object LastWriteTime -Descending | Select-Object -ExpandProperty FullName
                } catch {
                    Write-Error "Unable to get logs from '$lFolder'. Error was: $_"
                    $inaccessibleLogFolder += $lFolder
                    continue
                }

                if ($availableLogs) {
                    #region add wanted log
                    # omit '.lo_' logs because they are archived logs
                    $wantedLog = $availableLogs | ? { $_ -match "\.log$" } | select -First 1

                    if ($wantedLog) {
                        Write-Verbose "`t- adding:`n'$wantedLog'"
                        $logPath += $wantedLog
                    }
                    #endregion add wanted log

                    #region add archived log(s)
                    if ($maxHistory -and $wantedLog) {
                        # $wantedLog is set means that I am searching in the right folder
                        $archivedLog = @($availableLogs | Select-Object -Skip 1 -First $maxHistory)

                        if ($archivedLog) {
                            Write-Verbose "`t- adding archive(s):`n$($archivedLog -join "`n")"
                            $logPath = @($logPath) + @($archivedLog) | Select-Object -Unique
                        } else {
                            Write-Verbose "`t- there are no archived versions"
                        }
                    }
                    #endregion add archived log(s)
                }
            }

            if (!$wantedLog) {
                Write-Warning "No '$lName' logs found in $(($logFolder | % {"'$_'"} ) -join ', ')"
            }
        }
        #endregion get log path

        #region open the log(s)
        if ($logPath) {
            if ($viewer -and $viewer -match "CMLogViewer\.exe$") {
                # open all logs in one CMLogViewer instance
                $quotedLog = ($logPath | % {
                        "`"$_`""
                    }) -join " "
                Start-Process $viewer -ArgumentList $quotedLog
            } elseif ($viewer -and $viewer -match "CMPowerLogViewer\.exe$") {
                # open all logs in one CMPowerLogViewer instance
                $quotedLog = ($logPath | % {
                        "`"$_`""
                    }) -join " "
                Start-Process $viewer -ArgumentList "--files $quotedLog"
            } else {
                # cmtrace (or notepad) don't support opening multiple logs in one instance, so open each log in separate viewer process
                foreach ($lPath in $logPath) {
                    if (!(Test-Path $lPath -ErrorAction SilentlyContinue)) {
                        continue
                    }

                    Write-Verbose "Opening $lPath"
                    if ($viewer -and $viewer -match "CMTrace\.exe$") {
                        # in case CMTrace viewer exists, use it
                        Start-Process $viewer -ArgumentList "`"$lPath`""
                    } else {
                        # use associated viewer
                        & $lPath
                    }
                }
            }
        } else {
            Write-Warning "There is no log to open"
        }
        #endregion open the log(s)
    }
    #endregion helper functions

    #region get log description from Microsoft documentation page
    $cachedLogDescription = "$env:TEMP\cachedLogDescription_8437973289.xml"
    $thresholdForGetNewData = 180
    $script:logDescription = $null

    if ((Test-Path $cachedLogDescription -ErrorAction SilentlyContinue) -and (Get-Item $cachedLogDescription).LastWriteTime -gt [datetime]::Now.AddDays(-$thresholdForGetNewData)) {
        # use cached version
        Write-Verbose "Use cached version of log information from $((Get-Item $cachedLogDescription).LastWriteTime)"
        $script:logDescription = Import-Clixml $cachedLogDescription
    } else {
        # get recent data and cache them
        try {
            _getAndCacheLogDescription
        } catch {
            Write-Warning $_
        }
    }
    #endregion get log description from Microsoft documentation page

    # hash where key is name of the area and value is hash with logs that should be opened and info that should be outputted
    # allowed keys in nested hash: log, writeHost, warningHost
    $areaDetails = @{
        "ApplicationInstallation"                    = @{
            log       = 'AppDiscovery', 'AppEnforce', 'AppIntentEval', 'Execmgr'
            writeHost = "More info at https://blogs.technet.microsoft.com/sudheesn/2011/01/31/troubleshooting-sccm-part-vi-software-distribution/"
        }

        "ApplicationDiscovery"                       = @{
            log = 'AppDiscovery'
        }

        "ApplicationDownload"                        = @{
            log       = 'DataTransferService'
            writeHost = "You can also try to run: Get-BitsTransfer -AllUsers | sort jobid | Format-List *"
        }

        "PXE"                                        = @{
            log = 'Distmgr', 'Smspxe', 'MP_ClientIDManager'
        }

        "ContentDistribution"                        = @{
            log = 'Distmgr'
        }

        "OSDeployment_clientPerspective"             = @{
            log = 'MP_ClientIDManager', 'Smsts', 'Execmgr'
        }

        "ClientInstallation"                         = @{
            log = 'Ccmsetup', 'Ccmsetup-ccmeval', 'CcmRepair', 'Client.msi', 'client.msi_uninstall'
        }

        "ClientPush"                                 = @{
            log = 'ccm'
        }

        "ApplicationMetering"                        = @{
            log = 'mtrmgr'
        }

        "Co-Management"                              = @{
            log       = 'CoManagementHandler', 'ComplRelayAgent'
            writeHost = "Check also Event Viewer: 'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin' and 'Microsoft-Windows-AAD/Operational'"
        }

        "PolicyProcessing"                           = @{
            log = 'PolicyAgent', 'CcmMessaging'
        }

        "CMG"                                        = @{
            log          = 'CloudMgr', 'SMS_CLOUD_PROXYCONNECTOR', 'CMGService', 'CMGSetup', 'CMGContentService'
            writeWarning = "CMG* logs are stored on CMG machine and periodically downloaded to SCCM server. So there can be delay (approx. 10 minutes)."
        }

        "CMGDeployments"                             = @{
            log          = 'CloudMgr', 'CMGSetup'
            writeWarning = "CMG* logs are stored on CMG machine and periodically downloaded to SCCM server. So there can be delay (approx. 10 minutes)."
        }

        "CMGHealth"                                  = @{
            log          = 'CMGService', 'SMS_Cloud_ProxyConnector'
            writeWarning = "CMG* logs are stored on CMG machine and periodically downloaded to SCCM server. So there can be delay (approx. 10 minutes)."
        }

        "CMGClientTraffic"                           = @{
            log          = 'CMGHttpHandler', 'CMGService', 'SMS_Cloud_ProxyConnector'
            writeWarning = "CMG* logs are stored on CMG machine and periodically downloaded to SCCM server. So there can be delay (approx. 10 minutes)."
        }

        "Compliance"                                 = @{
            log = 'CIAgent', 'CITaskManager', 'DCMAgent', 'DCMReporting', 'DcmWmiProvider'
        }

        "Discovery"                                  = @{
            log = 'adsgdis', 'adsysdis', 'adusrdis', 'ADForestDisc', 'ddm', 'InventoryAgent', 'netdisc'
        }

        "Inventory"                                  = @{
            log = 'InventoryAgent'
        }

        "InventoryProcessing"                        = @{
            log = 'dataldr', 'invproc', 'sinvproc'
        }

        "WOL"                                        = @{
            log = 'Wolmgr', 'WolCmgr'
        }

        "NotificationServerInstall"                  = @{
            log = 'BgbSetup', 'bgbisapiMSI'
        }

        "NotificationServer"                         = @{
            log = 'bgbmgr', 'BGBServer', 'BgbHttpProxy'
        }

        "NotificationClient"                         = @{
            log = 'CcmNotificationAgent'
        }

        "BootImageUpdate"                            = @{
            log = 'dism'
        }

        "ApplicationManagement"                      = @{
            log = 'AppIntentEval', 'AppDiscovery', 'AppEnforce', 'AppGroupHandler', 'BusinessAppProcessWorker', 'Ccmsdkprovider', 'colleval', 'WsfbSyncWorker', 'NotiCtrl', 'PrestageContent', 'SettingsAgent', 'SMS_BUSINESS_APP_PROCESS_MANAGER', 'SMS_CLOUDCONNECTION', 'SMS_ImplicitUninstall', 'SMSdpmon', 'SoftwareCenterSystemTasks', 'TSDTHandler'
        }

        "PackagesAndPrograms"                        = @{
            log = 'colleval', 'execmgr'
        }

        "AssetIntelligence"                          = @{
            log = 'AssetAdvisor', 'aikbmgr', 'AIUpdateSvc', 'AIUSMSI', 'AIUSSetup', 'ManagedProvider', 'MVLSImport'
        }

        "BackupAndRecovery"                          = @{
            log = 'ConfigMgrSetup', 'Smsbkup', 'smssqlbkup', 'Smswriter'
        }

        "CertificateEnrollment"                      = @{
            log       = 'CertEnrollAgent', 'Crp', 'Crpctrl', 'Crpsetup', 'Crpmsi', 'NDESPlugin'
            writeHost = "You can also use the following log files:`nIIS log files for Network Device Enrollment Service: %SYSTEMDRIVE%\inetpub\logs\LogFiles\W3SVC1`nIIS log files for the certificate registration point: %SYSTEMDRIVE%\inetpub\logs\LogFiles\W3SVC1`nAnd mscep.log (This file is located in the folder for the NDES account profile, for example, in C:\Users\SCEPSvc)"
        }

        "ClientNotification"                         = @{
            log = 'bgbmgr', 'BGBServer', 'BgbSetup', 'bgbisapiMSI', 'BgbHttpProxy', 'CcmNotificationAgent'
        }

        "ComplianceSettingsAndCompanyResourceAccess" = @{
            log = 'CIAgent', 'CITaskManager', 'DCMAgent', 'DCMReporting', 'DcmWmiProvider'
        }

        "ConfigurationManagerConsole"                = @{
            log = 'ConfigMgrAdminUISetup', 'SmsAdminUI', 'Smsprov'
        }

        "ContentManagement"                          = @{
            log = 'CloudDP', 'CloudMgr', 'DataTransferService', 'PullDP', 'PrestageContent', 'PkgXferMgr', 'SMSdpmon', 'smsdpprov', 'smsdpusage'
        }

        "DesktopAnalytics"                           = @{
            log = 'M365ADeploymentPlanWorker', 'M365ADeviceHealthWorker', 'M365AHandler', 'M365AUploadWorker', 'SmsAdminUI'
        }

        "EndpointAnalytics"                          = @{
            log = 'UXAnalyticsUploadWorker', 'SensorWmiProvider', 'SensorEndpoint', 'SensorManagedProvider'
        }

        "EndpointProtection"                         = @{
            log = 'EndpointProtectionAgent', 'EPCtrlMgr', 'EPMgr', 'EPSetup'
        }

        "Extensions"                                 = @{
            log = 'AdminUI.ExtensionInstaller', 'FeatureExtensionInstaller', 'SmsAdminUI'
        }

        "Metering"                                   = @{
            log = 'mtrmgr', 'SWMTRReportGen', 'swmproc'
        }

        "Migration"                                  = @{
            log = 'migmctrl'
        }

        "MobileDevicesEnrollment"                    = @{
            log = 'DMPRP', 'dmpmsi', 'DMPSetup', 'enrollsrvMSI', 'enrollmentweb', 'enrollwebMSI', 'enrollmentservice', 'SMS_DM'
        }

        "ExchangeServerConnector"                    = @{
            log = 'easdisc'
        }

        "MobileDeviceLegacy"                         = @{
            log = 'DmCertEnroll', 'DMCertResp.htm', 'DmClientHealth', 'DmClientRegistration', 'DmClientSetup', 'DmClientXfer', 'DmCommonInstaller', 'DmInstaller', 'DmpDatastore', 'DmpDiscovery', 'DmpHardware', 'DmpIsapi', 'dmpmsi', 'DMPSetup', 'DmpSoftware', 'DmpStatus', 'DmSvc', 'FspIsapi'
        }

        "OSDeployment"                               = @{
            log = 'CAS', 'ccmsetup', 'CreateTSMedia', 'Dism', 'Distmgr', 'DriverCatalog', 'mcsisapi', 'mcsexec', 'mcsmgr', 'mcsprv', 'MCSSetup', 'MCSMSI', 'Mcsperf', 'MP_ClientIDManager', 'MP_DriverManager', 'OfflineServicingMgr', 'Setupact', 'Setupapi', 'Setuperr', 'smpisapi', 'Smpmgr', 'smpmsi', 'smpperf', 'smspxe', 'smssmpsetup', 'SMS_PhasedDeployment', 'Smsts', 'TSAgent', 'TaskSequenceProvider', 'loadstate', 'scanstate'
        }

        "PowerManagement"                            = @{
            log = 'pwrmgmt'
        }

        "RemoteControl"                              = @{
            log = 'CMRcViewer'
        }

        "Reporting"                                  = @{
            log = 'srsrp', 'srsrpMSI', 'srsrpsetup'
        }

        "Role-basedAdministration"                   = @{
            log = 'hman', 'SMSProv'
        }

        "SoftwareMetering"                           = @{
            log = 'mtrmgr'
        }

        "SoftwareUpdates"                            = @{
            log = 'AlternateHandler', 'ccmperf', 'DeltaDownload', 'PatchDownloader', 'PolicyEvaluator', 'RebootCoordinator', 'ScanAgent', 'SdmAgent', 'ServiceWindowManager', 'SMS_ISVUPDATES_SYNCAGENT', 'SMS_OrchestrationGroup', 'SmsWusHandler', 'StateMessage', 'SUPSetup', 'UpdatesDeployment', 'UpdatesHandler', 'UpdatesStore', 'WCM', 'WSUSCtrl', 'wsyncmgr', 'WUAHandler'
        }

        "WindowsServicing"                           = @{
            log = 'CBS', 'DISM', 'setupact'
        }

        "WindowsUpdateAgent"                         = @{
            log = 'WindowsUpdate'
        }

        "WSUSServer"                                 = @{
            log = 'Change', 'SoftwareDistribution'
        }
    }
    #endregion prepare

    #region open corresponding logs etc
    if ($area) {
        $result = $areaDetails.GetEnumerator() | ? Key -EQ $area | select -ExpandProperty Value

        if (!$result) { throw "Undefined area '$area'" }

        $logName = $result.log | Sort-Object
    } else {
        # user have used logName parameter
    }

    Write-Warning "Opening log(s): $($logName -join ', ')"

    # output logs description
    _getLogDescription $logName

    if ($result.writeHost) { Write-Host ("`n" + $result.writeHost + "`n") }
    if ($result.writeWarning) { Write-Warning $result.writeWarning }

    # open logs
    _openLog $logName
    #endregion open corresponding logs etc
}

function Invoke-CMAdminServiceQuery {
    <#
    .SYNOPSIS
    Function for retrieving information from SCCM Admin Service REST API.
    Will connect to API and return results according to given query.
    Supports local connection and also internet through CMG.

    .DESCRIPTION
    Function for retrieving information from SCCM Admin Service REST API.
    Will connect to API and return results according to given query.
    Supports local connection and also internet through CMG.
    Use credentials with READ rights on queried source at least.
    For best performance defined filter and select parameters.

    .PARAMETER ServerFQDN
    For intranet clients
    The fully qualified domain name of the server hosting the AdminService

    .PARAMETER Source
    For specifying what information are we looking for. You can use TAB completion!
    Accept string representing the source in format <source>/<wmiclass>.
    SCCM Admin Service offers two base Source:
     - wmi = for WMI classes (use it like wmi/<className>)
        - examples:
            - wmi/ = list all available classes
            - wmi/SMS_R_System = get all systems (i.e. content of SMS_R_System WMI class)
            - wmi/SMS_R_User = get all users
     - v1.0 = for WMI classes, that were migrated to this new Source
        - example v1.0/ = list all available classes
        - example v1.0/Application = get all applications

    .PARAMETER Filter
    For filtering the returned results.
    Accept string representing the filter statement.
    Makes query significantly faster!

    Examples:
    - "name eq 'ni-20-ntb'"
    - "startswith(Name,'Drivers -')"

    Usable operators:
    any, all, cast, ceiling, concat, contains, day, endswith, filter, floor, fractionalseconds, hour, indexof, isof, length, minute, month, round, second, startswith, substring, tolower, toupper, trim, year, date, time

    https://docs.microsoft.com/en-us/graph/query-parameters

    .PARAMETER Select
    For filtering returned properties.
    Accept list of properties you want to return.
    Makes query significantly faster!

    Examples:
    - "MACAddresses", "Name"

    .PARAMETER ExternalUrl
    For internet clients
    ExternalUrl of the AdminService you wish to connect to. You can find the ExternalUrl by directly querying your CM database.
    Query: SELECT ProxyServerName,ExternalUrl FROM [dbo].[vProxy_Routings] WHERE [dbo].[vProxy_Routings].ExternalEndpointName = 'AdminService'
    It should look like this: HTTPS://<YOURCMG>.<FQDN>/CCM_Proxy_ServerAuth/<RANDOM_NUMBER>/AdminService

    .PARAMETER TenantId
    For internet clients
    Azure AD Tenant ID that is used for your CMG

    .PARAMETER ClientId
    For internet clients
    Client ID of the application registration created to interact with the AdminService

    .PARAMETER ApplicationIdUri
    For internet clients
    Application ID URI of the Configuration manager Server app created when creating your CMG.
    The default value of 'https://ConfigMgrService' should be good for most people.

    .PARAMETER BypassCertCheck
    Enabling this option will allow PowerShell to accept any certificate when querying the AdminService.
    If you do not enable this option, you need to make sure the certificate used by the AdminService is trusted by the device.

    .EXAMPLE
    Invoke-CMAdminServiceQuery -Source wmi/

    Use TAB for getting all available wmi sources.

    .EXAMPLE
    Invoke-CMAdminServiceQuery -Source v1.0/

    Use TAB for getting all available v1.0 sources.

    .EXAMPLE
    Invoke-CMAdminServiceQuery -Source "wmi/SMS_R_SYSTEM" -Filter "name eq 'ni-20-ntb'" -Select MACAddresses

    .EXAMPLE
    Invoke-CMAdminServiceQuery -Source "wmi/SMS_R_SYSTEM" -Filter "startswith(Name,'AE-')" -Select Name, MACAddresses

    .NOTES
    !!!Credits goes to author of https://github.com/CharlesNRU/mdm-adminservice/blob/master/Invoke-GetPackageIDFromAdminService.ps1 (I just generalize it and made some improvements)
    Lot of useful information https://www.asquaredozen.com/2019/02/12/the-system-center-configuration-manager-adminservice-guide
    #>

    [CmdletBinding()]
    param(
        [parameter(Mandatory = $false, HelpMessage = "Set the FQDN of the server hosting the ConfigMgr AdminService.", ParameterSetName = "Intranet")]
        [ValidateNotNullOrEmpty()]
        [string] $ServerFQDN = $_SCCMServer
        ,
        [Parameter(Mandatory = $true)]
        [ValidateScript( {
                If ($_ -match "(^wmi/)|(^v1.0/)") {
                    $true
                } else {
                    Throw "$_ is not a valid source (for example: wmi/SMS_Package or v1.0/whatever"
                }
            })]
        [ArgumentCompleter( {
                param ($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)
                $source = ($WordToComplete -split "/")[0]
                $class = ($WordToComplete -split "/")[1]
                Invoke-CMAdminServiceQuery -Source "$source/" | ? { $_.url -like "*$class*" } | select -exp url | % { "$source/$_" }
            })]
        [string] $Source
        ,
        [string] $Filter
        ,
        [string[]] $Select
        ,
        [parameter(Mandatory = $true, HelpMessage = "Set the CMG ExternalUrl for the AdminService.", ParameterSetName = "Internet")]
        [ValidateNotNullOrEmpty()]
        [string] $ExternalUrl
        ,
        [parameter(Mandatory = $true, HelpMessage = "Set your TenantID.", ParameterSetName = "Internet")]
        [ValidateNotNullOrEmpty()]
        [string] $TenantID
        ,
        [parameter(Mandatory = $true, HelpMessage = "Set the ClientID of app registration to interact with the AdminService.", ParameterSetName = "Internet")]
        [ValidateNotNullOrEmpty()]
        [string] $ClientID
        ,
        [parameter(Mandatory = $false, HelpMessage = "Specify URI here if using non-default Application ID URI for the configuration manager server app.", ParameterSetName = "Internet")]
        [ValidateNotNullOrEmpty()]
        [string] $ApplicationIdUri = 'https://ConfigMgrService'
        ,
        [parameter(Mandatory = $false, HelpMessage = "Specify the credentials that will be used to query the AdminService.", ParameterSetName = "Intranet")]
        [parameter(Mandatory = $true, HelpMessage = "Specify the credentials that will be used to query the AdminService.", ParameterSetName = "Internet")]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential] $Credential
        ,
        [parameter(Mandatory = $false, HelpMessage = "If set to True, PowerShell will bypass SSL certificate checks when contacting the AdminService.", ParameterSetName = "Intranet")]
        [parameter(Mandatory = $false, HelpMessage = "If set to True, PowerShell will bypass SSL certificate checks when contacting the AdminService.", ParameterSetName = "Internet")]
        [bool]$BypassCertCheck = $false
    )

    Begin {
        #region functions
        function Get-AdminServiceUri {
            switch ($PSCmdlet.ParameterSetName) {
                "Intranet" {
                    if (!$ServerFQDN) { throw "ServerFQDN isn't defined" }
                    Return "https://$($ServerFQDN)/AdminService"
                }
                "Internet" {
                    if (!$ExternalUrl) { throw "ExternalUrl isn't defined" }
                    Return $ExternalUrl
                }
            }
        }

        function Import-MSALPSModule {
            Write-Verbose "Checking if MSAL.PS module is available on the device."
            $MSALModule = Get-Module -ListAvailable MSAL.PS
            If ($MSALModule) {
                Write-Verbose "Module is already available."
            } Else {
                #Setting PowerShell to use TLS 1.2 for PowerShell Gallery
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

                Write-Verbose "MSAL.PS is not installed, checking for prerequisites before installing module."

                Write-Verbose "Checking for NuGet package provider... "
                If (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
                    Write-Verbose "NuGet package provider is not installed, installing NuGet..."
                    $NuGetVersion = Install-PackageProvider -Name NuGet -Force -ErrorAction Stop | Select-Object -ExpandProperty Version
                    Write-Verbose "NuGet package provider version $($NuGetVersion) installed."
                }

                Write-Verbose "Checking for PowerShellGet module version 2 or higher "
                $PowerShellGetLatestVersion = Get-Module -ListAvailable -Name PowerShellGet | Sort-Object -Property Version -Descending | Select-Object -First 1 -ExpandProperty Version
                If ((-not $PowerShellGetLatestVersion)) {
                    Write-Verbose "Could not find any version of PowerShellGet installed."
                }
                If (($PowerShellGetLatestVersion.Major -lt 2)) {
                    Write-Verbose "Current PowerShellGet version is $($PowerShellGetLatestVersion) and needs to be updated."
                }
                If ((-not $PowerShellGetLatestVersion) -or ($PowerShellGetLatestVersion.Major -lt 2)) {
                    Write-Verbose "Installing latest version of PowerShellGet..."
                    Install-Module -Name PowerShellGet -AllowClobber -Force
                    $InstalledVersion = Get-Module -ListAvailable -Name PowerShellGet | Sort-Object -Property Version -Descending | Select-Object -First 1 -ExpandProperty Version
                    Write-Verbose "PowerShellGet module version $($InstalledVersion) installed."
                }

                Write-Verbose "Installing MSAL.PS module..."
                If ((-not $PowerShellGetLatestVersion) -or ($PowerShellGetLatestVersion.Major -lt 2)) {
                    Write-Verbose "Starting another powershell process to install the module..."
                    $result = Start-Process -FilePath powershell.exe -ArgumentList "Install-Module MSAL.PS -AcceptLicense -Force" -PassThru -Wait -NoNewWindow
                    If ($result.ExitCode -ne 0) {
                        Write-Verbose "Failed to install MSAL.PS module"
                        Throw "Failed to install MSAL.PS module"
                    }
                } Else {
                    Install-Module MSAL.PS -AcceptLicense -Force
                }
            }
            Write-Verbose "Importing MSAL.PS module..."
            Import-Module MSAL.PS -Force
            Write-Verbose "MSAL.PS module successfully imported."
        }
        #endregion functions
    }

    Process {
        Try {
            #region connect Admin Service
            Write-Verbose "Processing credentials..."
            switch ($PSCmdlet.ParameterSetName) {
                "Intranet" {
                    If ($Credential) {
                        If ($Credential.GetNetworkCredential().password) {
                            Write-Verbose "Using provided credentials to query the AdminService."
                            $InvokeRestMethodCredential = @{
                                "Credential" = ($Credential)
                            }
                        } Else {
                            throw "Username provided without a password, please specify a password."
                        }
                    } Else {
                        Write-Verbose "No credentials provided, using current user credentials to query the AdminService."
                        $InvokeRestMethodCredential = @{
                            "UseDefaultCredentials" = $True
                        }
                    }

                }
                "Internet" {
                    Import-MSALPSModule

                    Write-Verbose "Getting access token to query the AdminService via CMG."
                    $Token = Get-MsalToken -TenantId $TenantID -ClientId $ClientID -UserCredential $Credential -Scopes ([String]::Concat($($ApplicationIdUri), '/user_impersonation')) -ErrorAction Stop
                    Write-Verbose "Successfully retrieved access token."
                }
            }

            If ($BypassCertCheck) {
                Write-Verbose "Bypassing certificate checks to query the AdminService."
                #Source: https://til.intrepidintegration.com/powershell/ssl-cert-bypass.html
                Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
                [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Ssl3, [Net.SecurityProtocolType]::Tls, [Net.SecurityProtocolType]::Tls11, [Net.SecurityProtocolType]::Tls12
            }
            #endregion connect Admin Service

            #region make&execute query
            $URI = (Get-AdminServiceUri) + "/" + $Source

            $Body = @{}

            if ($Filter) {
                $Body."`$filter" = $Filter
            }
            if ($Select) {
                $Body."`$select" = ($Select -join ",")
            }

            switch ($PSCmdlet.ParameterSetName) {
                'Intranet' {
                    Invoke-RestMethod -Method Get -Uri $URI -Body $Body @InvokeRestMethodCredential | Select-Object -ExpandProperty value
                }
                'Internet' {
                    $authHeader = @{
                        'Content-Type'  = 'application/json'
                        'Authorization' = "Bearer " + $token.AccessToken
                        'ExpiresOn'     = $token.ExpiresOn
                    }
                    $Packages = Invoke-RestMethod -Method Get -Uri $URI -Headers $authHeader -Body $Body | Select-Object -ExpandProperty value
                }
            }
            #endregion make&execute query
        } Catch {
            throw "Error: $($_.Exception.HResult)): $($_.Exception.Message)`n$($_.InvocationInfo.PositionMessage)"
        }
    }
}

function Invoke-CMAppInstall {
    <#
		.SYNOPSIS
			Spusti instalaci nenainstalovanych aplikaci (viditelnych v Software Center). Ale pouze pokud nevyzaduji restart mimo service window.
			Vyzaduje pripojeni na remote WMI.

		.DESCRIPTION
			Spusti instalaci nenainstalovanych aplikaci (viditelnych v Software Center). Ale pouze pokud nevyzaduji restart mimo service window.
			Vyzaduje pripojeni na remote WMI.

		.PARAMETER ComputerName
            Jmeno stroje/u kde se ma provest vynuceni insstalace.

        .PARAMETER appName
            Jmeno aplikace, jejiz instalace se ma vynutit.
            Staci cast nazvu.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = "zadej jmeno stroje/ů")]
        [Alias("c", "CN", "__Server", "IPAddress", "Server", "Computer", "Name", "SamAccountName")]
        [ValidateNotNullOrEmpty()]
        [string[]] $computerName = $env:computerName
        ,
        [Parameter(Mandatory = $false, Position = 1)]
        [string] $appName
    )

    begin {
        $appName = "*" + $appName + "*"
    }

    process {
        Write-Verbose "Will query '$($Clients.Count)' clients"
        foreach ($Computer in $Computername) {
            try {
                if (!(Test-Connection -ComputerName $Computer -Quiet -Count 1)) {
                    throw "$Computer is offline"
                } else {
                    $Params = @{
                        'Namespace' = 'root\ccm\clientsdk'
                        'Class'     = 'CCM_Application'
                    }

                    if ($Computer -notin "localhost", $env:computerName) {
                        $params.computerName = $Computer
                    }

                    $ApplicationClass = [WmiClass]"\\$Computer\root\ccm\clientSDK:CCM_Application"
                    # EvaluationState 1 je Required
                    # EvaluationState 3 je Available
                    Get-WmiObject @Params | Where-Object { $_.FullName -like $appName -and $_.InstallState -notlike "installed" -and $_.ApplicabilityState -eq "Applicable" -and $_.EvaluationState -eq 1 -and $_.RebootOutsideServiceWindow -eq $false } | % {
                        $Application = $_
                        $ApplicationID = $Application.Id
                        $ApplicationRevision = $Application.Revision
                        $ApplicationIsMachineTarget = $Application.ismachinetarget
                        $EnforcePreference = "Immediate"
                        $Priority = "high"
                        $IsRebootIfNeeded = $false

                        Write-Output "Na $computer instaluji $($application.fullname)"
                        $null = $ApplicationClass.Install($ApplicationID, $ApplicationRevision, $ApplicationIsMachineTarget, 0, $Priority, $IsRebootIfNeeded)
                        # spravne poradi parametru ziskam pomoci $ApplicationClass.GetMethodParameters("install") | select -first 1 | select -exp properties
                        #Invoke-WmiMethod -ComputerName titan02 -Class $Params.Class -Namespace $Params.Namespace -Name install -ArgumentList 0,$ApplicationID,$ApplicationIsMachineTarget,$IsRebootIfNeeded,$Priority,$ApplicationRevision
                    }
                }
            } catch {
                Write-Warning $_.Exception.Message
            }
        }
    }
}

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

function Invoke-CMComplianceEvaluation {
    <#
    .SYNOPSIS
    Function triggers evaluation of available SCCM compliance baselines.

    .DESCRIPTION
    Function triggers evaluation of available SCCM compliance baselines.
    It supports evaluation of device and user compliance policies! Users part thanks to Invoke-AsCurrentUser.
    Disadvantage is, that function returns string as output, not object, but only in case, you run it against remote computer (locally is used classic Invoke-Command).

    .PARAMETER computerName
    Default is localhost.

    .PARAMETER baselineName
    Optional parameter for filtering baselines to evaluate.

    .EXAMPLE
    Invoke-CMComplianceEvaluation

    Trigger evaluation of all compliance baselines on localhost targeted to device and user, that run this function.

    .EXAMPLE
    Invoke-CMComplianceEvaluation -computerName ae-01-pc -baselineName "KTC_compliance_policy"

    Trigger evaluation of just KTC_compliance_policy compliance baseline on ae-01-pc. But only in case, such baseline is targeted to device, not user.

    .NOTES
    Modified from https://social.technet.microsoft.com/Forums/en-US/76afbba5-065e-4809-9720-024ea05d6cee/trigger-baseline-evaluation?forum=configmanagersdk
    #>

    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline = $true)]
        [string] $computerName
        ,
        [string[]] $baselineName
    )

    #region prepare param for Invoke-AsLoggedUser
    $param = @{ReturnTranscript = $true }

    if ($baselineName) {
        $param.argument = @{baselineName = $baselineName }
    }

    if ($computerName -and $computerName -notmatch "localhost|$env:COMPUTERNAME") {
        $param.computerName = $computerName
    }
    #endregion prepare param for Invoke-AsLoggedUser

    $scriptBlockText = @'
#Start-Transcript (Join-Path $env:TEMP ((Split-Path $PSCommandPath -Leaf) + ".log"))

$Baselines = Get-CimInstance -Namespace root\ccm\dcm -Class SMS_DesiredConfiguration
ForEach ($Baseline in $Baselines) {
    $bsDisplayName = $Baseline.DisplayName
    if ($baselineName -and $bsDisplayName -notin $baselineName) {
        Write-Verbose "Skipping $bsDisplayName baseline"
        continue
    }

    $name = $Baseline.Name
    $IsMachineTarget = $Baseline.IsMachineTarget
    $IsEnforced = $Baseline.IsEnforced
    $PolicyType = $Baseline.PolicyType
    $version = $Baseline.Version

    $MC = [WmiClass]"\\localhost\root\ccm\dcm:SMS_DesiredConfiguration"

    $Method = "TriggerEvaluation"
    $InParams = $MC.psbase.GetMethodParameters($Method)
    $InParams.IsEnforced = $IsEnforced
    $InParams.IsMachineTarget = $IsMachineTarget
    $InParams.Name = $name
    $InParams.Version = $version
    $InParams.PolicyType = $PolicyType

    switch ($Baseline.LastComplianceStatus) {
        0 {$bsStatus = "Noncompliant"}
        1 {$bsStatus = "Compliant"}
        default {$bsStatus = "Noncompliant"}
    }
    "Evaluating: '$bsDisplayName' Last status: $bsStatus Last evaluated: $($Baseline.LastEvalTime)"

    $result = $MC.InvokeMethod($Method, $InParams, $null)

    if ($result.ReturnValue -eq 0) {
        Write-Verbose "OK"
    } else {
        Write-Error "There was an error.`n$result"
    }
}
'@ # end of scriptBlock text

    $scriptBlock = [Scriptblock]::Create($scriptBlockText)

    if ($param.computerName) {
        Invoke-AsLoggedUser -ScriptBlock $scriptBlock @param
    } else {
        Invoke-Command -ScriptBlock $scriptBlock
    }
}

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
        $AppID = Get-WmiObject -ComputerName $sccmServer -Namespace root\SMS\Site_$siteCode -Class SMS_PackageBaseclass -Filter "Name='$App'" | select -exp PackageID
        $distributed = Get-WmiObject -ComputerName $sccmServer -Namespace root\SMS\Site_$siteCode -Class SMS_DistributionStatus | where { $_.packageid -eq $AppID }
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
        $isUserCollection = Get-WmiObject -ComputerName $sccmServer -Namespace "root\sms\site_$siteCode" -Query "SELECT * FROM SMS_Collection where name=`"$collection`" and collectiontype = 1"

        try {
            foreach ($App in $AppName) {
                $deployed = Get-CMDeployment -SoftwareName $App -CollectionName $collection | ? {
                    if (($DeployAction -eq "Install" -and $_.DesiredConfigType -eq 1) -or ($DeployAction -eq "Uninstall" -and $_.DesiredConfigType -eq 2)) { $true } else { $false } }
                if ($deployed) {
                    Write-Warning "Application $App is already deployed to $collection collection. Skipping"
                    continue
                }

                if (!$isUserCollection) {
                    [System.Collections.ArrayList] $appCategory = @(Get-WmiObject -ComputerName $sccmServer -Namespace "root\sms\site_$siteCode" -Query "SELECT LocalizedCategoryInstanceNames FROM SMS_Application WHERE LocalizedDisplayName = `'$App`' AND IsLatest = 1" | select -exp LocalizedCategoryInstanceNames)
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
                    [System.Collections.ArrayList] $appCategory = @(Get-WmiObject -ComputerName $sccmServer -Namespace "root\sms\site_$siteCode" -Query "SELECT LocalizedCategoryInstanceNames FROM SMS_Application WHERE LocalizedDisplayName = `'$App`' AND IsLatest = 1" | select -exp LocalizedCategoryInstanceNames)

                    # zjistim jestli jde o placeny SW
                    $licensedApp = ''
                    if ($appCategory -contains $licensedCategory) {
                        $licensedApp = 'Y' #Get-WmiObject -computername $sccmServer -Namespace "root\sms\site_$siteCode" -query "SELECT LocalizedDisplayName FROM SMS_Application WHERE LocalizedDisplayName = `'$App`' AND LocalizedCategoryInstanceNames = `'$licensedCategory`'"
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
                            [System.Collections.ArrayList] $appCategory = @(Get-WmiObject -ComputerName $sccmServer -Namespace "root\sms\site_$siteCode" -Query "SELECT LocalizedCategoryInstanceNames FROM SMS_Application WHERE LocalizedDisplayName = `'$App`' AND IsLatest = 1" | select -exp LocalizedCategoryInstanceNames)

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
                $apps = Get-WmiObject -Namespace "root\sms\site_$siteCode" -ComputerName $sccmServer -Query "SELECT * FROM SMS_ApplicationAssignment WHERE CollectionName = `'$collection`' and ApplicationName = `'$App`'"
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
        $AppID = Get-WmiObject -ComputerName $sccmServer -Namespace root\SMS\Site_$siteCode -Class SMS_PackageBaseclass -Filter "Name='$App'" | select -exp PackageID
        $distributed = Get-WmiObject -ComputerName $sccmServer -Namespace root\SMS\Site_$siteCode -Class SMS_DistributionStatus | where { $_.packageid -eq $AppID }
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

function Refresh-CMCollection {
    <#
    .SYNOPSIS
    Function for forcing full membership update on selected (all) device collection(s).

    .DESCRIPTION
    Function for forcing full membership update on selected (all) device collection(s).
    Before membership update, full AD discovery is being run.

    .PARAMETER collectionName
    Name of collection(s) you want to refresh.
    If not specified all device collections will be refreshed.

    .EXAMPLE
    Refresh-CMCollection

    Runs full AD discovery and than updates membership of all device collections.

    .EXAMPLE
    Refresh-CMCollection -collectionName _workstations

    Runs full AD discovery and than updates membership of _workstations collection.
    #>

    [CmdletBinding()]
    param ([string[]] $collectionName)

    # connect to SCCM
    Connect-SCCM -ea Stop

    # run AD discovery
    Invoke-CMGroupDiscovery
    Invoke-CMSystemDiscovery

    "Wait one minute so AD discovery has time to finish"
    Start-Sleep 60

    # update collection(s) membership
    if (!$collectionName) {
        Write-Verbose "Getting device collections"
        $collectionName = Get-CMDeviceCollection | select -exp Name
    }
    $collectionName | % {
        Write-Verbose "Updating collection '$_'"
        Invoke-CMCollectionUpdate -Name $_ -Confirm:$false
    }
}

function Set-CMDeviceDJoinBlobVariable {
    <#
    .SYNOPSIS
    Function for enabling Offline Domain Join in OSD process of given computer.

    .DESCRIPTION
    Function for enabling Offline Domain Join in OSD process of given computer.

    It will:
     - create Offline Domain Join blob using djoin.exe
     - save resultant blob content as computer variable DJoinBlob
        - so it can be used during OSD for domain join

    When the computer connects eventually to one of the DCs. It will automatically reset its password. So generated djoin blob will be invalidated (it contains password, that is being set, when computer joins the domain).

    .PARAMETER computerName
    Name of the computer, that should be joined to domain during the OSD.

    It doesn't matter, what name it actually has, it will be changed, to this one!

    .PARAMETER ou
    OU where should be computer placed (in case it doesn't already exists in AD).

    .PARAMETER reuse
    Switch that has to be used in case, such computer already exists in AD.

    Its password will be immediately reset!!!

    .PARAMETER domainName
    Name of domain.

    .EXAMPLE
    Set-CMDeviceDJoinBlobVariable -computerName PC-1 -reuse

    Function will generate offline domain join blob for joining computer PC-1.
    This blob will be saved as Task Sequence Variable in properties of given computer.
    In case computer already exists in AD, its password will be immediately reset.

    .NOTES
    # jak dat do unattend souboru https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/dd392267(v=ws.10)?redirectedfrom=MSDN#offline-domain-join-process-and-djoinexe-syntax
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $computerName,

        [ValidateScript( {
                If (Get-ADOrganizationalUnit -Filter "distinguishedname -eq '$_'") {
                    $true
                } else {
                    Throw "$_ is not a valid OU distinguishedName."
                }
            })]
        [string] $ou,

        [switch] $reuse,

        [string] $domainName = $domainName
    )

    process {
        $adComputer = Get-ADComputer -Filter "name -eq '$computerName'" -Properties Name, Enabled, DistinguishedName -ErrorAction Stop

        #region checks
        if ($reuse -and $adComputer -and $adComputer.Enabled) {
            Write-Warning "Reuse parameter will immediately reset $computerName AD password!"
            $choice = ""
            while ($choice -notmatch "^[Y|N]$") {
                $choice = Read-Host "Continue? (Y|N)"
            }
            if ($choice -eq "N") {
                break
            }
        }

        if (!$adComputer -and !$ou) {
            do {
                $ou = Read-Host "Computer $computerName doesn't exist. Enter existing OU distinguishedName, where it should be created"
            } while (!(Get-ADOrganizationalUnit -Filter "distinguishedname -eq '$ou'"))
        }

        if ($adComputer -and !$reuse) {
            throw "$computerName already exists in AD so 'reuse' parameter has to be used!"
        }

        Connect-SCCM -commandName Get-CMDeviceVariable, Remove-CMDeviceVariable, New-CMDeviceVariable, Get-CMDevice

        $device = Get-CMDevice -Name $computerName
        if (!$device) { throw "$computerName isn't in SCCM database" }
        if ($device.count -gt 1) { throw "There are $($device.count) devices in SCCM database with name $computerName" }
        #endregion checks

        #region create djoin connection blob
        "Creating djoin connection blob"
        $blobFile = (Get-Random)
        # /reuse provede reset computer hesla!
        # /rootcacerts /certtemplate "WorkstationAuthentication-PrimaryTPM"
        $djoinArgument = "/provision /domain $domainName /machine $computerName /savefile $blobFile /printblob"
        if ($reuse) { $djoinArgument += " /reuse" }
        if ($ou) { $djoinArgument += " /machineou $ou" }

        $djoin = Start-Process2 "$env:windir\system32\djoin.exe" -argumentList $djoinArgument

        if (!($djoin -match "The operation completed successfully")) {
            throw $djoin
        }

        # I don't need this file
        Remove-Item $blobFile -Force

        # Get the blob
        $djoinBlob = ($djoin -split "`n")[6].trim()
        if ($djoinBlob -notmatch "=$") { throw "$djoinBlob is not valid djoin blob" }
        #endregion create djoin connection blob

        #region customize SCCM Device DJoinBlob TS Variable
        # variable name that should contain djoin blob for offline domain join
        $variableName = "DJoinBlob"

        "Setting variable '$variableName' for SCCM device $computerName"

        # !Get-CMDeviceVariable is case insensitive, but Set-CMDeviceVariable isn't! therefore I use existing name, just in case
        if ($foundVariableName = Get-CMDeviceVariable -DeviceName $computerName -VariableName $variableName | select -ExpandProperty Name) {
            # variable already exists, delete
            $variableName = $foundVariableName
            Remove-CMDeviceVariable -DeviceName $computerName -VariableName $variableName -Force
        }

        New-CMDeviceVariable -DeviceName $computerName -VariableName $variableName -VariableValue $djoinBlob | Out-Null #-IsMask $true
        #endregion customize SCCM Device DJoinBlob TS Variable
    }

    end {
        Write-Warning "You can use this blob to join any computer, but $computerName will be new computer name, no matter what name computer already has"
    }
}

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

function Update-CMClientPolicy {
    <#
    .SYNOPSIS
    Function for invoking update of SCCM client policy.

    .DESCRIPTION
    Function for invoking update of SCCM client policy.

    .PARAMETER computerName
    Name of the computer where you want to make update.

    .PARAMETER evaluateBaseline
    Switch for invoking evaluation of compliance policies.

    .PARAMETER resetPolicy
    Switch for resetting policies (Machine Policy Agent Cleanup).
    #>

    [cmdletbinding()]
    [Alias("Invoke-CMClientPolicyUpdate")]
    Param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $True, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string[]]$computerName = $env:COMPUTERNAME
        ,
        [switch] $evaluateBaseline
        ,
        [switch] $resetPolicy
    )

    BEGIN {
        if ($env:COMPUTERNAME -in $computerName) {
            if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
                throw "Run with administrator rights!"
            }
        }

        $allFunctionDefs = "function Invoke-CMComplianceEvaluation { ${function:Invoke-CMComplianceEvaluation} }"
    }

    PROCESS {

        $param = @{
            scriptBlock  = {
                param ($resetPolicy, $evaluateBaseline, $allFunctionDefs)

                $ErrorActionPreference = 'stop'
                # list of triggers https://blogs.technet.microsoft.com/charlesa_us/2015/03/07/triggering-configmgr-client-actions-with-wmic-without-pesky-right-click-tools/
                try {
                    foreach ($functionDef in $allFunctionDefs) {
                        . ([ScriptBlock]::Create($functionDef))
                    }

                    if ($resetPolicy) {
                        $null = ([wmiclass]'ROOT\ccm:SMS_Client').ResetPolicy(1)
                        # invoking Machine Policy Agent Cleanup
                        $null = Invoke-WmiMethod -Class SMS_client -Namespace "root\ccm" -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000040}"
                        Start-Sleep -Seconds 5
                    }
                    # invoking receive of computer policies
                    $null = Invoke-WmiMethod -Class SMS_client -Namespace "root\ccm" -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000021}"
                    Start-Sleep -Seconds 1
                    # invoking Machine Policy Evaluation Cycle
                    $null = Invoke-WmiMethod -Class SMS_client -Namespace "root\ccm" -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000022}"
                    if (!$resetPolicy) {
                        # after hard reset I have to wait a little bit before this method can be used again
                        Start-Sleep -Seconds 5
                        # invoking Application Deployment Evaluation Cycle
                        $null = Invoke-WmiMethod -Class SMS_client -Namespace "root\ccm" -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000121}"
                    }

                    # invoke evaluation of compliance policies
                    if ($evaluateBaseline) {
                        Invoke-CMComplianceEvaluation
                    }

                    Write-Output "Policy update started on $env:COMPUTERNAME"
                } catch {
                    throw "$env:COMPUTERNAME is probably missing SCCM client.`n`n$_"
                }
            }

            ArgumentList = $resetPolicy, $evaluateBaseline, $allFunctionDefs
        }
        if ($computerName -and $computerName -notin "localhost", $env:COMPUTERNAME) {
            $param.computerName = $computerName
        }

        Invoke-Command @param
    }

    END {
        if ($resetPolicy) {
            Write-Warning "Is is desirable to run Update-CMClientPolicy again after a few minutes to get new policies ASAP"
        }
    }
}

Export-ModuleMember -function Add-CMDeviceToCollection, Clear-CMClientCache, Connect-SCCM, Get-CMAppDeploymentStatus, Get-CMApplicationOGV, Get-CMAutopilotHash, Get-CMCollectionComplianceStatus, Get-CMCollectionOGV, Get-CMComputerCollection, Get-CMComputerComplianceStatus, Get-CMDeploymentStatus, Get-CMLog, Invoke-CMAdminServiceQuery, Invoke-CMAppInstall, Invoke-CMClientReinstall, Invoke-CMComplianceEvaluation, New-CMAppDeployment, New-CMAppPhasedDeploment, New-CMDevice, Refresh-CMCollection, Set-CMDeviceDJoinBlobVariable, Set-CMDeviceSerialNumber, Update-CMAppSourceContent, Update-CMClientPolicy

Export-ModuleMember -alias Invoke-CMAppDeployment, Invoke-CMAppPhasedDeployment, Invoke-CMClientPolicyUpdate, Set-CMDeviceServiceTag
