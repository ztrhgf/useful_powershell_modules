function Get-PSHScriptBlockLoggingEvent {
    <#
    .SYNOPSIS
    Function returns commands that was run in PowerShell, captured using "PowerShell Script Block logging" feature. Moreover it enhances such data with context, like how the parent PowerShell process was called, by whom, when it started/ended, whether it was local/remote session, whether it was Windows PowerShell or PowerShell Core and what scripts was being run during the session.

    .DESCRIPTION
    Function returns commands that was run in PowerShell, captured using "PowerShell Script Block logging" feature. Moreover it enhances such data with context, like how the parent PowerShell process was called, by whom, when it started/ended, whether it was local/remote session, whether it was Windows PowerShell or PowerShell Core and what scripts was being run during the session.

    To get all possible context information these event logs are used:
        - 'Microsoft-Windows-PowerShell/Operational'(for Windows PowerShell)
        - 'PowerShellCore/Operational' (for PowerShell Core)
        - 'Microsoft-Windows-WinRM/Operational'
        - 'Windows PowerShell'

    How this functions works:
    - start/stop session events are gathered
        - such data contains additional context, like who and how run the PSH session
        - stop events are found using unique hostId that is same as for start event
    - Script Block logging events are gathered and grouped by machineName and ProcessId
    - For each ProcessId is found related start/stop data
        - because start/stop events doesn't contain called ProcessId, the closest one is picked
    - Merged result is returned sorted by session start time

    Function gathers these events:
    - Script Block logging events that contain content of the invoked commands:
        - log 'Microsoft-Windows-PowerShell/Operational', event '4104' (for Windows PowerShell)
        - log 'PowerShellCore/Operational', event '4104' (for PowerShell Core)
    - Script Block logging events that contain start of the invoked PSH session:
        Contains just start time without any additional information like who and how the sessions started, so additional data has to be gathered.
        - log 'Microsoft-Windows-PowerShell/Operational', event '40961' (for Windows PowerShell)
        - log 'PowerShellCore/Operational', event '40961' (for PowerShell Core)
    - WinRM events that contain winrm remote session start:
        Contains start time of the session, who and from which host started it.
        - log 'Microsoft-Windows-WinRM/Operational', event 91
    - Windows PowerShell events that contain details about started session:
        Contains how the session was invoked and by whom and is logged few milliseconds (or seconds :D) after 40961 event.
        Unfortunately doesn't contain any unique identifier to correlate this event with 40961. So the closest event is picked as the right one.
        - log 'Windows PowerShell', event 400
    - Windows PowerShell events that contain end of the invoked PSH session:
        Contains when the session ended and can be found through unique hostid that is same as for session start event (400)
        - log 'Windows PowerShell', event 403

    Unfortunately PowerShell Core doesn't log 400, 403 events at all, so there are no additional data (how it was invoked and when it ended) available.

    Function supports searching through local event logs, logs from remote computer (exported as evtx files) or forwarded events (saved in special ForwardedEvents event log).

    Function supports reading of protected (encrypted) events if decryption certificate (with private key) is stored in certificate personal store.

    Searched event logs can be defined via name or path to evtx file.

    .PARAMETER startTime
    Start time from which Script Block logging events should be searched.

    By default a day ago from now.

    .PARAMETER endTime
    End time to which Script Block logging events should be searched.

    By default now.

    .PARAMETER microsoftWindowsPowerShellOperational_LogName
    By default "Microsoft-Windows-PowerShell/Operational".

    .PARAMETER powerShellCoreOperational_LogName
    By default "PowerShellCore/Operational".

    .PARAMETER windowsPowerShell_LogName
    By default "Windows PowerShell".

    .PARAMETER microsoftWindowsWinRM_LogName
    By default "Microsoft-Windows-WinRM/Operational".

    .PARAMETER microsoftWindowsPowerShellOperational_LogPath
    Path to saved evtx file of the "Microsoft-Windows-PowerShell/Operational" event log.

    .PARAMETER powerShellCoreOperational_LogPath
    Path to saved evtx file of the "PowerShellCore/Operational" event log.

    .PARAMETER windowsPowerShell_LogPath
    Path to saved evtx file of the "Windows PowerShell" event log.

    .PARAMETER microsoftWindowsWinRM_LogPath
    Path to saved evtx file of the "Microsoft-Windows-WinRM/Operational" event log.

    .PARAMETER machineName
    Name of the computer you want to get events for.
    Make sense to use if forwarded events from multiple computers are searched.

    .PARAMETER contextEventsStartTime
    Start time for searching helper events.

    By default value of startTime parameter minus one day.

    .PARAMETER contextEventsEndTime
    End time for searching helper events.

    By default value of endTime parameter plus one day.

    .PARAMETER PSHType
    What type of sessions should be searched.

    Possible values: "WindowsPowerShell", "PowerShellCore"

    By default both PSH types are searched.

    .PARAMETER omitScriptBlockLoggingStatusCheck
    Switch for skipping check that Script Block logging is enabled & proposing enablement.

    .EXAMPLE
    Get-PSHScriptBlockLoggingEvent

    Get PSH Script Block logging events from this computer events log.
    Events for past 24 hours will be searched.

    .EXAMPLE
    Get-PSHScriptBlockLoggingEvent -startTime "7.8.2023 9:00" -endTime "10.8.2023 15:00"

    Get PSH Script Block logging events from this computer events log.
    Events for given time span will be searched.

    .EXAMPLE
    Get-PSHScriptBlockLoggingEvent -MicrosoftWindowsPowerShellOperational_LogName ForwardedEvents -WindowsPowerShell_LogName ForwardedEvents -powerShellCoreOperational_LogName ForwardedEvents -microsoftWindowsWinRM_LogName ForwardedEvents -machineName pc-01.contoso.com

    Get PSH Script Block logging events from forwarded events log (using log name) for computer 'pc-01.contoso.com'.

    .EXAMPLE
    Get-PSHScriptBlockLoggingEvent -MicrosoftWindowsPowerShellOperational_LogPath "C:\CapturedLogs\Microsoft-Windows-PowerShell%4Operational.evtx" -WindowsPowerShell_LogPath "C:\CapturedLogs\Windows PowerShell.evtx" -microsoftWindowsWinRM_LogPath "C:\CapturedLogs\Microsoft-Windows-WinRM%4Operational.evtx" -PSHType WindowsPowerShell

    Get Windows PowerShell Script Block logging events from given evtx files.

    .NOTES
    Returned data don't have to be 100% accurate! Unfortunately there is no unique identifier used across related events for grouping them, so there has to be some guessing.

    What makes this thing even more difficult is that
    - PSH start events are sometimes NOT logged at all
    - PSH session ProcessId is being reused quite often

    Commands invoked via PowerShell version older than 5.x won't be shown (because don't support Script Block logging)!
    You can search such invokes via:
    Get-WinEvent -LogName "Windows PowerShell" |
    Where-Object Id -EQ 400 |
    ForEach-Object {
        $version = [Version] (
            $_.Message -replace '(?s).*EngineVersion=([\d\.]+)*.*', '$1')
        if ($version -lt ([Version] "5.0")) { $_ }
    }

    https://nsfocusglobal.com/attack-and-defense-around-powershell-event-logging/
    #>

    [CmdletBinding(DefaultParameterSetName = 'LogName')]
    param (
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                if (($_.getType().name -eq "string" -and [DateTime]::Parse($_)) -or ($_.getType().name -eq "dateTime")) {
                    $true
                } else {
                    throw "Enter in format per your culture. For cs-CZ: 15.2.2019 15:00. For en-US: 2.15.2019 15:00."
                }
            })]
        $startTime = ([datetime]::Now).addDays(-1),

        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                if (($_.getType().name -eq "string" -and [DateTime]::Parse($_)) -or ($_.getType().name -eq "dateTime")) {
                    $true
                } else {
                    throw "Enter in format per your culture. For cs-CZ: 15.2.2019 15:00. For en-US: 2.15.2019 15:00."
                }
            })]
        $endTime = [datetime]::Now,

        [Parameter(Mandatory = $false, ParameterSetName = "LogName")]
        [string] $microsoftWindowsPowerShellOperational_LogName = "Microsoft-Windows-PowerShell/Operational",

        [Parameter(Mandatory = $false, ParameterSetName = "LogName")]
        [string] $powerShellCoreOperational_LogName = "PowerShellCore/Operational",

        [Parameter(Mandatory = $false, ParameterSetName = "LogName")]
        [string] $windowsPowerShell_LogName = "Windows PowerShell",

        [Parameter(Mandatory = $false, ParameterSetName = "LogName")]
        [string] $microsoftWindowsWinRM_LogName = "Microsoft-Windows-WinRM/Operational",

        [Parameter(Mandatory = $false, ParameterSetName = "LogPath")]
        [ValidateScript( {
                if ((Test-Path -Path $_) -and ($_ -like "*.evtx")) {
                    $true
                } else {
                    throw "$_ doesn't exist or it is not an event log EVTX file"
                }
            })]
        [string] $microsoftWindowsPowerShellOperational_LogPath,

        [Parameter(Mandatory = $false, ParameterSetName = "LogPath")]
        [ValidateScript( {
                if ((Test-Path -Path $_) -and ($_ -like "*.evtx")) {
                    $true
                } else {
                    throw "$_ doesn't exist or it is not an event log EVTX file"
                }
            })]
        [string] $powerShellCoreOperational_LogPath,

        [Parameter(Mandatory = $false, ParameterSetName = "LogPath")]
        [ValidateScript( {
                if ((Test-Path -Path $_) -and ($_ -like "*.evtx")) {
                    $true
                } else {
                    throw "$_ doesn't exist or it is not an event log EVTX file"
                }
            })]
        [string] $windowsPowerShell_LogPath,

        [Parameter(Mandatory = $false, ParameterSetName = "LogPath")]
        [ValidateScript( {
                if ((Test-Path -Path $_) -and ($_ -like "*.evtx")) {
                    $true
                } else {
                    throw "$_ doesn't exist or it is not an event log EVTX file"
                }
            })]
        [string] $microsoftWindowsWinRM_LogPath,

        [string[]] $machineName,

        [ValidateScript({
                if (($_.getType().name -eq "string" -and [DateTime]::Parse($_)) -or ($_.getType().name -eq "dateTime")) {
                    $true
                } else {
                    throw "Enter in format per your culture. For cs-CZ: 15.2.2019 15:00. For en-US: 2.15.2019 15:00."
                }
            })]
        $contextEventsStartTime,

        [ValidateScript({
                if (($_.getType().name -eq "string" -and [DateTime]::Parse($_)) -or ($_.getType().name -eq "dateTime")) {
                    $true
                } else {
                    throw "Enter in format per your culture. For cs-CZ: 15.2.2019 15:00. For en-US: 2.15.2019 15:00."
                }
            })]
        $contextEventsEndTime,

        [ValidateNotNullOrEmpty()]
        [ValidateSet("WindowsPowerShell", "PowerShellCore")]
        [string[]] $PSHType = @("WindowsPowerShell", "PowerShellCore"),

        [switch] $omitScriptBlockLoggingStatusCheck
    )

    #region prepare
    if ($startTime -and $startTime.getType().name -eq "string") { $startTime = [DateTime]::Parse($startTime) }
    if ($endTime -and $endTime.getType().name -eq "string") { $endTime = [DateTime]::Parse($endTime) }
    if ($contextEventsStartTime -and $contextEventsStartTime.getType().name -eq "string") { $contextEventsStartTime = [DateTime]::Parse($contextEventsStartTime) }
    if ($contextEventsEndTime -and $contextEventsEndTime.getType().name -eq "string") { $contextEventsEndTime = [DateTime]::Parse($contextEventsEndTime) }

    if ($startTime -and $endTime -and $startTime -gt $endTime) {
        throw "'startTime' cannot be after 'endTime'"
    }

    if ($startTime -gt [DateTime]::Now) {
        throw "'startTime' cannot be in the future"
    }

    if (!$contextEventsStartTime) {
        $contextEventsStartTime = $startTime.addDays(-1)
        Write-Verbose "'contextEventsStartTime' not defined. Set it to $contextEventsStartTime"
    }

    if (!$contextEventsEndTime) {
        $contextEventsEndTime = $endTime.addDays(1)
        Write-Verbose "'contextEventsEndTime' not defined. Set it to $contextEventsEndTime"
    }

    if ($contextEventsStartTime -ge $startTime) {
        throw "'contextEventsStartTime' has to have date older than 'startTime'"
    }

    if ($contextEventsEndTime -le $endTime) {
        throw "'contextEventsEndTime' has to have later date than 'startTime'"
    }

    if (!$startTime -or !$endTime -or !$contextEventsStartTime -or !$contextEventsEndTime) {
        throw "Some parameter value is missing! All 'startTime', 'endTime', 'contextEventsStartTime' and 'contextEventsEndTime' need to have a value."
    }
    #endregion prepare

    Write-Warning "Searching for Script Block logging events created between '$startTime' and '$endTime' and helper events between '$contextEventsEndTime' and '$contextEventsEndTime'"

    #region checks
    # check that all or none log related parameters were modified
    $logParam = "microsoftWindowsPowerShellOperational_LogName", "powerShellCoreOperational_LogName", "windowsPowerShell_LogName", "microsoftWindowsWinRM_LogName", "microsoftWindowsPowerShellOperational_LogPath", "powerShellCoreOperational_LogPath", "windowsPowerShell_LogPath", "microsoftWindowsWinRM_LogPath"
    $changedLogParam = $PSBoundParameters.Keys | ? { $_ -in $logParam }
    # $logParam/2 because *_LogName or *_LogPath params can be used but not both
    if ($changedLogParam -and $changedLogParam.count -ne ($logParam.count / 2)) {
        Write-Warning "You've defined some of the LogName/LogPath parameters but not all of them. This means that some of the events will be searched in local default logs and some in the ones you've specified. This is most probably a mistake!"
    }

    # check whether PSH Core event log exists
    # btw you must register log manifest during PSH Core installation a.k.a. you can have PSH Core installed without this event log activated!
    $PSHCoreIsAvailable = Get-WinEvent -ListLog "PowerShellCore/Operational" -ErrorAction SilentlyContinue

    # check whether the searched logs are from this or other computer
    # some checks etc don't make sense in case logs from a different computer are searched
    $logFromOtherComputer = $false
    if ($windowsPowerShell_LogName -ne "Windows PowerShell" -or $windowsPowerShell_LogPath -or $microsoftWindowsPowerShellOperational_LogName -ne "Microsoft-Windows-PowerShell/Operational" -or $microsoftWindowsPowerShellOperational_LogPath) {
        Write-Verbose "Logs seems to be from a different computer"
        $logFromOtherComputer = $true
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

    #region check that Script BlockLogging is enabled & propose enablement if it isn't
    if (!$logFromOtherComputer -and !$omitScriptBlockLoggingStatusCheck) {
        #region Windows PSH
        if ($PSHType -contains "WindowsPowerShell") {
            $regPath = "HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
            try {
                $enabledPSHScriptBlockLogging = Get-ItemPropertyValue $regPath "EnableScriptBlockLogging" -ErrorAction stop
            } catch {}

            if ($enabledPSHScriptBlockLogging -ne 1) {
                Write-Warning "Windows PowerShell Script Block logging isn't enabled on this system"

                if ($isAdmin) {
                    $choice = ""
                    while ($choice -notmatch "^[Y|N]$") {
                        $choice = Read-Host "Enable ScriptBlock logging? (Y|N)"
                    }
                    if ($choice -eq "N") {
                        # there might be old logging events, don't terminate this function
                    } else {
                        $null = New-Item -Path $regPath -Force
                        $null = Set-ItemProperty -Path $regPath -Name "EnableScriptBlockLogging" -Value 1 -Force
                        return "Script Block logging was enabled. Start a NEW Windows PowerShell console, run some code and try this function again."
                    }
                } else {
                    Write-Warning "Enable manually or run this function again as administrator"
                }
            }
        }
        #endregion Windows PSH

        # PSH Core 6.x is unsupported therefore ignored, but logging can be turned on in HKLM:\SOFTWARE\Policies\Microsoft\PowerShellCore\ScriptBlockLogging (event log manifest is incompatible with 7.x version aka events just from one version can be logged anyway)

        #region PSH Core 7.x
        if ($PSHType -contains "PowerShellCore") {
            $PSHCoreInstalledVersionKey = "HKLM:\SOFTWARE\Microsoft\PowerShellCore\InstalledVersions"
            if ((Test-Path $PSHCoreInstalledVersionKey -ea SilentlyContinue)) {
                # PSH Core is installed

                $regPath = "HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\PowerShellCore\ScriptBlockLogging"

                try {
                    $enabledPSHCoreScriptBlockLogging = Get-ItemPropertyValue $regPath "EnableScriptBlockLogging" -ErrorAction stop
                } catch {}

                if ($enabledPSHCoreScriptBlockLogging -ne 1) {
                    Write-Warning "PowerShell Core 7.x Script Block logging isn't enabled on this system"

                    if ($isAdmin) {
                        $choice = ""
                        while ($choice -notmatch "^[Y|N]$") {
                            $choice = Read-Host "Enable ScriptBlock logging? (Y|N)"
                        }
                        if ($choice -eq "N") {
                            # there might be old logging events, don't terminate this function
                        } else {
                            $null = New-Item -Path $regPath -Force
                            $null = Set-ItemProperty -Path $regPath -Name "EnableScriptBlockLogging" -Value 1 -Force
                            return "Script Block logging was enabled. Start a NEW PowerShell Core console, run some code and try this function again."
                        }
                    } else {
                        Write-Warning "Enable manually or run this function again as administrator"
                    }
                }
            }
        }
        #endregion PSH Core 7.x
    }
    #endregion check that Script BlockLogging is enabled & propose enablement if it isn't

    #region check event logs are enabled & enable
    if (!$logFromOtherComputer) {
        # "Windows Powershell" event log cannot be disabled
        "Microsoft-Windows-PowerShell/Operational", "PowerShellCore/Operational", "Microsoft-Windows-WinRM/Operational" | % {
            $logState = Get-WinEvent -ListLog $_ -ErrorAction SilentlyContinue # Core doesn't have to be installed or registered for event logging (part of installation)
            if ($logState -and (!$logState.IsEnabled)) {
                Write-Warning "Event log '$_' isn't enabled! Enabling"
                if ($isAdmin) {
                    wevtutil.exe sl "$_" /enabled:true
                } else {
                    Write-Error "Unable to enable event log '$_'. Not running as admin."
                }
            }
        }
    }
    #endregion check event logs are enabled & enable

    #region check Protected Event Logging settings
    try { $enableProtectedEventLogging = Get-ItemPropertyValue "HKLM:\Software\Policies\Microsoft\Windows\EventLog\ProtectedEventLogging" "EnableProtectedEventLogging" -ErrorAction stop } catch {}
    # check for decryption certificate in either case, because just because now PEL isn't enabled doesn't mean it wasn't enabled in the past
    $decryptionCert = Get-ChildItem -Path 'Cert:\LocalMachine\My\', 'Cert:\CurrentUser\My\' -Recurse | ? { $_.EnhancedKeyUsageList.FriendlyName -eq "Document Encryption" -and $_.HasPrivateKey -and $_.Extensions.KeyUsages -eq "DataEncipherment, KeyEncipherment" }

    if (!$decryptionCert -and $enableProtectedEventLogging -eq 1) {
        Write-Warning "Protected Event Logging (PEL) is enabled on this system, but PEL decryption certificate (with private key) isn't imported in your Personal certificate store a.k.a. called commands stays encrypted"
    }

    if (!$decryptionCert -and $logFromOtherComputer) {
        Write-Warning "Logs are from different computer and PEL decryption certificate (with private key) isn't imported in your Personal certificate store a.k.a. called commands stays encrypted (if encrypted)"
    }
    #endregion check Protected Event Logging settings
    #endregion checks

    #region get additional PSH console data
    #region helper function
    function _getPSHInvokedVia {
        param ($startEvent)

        if (!$startEvent) {
            Write-Verbose "Unable to find related PSH start event (ID 400) for ProcessId $processId. 'InvokedVia' property cannot be retrieved."
            return "<<unknown>>"
        }

        ($startEvent.Properties[2].Value.Split("`n") | Select-String "HostApplication=") -replace "^\s*HostApplication=" #"^.+?powershell.exe", "powershell.exe"
    }

    function _getInvokedScript {
        param ($eventList)

        if (!$eventList) { return }

        $invokedScript = $eventList | % {
            if ($_.Properties[-1].value) {
                $_.Properties[-1].value # last item contains invoked script
            }
        }

        $invokedScript | select -Unique
    }

    function _getSessionType {
        param ($startEvent)

        #TODO jak vypada kdyz se z core pripojim remote na stroj? kam se loguje?

        if ($startEvent.ProviderName -in 'PowerShellCore', 'Microsoft-Windows-PowerShell') {
            return "local"
        } elseif ($startEvent.ProviderName -eq 'Microsoft-Windows-WinRM') {
            $remoteConnectionInfo = ([regex]"\((.+)\)").Matches($startEvent.properties.value).groups[1].value
            return "remote ($remoteConnectionInfo)"
        } else {
            throw "Undefined ProviderName $($startEvent.ProviderName)"
        }
    }

    function _getCommandText {
        param ($eventList)

        if (!$eventList) { return }

        $eventList | % {
            if ($decryptionCert -and $_.message -like "Creating Scriptblock text*-----BEGIN CMS-----*ScriptBlock ID:*") {
                # sometimes Unprotect-CmsMessage returns zero :) bug? probably
                Unprotect-CmsMessage -Content $_.message
            } else {
                $_.properties[2].value
                # (([xml]$_.toxml()).Event.EventData.Data | ? name -EQ "ScriptBlockText").'#text'
            }
        }
    }
    #endregion helper function

    #region get Windows PowerShell basic start events (without arguments etc)
    if ($PSHType -contains "WindowsPowerShell") {
        Write-Progress -Activity "Getting helper events" -Status "Getting Windows PowerShell basic start events" -PercentComplete (20)

        $filterHashtable = @{
            id        = 40961
            startTime = $contextEventsStartTime
            endTime   = $endTime
        }
        if ($microsoftWindowsPowerShellOperational_LogPath) {
            $filterHashtable.path = $microsoftWindowsPowerShellOperational_LogPath
        } else {
            $filterHashtable.logname = $microsoftWindowsPowerShellOperational_LogName
        }

        try {
            $PSHBasicStartEvent = Get-WinEvent -FilterHashtable $filterHashtable -ErrorAction Stop | ? ProviderName -EQ "Microsoft-Windows-PowerShell" | ? { if (!$machineName -or ($machineName -and $_.MachineName -in $machineName)) { $_ } }
        } catch {
            if ($_ -like "*No events were found that match the specified selection criteria*") {
                Write-Warning "No events (ID: 40961) were found in Windows PowerShell Operational event log (from $contextEventsStartTime to $endTime)"
            } else {
                throw $_
            }
        }
    }
    #endregion get Windows PowerShell basic start events (without arguments etc)

    #region get PowerShell Core basic start events (without arguments etc)
    if ($PSHType -contains "PowerShellCore" -and ($PSHCoreIsAvailable -or $logFromOtherComputer)) {
        Write-Progress -Activity "Getting helper events" -Status "Getting PowerShell Core basic start events" -PercentComplete (40)

        $filterHashtable = @{
            id        = 40961
            startTime = $contextEventsStartTime
            endTime   = $endTime
        }
        if ($powerShellCoreOperational_LogPath) {
            $filterHashtable.path = $powerShellCoreOperational_LogPath
        } else {
            $filterHashtable.logname = $powerShellCoreOperational_LogName
        }

        try {
            $PSHCoreBasicStartEvent = Get-WinEvent -FilterHashtable $filterHashtable -ErrorAction Stop | ? ProviderName -EQ "PowerShellCore" | ? { if (!$machineName -or ($machineName -and $_.MachineName -in $machineName)) { $_ } }
        } catch {
            if ($_ -like "*No events were found that match the specified selection criteria*") {
                Write-Warning "No events (ID: 40961) were found in PowerShell Core Operational event log (from $contextEventsStartTime to $endTime)"
            } else {
                throw $_
            }
        }
    }
    #endregion get PowerShell Core basic start events (without arguments etc)

    #region get Windows PowerShell start events with additional data (with arguments etc)
    Write-Progress -Activity "Getting helper events" -Status "Getting Windows PowerShell start events with additional data" -PercentComplete (60)

    $filterHashtable = @{
        id        = 400
        startTime = $contextEventsStartTime
        endTime   = $endTime
    }
    if ($windowsPowerShell_LogPath) {
        $filterHashtable.path = $windowsPowerShell_LogPath
    } else {
        $filterHashtable.logname = $windowsPowerShell_LogName
    }

    try {
        $PSHEnhancedStartEvent = Get-WinEvent -FilterHashtable $filterHashtable -ErrorAction stop | ? ProviderName -EQ "PowerShell" | ? { if (!$machineName -or ($machineName -and $_.MachineName -in $machineName)) { $_ } }
    } catch {
        if ($_ -like "*No events were found that match the specified selection criteria*") {
            Write-Warning "No events (ID: 400) were found in Windows PowerShell event log (from $contextEventsStartTime to $endTime)"
        } else {
            throw $_
        }
    }
    #endregion get Windows PowerShell start events with additional data (with arguments etc)

    #region get Windows PowerShell end events
    # Script Block logging event log doesn't contain console termination events, therefore this log have to be searched
    Write-Progress -Activity "Getting helper events" -Status "Getting Windows PowerShell end events" -PercentComplete (80)

    $filterHashtable = @{
        id        = 403
        startTime = $startTime
        endTime   = $contextEventsEndTime
    }
    if ($windowsPowerShell_LogPath) {
        $filterHashtable.path = $windowsPowerShell_LogPath
    } else {
        $filterHashtable.logname = $windowsPowerShell_LogName
    }

    try {
        $PSHEnhancedEndEvent = Get-WinEvent -FilterHashtable $filterHashtable -ErrorAction stop | ? ProviderName -EQ "PowerShell" | ? { if (!$machineName -or ($machineName -and $_.MachineName -in $machineName)) { $_ } }
    } catch {
        if ($_ -like "*No events were found that match the specified selection criteria*") {
            Write-Warning "No events (ID: 403) were found in Windows PowerShell event log (from $startTime to $contextEventsEndTime)"
        } else {
            throw $_
        }
    }
    #endregion get Windows PowerShell end events

    #region get Windows PowerShell remote session start events
    # Script Block logging event log doesn't contain remote session start events
    Write-Progress -Activity "Getting helper events" -Status "Getting Windows PowerShell remote session start events" -PercentComplete (100)

    $filterHashtable = @{
        id        = 91
        startTime = $contextEventsStartTime
        endTime   = $contextEventsEndTime
    }
    if ($microsoftWindowsWinRM_LogPath) {
        $filterHashtable.path = $microsoftWindowsWinRM_LogPath
    } else {
        $filterHashtable.logname = $microsoftWindowsWinRM_LogName
    }

    try {
        $PSHRemoteSessionStartEvent = Get-WinEvent -FilterHashtable $filterHashtable -ErrorAction stop | ? ProviderName -EQ "Microsoft-Windows-WinRM" | ? { if (!$machineName -or ($machineName -and $_.MachineName -in $machineName)) { $_ } }
    } catch {
        if ($_ -like "*No events were found that match the specified selection criteria*") {
            Write-Warning "No events (ID: 91) were found in WinRM event log (from $contextEventsStartTime to $contextEventsEndTime)"
        } else {
            throw $_
        }
    }
    #endregion get Windows PowerShell remote session start events
    #endregion get additional PSH console data

    #region get PSH start/stop data
    # this data are particularly helpful when more separate events, but with same processId are processed
    $startStopList = New-Object System.Collections.ArrayList

    # get all START events
    $PSHStartEventList = New-Object System.Collections.ArrayList

    $PSHBasicStartEvent | ? { $_ } | % { $null = $PSHStartEventList.Add($_) }
    $PSHRemoteSessionStartEvent | ? { $_ } | % { $null = $PSHStartEventList.Add($_) }
    $PSHCoreBasicStartEvent | ? { $_ } | % { $null = $PSHStartEventList.Add($_) }

    # from oldest to newest so I can easily pick the correct helper events later
    $PSHStartEventList = $PSHStartEventList | sort TimeCreated

    $problematicEventCount = 0
    $i = 0

    # get corresponding END events and merge it all together
    foreach ($PSHStartEvent in $PSHStartEventList) {
        $timeCreated = $PSHStartEvent.TimeCreated
        $processId = $PSHStartEvent.processId
        $eventMachineName = $PSHStartEvent.machineName
        $PSHHostId = $null
        $stopTime = ""
        $startEventWithDetails = $null
        $stopEvent = $null

        Write-Progress -Activity "Merging START&STOP events" -Status "Processing start event created at $timeCreated" -PercentComplete ((++$i / $PSHStartEventList.count) * 100)

        # it can take time before helper event occurs, therefore check time range
        # all available events
        $startEventWithDetailsList = $PSHEnhancedStartEvent | ? { $_.machineName -eq $eventMachineName -and $_.TimeCreated -ge $timeCreated -and $_.TimeCreated -le $timeCreated.AddMilliseconds(10000) } | sort TimeCreated

        if ($startEventWithDetailsList.count -gt 1 -and ($startEventWithDetailsList[0].TimeCreated -eq $startEventWithDetailsList[1].TimeCreated)) {
            if ($lastProcessedStartEventWithDetails.TimeCreated -eq $startEventWithDetailsList[0].TimeCreated) {
                # this is second or more event where helper event has to be guessed, because of same creation time
                # pick the next one
                Write-Warning "ProcessId $processId (start $timeCreated) is $($problematicEventCount + 1). in a row where there are multiple helper events with exactly the same creation time. The $($problematicEventCount + 1). will be used, but it is just a GUESS!"
                $startEventWithDetails = $startEventWithDetailsList[$problematicEventCount]
                ++$problematicEventCount
            } else {
                # this is first event where helper event has to be guessed, because of same creation time
                # pick the first one
                Write-Warning "For ProcessId $processId (start $timeCreated) events there are multiple helper events with exactly the SAME creation time. The one to use will be therefore GUESSED! So there is chance that properties gathered thanks to this helper event (InvokedVia, StopTime, who & how invoked this, ...) won't be correct!!!"
                $startEventWithDetails = $startEventWithDetailsList[0]
                ++$problematicEventCount
            }
        } else {
            # pick the closest not-yet-used one
            # because it with highest probability corresponds to the processed one
            $startEventWithDetails = $startEventWithDetailsList | select -First 1
            $problematicEventCount = 0
        }

        $lastProcessedStartEventWithDetails = $startEventWithDetails

        # ProcessID can be reused, but with filtering via ProcessName and StartTime (in case there are multiple PSH sessions with same ProcessId) it should be fine
        if ($eventMachineName -like "$env:COMPUTERNAME*" -and (Get-Process -Id $processId -ErrorAction SilentlyContinue | ? { $_.ProcessName -match "powershell|pwsh" -and ($_.StartTime -ge $timeCreated.AddMilliseconds(-3000) -or $_.StartTime -le $timeCreated.AddMilliseconds(3000)) })) {
            $stopTime = "<<still running>>"
        } else {
            if (!$startEventWithDetails) {
                $stopTime = "<<unknown>>"
            } else {
                # get HostId from the console start event
                $PSHHostId = ((($startEventWithDetails.Message) -split "`n" | Select-String "^\s+HostId=") -replace "^\s+HostId=").trim()

                # find out when PSH console with given HostId ended
                $stopEvent = $PSHEnhancedEndEvent | ? { $_.machineName -eq $eventMachineName -and $_.TimeCreated -ge $timeCreated -and $_.Message -like "*HostId=$PSHHostId*" } | select -Last 1

                if ($stopEvent) {
                    $stopTime = $stopEvent.TimeCreated
                } else {
                    $stopTime = "<<unknown>>"
                }
            }
        }

        $r = [PSCustomObject]@{
            ProcessId             = $processId
            HostId                = $PSHHostId
            StartTime             = $timeCreated
            StopTime              = $stopTime
            StartEvent            = $PSHStartEvent
            StartEventWithDetails = $startEventWithDetails
            StopEvent             = $stopEvent
            MachineName           = $PSHStartEvent.MachineName
        }

        $null = $startStopList.add($r)
    }
    #endregion get PSH start/stop data

    $result = New-Object System.Collections.ArrayList

    #region get PowerShell Core Script Block logging events
    if ($PSHType -contains "PowerShellCore" -and ($PSHCoreIsAvailable -or $logFromOtherComputer)) {
        Write-Progress -Activity "Retrieving Core Script Block Logging events"

        $filterHashtable = @{
            id    = 4104
            level = 3, 5 # just warning and verbose events contain command lines
        }
        if ($powerShellCoreOperational_LogPath) {
            $filterHashtable.path = $powerShellCoreOperational_LogPath
        } else {
            $filterHashtable.logname = $powerShellCoreOperational_LogName
        }
        if ($startTime) {
            $filterHashtable.startTime = $startTime
        }
        if ($endTime) {
            $filterHashtable.endTime = $endTime
        }

        # ProviderName filtering via Where-Object and not directly in Get-WinEvent, because of error "The specified providers do not write events to the forwardedevents log" in case Forwarded event log is searched
        try {
            $PSHCoreEvent = Get-WinEvent -FilterHashtable $filterHashtable -ErrorAction Stop |
                ? ProviderName -EQ "PowerShellCore" |
                ? { if (!$machineName -or ($machineName -and $_.MachineName -in $machineName)) { $_ } }
        } catch {
            if ($_ -like "*No events were found that match the specified selection criteria*") {
                Write-Warning "No PowerShell Core invocations were found"
            } else {
                throw $_
            }
        }

        if ($PSHCoreEvent) {
            # oldest events first
            [array]::Reverse($PSHCoreEvent)
            # group events
            $PSHCoreEvent = $PSHCoreEvent | Group-Object MachineName, ProcessId

            $i = 0

            # process grouped PowerShell Core script block logging events
            $PSHCoreEvent | % {
                $eventMachineName = ($_.Name -split ",")[0].trim()
                [int]$processId = ($_.Name -split ",")[1].trim()
                $groupedEvent = $_.Group
                $firstEventTimeCreated = $groupedEvent[0].TimeCreated
                $lastEventTimeCreated = $groupedEvent[-1].TimeCreated

                Write-Progress -Activity "Processing Core Script Block Logging events" -Status "Processing events with processId $processId" -PercentComplete ((++$i / $PSHCoreEvent.count) * 100)

                $scriptBlockPart = ([regex]"Creating Scriptblock text \((\d+) of \d+\)").Matches($groupedEvent[0].message).captures.groups[1].value
                if ($scriptBlockPart -and $scriptBlockPart -ne 1) {
                    Write-Warning "Invoked commands for processid: $processId are trimmed (events were probably overwriten). Commands starts from capture script block number $scriptBlockPart"
                }

                $processStartStopData = $startStopList | ? { $_.machineName -eq $eventMachineName -and $_.processId -eq $processId -and ($_.StartTime -le $lastEventTimeCreated -and ($_.StopTime -in "<<unknown>>", "<<still running>>" -or $_.StopTime -ge $firstEventTimeCreated)) }

                if (!$processStartStopData) {
                    # context data about start/stop are missing
                    Write-Warning "Unable to find start/stop events for $eventMachineName processid: $processId, first event: $firstEventTimeCreated, last event: $lastEventTimeCreated.`nCreate time of the first/last event will be used instead"
                    $null = $result.Add(
                        [PSCustomObject]@{
                            ProcessId     = $processId
                            ProcessStart  = $firstEventTimeCreated
                            ProcessEnd    = "<<unknown (such event is not logged for PSH Core)>>"
                            InvokedVia    = "<<unknown (such event is not logged for PSH Core)>>"
                            CommandCount  = $groupedEvent.count
                            # decrypt only if message is really encrypted (encrypting certificate can be missing, encryption could be enabled recently so some events are still not-encrypted)
                            CommandList   = _getCommandText -eventList $groupedEvent
                            UserId        = $groupedEvent.UserId | select -Unique
                            EventList     = $groupedEvent
                            InvokedScript = _getInvokedScript -eventList $groupedEvent
                            SessionType   = "local (probably)" # start event is missing so I am just guessing
                            PSHType       = 'PowerShell Core'
                            MachineName   = $eventMachineName
                        }
                    )
                } elseif (@($processStartStopData).count -eq 1) {
                    # there is just one start/stop event for events with same processid, no need to split
                    $null = $result.Add(
                        [PSCustomObject]@{
                            ProcessId     = $processId
                            ProcessStart  = $processStartStopData.StartTime
                            ProcessEnd    = "<<unknown (such event is not logged for PSH Core)>>"
                            InvokedVia    = "<<unknown (such event is not logged for PSH Core)>>"
                            CommandCount  = $groupedEvent.count
                            CommandList   = _getCommandText -eventList $groupedEvent
                            UserId        = @($groupedEvent.UserId)[0]
                            EventList     = $groupedEvent
                            InvokedScript = _getInvokedScript -eventList $groupedEvent
                            SessionType   = _getSessionType -startEvent $processStartStopData.StartEvent
                            PSHType       = 'PowerShell Core'
                            MachineName   = $eventMachineName
                        }
                    )
                } else {
                    # there are multiple start/stop events for events with same processid
                    $i = 0
                    foreach ($startStopData in $processStartStopData) {
                        Write-Verbose "Splitting events for $eventMachineName processid: $processId"
                        $start = $startStopData.startTime
                        $stop = $startStopData.stopTime
                        if ($stop -eq "<<unknown>>") {
                            if ($processStartStopData[$i + 1]) {
                                # use next round start as this round stop time
                                $stop = ($processStartStopData[$i + 1].startTime).AddMilliseconds(-1)
                                Write-Verbose "`t- unknown process end time, using startime of the next start/stop round"
                            } else {
                                # super future aka get all events till the end
                                $stop = Get-Date -Year 2100
                            }
                        }
                        if ($stop -eq "<<still running>>") {
                            # super future aka get all events till the end
                            $stop = Get-Date -Year 2100
                        }

                        if ($stop -le $startTime) {
                            Write-Verbose "`t- this start/stop ($start - $stop) data are outside of the required scope ($startTime - $endTime), skipping"
                            continue
                        }

                        Write-Verbose "`t- process events created from: $start to: $stop"

                        $eventList = $groupedEvent | ? { $_.TimeCreated -ge $start -and $_.TimeCreated -le $stop }
                        if (!$eventList) {
                            Write-Error "There are no events for processId $processId between found start ($start) and stop ($stop) events. Processed first events are from $firstEventTimeCreated to $lastEventTimeCreated and number of all events is $($groupedEvent.count)). This shouldn't happen and is caused by BUG in the function logic probably!"
                        }

                        $null = $result.Add(
                            [PSCustomObject]@{
                                ProcessId     = $processId
                                ProcessStart  = $startStopData.startTime
                                ProcessEnd    = "<<unknown (such event is not logged for PSH Core)>>"
                                InvokedVia    = "<<unknown (such event is not logged for PSH Core)>>"
                                CommandCount  = $eventList.count
                                CommandList   = _getCommandText -eventList $eventList
                                UserId        = @($eventList.UserId)[0]
                                EventList     = $eventList
                                InvokedScript = _getInvokedScript -eventList $eventList
                                SessionType   = _getSessionType -startEvent $startStopData.startEvent
                                PSHType       = 'PowerShell Core'
                                MachineName   = $eventMachineName
                            })

                        ++$i
                    }
                }
            }
        }
    }
    #endregion get Core PowerShell Script Block logging events

    #region get Windows PowerShell Script Block logging events
    if ($PSHType -contains "WindowsPowerShell") {
        Write-Progress -Activity "Retrieving Windows PowerShell Script Block Logging events"

        $filterHashtable = @{
            id    = 4104
            level = 3, 5 # just warning and verbose events contain invoked commands
        }
        if ($microsoftWindowsPowerShellOperational_LogPath) {
            $filterHashtable.path = $microsoftWindowsPowerShellOperational_LogPath
        } else {
            $filterHashtable.logname = $microsoftWindowsPowerShellOperational_LogName
        }
        if ($startTime) {
            $filterHashtable.startTime = $startTime
        }
        if ($endTime) {
            $filterHashtable.endTime = $endTime
        }

        # ProviderName filtering via Where-Object and not directly in Get-WinEvent, because of error "The specified providers do not write events to the forwardedevents log" in case Forwarded event log is searched
        try {
            $PSHEvent = Get-WinEvent -FilterHashtable $filterHashtable -ErrorAction Stop |
                ? ProviderName -EQ "Microsoft-Windows-PowerShell" |
                ? { if (!$machineName -or ($machineName -and $_.MachineName -in $machineName)) { $_ } }
        } catch {
            if ($_ -like "*No events were found that match the specified selection criteria*") {
                Write-Warning "No Windows PowerShell invocations were found"
            } else {
                throw $_
            }
        }

        if ($PSHEvent) {
            # oldest events first
            [array]::Reverse($PSHEvent)
            # group events
            $PSHEvent = $PSHEvent | Group-Object MachineName, ProcessId

            $i = 0

            # process grouped Windows PowerShell script block logging events
            $PSHEvent | % {
                $eventMachineName = ($_.Name -split ",")[0].trim()
                [int]$processId = ($_.Name -split ",")[1].trim()
                $groupedEvent = $_.Group
                $firstEventTimeCreated = $groupedEvent[0].TimeCreated
                $lastEventTimeCreated = $groupedEvent[-1].TimeCreated

                Write-Progress -Activity "Processing Windows PowerShell Script Block Logging events" -Status "Processing events with processId $processId" -PercentComplete (($i++ / $PSHEvent.count) * 100)

                if ($groupedEvent) {
                    $scriptBlockPart = ([regex]"Creating Scriptblock text \((\d+) of \d+\)").Matches($groupedEvent[0].message).captures.groups[1].value
                    if ($scriptBlockPart -and $scriptBlockPart -ne 1) {
                        Write-Warning "Invoked commands for processid: $processId are trimmed (events were probably overwriten). Commands starts from capture script block number $scriptBlockPart"
                    }
                }

                $processStartStopData = $startStopList | ? { $_.machineName -eq $eventMachineName -and $_.processId -eq $processId -and ($_.StartTime -le $lastEventTimeCreated -and ($_.StopTime -in "<<unknown>>", "<<still running>>" -or $_.StopTime -ge $firstEventTimeCreated)) }

                if (!$processStartStopData) {
                    # context data about start/stop are missing
                    Write-Warning "Unable to find start/stop events for $eventMachineName processid: $processId, first event: $firstEventTimeCreated, last event: $lastEventTimeCreated.`nCreate time of the first/last event will be used instead"
                    $null = $result.Add(
                        [PSCustomObject]@{
                            ProcessId     = $processId
                            ProcessStart  = $firstEventTimeCreated
                            ProcessEnd    = $lastEventTimeCreated
                            InvokedVia    = _getPSHInvokedVia
                            CommandCount  = $groupedEvent.count
                            # decrypt only if message is really encrypted (encrypting certificate can be missing, encryption could be enabled recently so some events are still not-encrypted)
                            CommandList   = _getCommandText -eventList $groupedEvent
                            UserId        = $groupedEvent.UserId | select -Unique
                            EventList     = $groupedEvent
                            InvokedScript = _getInvokedScript -eventList $groupedEvent
                            SessionType   = "local (probably)" # start event is missing so I am just guessing
                            PSHType       = 'Windows PowerShell'
                            MachineName   = $eventMachineName
                        }
                    )
                } elseif (@($processStartStopData).count -eq 1) {
                    # there is just one start/stop event for events with same processid, no need to split
                    $null = $result.Add(
                        [PSCustomObject]@{
                            ProcessId     = $processId
                            ProcessStart  = $processStartStopData.StartTime
                            ProcessEnd    = $processStartStopData.StopTime
                            InvokedVia    = _getPSHInvokedVia -startEvent $processStartStopData.StartEventWithDetails
                            CommandCount  = $groupedEvent.count
                            CommandList   = _getCommandText -eventList $groupedEvent
                            UserId        = @($groupedEvent.UserId)[0]
                            EventList     = $groupedEvent
                            InvokedScript = _getInvokedScript -eventList $groupedEvent
                            SessionType   = _getSessionType -startEvent $processStartStopData.StartEvent
                            PSHType       = 'Windows PowerShell'
                            MachineName   = $eventMachineName
                        }
                    )
                } else {
                    # there are multiple start/stop events for events with same processid
                    $i = 0
                    foreach ($startStopData in $processStartStopData) {
                        Write-Verbose "Splitting events for $eventMachineName processid: $processId"
                        $start = $startStopData.startTime
                        $stop = $startStopData.stopTime
                        if ($stop -eq "<<unknown>>") {
                            if ($processStartStopData[$i + 1]) {
                                # use next round start as this round stop time
                                $stop = ($processStartStopData[$i + 1].startTime).AddMilliseconds(-1)
                                Write-Verbose "`t- unknown process end time, using startime of the next start/stop round"
                            } else {
                                # super future aka get all events till the end
                                $stop = Get-Date -Year 2100
                            }
                        }
                        if ($stop -eq "<<still running>>") {
                            # super future aka get all events till the end
                            $stop = Get-Date -Year 2100
                        }

                        if ($stop -le $startTime) {
                            Write-Verbose "`t- this start/stop ($start - $stop) data are outside of the required scope ($startTime - $endTime), skipping"
                            continue
                        }

                        if ($stop -lt $firstEventTimeCreated) {
                            Write-Verbose "`t- this start/stop ($start - $stop) data misses first event creation time ($firstEventTimeCreated), skipping"
                            continue
                        }

                        Write-Verbose "`t- process events created from: $start to: $stop"

                        $eventList = $groupedEvent | ? { $_.TimeCreated -ge $start -and $_.TimeCreated -le $stop }
                        if (!$eventList) {
                            Write-Error "There are no events for processId $processId between found start ($start) and stop ($stop) events. Processed first events are from $firstEventTimeCreated to $lastEventTimeCreated and number of all events is $($groupedEvent.count)). This shouldn't happen and is caused by BUG in the function logic probably!"
                        }

                        $null = $result.Add(
                            [PSCustomObject]@{
                                ProcessId     = $processId
                                ProcessStart  = $startStopData.startTime
                                ProcessEnd    = $startStopData.stopTime
                                InvokedVia    = _getPSHInvokedVia -startEvent $startStopData.StartEventWithDetails
                                CommandCount  = $eventList.count
                                CommandList   = _getCommandText -eventList $eventList
                                UserId        = @($eventList.UserId)[0]
                                EventList     = $eventList
                                InvokedScript = _getInvokedScript -eventList $eventList
                                SessionType   = _getSessionType -startEvent $startStopData.startEvent
                                PSHType       = 'Windows PowerShell'
                                MachineName   = $eventMachineName
                            }
                        )

                        ++$i
                    }
                }
            }
        }
    }
    #endregion get Windows PowerShell Script Block logging events

    # output the results
    $result | Sort-Object ProcessStart
}