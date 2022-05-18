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