function Invoke-FileContentWatcher {
    <#
    .SYNOPSIS
    Function for monitoring file content.

    .DESCRIPTION
    Function for monitoring file content.
    Allows you to react on create of new line with specific content.

    Outputs line(s) that match searched string.

    .PARAMETER path
    Path to existing file that should be monitored.

    .PARAMETER searchString
    String that should be searched in newly added lines.

    .PARAMETER searchAsRegex
    Searched string is regex.

    .PARAMETER stopOnFirstMatch
    Switch for stopping search on first match.

    .EXAMPLE
    Invoke-FileContentWatcher -Path C:\temp\mylog.txt -searchString "Error occurred"

    Start monitoring of newly added lines in C:\temp\mylog.txt file. If some line should contain "Error occurred" string, whole line will be outputted into console.

    .EXAMPLE
    Invoke-FileContentWatcher -Path C:\temp\mylog.txt -searchString "Action finished" -stopOnFirstMatch

    Start monitoring of newly added lines in C:\temp\mylog.txt file. If some line should contain "Action finished" string, whole line will be outputted into console and function will end.
    #>

    [Alias("Watch-FileContent")]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $path,

        [Parameter(Mandatory = $true)]
        [string] $searchString,

        [switch] $searchAsRegex,

        [switch] $stopOnFirstMatch
    )

    $fileName = Split-Path $path -Leaf
    $jobName = "ContentWatcher_" + $fileName + "_" + (Get-Date).ToString('HH:mm.ss')

    $null = Start-Job -Name $jobName -ScriptBlock {
        param ($path, $searchString, $searchAsRegex)

        $gcParam = @{
            Path        = $path
            Wait        = $true
            Tail        = 0 # I am interested just in newly added lines
            ErrorAction = 'Stop'
        }

        if ($searchAsRegex) {
            Get-Content @gcParam | ? { $_ -match "$searchString" }
        } else {
            Get-Content @gcParam | ? { $_ -like "*$searchString*" }
        }
    } -ArgumentList $path, $searchString, $searchAsRegex

    while (1) {
        Start-Sleep -Milliseconds 300

        if ((Get-Job -Name $jobName).state -eq 'Completed') {
            $result = Get-Job -Name $jobName | Receive-Job

            Get-Job -Name $jobName | Remove-Job -Force

            throw "Watcher $jobName failed with error: $result"
        }

        if (Get-Job -Name $jobName | Receive-Job -Keep) {
            # searched string was found
            $result = Get-Job -Name $jobName | Receive-Job

            if ($stopOnFirstMatch) {
                Get-Job -Name $jobName | Remove-Job -Force

                return $result
            } else {
                $result
            }
        }
    }
}