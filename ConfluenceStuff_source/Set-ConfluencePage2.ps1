#Requires -Module ConfluencePS
function Set-ConfluencePage2 {
    <#
    .SYNOPSIS
    Proxy function for Set-ConfluencePage. Adds possibility to set just selected table's content on given page (and leave rest of the page intact).

    .DESCRIPTION
    Proxy function for Set-ConfluencePage. Adds possibility to set just selected table's content on given page (and leave rest of the page intact).

    .PARAMETER pageID
    Page ID of the Confluence page.

    .PARAMETER body
    HTML code that should be set as the new page content.

    In case you use setJustTable switch, given HTML code will replace just code of the specified (tableIndex) table.

    .PARAMETER setJustTable
    Switch for replacing just specified (tableIndex) table's HTML code (body) that is on Confluence page, nothing else.

    .PARAMETER tableIndex
    Index of the HTML table you want to replace by code specified in body parameter.
    Used only when setJustTable parameter is used.

    By default 0 a.k.a. the first one.

    .EXAMPLE
    Connect-Confluence

    $body = get-process notepad | select name, cpu, id | ConvertTo-ConfluenceTable | ConvertTo-ConfluenceStorageFormat
    Set-ConfluencePage2 -pageID 1234 -body $body -setJustTable

    Replace just HTML code of the first table on the Confluence page (ID 1234) with new code (specified in body parameter). Leaves what was before and after that table intact.

    .EXAMPLE
    Connect-Confluence

    $body = get-process notepad | select name, cpu, id | ConvertTo-ConfluenceTable | ConvertTo-ConfluenceStorageFormat
    Set-ConfluencePage2 -pageID 1234 -body $body -setJustTable -tableIndex 1

    Replace just HTML code of the second table on the Confluence page (ID 1234) with new code (specified in body parameter). Leaves what was before and after that table intact.

    .NOTES
    Update of existing table was inspired by https://garytown.com/atlassian-confluence-updating-tables-with-powershell.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Uint64] $pageID,

        [Parameter(Mandatory = $true)]
        [string] $body,

        [switch] $setJustTable,

        [int] $tableIndex = 0
    )

    try {
        $pageToUpdate = Get-ConfluencePage -PageID $pageID -ErrorAction Stop
    } catch {
        throw "You have to connect to the Confluence page first. Error was:`n$_"
    }

    if ($setJustTable) {
        # only specified ($tableIndex) html table should be updated using given html code ($body)
        # rest of the page should stay intact

        # open table tag because of: <table data-layout="default" and such
        $tableOpenTagRegex = "<table[^>]*>"
        $tableCloseTagRegex = "</table>"

        if ($body -notmatch $tableOpenTagRegex) {
            throw "Body parameter should contains string defining HTML table because you've used setJustTable switch"
        }

        # body is one big one-liner
        # to make it easy to work with, split it into the lines by closing tags
        $pageToUpdateBody = ($pageToUpdate.body -replace "><", ">`n<") -split "`n"

        $tableCount = ($pageToUpdateBody -match $tableOpenTagRegex).count
        if (!$tableCount) {
            throw "Confluence page doesn't contain any table to update"
        } elseif ($tableIndex -gt ($tableCount - 1)) {
            throw "Confluence page contains $tableCount table(s), but you want to update table number $($tableIndex + 1)"
        } else {
            Write-Verbose "Page contains $tableCount table(s)"
        }

        #region get & save all open/close html table tag line indexes
        # TIP: I assume tables are not nested
        # index of the html code line
        $i = 0
        $tableTagIndex = @()

        $pageToUpdateBody | % {
            if (($_ -match $tableOpenTagRegex) -or ($_ -match $tableCloseTagRegex)) {
                "Line with index: $i contains open/close table tag: $_"
                $tableTagIndex += $i
            }

            ++$i
        }

        # check whether number of html table tags is even
        if ($tableTagIndex.count % 2) {
            throw "Some opening or closing HTML table tag is missing"
        }
        #endregion get & save all open/close html table tag line indexes

        # create array of arrays where each array contains line indexes of open/close tags of one of the html tables on existing page
        $tableList = @()

        for ($i = 0; $i -le ($tableTagIndex.count - 1); ($i = $i + 2)) {
            $tableList += , @($tableTagIndex[$i], $tableTagIndex[$i + 1])
        }

        # get open/close line indexes of specified table
        $tableToUpdateIndex = $tableList[$tableIndex]
        $tableToUpdateOpenTagIndex = $tableToUpdateIndex[0]
        $tableToUpdateCloseTagIndex = $tableToUpdateIndex[1]

        Write-Verbose "Table to replace starts at $tableToUpdateOpenTagIndex line index and ends at $tableToUpdateCloseTagIndex"

        # get html code that is before specified table
        if ($tableToUpdateOpenTagIndex -eq 0) {
            # table is first element on the page
            $bodyBeforeTable = $null
        } else {
            # there is some content on the page before the table
            $bodyBeforeTable = $pageToUpdateBody[0..($tableToUpdateOpenTagIndex - 1)]
        }

        # get html code that is after specified table
        if ($tableToUpdateCloseTagIndex -eq ($pageToUpdateBody.count - 1)) {
            # table is last element on the page
            $bodyAfterTable = $null
        } else {
            # there is some content on the page after the table
            $bodyAfterTable = $pageToUpdateBody[($tableToUpdateCloseTagIndex + 1)..(($pageToUpdateBody.count - 1))]
        }

        # take existing page html code and replace specified table's code with the new one
        $body = ($bodyBeforeTable -join '') + $body + ($bodyAfterTable -join '')
    }

    Write-Verbose "Set content of the Confluence page with ID $pageID to:`n$body"
    Set-ConfluencePage -PageID $pageID -Body $body
}