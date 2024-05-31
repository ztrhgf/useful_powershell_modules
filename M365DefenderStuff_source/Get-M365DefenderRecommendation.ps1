function Get-M365DefenderRecommendation {
    <#
    .SYNOPSIS
    Get list of all/just selected (by name or machine) recommendation/s.

    .DESCRIPTION
    Get list of all/just selected (by name or machine) recommendation/s.

    .PARAMETER productName
    Name of the product to search recommendations for.

    .PARAMETER machineId
    Id of the machine you want recommendations for.

    .PARAMETER header
    Header created using New-M365DefenderAuthHeader.

    .PARAMETER apiUrl
    API url.

    By default "api-eu.securitycenter.microsoft.com" for best performance in EU region.

    .EXAMPLE
    Get-M365DefenderRecommendation

    Get all security recommendations.

    .EXAMPLE
    Get-M365DefenderRecommendation -productName putty

    Get security recommendations just for Putty software.

    .EXAMPLE
    Get-M365DefenderRecommendation -machineId 43a802402664e76a021c8dda2e2aa7db6a09a5a4

    Get all security recommendations for given machine.

    .NOTES
    Requires SecurityRecommendation.Read.All permission.

    https://learn.microsoft.com/en-us/defender-endpoint/api/get-all-recommendations?view=o365-worldwide
    #>

    [CmdletBinding(DefaultParameterSetName = 'productName')]
    param (
        [Parameter(Mandatory = $false, ParameterSetName = "productName")]
        [string] $productName,

        [Parameter(Mandatory = $true, ParameterSetName = "machineId")]
        [string] $machineId,

        $header,

        [ValidateSet("api.securitycenter.microsoft.com", "api-eu.securitycenter.microsoft.com", "api-us.securitycenter.microsoft.com", "api-uk.securitycenter.microsoft.com", "api-au.securitycenter.microsoft.com")]
        [string] $apiUrl = "api-eu.securitycenter.microsoft.com"
    )

    if (!$header) {
        $header = New-M365DefenderAuthHeader -ErrorAction Stop
    }

    if ($machineId) {
        $url = "https://$apiUrl/api/machines/$machineId/recommendations"
    } else {
        $url = "https://$apiUrl/api/recommendations"
        if ($productName) {
            $url = $url + '?$filter=' + "productName eq '$productName'"
        }
    }

    Invoke-RestMethod2 -uri $url -headers $header
}