function Invoke-IntuneCommand {
    <#
    .SYNOPSIS
    Function mimics Invoke-Command, but for Intune managed Windows clients a.k.a. invokes given code on selected device(s) and returns the output (this part is a bit complicated therefore check DESCRIPTION for more details).

    .DESCRIPTION
    Function mimics Invoke-Command, but for Intune managed Windows clients a.k.a. invokes given code on selected device(s) and returns the output.

    Because Intune on-demand remediation feature is used behind the scene, there are some limitations regarding the returned output:
    - only the last line of your command output is returned and its length is limited to 2048 chars!
        - thanks to Intune remediation built-in restrictions
    - you must use 'Write-Output' instead of 'Write-Host'!
    - if you wish to transform the result back into an object, ensure that your command returns a single compressed JSON string
        - function automatically tries to decompress the output (using ConvertFrom-CompressedString) and then converts back the JSON string (using ConvertFrom-Json) to the original object. The result of this operation is saved in special property named 'ProcessedOutput'.

    Invocation time line:
    - create the remediation = a few seconds
    - invoke the remediation = a few seconds per device
    - wait for remediation to finish = 3 minutes at minimum + command itself run time
    - gather the results from the Intune = a few seconds
    - delete remediation = a few seconds

    .PARAMETER deviceName
    Name of the Intune device(s) you want to run the command on.

    If not provided, run command against ALL Windows managed devices.

    .PARAMETER command
    String representing the command you want to run on the devices.

    .PARAMETER scriptFile
    Path to the file with the command, you want to run on the devices.

    It must be UTF8 encoded!

    .PARAMETER scriptBlock
    ScriptBlock that should be invoked on the devices.

    .PARAMETER runAs
    System or User.

    By default SYSTEM.

    .PARAMETER runAs32
    Boolean value. True if should be run in 32 bit PowerShell.

    By default false == run in 64 bit PowerShell.

    .PARAMETER waitTime
    How long should this function wait for the results retrieval before termination.

    Minimum is 3 minutes, because even though command invokes immediately, it takes time before results shows up in the Intune.

    If the time limit expires and there are devices that have not executed the command, they will no longer be able to do so as the helper remediation will be removed.

    By default 10 minutes.

    .PARAMETER dontWait
    Switch for just invoking the command but not waiting for the results.

    The helper remediation, which operates in the background and is necessary for clients to execute the code, will not be automatically deleted. Instead, you will need to manually remove it when suitable.

    .PARAMETER letCommandFinish
    Don't automatically delete the helper remediation if there are still some devices that didn't run it.
    Useful if you wan't make sure, the code will run on all targeted devices eventually.

    Once suitable, you will have to delete the helper remediation manually!

    .PARAMETER remediationSuffix
    String that will be added to created helper remediation name.
    Usable for long running remediations where 'letCommandFinish' parameter is used.

    .PARAMETER prependCommandDefinition
    List of command names whose text definition should be added at the beginning of the invoked command.
    Useful if you want to run some command that is not available on the remote system, but is available in your local PSH session.
    If it is not, you will have to add its definition to the 'command' parameter yourself!

    .EXAMPLE
    $command = @'
        $r = get-process powershell | select processname, id
        $r | ConvertTo-Json -Compress
    '@

    Invoke-IntuneCommand -deviceName PC-01, PC-02 -command $command -verbose

    Run selected command on PC-01 and PC-02.

    .EXAMPLE
    $command = @'
        if (Test-Path C:\temp -errorAction silentlycontinue) {
            Write-Output "Folder exists"
        }
    '@

    Invoke-IntuneCommand -deviceName PC-01 -command $command -verbose

    Run selected command on PC-01.

    If the wait time limit is reached (by default 10 minutes), the devices that missed it will no longer run the given code, because helper remediation will be deleted.

    .EXAMPLE
    Invoke-IntuneCommand -deviceName PC-01 -scriptFile C:\scripts\intunescript.ps1 -verbose -waitTime 30

    Use content of the C:\scripts\intunescript.ps1 file as a command that will be run on PC-01 device.
    Wait time is set to 30 minutes, because we expect the command to run longer than default 10 minutes.

    If the wait time limit is reached, the devices that missed it will no longer run the given code, because helper remediation will be deleted.

    .EXAMPLE
    $command = @'
        mkdir C:\temp
    '@

    Invoke-IntuneCommand -deviceName PC-01 -command $command -dontWait

    Run selected command on PC-01, but don't wait on the results.

    Helper remediation will not be deleted automatically, hence you will need to delete it manually when suitable.

    .EXAMPLE
    $command = @'
        if (Test-Path C:\temp -errorAction silentlycontinue) {
            Write-Output "Folder exists"
        }
    '@

    Invoke-IntuneCommand -deviceName PC-01, PC-02, PC-03, PC-04 -command $command -letCommandFinish

    Run selected command on specified devices.

    If the wait time limit is reached (by default 10 minutes) adn there are still some devices where code wasn't run, helper remediation will not be deleted, so the devices can run it when available. You will need to delete the remediation manually when suitable.

    .EXAMPLE
    $command = @"
        $output = Get-Process 'PowerShell' | ConvertTo-Json -Compress | ConvertTo-CompressedString
        return $compressedString
    "@

    # text definition of the ConvertTo-CompressedString function will be added to the command, so it doesn't matter whether it is available on the remote system
    Invoke-IntuneCommand -command $command -deviceName PC-01 -prependCommandDefinition ConvertTo-CompressedString

    Get the data from the client as a compressed JSON string (to hopefully avoid 2048 chars limit).
    Result will be automatically decompressed and converted back from JSON to object.

    .EXAMPLE
    $command = 'Get-Content "C:\Windows\Temp\InstallPSHModuleFromStorageAccount_test.log" -Raw | ConvertTo-CompressedString'
    Invoke-IntuneCommand -command $command -deviceName PC-01 -prependCommandDefinition ConvertTo-CompressedString

    Get content of the log file.
    Result will be automatically decompressed to the original text.

    .NOTES
    Permission requirements:
    - DeviceManagementConfiguration.Read.All
    - DeviceManagementManagedDevices.Read.All
    - DeviceManagementManagedDevices.PrivilegedOperations.All

    General requirements:
    - https://learn.microsoft.com/en-us/mem/intune/fundamentals/remediations#script-requirements
    - https://learn.microsoft.com/en-us/mem/intune/fundamentals/remediations#prerequisites-for-running-a-remediation-script-on-demand


    If your command throws an error, the whole invocation takes more time, because if detection part of the Intune remediation script fails, the remediation part (dummy 'exit 0' in our case) will be run automatically too.
    #>

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [string[]] $deviceName,

        [Parameter(Mandatory = $true, ParameterSetName = "Default")]
        [string] $command,

        [Parameter(Mandatory = $true, ParameterSetName = "scriptFile")]
        [ValidateScript( {
                if (Test-Path -Path $_ -PathType Leaf) {
                    $true
                } else {
                    throw "$_ is not a file."
                }
            })]
        [string] $scriptFile,

        [Parameter(Mandatory = $true, ParameterSetName = "scriptBlock")]
        [scriptblock] $scriptBlock,

        [ValidateSet('system', 'user')]
        [string] $runAs = "system",

        [boolean] $runAs32 = $false,

        [ValidateRange(3, 10080)]
        [int] $waitTime = 10,

        [switch] $dontWait,

        [Alias("dontDeleteRemediation")]
        [switch] $letCommandFinish,

        [ValidateLength(1, 64)]
        [string] $remediationSuffix,

        [string[]] $prependCommandDefinition
    )

    $ErrorActionPreference = "Stop"

    $startTimeUTC = [DateTime]::UtcNow

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    #region helper functions
    function _processOutput {
        # tries to convert the output to original object created using ConvertTo-Json (and maybe ConvertTo-CompressedString)
        param (
            [string] $string
        )

        if (!$string) {
            return
        }

        if (($string | Measure-Object -Character).Characters -ge 2048) {
            Write-Warning "Output for device $deviceId exceeded 2048 chars a.k.a. is truncated. Limit amount of returned data for example using 'Select-Object -Property' and 'ConvertTo-Json -Compress' combined with 'ConvertTo-CompressedString'"
        }

        # decompress the string if it is compressed
        try {
            $decompressedString = ConvertFrom-CompressedString $string -ErrorAction Stop
            $string = $decompressedString
        } catch {
            Write-Verbose "Not a compressed string"
        }

        # convert to object if the string is a JSON
        try {
            $string | ConvertFrom-Json -ErrorAction Stop
            return
        } catch {
            Write-Verbose "Not a JSON"
        }

        return
    }

    function Get-FunctionDefinition {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string] $functionName
        )

        try {
            $fObject = Get-ChildItem Function:\$functionName -ErrorAction Stop
        } catch {
            throw "Unable to get function '$functionName' definition"
        }

        return "Function $functionName {`r`n$($fObject.Definition)`r`n}"
    }
    #endregion helper functions

    #region prepare
    #region get device ids
    $deviceName = $deviceName | select -Unique

    $deviceList = @{}

    if ($deviceName) {
        $deviceName | % {
            $device = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$_'" -Property Id, OperatingSystem, ManagementAgent
            if ($device) {
                if ($device.OperatingSystem -eq "Windows" -and $device.ManagementAgent -in "mdm", "configurationManagerClientMdm") {
                    $deviceList.($device.Id) = $_
                } else {
                    Write-Warning "Device '$_' isn't Windows client or isn't managed by Intune"
                }
            } else {
                Write-Warning "Device '$_' doesn't exist"
            }
        }
    } else {
        # unable to filter using DeviceEnrollmentType property?!
        Write-Warning "Running against ALL Windows managed clients!"
        Get-MgDeviceManagementManagedDevice -All -Filter "operatingSystem eq 'Windows'" -Property Id, DeviceName, ManagementAgent | ? ManagementAgent -In 'mdm', 'configurationManagerClientMdm' | % { $deviceList.($_.Id) = $_.DeviceName
        }
    }

    $deviceIdList = $deviceList.Keys
    #endregion get device ids

    if (!$deviceIdList) {
        Write-Warning " No devices to run against"
        return
    }

    if ($scriptFile) {
        Write-Warning "Make sure the '$scriptFile' is encoded using UTF8!"
        $command = Get-Content -Path $scriptFile -Raw -Encoding UTF8 -ErrorAction Stop
    }

    if ($scriptBlock) {
        $command = $scriptBlock.ToString()
    }

    #region add selected command definition to the beginning of the invoked code
    if ($prependCommandDefinition) {
        $allFunctionDefs = "#region prepended functions`n"

        foreach ($fName in $prependCommandDefinition) {
            $fDefinition = Get-FunctionDefinition $fName

            if (!$fDefinition) {
                throw "Unable to find definition of the function '$fName'"
            }

            $allFunctionDefs += "$fDefinition`n"
        }

        $allFunctionDefs += "#endregion prepended functions"

        $command = $allFunctionDefs + "`n`n" + $command
    }
    #endregion add selected command definition to the beginning of the invoked code
    #endregion prepare

    Write-Verbose "Command that will be invoked on the client(s):`n$command"

    #region create the remediation
    $remediationStart = [datetime]::Now
    $remediationScriptName = "_invCmd_" + $remediationStart.ToString('yyyy.MM.dd_HH:mm')

    if ($remediationSuffix) {
        $remediationScriptName = $remediationScriptName + "_" + $remediationSuffix
    }

    Write-Verbose "Creating remediation script '$remediationScriptName'"

    $param = @{
        displayName     = $remediationScriptName
        description     = "on demand remediation script"
        detectScript    = $command # detection is run before remediation, hence it is faster to use in our use case
        remediateScript = "exit 0" # dummy code
        publisher       = "on-demand"
        runAs           = $runAs
        runAs32         = $runAs32
    }
    $remediationScript = New-IntuneRemediation @param
    #endregion create the remediation

    try {
        $skippedDeviceIdList = New-Object System.Collections.ArrayList

        #region invoke the remediation
        $deviceIdList | % {
            $deviceId = $_
            $i = 0
            $retryLimit = 2

            Write-Verbose "Invoking command for device $deviceId"

            while ($i -le $retryLimit) {
                try {
                    Invoke-IntuneRemediationOnDemand -remediationScriptId $remediationScript.Id -deviceId $deviceId -ErrorAction Stop
                    break
                } catch {
                    ++$i

                    if ($_ -like "*Not Found*") {
                        # temporary error, try again
                        Write-Warning " Trying again. Error was: $_"
                        Start-Sleep 5
                    } else {
                        Write-Warning " Skipping. Error was: $_"
                        break
                    }
                }
            }

            if ($i -gt $retryLimit) {
                # failed to run the remediation
                $null = $skippedDeviceIdList.Add($deviceId)
            }
        }
        #endregion invoke the remediation

        if ($dontWait) {
            # go to finally block
            return
        }

        if ($deviceIdList.count -eq $skippedDeviceIdList.count) {
            Write-Warning "Skipped on all selected devices"

            # go to finally block
            return

            #TODO remove remediation if it was skipped on every client?
        }

        #region wait for the remediation & output the results
        $finishedDeviceIdList = New-Object System.Collections.ArrayList

        Write-Warning "Waiting for command to finish on the $($deviceIdList.count) device(s)"
        # 30 seconds is the absolute minimum to get some results
        sleep 30

        while ($deviceIdList.count -ne ($finishedDeviceIdList.count + $skippedDeviceIdList.count) -and [datetime]::Now -lt $remediationStart.AddMinutes($waitTime)) {
            #TIP it takes some time before remediation result can be retrieved (via Get-MgBetaDeviceManagementDeviceHealthScriptDeviceRunState) even though device says (via Get-MgDeviceManagementManagedDevice) that remediation was finished on it already
            $remediationResult = Get-MgBetaDeviceManagementDeviceHealthScriptDeviceRunState -DeviceHealthScriptId $remediationScript.Id -All

            foreach ($result in $remediationResult) {
                $deviceId = $result.id.split(":")[1]

                if ($deviceId -in $finishedDeviceIdList) { continue }

                Write-Verbose "Device $deviceId has finished on-demand remediation"

                $null = $finishedDeviceIdList.Add($deviceId)

                [PSCustomObject]@{
                    DeviceId            = $deviceId
                    DeviceName          = $deviceList.$deviceId
                    LastSyncDateTimeUTC = $result.LastStateUpdateDateTime # LastSyncDateTime doesn't show date when device contacted Intune last time, therefore I use LastStateUpdateDateTime (it doesn't matter, because I know the command was run now)
                    ProcessedOutput     = _processOutput $result.PreRemediationDetectionScriptOutput
                    Output              = $result.PreRemediationDetectionScriptOutput
                    Error               = $result.PreRemediationDetectionScriptError
                    Status              = $result.DetectionState
                }
            }

            $unfinishedDeviceIdList = $deviceIdList | ? { $_ -notin $finishedDeviceIdList }
            if ($unfinishedDeviceIdList) {
                Write-Verbose "`t- unfinished device(s): $($unfinishedDeviceIdList.count), remaining time: $(($remediationStart.AddMinutes($waitTime) - [datetime]::Now).tostring("mm\:ss"))"
                sleep 5
            }
        }

        if ([datetime]::Now -ge $remediationStart.AddMinutes($waitTime)) {
            Write-Warning "Invocation exceeded $waitTime minutes time out"
        }
        #endregion wait for the remediation & output the results
    } catch {
        throw $_
    } finally {
        #TIP finally block catches even termination through CTRL + C
        # but if CTRL + C was pressed, you cannot use output: "some text" or write-output "some text" or other similar methods to output anything to the console, because that would break the finally block!

        if ($dontWait) {
            # nothing to do really
            if (!$letCommandFinish) {
                Write-Warning "Because 'dontWait' was used, helper remediation '$remediationScriptName' ($($remediationScript.Id)) won't be deleted, because that would cause clients not to run the defined command. Do it manually."
            }
        } else {
            #region output devices that didn't make it in time
            $deviceResult = New-Object System.Collections.ArrayList
            $reallyUnfinishedDeviceIdList = New-Object System.Collections.ArrayList
            $unfinishedDeviceIdList = $deviceIdList | ? { $_ -notin $finishedDeviceIdList }

            foreach ($deviceId in $unfinishedDeviceIdList) {
                # process devices that have no processing data in the remediation object
                # it takes time before remediation results data from the client find their way to remediation object
                # therefore to not confuse user with inaccurate data get the real results from the clients themselves
                # (just the last invoked on-demand remediation is stored)
                $deviceDetails = Get-MgDeviceManagementManagedDevice -ManagedDeviceId $deviceId -Property DeviceActionResults, LastSyncDateTime
                $onDemandRemediationData = $deviceDetails.DeviceActionResults | ? ActionName -EQ 'initiateOnDemandProactiveRemediation'
                $onDemandRemediationStatus = $onDemandRemediationData.ActionState

                if ($onDemandRemediationData.StartDateTime -lt $startTimeUTC) {
                    # current remediation invocation obviously failed on this client (StartDateTime is before this function started)
                    $onDemandRemediationStatus = "Remediation not invoked"
                }

                # output just some basic info, because $deviceResult will not be returned if CTRL + C was pressed
                Write-Warning "Device $deviceId has remediation in state '$onDemandRemediationStatus'"

                # output devices where because of reaching the time out threshold, the results weren't retrieved
                # because that doesn't mean the code wasn't run!
                $null = $deviceResult.Add([PSCustomObject]@{
                        DeviceId            = $deviceId
                        DeviceName          = $deviceList.$deviceId
                        LastSyncDateTimeUTC = $deviceDetails.LastSyncDateTime
                        ProcessedOutput     = $null
                        Output              = $null
                        Error               = $null
                        Status              = $onDemandRemediationStatus
                    })

                if ($onDemandRemediationStatus -ne "done") {
                    # "done" state means the code was run actually
                    $null = $reallyUnfinishedDeviceIdList.Add($deviceId)
                }
            }
            #endregion output devices that didn't make it in time

            if ($reallyUnfinishedDeviceIdList -and $letCommandFinish) {
                # command wasn't invoked on all devices, but it should be allowed to

                Write-Warning "'$remediationScriptName' ($($remediationScript.Id)) helper remediation will not be deleted. Do it manually when the rest of the devices $($reallyUnfinishedDeviceIdList.count) run it."
            } elseif ($reallyUnfinishedDeviceIdList) {
                # command wasn't invoked on all devices

                Write-Warning "Removing '$remediationScriptName' ($($remediationScript.Id)) helper remediation. Which means that your command won't be run on the following device(s):$($reallyUnfinishedDeviceIdList | % { "`n`t" + $deviceList.$_ + " ($_)" })"

                # remove the remediation
                Remove-IntuneRemediation -remediationScriptId $remediationScript.Id
            } else {
                # command was invoked on all devices

                # remove the remediation
                Remove-IntuneRemediation -remediationScriptId $remediationScript.Id
            }

            # outputting the results breaks the finally block invocation if CTRL + C was pressed
            # therefore placed at the total invocation end, so that remediation gets deleted etc
            # will NOT be returned if CTRL + C was pressed!
            $deviceResult
        }
    }
}