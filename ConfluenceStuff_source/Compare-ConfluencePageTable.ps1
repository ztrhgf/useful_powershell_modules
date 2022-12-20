function Compare-ConfluencePageTable {
    <#
    .SYNOPSIS
    Function for comparing two list of objects. First one is gathered from given Confluence wiki page table (identified using page ID and table index), second one is given by parameter newContent.

    If both are the same, return $true else $false.

    Can be used for detection whether confluence page table has to be filled with new data.

    .DESCRIPTION
    Function for comparing two list of objects. First one is gathered from given Confluence wiki page table (identified using page ID and table index), second one is given by parameter newContent.

    If both are the same, return $true else $false.

    Can be used for detection whether confluence page table has to be filled with new data.

    Text values are trimmed before compare operation.

    .PARAMETER newContent
    Object(s) that will be compared with content gathered from Confluence page table.

    .PARAMETER pageID
    ID of the Confluence page where table content for compare will be gathered.

    .PARAMETER property
    Optional parameter for specifying list of properties, that should be used for compare.
    Otherwise all available properties will be used.

    .PARAMETER excludeProperty
    Optional parameter for specifying list of properties, that should be excluded from compare.

    .PARAMETER index
    Index of the table to get the content from.

    By default 0 a.k.a. the first one.

    .EXAMPLE
    Connect-Confluence

    $ADComputer = Get-ADComputer -filter * -properties name, description, DistinguishedName

    Compare-ConfluencePageTable -newContent $ADComputer -pageID "1318781218" -property name,description

    Will return $true if content of $ADComputer is the same as content of first HTML table on the Confluence page with ID "1318781218".
    For comparison of objects only name and description properties will be used.

    .OUTPUTS
    Boolean. True if content matches otherwise False.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $newContent
        ,
        [Parameter(Mandatory = $true)]
        [Uint64] $pageID
        ,
        [string[]] $property
        ,
        [string[]] $excludeProperty
        ,
        [int] $index = 0
    )

    $confluenceContent = Get-ConfluencePageTable -pageID $pageID -index $index

    $params = @{
        input1             = $newContent
        input2             = $confluenceContent
        trimStringProperty = $true
        #outputItemWithoutMatch = $true
    }
    if ($property) {
        $params.property = $property
    }
    if ($excludeProperty) {
        $params.excludeProperty = $excludeProperty
    }
    if ($VerbosePreference -eq "Continue") {
        $params.Verbose = $true
    }

    # compare confluence page content with the given one
    Compare-Object2 @params
}