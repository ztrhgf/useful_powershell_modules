function Get-SFCLogEvent {
    <#
    .SYNOPSIS
    Function for outputting SFC related lines from CBS.log.

    .DESCRIPTION
    Function for outputting SFC related lines from CBS.log.

    .PARAMETER computerName
    Remote computer name.

    .PARAMETER justError
    Output just lines that matches regex specified in $errorRegex

    .NOTES
    https://docs.microsoft.com/en-US/troubleshoot/windows-client/deployment/analyze-sfc-program-log-file-entries
    #>

    [CmdletBinding()]
    param(
        [string] $computerName
        ,
        [switch] $justError
    )

    $cbsLog = "$env:windir\logs\cbs\cbs.log"

    if ($computerName) {
        $cbsLog = "\\$computerName\$cbsLog" -replace ":", "$"
    }

    Write-Verbose "Log path $cbsLog"

    if (Test-Path $cbsLog) {
        Get-Content $cbsLog | Select-String -Pattern "\[SR\] .*" | % {
            if (!$justError -or ($justError -and ($_ | Select-String -Pattern "verify complete|Verifying \d+|Beginning Verify and Repair transaction" -NotMatch))) {
                $match = ([regex]"^(\d{4}-\d{2}-\d{2} \d+:\d+:\d+), (\w+) \s+(.+)\[SR\] (.+)$").Match($_)

                [PSCustomObject]@{
                    Date    = Get-Date ($match.Captures.groups[1].value)
                    Type    = $match.Captures.groups[2].value
                    Message = $match.Captures.groups[4].value
                }
            }
        }

        if ($justError) {
            Write-Warning "If didn't returned anything, command 'sfc /scannow' haven't been run here or there are no errors (regex: $errorRegex)"
        } else {
            Write-Warning "If didn't returned anything, command 'sfc /scannow' probably haven't been run here"
        }
    } else {
        Write-Warning "Log $cbsLog is missing. Run 'sfc /scannow' to create it"
    }
}