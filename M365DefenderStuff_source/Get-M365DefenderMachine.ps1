function Get-M365DefenderMachine {
    <#
    .SYNOPSIS
    Get list of just one/all machine/s.

    .DESCRIPTION
    Get list of just one/all machine/s.

    .PARAMETER machineId
    (optional) specific machine ID you want to retrieve.

    .PARAMETER header
    Header created using New-M365DefenderAuthHeader.

    .PARAMETER apiUrl
    API url.

    By default "api-eu.securitycenter.microsoft.com" for best performance in EU region.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    $allMachines = Get-M365DefenderMachine -header $header

    Get all machines from defender portal.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    $machine = Get-M365DefenderMachine -header $header -machineId 09a3a0af67c7bc1e5efc1a334114d00df3042cc8

    Get just one specific machine from defender portal.

    .NOTES
    Requires Machine.Read.All permission.

    https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/api/get-machine-by-id?view=o365-worldwide
    #>

    [CmdletBinding()]
    param (
        [string] $machineId,

        $header,

        [ValidateSet("api.securitycenter.microsoft.com", "api-eu.securitycenter.microsoft.com", "api-us.securitycenter.microsoft.com", "api-uk.securitycenter.microsoft.com", "api-au.securitycenter.microsoft.com")]
        [string] $apiUrl = "api-eu.securitycenter.microsoft.com"
    )

    if (!$header) {
        $header = New-M365DefenderAuthHeader -ErrorAction Stop
    }

    $url = "https://$apiUrl/api/machines"
    if ($machineId) {
        $url = $url + "/$machineId"
    }

    Invoke-RestMethod2 -uri $url -headers $header
}