function Get-ConfluencePage2 {
    <#
    .SYNOPSIS
    Function returns Confluence page content using native Invoke-WebRequest. Returned object contains parsed HTML (as Com object), raw HTML page content etc.

    .DESCRIPTION
    Function returns Confluence page content using native Invoke-WebRequest. Returned object contains parsed HTML (as Com object), raw HTML page content etc.

    .PARAMETER pageID
    ID of the Confluence page.

    Can be extracted from page URL https://contoso.atlassian.net/wiki/spaces/KID/pages/123456789/dummyname a.k.a. it's 123456789 in this case.

    .PARAMETER header
    Authentication header created using Create-BasicAuthHeader.

    .EXAMPLE
    $baseUri = 'https://contoso.atlassian.net/wiki'
    $credential = Get-Credential

    Connect-Confluence -baseUri $baseUri -credential $credential
    $header = Create-BasicAuthHeader -credential $credential

    $response = Get-ConfluencePage2 -pageId 123456789 -baseUri $baseUri -header $header

    # get page html code as a string
    $response.Content

    # get page as parsed Com object
    $response.ParsedHtml

    # use parsed Com object for extracting existing table as a psobject
    ConvertFrom-HTMLTable -htmlComObj $response.ParsedHtml
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [Uint64] $pageID,

        [Parameter(Mandatory = $true)]
        [ValidateScript( {
                if ($_ -match "^https://.+/wiki$") {
                    $true
                } else {
                    throw "$_ is not a valid Confluence wiki URL. Should be something like 'https://contoso.atlassian.net/wiki'"
                }
            })]
        [string] $baseUri,

        [Parameter(Mandatory = $true)]
        $header
    )


    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        $response = Invoke-WebRequest -Method GET -Headers $header -Uri "$baseUri/rest/api/content/$pageID`?expand=body.storage" -ea stop
    } catch {
        if ($_.exception -match "The response content cannot be parsed because the Internet Explorer engine is not available") {
            throw "Error was: $($_.exception)`n Run following command on $env:COMPUTERNAME to solve this:`nSet-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Internet Explorer\Main' -Name DisableFirstRunCustomize -Value 2"
        } else {
            throw $_
        }
    }

    $response.ParsedHtml
}