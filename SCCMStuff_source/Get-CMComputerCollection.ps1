function Get-CMComputerCollection {
    <#
    .SYNOPSIS
    Function returns name of computer's collection(s).

    .DESCRIPTION
    Function returns name of computer's collection(s).

    .PARAMETER computerName
    Name of computer.

    .PARAMETER SCCMServer
    Name of the SCCM server.

    Default is $_SCCMServer.

    .EXAMPLE
    Get-CMComputerCollection ni-20-ntb
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $computerName,

        [ValidateNotNullOrEmpty()]
        [string] $SCCMServer = $_SCCMServer
    )

    if (!$SCCMServer) { throw "Undefined SCCMServer" }

    (Get-WmiObject -ComputerName $SCCMServer -Namespace root/SMS/site_$_SCCMSiteCode -Query "SELECT SMS_Collection.* FROM SMS_FullCollectionMembership, SMS_Collection where name = '$computerName' and SMS_FullCollectionMembership.CollectionID = SMS_Collection.CollectionID").Name
}