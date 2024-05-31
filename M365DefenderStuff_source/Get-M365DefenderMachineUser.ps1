function Get-M365DefenderMachineUser {
    <#
    .SYNOPSIS
    Retrieves a list of all users that logged in to the specified computer.

    .DESCRIPTION
    Retrieves a list of all users that logged in to the specified computer.

    .PARAMETER header
    Header created using New-M365DefenderAuthHeader.

    .PARAMETER machineId
    Machine ID.

    .PARAMETER apiUrl
    API url.

    By default "api-eu.securitycenter.microsoft.com" for best performance in EU region.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    Get-M365DefenderMachineUser -header $header -machineId 23de7fcd303b5cee7b7aee032276bf2690448582

    Get all users for specified device.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    Get-M365DefenderMachineUser -header $header

    Get all computers and their users.

    .NOTES
    Requires User.Read.All.

    https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/api/get-machine-log-on-users?view=o365-worldwide
    #>

    [CmdletBinding()]
    param (
        $header,

        [string[]] $machineId,

        [ValidateSet("api.securitycenter.microsoft.com", "api-eu.securitycenter.microsoft.com", "api-us.securitycenter.microsoft.com", "api-uk.securitycenter.microsoft.com", "api-au.securitycenter.microsoft.com")]
        [string] $apiUrl = "api-eu.securitycenter.microsoft.com"
    )

    if (!$header) {
        $header = New-M365DefenderAuthHeader -ErrorAction Stop
    }

    if (!$machineId) {
        $machineId = Get-M365DefenderMachine -header $header | select -ExpandProperty Id
    }

    foreach ($id in $machineId) {
        $url = "https://$apiUrl/api/machines/$id/logonusers"

        Invoke-RestMethod2 -uri $url -headers $header | select *, @{n = 'MachineId'; e = { $id } }
    }
}