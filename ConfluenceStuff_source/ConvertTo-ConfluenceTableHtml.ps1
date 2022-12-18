#requires -module ConfluencePS
function ConvertTo-ConfluenceTableHtml {
    <#
    .SYNOPSIS
    Function converts given object into HTML table code.
    Should be used instead of original '$someObject | ConvertTo-ConfluenceTable | ConvertTo-ConfluenceStorageFormat', because:
    - pipe '|' sign in object value no more breaks table formatting
    - values in cells are not surrounded with spaces a.k.a. table columns can be sorted

    .DESCRIPTION
    Function converts given object into HTML table code.
    Should be used instead of original '$someObject | ConvertTo-ConfluenceTable | ConvertTo-ConfluenceStorageFormat', because:
    - pipe '|' sign in object value no more breaks table formatting
    - values in cells are not surrounded with spaces a.k.a. table columns can be sorted

    You have to be authenticated to the Confluence before you use this function!

    .PARAMETER object
    PowerShell object that should be converted into the HTML table.

    .EXAMPLE
    # connect to your Confluence wiki
    Connect-Confluence

    # convert given objects to HTML table
    $tableHtml = ConvertTo-ConfluenceTableHtml -object (get-process svchost | select name, cpu, id )

    # replace existing Confluence page content with your table
    Set-ConfluencePage -pageID 1234 -body $tableHtml

    .NOTES
    Requires original ConfluencePS module.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $object
    )

    # requirements check
    if (!(Get-Module ConfluencePS) -and !(Get-Module ConfluencePS -ListAvailable)) {
        throw "Module ConfluencePS is missing. Function $($MyInvocation.MyCommand) cannot continue"
    }

    #region replace '|' a.k.a. pipe sign temporarily, because confluence ConvertTo-ConfluenceTable uses it for describing html table form
    $pipePlaceholder = "###PIPE###"

    $object = $object | % {
        $obj = $_
        $obj | Get-Member -MemberType NoteProperty, Property, Properties, ScriptProperty | select -ExpandProperty name | % {
            if ($obj.$_ -match "\|") {
                Write-Verbose "replacing '|' in: $($obj.$_)"
                $obj.$_ = $obj.$_ -replace "\|", $pipePlaceholder
            }
        }

        $obj
    }
    #endregion replace '|' a.k.a. pipe sign temporarily, because confluence ConvertTo-ConfluenceTable uses it for describing html table form

    $confluenceTableFormat = $object | ConvertTo-ConfluenceTable -ErrorAction Stop | ConvertTo-ConfluenceStorageFormat

    # replace pipe placeholder back to pipe sign
    $confluenceTableFormat = $confluenceTableFormat -replace $pipePlaceholder, "|"

    #region get rid of surrounding white spaces to make the table sortable
    <#
    <th><p> Name </p></th>
    <th><p> Id </p></th>
    <th><p> CPU </p></th>

    converts to:

    <th><p>Name</p></th>
    <th><p>Id</p></th>
    <th><p>CPU</p></th>
    #>
    $confluenceTableFormat = $confluenceTableFormat -replace "><p>\s+", "><p>" -replace "\s+</p><", "</p><"
    $confluenceTableFormat
    #endregion get rid of surrounding white spaces to make the table sortable
}