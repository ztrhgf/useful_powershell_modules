function Connect-Confluence {
    <#
    .SYNOPSIS
    Function for connecting to Confluence a.k.a. setting default ApiUri and Credential parameters for every Confluence cmdlet.

    .DESCRIPTION
    Function for connecting to Confluence a.k.a. setting default ApiUri and Credential parameters for every Confluence cmdlet.

    Detects already existing connection. Validates provided credentials.

    .PARAMETER baseUri
    Base URI of your cloud Confluence page. It should look like 'https://contoso.atlassian.net/wiki'.

    .PARAMETER credential
    Credentials for connecting to your cloud Confluence API.
    Use login and generated PAT (not password!).

    .EXAMPLE
    Connect-Confluence -baseUri 'https://contoso.atlassian.net/wiki' -credential (Get-Credential)

    Connects to 'https://contoso.atlassian.net/wiki' cloud Confluence base page using provided credentials.

    .NOTES
    Requires official module ConfluencePS.
    #>

    [CmdletBinding()]
    param (
        [ValidateScript( {
                if ($_ -match "^https://.+/wiki$") {
                    $true
                } else {
                    throw "$_ is not a valid Confluence wiki URL. Should be something like 'https://contoso.atlassian.net/wiki'"
                }
            })]
        [string] $baseUri = $_baseUri
        ,
        [System.Management.Automation.PSCredential] $credential
    )

    if (!$baseUri) {
        throw "BaseUri parameter has to be set. Something like 'https://contoso.atlassian.net/wiki'"
    }

    if (!(Get-Command Set-ConfluenceInfo)) {
        throw "Module ConfluencePS is missing. Unable to authenticate to the Confluence using Set-ConfluenceInfo."
    }

    # check whether already connected
    $setApiUri = $PSDefaultParameterValues.GetEnumerator() | ? Name -EQ "Get-ConfluencePage:ApiUri" | select -ExpandProperty Value

    # authenticate to Confluence
    if ($setApiUri -and $setApiUri -like "$baseUri*") {
        Write-Verbose "Already connected to $baseUri" # I assume that provided credentials are correct
        return
    } else {
        Write-Verbose "Setting ApiUri and Credential parameters for every Confluence cmdlet a.k.a. connecting to Confluence"

        Add-Type -AssemblyName System.Web

        while (!$credential) {
            $credential = Get-Credential -Message "Enter login and API key (instead of password!) for connecting to the Confluence"
        }

        # check whether provided credentials are valid
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        # create basic auth. header
        $Headers = @{"Authorization" = "Basic " + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($credential.UserName + ":" + [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($credential.Password)) ))) }
        try {
            $null = Invoke-WebRequest -Method GET -Headers $Headers -Uri "$baseUri/rest/api/content" -UseBasicParsing -ErrorAction Stop
        } catch {
            if ($_ -like "*(401) Unauthorized*") {
                throw "Provided Confluence credentials aren't valid (have you provided PAT instead of password?). Error was: $_"
            } else {
                throw $_
            }
        }

        # set default variables ApiUri and Credential parameters for every Confluence cmdlet
        Set-ConfluenceInfo -BaseURi $baseUri -Credential $credential
    }
}

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
    $body = get-process notepad | select name, cpu, id | ConvertTo-ConfluenceTable | ConvertTo-ConfluenceStorageFormat
    Set-ConfluencePage2 -pageID 1234 -body $body -setJustTable

    Replace just HTML code of the first table on the Confluence page (ID 1234) with new code (specified in body parameter). Leaves what was before and after that table intact.

    .EXAMPLE
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

Export-ModuleMember -function Connect-Confluence, ConvertTo-ConfluenceTableHtml, Get-ConfluencePage2, Get-ConfluencePageTable, Set-ConfluencePage2

