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