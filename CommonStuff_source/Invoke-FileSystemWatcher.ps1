function Invoke-FileSystemWatcher {
    <#
    .SYNOPSIS
    Function for monitoring changes made in given folder.

    .DESCRIPTION
    Function for monitoring changes made in given folder.
    Thanks to Action parameter, you can react as you wish.

    .PARAMETER PathToMonitor
    Path to folder to watch.

    .PARAMETER Filter
    How should name of file/folder to watch look like. Same syntax as for -like operator.

    Default is '*'.

    .PARAMETER IncludeSubdirectories
    Switch for monitoring also changes in subfolders.

    .PARAMETER Action
    What should happen, when change is detected. Value should be string quoted by @''@.

    Default is: @'
            $details = $event.SourceEventArgs
            $Name = $details.Name
            $FullPath = $details.FullPath
            $OldFullPath = $details.OldFullPath
            $OldName = $details.OldName
            $ChangeType = $details.ChangeType
            $Timestamp = $event.TimeGenerated
            if ($ChangeType -eq "Renamed") {
                $text = "{0} was {1} at {2} to {3}" -f $FullPath, $ChangeType, $Timestamp, $Name
            } else {
                $text = "{0} was {1} at {2}" -f $FullPath, $ChangeType, $Timestamp
            }
            Write-Host $text
    '@

    so outputting changes to console.

    .PARAMETER ChangeType
    What kind of actions should be monitored.
    Default is all i.e. "Created", "Changed", "Deleted", "Renamed"

    .PARAMETER NotifyFilter
    What kind of "sub" actions should be monitored. Can be used also to improve performance.
    More at https://docs.microsoft.com/en-us/dotnet/api/system.io.notifyfilters?view=netframework-4.8

    For example: 'FileName', 'DirectoryName', 'LastWrite'

    .EXAMPLE
    Invoke-FileSystemWatcher C:\temp "*.txt"

    Just changes to txt files in root of temp folder will be monitored.

    Just changes in name of files and folders in temp folder and its subfolders will be outputted to console and send by email.
    #>

    [CmdletBinding()]
    [Alias("Watch-FileSystem")]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript( {
                If (Test-Path -Path $_ -PathType Container) {
                    $true
                } else {
                    Throw "$_ doesn't exist or it's not a folder."
                }
            })]
        [string] $PathToMonitor
        ,
        [string] $Filter = "*"
        ,
        [switch] $IncludeSubdirectories
        ,
        [scriptblock] $Action = {
            $details = $event.SourceEventArgs
            $Name = $details.Name
            $FullPath = $details.FullPath
            $OldFullPath = $details.OldFullPath
            $OldName = $details.OldName
            $ChangeType = $details.ChangeType
            $Timestamp = $event.TimeGenerated
            if ($ChangeType -eq "Renamed") {
                $text = "{0} was {1} at {2} (previously {3})" -f $FullPath, $ChangeType, $Timestamp, $OldName
            } else {
                $text = "{0} was {1} at {2}" -f $FullPath, $ChangeType, $Timestamp
            }
            Write-Host $text
        }
        ,
        [ValidateSet("Created", "Changed", "Deleted", "Renamed")]
        [string[]] $ChangeType = ("Created", "Changed", "Deleted", "Renamed")
        ,
        [string[]] $NotifyFilter
    )

    $FileSystemWatcher = New-Object System.IO.FileSystemWatcher
    $FileSystemWatcher.Path = $PathToMonitor
    if ($IncludeSubdirectories) {
        $FileSystemWatcher.IncludeSubdirectories = $true
    }
    if ($Filter) {
        $FileSystemWatcher.Filter = $Filter
    }
    if ($NotifyFilter) {
        $NotifyFilter = $NotifyFilter -join ', '
        $FileSystemWatcher.NotifyFilter = [IO.NotifyFilters]$NotifyFilter
    }
    # Set emits events
    $FileSystemWatcher.EnableRaisingEvents = $true

    # Set event handlers
    $handlers = . {
        $changeType | % {
            Register-ObjectEvent -InputObject $FileSystemWatcher -EventName $_ -Action $Action -SourceIdentifier "FS$_"
        }
    }

    Write-Verbose "Watching for changes in $PathToMonitor where file/folder name like '$Filter'"

    try {
        do {
            Wait-Event -Timeout 1
        } while ($true)
    } finally {
        # End script actions + CTRL+C executes the remove event handlers
        $changeType | % {
            Unregister-Event -SourceIdentifier "FS$_"
        }

        # Remaining cleanup
        $handlers | Remove-Job

        $FileSystemWatcher.EnableRaisingEvents = $false
        $FileSystemWatcher.Dispose()

        Write-Warning -Message 'Event Handler completed and disabled.'
    }
}
