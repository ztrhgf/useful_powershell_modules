#requires -module ConfluencePS

function Get-ConfluencePageTable {
    <#
    .SYNOPSIS
    Function extracts table from given Confluence page and converts it into the psobject.

    .DESCRIPTION
    Function extracts table from given Confluence page and converts it into the psobject.

    .PARAMETER pageID
    Confluence page ID.

    .PARAMETER index
    Index of the table to extract.

    By default 0 a.k.a. the first one.

    .PARAMETER useHTMLAgilityPack
    Switch for using 3rd party HTML Agility Pack dll (requires PowerHTML wrapper module!) instead of the native one.
    Mandatory for Core OS, Azure Automation etc, where native dll isn't available.
    Also it is much faster then native parser which sometimes is suuuuuuper slow.

    .PARAMETER splitValue
    Switch for splitting table cell values a.k.a. get array of cell values instead of one string.
    Delimiter is defined in splitValueBy parameter.

    .PARAMETER splitValueBy
    Delimiter for splitting column values.

    .PARAMETER all
    Switch to process all tables in given HTML.

    .PARAMETER tableName
    Adds property tableName with given name to each returned object.
    If more than one table is returned, adds table number suffix to the given name.

    .PARAMETER omitEmptyTable
    Switch to skip empty tables.
    Empty means there are no other rows except the header one.

    .PARAMETER asArrayOfTables
    Switch for returning the result as array of tables where each array contains rows of such table.
    By default array of all rows from all tables is being returned at once.

    Beware that if only one table is returned, PowerShell automatically expands this one array to array of containing items! To avoid this behavior use @():
        $result = @(ConvertFrom-HTMLTable -htmlFile "C:\Users\Public\Documents\MDMDiagnostics\MDMDiagReport.html" -all -asArrayOfTables).

    .EXAMPLE
    Connect-Confluence

    Get-ConfluencePageTable -PageID 123456789

    Get & convert just first table existing at given confluence page using native parser. Table lines will be returned one by one.

    .EXAMPLE
    Connect-Confluence

    Get-ConfluencePageTable -PageID 123456789 -useHTMLAgilityPack -index 1

    Get & convert just second table existing at given confluence page using 3rd party (HTML Agility Pack) parser. Table lines will be returned one by one.

    .EXAMPLE
    Connect-Confluence

    Get-ConfluencePageTable -PageID 123456789 -useHTMLAgilityPack -all -omitEmptyTable -asArrayOfTables

    Get & convert all tables existing at given confluence page using 3rd party (HTML Agility Pack) parser. Table's lines will be returned inside an array a.k.a. result will be array of arrays. Empty tables will be omitted (instead of returning empty object).
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [Uint64] $pageID
        ,
        [ValidateNotNullOrEmpty()]
        [int] $index = 0
        ,
        [switch] $useHTMLAgilityPack
        ,
        [switch] $splitValue
        ,
        [string] $splitValueBy = ","
        ,
        [switch] $all,

        [string] $tableName,

        [switch] $omitEmptyTable,

        [switch] $asArrayOfTables
    )

    # requirements check
    if (!(Get-Module ConfluencePS) -and !(Get-Module ConfluencePS -ListAvailable)) {
        throw "Module ConfluencePS is missing. Function $($MyInvocation.MyCommand) cannot continue"
    }

    # get confluence page content
    $pageContent = (Get-ConfluencePage -PageID $pageID -ea Stop).body

    # create ConvertFrom-HTMLTable parameter hash
    $param = @{
        htmlString = $pageContent
    }
    # pass other defined parameters
    # exclude parameters not for ConvertFrom-HTMLTable
    $PSBoundParameters.getenumerator() | ? { $_.key -ne 'pageID' } | % {
        $param.($_.key) = $_.value
    }

    # extract & convert table(s) from given html code using provided parameters
    ConvertFrom-HTMLTable @param
}