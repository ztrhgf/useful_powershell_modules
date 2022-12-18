function ConvertFrom-HTMLTable {
    <#
    .SYNOPSIS
    Function extracts table(s) from given HTML string, file or Com object and converts it/them into the PSObject(s).

    .DESCRIPTION
    Function extracts table(s) from given HTML string, file or Com object and converts it/them into the PSObject(s).

    Native parser can be used or HTML Agility Pack 3rd party dll (using PowerHTML wrapper module).

    .PARAMETER htmlString
    HTML string to parse.

    .PARAMETER htmlFile
    File with HTML content to parse.

    .PARAMETER htmlComObj
    HTML Com object to process.
    Html Com object can be retrieved by (Invoke-WebRequest).parsedHtml or (New-Object -Com "HTMLFile").IHTMLDocument2_write($htmlContentString).

    .PARAMETER index
    Index of the table to extract.

    By default 0 a.k.a. the first one.

    .PARAMETER useHTMLAgilityPack
    Switch for using 3rd party HTML Agility Pack dll (requires PowerHTML wrapper module!) instead of the native one.
    Mandatory for Core OS, Azure Automation etc, where native dll isn't available.
    Also it is much faster then native parser which sometimes is suuuuuuper slow, but results can slightly differ, so test thoroughly.

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
    $uri = "https://learn.microsoft.com/en-us/mem/configmgr/core/plan-design/hierarchy/communications-between-endpoints"
    $pageContent = (Invoke-WebRequest -Method GET -Uri $uri -UseBasicParsing).content
    ConvertFrom-HTMLTable $pageContent -all

    Get&convert all tables existing on given page using 3rd party parser dll.

    .EXAMPLE
    $uri = "https://learn.microsoft.com/en-us/mem/configmgr/core/plan-design/hierarchy/communications-between-endpoints"
    $pageContent = (Invoke-WebRequest -Method GET -Uri $uri -UseBasicParsing).content
    ConvertFrom-HTMLTable $pageContent -useHTMLAgilityPack -all

    Get&convert all tables existing on given page using native parser.
    All rows from all tables will be returned at once.

    .EXAMPLE
    ConvertFrom-HTMLTable -htmlFile "C:\Users\Public\Documents\MDMDiagnostics\MDMDiagReport.html"

    Get&convert just first table existing in given html file using native parser.
    All rows from all tables will be returned at once.

    .EXAMPLE
    $Source = Get-Content "C:\Users\Public\Documents\MDMDiagnostics\MDMDiagReport.html" -Raw
    $HTML = New-Object -Com "HTMLFile"
    $HTML.IHTMLDocument2_write($Source)
    ConvertFrom-HTMLTable $HTML.body

    Get&convert just first table existing in given html file using native parser.
    All rows from all tables will be returned at once.

    .EXAMPLE
    $allTables = @(ConvertFrom-HTMLTable -htmlFile "C:\Users\Public\Documents\MDMDiagnostics\MDMDiagReport.html" -all -asArrayOfTables)

    $firstTable = $allTables[0]
    $lastRowOfFirstTable = $firstTable[-1]
    $secondTable = $allTables[1]

    Get&convert all tables existing in given html file using native parser.
    Result will be array of arrays, where each array represents one table's rows.

    .EXAMPLE
    $pageContent = (Get-ConfluencePage -PageID 123456789).body
    ConvertFrom-HTMLTable $pageContent

    Get&convert just first table existing in given html string using native parser.

    .NOTES
    Good alternative seems to be PSParseHTML module.
    #>

    [CmdletBinding(DefaultParameterSetName = 'HtmlString')]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "HtmlString")]
        [ValidateScript( {
                if ($_.gettype().name -eq 'String') {
                    $true
                } else {
                    throw "HtmlString parameter isn't string but $($_.gettype().name)"
                }
            })]
        [string] $htmlString
        ,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "HtmlFile")]
        [ValidateScript( {
                if ($_ -like "*.html" -and (Test-Path -Path $_ -PathType leaf)) {
                    $true
                } else {
                    throw "'$_' is not a path to html file"
                }
            })]
        [string] $htmlFile
        ,
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "HtmlComObj")]
        [ValidateScript( {
                if ($_.gettype().name -in '__ComObject', 'HTMLDocumentClass') {
                    $true
                } else {
                    throw "HtmlComObj parameter isn't COM object but $($_.gettype().name).`nHtml Com object can be retrieved by (Invoke-WebRequest).parsedHtml or (New-Object -Com 'HTMLFile').IHTMLDocument2_write(`$htmlContentString)"
                }
            })]
        [System.__ComObject] $htmlComObj
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

    #region helper functions
    function _selectTable {
        param ($tableList)

        if (!$tableList) {
            throw "There is no table in the provided html code"
        }

        if ($index -and @($tableList).count -eq 1) {
            Write-Warning "There is only one table in the provided html code, parameter index will be ignored"
        } elseif ($index -ge @($tableList).count) {
            throw "There is only $(@($tableList).count) table(s) in the provided html code, parameter index is out of scope"
        } elseif ($index -lt @($tableList).count) {
            Write-Verbose "Selecting $($index + 1). table of $(@($tableList).count)"
            $tableList = @($tableList)[$index]
        }

        return $tableList
    }

    function _processValue {
        param ($value)

        if (!$value -or $value -in '&nbsp;', '&#32;', '&#160;') {
            $value = $null
        } else {
            if ($splitValue -and $value -like "*$splitValueBy*") {
                # value contains defined split char and should be splitted
                $value = $value -split [regex]::escape($splitValueBy)
            }

            if ($value) {
                # replace &nbsp; for " " etc
                # foreach to preserve array of values
                $value = $value | % { [System.Web.HttpUtility]::HtmlDecode($_) }
                $value = $value.trim()
            }
        }

        return $value
    }
    #endregion helper functions

    # to be able to use [System.Web.HttpUtility]::HtmlDecode()
    Add-Type -AssemblyName System.Web

    if ($htmlFile) {
        Write-Verbose "Processing HTML file '$htmlFile'"
        $htmlString = Get-Content $htmlFile -Encoding utf8 -Raw -ErrorAction Stop
    } elseif ($htmlComObj) {
        Write-Verbose "Processing given HTML Com object"
        if ($useHTMLAgilityPack) {
            $useHTMLAgilityPack = $false
            Write-Warning "Parameter useHTMLAgilityPack cannot be used with Com object"
        }
    } else {
        Write-Verbose "Processing given HTML string"
    }

    if ($useHTMLAgilityPack) {
        # process HTML content using 3rd party HTML Agility Pack
        # using wrapper a.k.a. PowerHTML module

        if (!(Get-Module PowerHTML) -and !(Get-Module PowerHTML -ListAvailable)) {
            throw "Module PowerHTML is missing. Use Install-Module command to get it."
        }

        $htmlDom = ConvertFrom-Html -Content $htmlString

        # get all table(s)
        $tableList = $htmlDom.SelectNodes('//table')

        if (!$all) {
            # select table using index
            $tableList = _selectTable $tableList
        }

        $tableNumber = 1

        foreach ($table in $tableList) {
            $result = @()
            $missingHeaderRow = $false
            # table rows
            $rowList = $table.SelectNodes('.//tr')

            Write-Verbose "$tableNumber. table has $($rowList.count) rows"

            # table column names
            $columnName = $table.SelectNodes('.//th') | % {
                # innerText on childNodes to have break lines for 'br' elements
                # remove empty lines (can exist thanks to br element)
                # return as single string because it doesn't make sense to have array of strings in header
                ($_.childNodes.innerText | ? { $_ } | % { _processValue $_ }) -join "`n"
            }
            if (!$columnName) {
                $missingHeaderRow = $true
                Write-Warning "Header row in $tableNumber. table is missing ('th' tag). Autogenerating column names"
                $columnCount = $rowList[0].SelectNodes('.//td').count
                if (!$columnCount) {
                    throw "Table is empty?"
                }
                $columnName = 0..($columnCount - 1) | % { "Column_$_" }
            } else {
                Write-Verbose "Column names are: $($columnName -join ' | ')"
            }

            if ($omitEmptyTable -and ((@($rowList).count -eq 0) -or (@($rowList).count -eq 1 -and !$missingHeaderRow))) {
                Write-Warning "Skipping $tableNumber. table because it is empty"
                ++$tableNumber
                continue
            }

            # convert each row into the PSObject
            foreach ($row in $rowList) {
                if ($row.SelectNodes('th')) {
                    Write-Verbose "Skipping header row"
                    continue
                }

                $property = [ordered]@{}

                if ($tableName) {
                    if ($tableList.count -gt 1) {
                        $property.TableName = "$tableName$tableNumber"
                    } else {
                        $property.TableName = $tableName
                    }
                }

                $i = 0
                $value = $null

                # fill property hash
                if (@($row.SelectNodes('td')).count) {
                    $row.SelectNodes('td') | % {
                        $value = ""

                        $_.childnodes | % {
                            Write-Verbose "nodeType: $($_.nodetype) name: $($_.name) innerText: $($_.innertext)"

                            if ($_.nodetype -eq 'Element' -and $_.name -eq 'br') {
                                $value += "`n"
                            } else {
                                $value += $_.innerText

                                # it is a paragraph, insert a new line
                                if ($_.nodetype -eq 'Element' -and $_.name -eq 'p') {
                                    $value += "`n"
                                }
                            }
                        }

                        $property.(@($columnName)[$i]) = (_processValue $value)

                        ++$i
                    }

                    if ($i -ne ($columnName.count)) {
                        throw "Row with value: $value is wrongly formatted. Number of values ($i) isn't same as number of columns ($($columnName.count))."
                    }

                } else {
                    # row is empty
                    0..($columnName.count - 1) | % {
                        $property.(@($columnName)[$i]) = $null

                        ++$i
                    }
                }

                $result += (New-Object -TypeName PSObject -Property $property)
            }

            ++$tableNumber

            if ($asArrayOfTables) {
                # force returning as ONE array containing table's rows
                @(, $result)
            } else {
                # return as array of table's rows
                $result
            }
        }
    } else {
        # process HTML content using native HTMLFILE COM object
        # not available on Core OS, Azure Automation sandbox etc

        if ($htmlComObj) {
            if (($htmlComObj | select -ExpandProperty TagName -ErrorAction SilentlyContinue) -eq 'table') {
                # TIP: $htmlComObj.TagName doesn't return anything
                $tableList = $htmlComObj
            } else {
                # get all table(s)
                $tableList = $htmlComObj.getElementsByTagName('table')
            }
        } else {
            try {
                $htmlDom = New-Object -ComObject "HTMLFILE" -ErrorAction Stop
            } catch {
                throw "Unable to create COM object HTMLFILE. Try calling this function with 'useHTMLAgilityPack' parameter"
            }

            try {
                # This works in PowerShell with Office installed
                $htmlDom.IHTMLDocument2_write($htmlString)
            } catch {
                # This works when Office is not installed
                $htmlDom.write([System.Text.Encoding]::Unicode.GetBytes($htmlString))
            }

            $htmlDom.Close()

            # get all table(s)
            $tableList = $htmlDom.getElementsByTagName('table')
        }

        if (!$all) {
            # select table using index
            $tableList = _selectTable $tableList
        }

        $tableNumber = 1

        foreach ($table in $tableList) {
            $result = @()
            $missingHeaderRow = $false
            # first row is header
            $startingRowIndex = 1
            # table rows
            $rowList = $table.getElementsByTagName("tr")

            Write-Verbose "$tableNumber. table has $(@($rowList).count) rows"

            # table column names
            $columnName = $table.getElementsByTagName("th") | % { $_.innerText -replace "^\s*|\s*$" }
            if (!$columnName) {
                $missingHeaderRow = $true
                Write-Warning "Header row in $tableNumber. table is missing ('th' tag). Autogenerating column names"
                $columnCount = @((@($rowList)[0].getElementsByTagName("td"))).count
                if (!$columnCount) {
                    throw "Table is empty"
                }
                $columnName = 0..($columnCount - 1) | % { "Column_$_" }
                # there is no header row
                $startingRowIndex = 0
            } else {
                Write-Verbose "Column names are: $($columnName -join ' | ')"
            }

            if ($omitEmptyTable -and ((@($rowList).count -eq 0) -or (@($rowList).count -eq 1 -and !$missingHeaderRow))) {
                Write-Warning "Skipping $tableNumber. table because it is empty"
                ++$tableNumber
                continue
            }

            foreach ($row in (@($table.getElementsByTagName('tr'))[$startingRowIndex..(@($rowList).count - 1)])) {
                $property = [ordered]@{}

                if ($tableName) {
                    if (@($tableList).count -gt 1) {
                        $property.TableName = "$tableName$tableNumber"
                    } else {
                        $property.TableName = $tableName
                    }
                }

                $i = 0
                $value = $null

                # fill property hash
                if (@($row.getElementsByTagName("td")).count) {
                    $row.getElementsByTagName("td") | % {
                        Write-Verbose "innerText: $($_.innertext)"

                        $value = _processValue $_.innerText

                        $property.(@($columnName)[$i]) = $value

                        ++$i
                    }

                    if ($i -ne ($columnName.count)) {
                        throw "Row with value: $value is wrongly formatted. Number of values ($i) isn't same as number of columns ($($columnName.count))."
                    }

                } else {
                    # row is empty
                    0..($columnName.count - 1) | % {
                        $property.(@($columnName)[$i]) = $null

                        ++$i
                    }
                }

                $result += (New-Object -TypeName PSObject -Property $property)
            }

            ++$tableNumber

            if ($asArrayOfTables) {
                # force returning as ONE array containing table's rows
                @(, $result)
            } else {
                # return as array of table's rows
                $result
            }
        }
    }
}