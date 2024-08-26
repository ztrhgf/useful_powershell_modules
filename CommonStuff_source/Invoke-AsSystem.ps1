function Invoke-AsSystem {
    <#
    .SYNOPSIS
    Function for running specified code under SYSTEM account.

    .DESCRIPTION
    Function for running specified code under SYSTEM account.

    Helper files and sched. tasks are automatically deleted.

    .PARAMETER scriptBlock
    Scriptblock that should be run under SYSTEM account.

    .PARAMETER scriptFile
    Script that should be run under SYSTEM account.

    .PARAMETER usePSHCore
    Switch for running the code using PowerShell Core instead of Windows PowerShell.

    .PARAMETER computerName
    Name of computer, where to run this.

    .PARAMETER returnTranscript
    Add creating of transcript to specified scriptBlock and returns its output.

    .PARAMETER cacheToDisk
    Necessity for long scriptBlocks. Content will be saved to disk and run from there.

    .PARAMETER argument
    If you need to pass some variables to the scriptBlock.
    Hashtable where keys will be names of variables and values will be, well values :)

    Example:
    [hashtable]$argument = @{
        name = "John"
        cities = "Boston", "Prague"
        hash = @{var1 = 'value1','value11'; var2 = @{ key ='value' }}
    }

    Will in beginning of the scriptBlock define variables:
    $name = 'John'
    $cities = 'Boston', 'Prague'
    $hash = @{var1 = 'value1','value11'; var2 = @{ key ='value' }

    ! ONLY STRING, ARRAY and HASHTABLE variables are supported !

    .PARAMETER runAs
    Let you change if scriptBlock should be running under SYSTEM, LOCALSERVICE or NETWORKSERVICE account.

    Default is SYSTEM.

    .PARAMETER PSHCorePath
    Path to PowerShell Core executable you want to use.

    By default Core 7 is used ("$env:ProgramFiles\PowerShell\7\pwsh.exe").

    .EXAMPLE
    Invoke-AsSystem -scriptBlock {New-Item $env:TEMP\abc}

    On local computer will call given scriptblock under SYSTEM account.

    .EXAMPLE
    Invoke-AsSystem -scriptBlock {New-Item "$env:TEMP\$name"} -computerName PC-01 -ReturnTranscript -Argument @{name = 'someFolder'} -Verbose

    On computer PC-01 will call given scriptblock under SYSTEM account i.e. will create folder 'someFolder' in C:\Windows\Temp.
    Transcript will be outputted in console too.

    .EXAMPLE
    Invoke-AsSystem -scriptFile C:\Scripts\dosomestuff.ps1 -ReturnTranscript

    On local computer will run given script under SYSTEM account and return the captured output.

    .EXAMPLE
    Invoke-AsSystem -scriptFile C:\Scripts\dosomestuff.ps1 -ReturnTranscript -usePSHCore

    On local computer will run given script under SYSTEM account using PowerShell Core 7 and return the captured output.
    #>

    [CmdletBinding(DefaultParameterSetName = 'scriptBlock')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "scriptBlock")]
        [scriptblock] $scriptBlock,

        [Parameter(Mandatory = $true, ParameterSetName = "scriptFile")]
        [ValidateScript( {
                if ((Test-Path -Path $_ ) -and $_ -like "*.ps1") {
                    $true
                } else {
                    throw "$_ is not a path to ps1 script file"
                }
            })]
        [string] $scriptFile,

        [switch] $usePSHCore,

        [string] $computerName,

        [switch] $returnTranscript,

        [hashtable] $argument,

        [ValidateSet('SYSTEM', 'NETWORKSERVICE', 'LOCALSERVICE')]
        [string] $runAs = "SYSTEM",

        [switch] $cacheToDisk,

        [ValidateScript( {
                if ((Test-Path -Path $_ ) -and $_ -like "*.exe") {
                    $true
                } else {
                    throw "$_ is not a path to executable"
                }
            })]
        [string] $PSHCorePath
    )

    (Get-Variable runAs).Attributes.Clear()
    $runAs = "NT Authority\$runAs"

    if ($PSHCorePath -and !$usePSHCore) {
        $usePSHCore = $true
    }

    #region prepare Invoke-Command parameters
    # export this function to remote session (so I am not dependant whether it exists there or not)
    $allFunctionDefs = "function Create-VariableTextDefinition { ${function:Create-VariableTextDefinition} }"

    $param = @{
        argumentList = $scriptBlock, $scriptFile, $usePSHCore, $PSHCorePath, $runAs, $cacheToDisk, $allFunctionDefs, $VerbosePreference, $returnTranscript, $argument
    }

    if ($computerName -and $computerName -notmatch "localhost|$env:COMPUTERNAME") {
        $param.computerName = $computerName
    } else {
        if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            throw "You don't have administrator rights"
        }
    }
    #endregion prepare Invoke-Command parameters

    Invoke-Command @param -ScriptBlock {
        param ($scriptBlock, $scriptFile, $usePSHCore, $PSHCorePath, $runAs, $cacheToDisk, $allFunctionDefs, $VerbosePreference, $returnTranscript, $argument)

        foreach ($functionDef in $allFunctionDefs) {
            . ([ScriptBlock]::Create($functionDef))
        }

        $transcriptPath = "$ENV:TEMP\Invoke-AsSYSTEM_$(Get-Random).log"
        $encodedCommand, $temporaryScript = $null

        if ($argument -or $returnTranscript) {
            # define passed variables
            if ($argument) {
                # convert hash to variables text definition
                $variableTextDef = Create-VariableTextDefinition $argument
            }

            if ($returnTranscript) {
                # modify scriptBlock to contain creation of transcript
                $transcriptStart = "Start-Transcript $transcriptPath"
                $transcriptEnd = 'Stop-Transcript'
            }

            if ($scriptBlock) {
                $codeText = $scriptBlock.ToString()
            } else {
                $codeText = Get-Content $scriptFile -Raw
            }

            $scriptBlockContent = ($transcriptStart + "`n`n" + $variableTextDef + "`n`n" + $codeText + "`n`n" + $transcriptEnd)
            Write-Verbose "####### SCRIPTBLOCK TO RUN"
            Write-Verbose $scriptBlockContent
            Write-Verbose "#######"
            $scriptBlock = [Scriptblock]::Create($scriptBlockContent)
        }

        if ($cacheToDisk) {
            $temporaryScript = "$env:temp\$(New-Guid).ps1"
            $null = New-Item $temporaryScript -Value $scriptBlock -Force
            $pshCommand = "-ExecutionPolicy Bypass -Window Hidden -noprofile -file `"$temporaryScript`""
        } else {
            $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($scriptBlock))
            $pshCommand = "-ExecutionPolicy Bypass -Window Hidden -noprofile -EncodedCommand $($encodedCommand)"
        }

        if ($encodedCommand) {
            $OSLevel = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentVersion

            if ($OSLevel -lt 6.2) { $maxLength = 8190 } else { $maxLength = 32767 }

            if ($encodedCommand.length -gt $maxLength -and $cacheToDisk -eq $false) {
                throw "The encoded script is longer than the command line parameter limit. Please execute the script with the -CacheToDisk option."
            }
        }

        try {
            #region create&run sched. task
            if ($usePSHCore) {
                if ($PSHCorePath) {
                    $pshPath = $PSHCorePath
                } else {
                    $pshPath = "$env:ProgramFiles\PowerShell\7\pwsh.exe"

                    if (!(Test-Path $pshPath -ErrorAction SilentlyContinue)) {
                        throw "PSH Core isn't installed at '$pshPath' use 'PSHCorePath' parameter to specify correct path"
                    }
                }
            } else {
                $pshPath = "$($env:windir)\system32\WindowsPowerShell\v1.0\powershell.exe"
            }

            $taskAction = New-ScheduledTaskAction -Execute $pshPath -Argument $pshCommand

            if ($runAs -match "\$") {
                # run as gMSA account
                $taskPrincipal = New-ScheduledTaskPrincipal -UserId $runAs -LogonType Password
            } else {
                # run as system account
                $taskPrincipal = New-ScheduledTaskPrincipal -UserId $runAs -LogonType ServiceAccount
            }

            $taskSetting = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -DontStopOnIdleEnd

            $taskName = "RunAsSystem_" + (Get-Random)

            try {
                $null = New-ScheduledTask -Action $taskAction -Principal $taskPrincipal -Settings $taskSetting -ErrorAction Stop | Register-ScheduledTask -Force -TaskName $taskName -ErrorAction Stop
            } catch {
                if ($_ -match "No mapping between account names and security IDs was done") {
                    throw "Account $runAs doesn't exist or cannot be used on $env:COMPUTERNAME"
                } else {
                    throw "Unable to create helper scheduled task. Error was:`n$_"
                }
            }

            # run scheduled task
            Start-Sleep -Milliseconds 200
            Start-ScheduledTask $taskName

            # wait for sched. task to end
            Write-Verbose "waiting on sched. task end ..."
            $i = 0
            while (((Get-ScheduledTask $taskName -ErrorAction silentlyContinue).state -ne "Ready") -and $i -lt 500) {
                ++$i
                Start-Sleep -Milliseconds 200
            }

            # get sched. task result code
            $result = (Get-ScheduledTaskInfo $taskName).LastTaskResult

            # read & delete transcript
            if ($returnTranscript) {
                # return just interesting part of transcript
                if (Test-Path $transcriptPath) {
                    $transcriptContent = (Get-Content $transcriptPath -Raw) -Split [regex]::escape('**********************')
                    # return command output
                    ($transcriptContent[2] -split "`n" | Select-Object -Skip 2 | Select-Object -SkipLast 3) -join "`n"

                    Remove-Item $transcriptPath -Force
                } else {
                    Write-Warning "There is no transcript, command probably failed!"
                }
            }

            if ($temporaryScript) { $null = Remove-Item $temporaryScript -Force }

            try {
                Unregister-ScheduledTask $taskName -Confirm:$false -ErrorAction Stop
            } catch {
                throw "Unable to unregister sched. task $taskName. Please remove it manually"
            }

            if ($result -ne 0) {
                throw "Command wasn't successfully ended ($result)"
            }
            #endregion create&run sched. task
        } catch {
            throw $_.Exception
        } finally {
            Unregister-ScheduledTask $taskName -Confirm:$false -ErrorAction SilentlyContinue
            if ($temporaryScript) { $null = Remove-Item $temporaryScript -Force -ErrorAction SilentlyContinue }
        }
    }
}