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