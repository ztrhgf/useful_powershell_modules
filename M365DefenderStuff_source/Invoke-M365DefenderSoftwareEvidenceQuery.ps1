function Invoke-M365DefenderSoftwareEvidenceQuery {
    <#
    .SYNOPSIS
    Get Software Evidence query results.

    .DESCRIPTION
    Get Software Evidence query results from DeviceTvmSoftwareEvidenceBeta table.

    .PARAMETER appName
    (optional) name of the app you want to get data for.

    .PARAMETER appVersion
    (optional) version of the app you want to get data for.

    .PARAMETER deviceId
    (optional) ID of the device you want to get data for.

    .PARAMETER header
    Header created using New-M365DefenderAuthHeader.

    .PARAMETER apiUrl
    API url.

    By default "api-eu.securitycenter.microsoft.com" for best performance in EU region.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    Invoke-M365DefenderSoftwareEvidenceQuery -header $header

    Get all (100 000 at most) results of Software Evidence table query.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    Invoke-M365DefenderSoftwareEvidenceQuery -header $header -appName JRE

    Get all (100 000 at most) results of Software Evidence table query related to JRE software.

    .NOTES
    Requires AdvancedQuery.Read.All permission.

    https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/api/run-advanced-query-api?view=o365-worldwide
    #>

    [CmdletBinding()]
    param (
        [string] $appName,

        [string] $appVersion,

        [string] $deviceId,

        $header,

        [ValidateSet("api.securitycenter.microsoft.com", "api-eu.securitycenter.microsoft.com", "api-us.securitycenter.microsoft.com", "api-uk.securitycenter.microsoft.com", "api-au.securitycenter.microsoft.com")]
        [string] $apiUrl = "api-eu.securitycenter.microsoft.com"
    )

    if (!$header) {
        $header = New-M365DefenderAuthHeader -ErrorAction Stop
    }

    #region create query
    $query = "DeviceTvmSoftwareEvidenceBeta`n| sort by SoftwareName, SoftwareVersion"

    if ($appName) {
        $query += "`n| where SoftwareName has '$appName'"
    }
    if ($appVersion) {
        $query += "`n| where SoftwareVersion has '$appVersion'"
    }
    if ($deviceId) {
        $query += "`n| where DeviceId has '$deviceId'"
    }
    #endregion create query

    Write-Verbose "Running query:`n$query"

    Invoke-M365DefenderAdvancedQuery -header $header -query $query
}