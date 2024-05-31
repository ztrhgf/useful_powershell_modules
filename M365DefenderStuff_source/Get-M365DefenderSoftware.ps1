function Get-M365DefenderSoftware {
    <#
    .SYNOPSIS
    Get list of just specific/all application/s.

    .DESCRIPTION
    Get list of just specific/all machine/s.

    .PARAMETER softwareId
    (optional) specific software ID you want to retrieve.

    .PARAMETER header
    Header created using New-M365DefenderAuthHeader.

    .PARAMETER apiUrl
    API url.

    By default "api-eu.securitycenter.microsoft.com" for best performance in EU region.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    $allApplications = Get-M365DefenderSoftware -header $header

    Get all applications from defender portal.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    $application = Get-M365DefenderSoftware -softwareId samsung-_-petservice -header $header

    Get just one specific application from defender portal.

    .NOTES
    Requires Software.Read.All permission.

    https://learn.microsoft.com/en-us/defender-endpoint/api/get-software?view=o365-worldwide
    #>

    [CmdletBinding()]
    param (
        [string] $softwareId,

        $header,

        [ValidateSet("api.securitycenter.microsoft.com", "api-eu.securitycenter.microsoft.com", "api-us.securitycenter.microsoft.com", "api-uk.securitycenter.microsoft.com", "api-au.securitycenter.microsoft.com")]
        [string] $apiUrl = "api-eu.securitycenter.microsoft.com"
    )

    if (!$header) {
        $header = New-M365DefenderAuthHeader -ErrorAction Stop
    }

    $url = "https://$apiUrl/api/software"
    if ($softwareId) {
        $url = $url + "/$softwareId"
    }

    Invoke-RestMethod2 -uri $url -headers $header
}