function Get-IntuneScriptContent {
    <#
    .SYNOPSIS
    Function for getting content of the (non-remediation) scripts deployed from Intune MDM to this computer.

    Unfortunately scripts has to be reapplied on the client, so take that into account! Only during this time, it is possible to copy the scripts content.

    .DESCRIPTION
    Function for getting content of the (non-remediation) scripts deployed from Intune MDM to this computer.

    Unfortunately scripts has to be reapplied on the client, so take that into account! Only during this time, it is possible to copy the scripts content.

    Data are gathered by:
     - forcing redeploy of Intune scripts (so we can capture them)
     - watching folder where Intune temporarily stores scripts before they are being run ("C:\Program Files (x86)\Microsoft Intune Management Extension\Policies\Scripts") and by copying them to user TEMP location for further processing
     - output the results as PS object

    .PARAMETER force
    Switch for skipping warning about redeploying Intune scripts.

    .EXAMPLE
    Get-IntuneScriptContent

    Redeploy all Intune scripts to this client, capture their content during this time and return it as an PowerShell objects.
    #>

    [CmdletBinding()]
    param (
        [switch] $force
    )

    # base variables
    $jobName = "Intune_Script_Copy_" + (Get-Date).ToString('HH:mm.ss')
    $tmpFolder = "$env:TEMP\intune_script_copy" # if modified, change also in Invoke-FileSystemWatcher Action parameter!

    if (!$force) {
        Write-Warning "All (non-remediation) scripts deployed from Intune will be reapplied! (this is the only way to get their content on the client side unfortunately)"

        $choice = ""
        while ($choice -notmatch "^[Y|N]$") {
            $choice = Read-Host "Do you really want to continue? (Y|N)"
        }
        if ($choice -eq "N") {
            return
        }
    }

    if (Test-Path $tmpFolder -ErrorAction SilentlyContinue) {
        # cleanup
        Remove-Item $tmpFolder -Recurse -Force -ErrorAction Stop
    }

    $null = New-Item -Path $tmpFolder -ItemType Directory

    # monitor & copy applied Intune scripts
    Write-Warning "Starting Intune script monitor&copy job ($jobName)"
    $null = Start-Job -Name $jobName {
        Invoke-FileSystemWatcher -PathToMonitor "C:\Program Files (x86)\Microsoft Intune Management Extension\Policies\Scripts" -ChangeType Created -Filter "*.ps1" -Action {
            $tmpFolder = "$env:TEMP\intune_script_copy" # has to be hardcoded :(

            $details = $event.SourceEventArgs
            $name = $details.Name -replace "\.ps1"
            $fullPath = $details.FullPath

            # Write-Host "Copying $name '$fullPath' to '$tmpFolder'"
            Copy-Item $fullPath $tmpFolder -Force
        }
    }

    # force Intune scripts redeployment
    if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Warning "You are not running this function as administrator. Redeploy of Intune scripts cannot be forced. Just new deployments processed in background will be captured!"
    } else {
        Write-Warning "Forcing redeploy of Intune scripts"
        Invoke-IntuneScriptRedeploy -scriptType script -all -WarningVariable redeployWarningMsg

        if ($redeployWarningMsg -match "No deployed scripts detected") {
            Write-Warning "Previous warning could be caused by running this function or 'Invoke-IntuneScriptRedeploy' in last few minutes. If this is the case, WAIT. If it is no, there are probably no Intune scripts deployed to your computer and you can cancel this function via CTRL + C shortcut."
            #TODO remove job $jobName in case user use CTRL + C
        }
    }

    # wait for Intune scripts processing to finish
    Write-Warning "Waiting for the completion of Intune scripts redeploy (this can take several minutes!)"
    $null = Invoke-FileContentWatcher -path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\AgentExecutor.log" -searchString "Agent executor completed." -stopOnFirstMatch

    # stop copying job because all scripts were already processed
    Write-Verbose "Removing Intune script copy job"
    $result = Get-Job -Name $jobName | Receive-Job
    Get-Job -Name $jobName | Remove-Job -Force

    #region process & output copied Intune scripts
    $intuneScript = Get-ChildItem $tmpFolder -File -Filter "*.ps1" | select -ExpandProperty FullName

    if (!$intuneScript) {
        throw "Script copy job haven't processed any scripts. Job output was: $result"
    }

    $intuneScript | % {
        $scriptPath = $_

        # script name is in format '<scope>_<scriptid>.ps1'
        $scriptFileName = (Split-Path $scriptPath -Leaf) -replace "\.ps1$"
        $scope = ($scriptFileName -split "_")[0]
        $scriptId = ($scriptFileName -split "_")[1]

        [PSCustomObject]@{
            Id      = $scriptId
            Scope   = $scope
            Content = Get-Content $scriptPath -Raw
        }
    }
    #endregion process & output copied Intune scripts

    # cleanup
    Write-Verbose "Removing folder '$tmpFolder'"
    Remove-Item $tmpFolder -Recurse -Force
}