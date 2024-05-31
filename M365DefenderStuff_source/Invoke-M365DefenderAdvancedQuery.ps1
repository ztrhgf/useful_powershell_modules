function Invoke-M365DefenderAdvancedQuery {
    <#
    .SYNOPSIS
    Returns result of the specified KQL.

    .DESCRIPTION
    Returns result of the specified KQL.

    .PARAMETER header
    Header created using New-M365DefenderAuthHeader.

    .PARAMETER apiUrl
    API url.

    By default "api-eu.securitycenter.microsoft.com" for best performance in EU region.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    Invoke-M365DefenderAdvancedQuery -header $header -query "DeviceInfo | join kind = fullouter DeviceTvmSoftwareEvidenceBeta on DeviceId"

    Returns result of the selected KQL query.

    .NOTES
    Requires AdvancedQuery.Read.All permission.

    https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/api/run-advanced-query-api?view=o365-worldwide
    #>

    [CmdletBinding()]
    param (
        [string] $query,

        $header,

        [ValidateSet("api.securitycenter.microsoft.com", "api-eu.securitycenter.microsoft.com", "api-us.securitycenter.microsoft.com", "api-uk.securitycenter.microsoft.com", "api-au.securitycenter.microsoft.com")]
        [string] $apiUrl = "api-eu.securitycenter.microsoft.com"
    )

    if (!$header) {
        $header = New-M365DefenderAuthHeader -ErrorAction Stop
    }

    $url = "https://$apiUrl/api/advancedqueries/run"

    $queryBody = ConvertTo-Json -InputObject @{ 'Query' = $query }

    Write-Verbose "Query: $query"

    Invoke-RestMethod2 -uri $url -headers $header -method POST -body $queryBody -ErrorAction Stop | select -ExpandProperty Results
}