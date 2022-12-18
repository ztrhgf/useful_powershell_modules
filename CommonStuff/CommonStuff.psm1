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

function ConvertFrom-XML {
    <#
    .SYNOPSIS
    Function for converting XML object (XmlNode) to PSObject.

    .DESCRIPTION
    Function for converting XML object (XmlNode) to PSObject.

    .PARAMETER node
    XmlNode object (retrieved like: [xml]$xmlObject = (Get-Content C:\temp\file.xml -Raw))

    .EXAMPLE
    [xml]$xmlObject = (Get-Content C:\temp\file.xml -Raw)
    ConvertFrom-XML $xmlObject

    .NOTES
    Based on https://stackoverflow.com/questions/3242995/convert-xml-to-psobject
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [System.Xml.XmlNode] $node
    )

    #region helper functions

    function ConvertTo-PsCustomObjectFromHashtable {
        param (
            [Parameter(
                Position = 0,
                Mandatory = $true,
                ValueFromPipeline = $true,
                ValueFromPipelineByPropertyName = $true
            )] [object[]]$hashtable
        );

        begin { $i = 0; }

        process {
            foreach ($myHashtable in $hashtable) {
                if ($myHashtable.GetType().Name -eq 'hashtable') {
                    $output = New-Object -TypeName PsObject;
                    Add-Member -InputObject $output -MemberType ScriptMethod -Name AddNote -Value {
                        Add-Member -InputObject $this -MemberType NoteProperty -Name $args[0] -Value $args[1];
                    };
                    $myHashtable.Keys | Sort-Object | % {
                        $output.AddNote($_, $myHashtable.$_);
                    }
                    $output
                } else {
                    Write-Warning "Index $i is not of type [hashtable]";
                }
                $i += 1;
            }
        }
    }
    #endregion helper functions

    $hash = @{}

    foreach ($attribute in $node.attributes) {
        $hash.$($attribute.name) = $attribute.Value
    }

    $childNodesList = ($node.childnodes | ? { $_ -ne $null }).LocalName

    foreach ($childnode in ($node.childnodes | ? { $_ -ne $null })) {
        if (($childNodesList.where( { $_ -eq $childnode.LocalName })).count -gt 1) {
            if (!($hash.$($childnode.LocalName))) {
                Write-Verbose "ChildNode '$($childnode.LocalName)' isn't in hash. Creating empty array and storing in hash.$($childnode.LocalName)"
                $hash.$($childnode.LocalName) += @()
            }
            if ($childnode.'#text') {
                Write-Verbose "Into hash.$($childnode.LocalName) adding '$($childnode.'#text')'"
                $hash.$($childnode.LocalName) += $childnode.'#text'
            } else {
                Write-Verbose "Into hash.$($childnode.LocalName) adding result of ConvertFrom-XML called upon '$($childnode.Name)' node object"
                $hash.$($childnode.LocalName) += ConvertFrom-XML($childnode)
            }
        } else {
            Write-Verbose "In ChildNode list ($($childNodesList -join ', ')) is only one node '$($childnode.LocalName)'"

            if ($childnode.'#text') {
                Write-Verbose "Into hash.$($childnode.LocalName) set '$($childnode.'#text')'"
                $hash.$($childnode.LocalName) = $childnode.'#text'
            } else {
                Write-Verbose "Into hash.$($childnode.LocalName) set result of ConvertFrom-XML called upon '$($childnode.Name)' $($childnode.Value) object"
                $hash.$($childnode.LocalName) = ConvertFrom-XML($childnode)
            }
        }
    }

    Write-Verbose "Returning hash ($($hash.Values -join ', '))"
    return $hash | ConvertTo-PsCustomObjectFromHashtable
}

function Create-BasicAuthHeader {
    <#
    .SYNOPSIS
    Function returns basic authentication header that can be used for web requests.

    .DESCRIPTION
    Function returns basic authentication header that can be used for web requests.

    .PARAMETER credential
    Credentials object that will be used to create auth. header.

    .EXAMPLE
    $header = Create-BasicAuthHeader -credential (Get-Credential)
    $response = Invoke-RestMethod -Uri "https://example.com/api" -Headers $header
    #>

    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential] $credential
    )

    @{
        "Authorization" = "Basic " + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($Credential.UserName + ":" + [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($Credential.Password)) )))
    }
}

function Export-ScriptsToModule {
    <#
    .SYNOPSIS
        Function for generating Powershell module from ps1 scripts (that contains definition of functions) that are stored in given folder.
        Generated module will also contain function aliases (no matter if they are defined using Set-Alias or [Alias("Some-Alias")].
        Every script file has to have exactly same name as function that is defined inside it (ie Get-LoggedUsers.ps1 contains just function Get-LoggedUsers).
        If folder with ps1 script(s) contains also module manifest (psd1 file), it will be added as manifest of the generated module.
        In console where you call this function, font that can show UTF8 chars has to be set.

    .PARAMETER configHash
        Hash in specific format, where key is path to folder with scripts and value is path to which module should be generated.

        eg.: @{"C:\temp\scripts" = "C:\temp\Modules\Scripts"}

    .PARAMETER enc
        Which encoding should be used.

        Default is UTF8.

    .PARAMETER includeUncommitedUntracked
        Export also functions from modified-and-uncommited and untracked files.
        And use modified-and-untracked module manifest if necessary.

    .PARAMETER dontCheckSyntax
        Switch that will disable syntax checking of created module.

    .PARAMETER dontIncludeRequires
        Switch that will lead to ignoring all #requires in scripts, so generated module won't contain them.
        Otherwise just module #requires will be added.

    .PARAMETER markAutoGenerated
        Switch will add comment '# _AUTO_GENERATED_' on first line of each module, that was created by this function.
        For internal use, so I can distinguish which modules was created from functions stored in scripts2module and therefore easily generate various reports.

    .EXAMPLE
        Export-ScriptsToModule @{"C:\DATA\POWERSHELL\repo\scripts" = "c:\DATA\POWERSHELL\repo\modules\Scripts"}
    #>

    [CmdletBinding()]
    param (
        [ValidateNotNullOrEmpty()]
        [hashtable] $configHash
        ,
        [ValidateNotNullOrEmpty()]
        [string] $enc = 'utf8'
        ,
        [switch] $includeUncommitedUntracked
        ,
        [switch] $dontCheckSyntax
        ,
        [switch] $dontIncludeRequires
        ,
        [switch] $markAutoGenerated
    )

    if (!(Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue) -and !$dontCheckSyntax) {
        Write-Warning "Syntax won't be checked, because function Invoke-ScriptAnalyzer is not available (part of module PSScriptAnalyzer)"
    }

    function _generatePSModule {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            $scriptFolder
            ,
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            $moduleFolder
            ,
            [switch] $includeUncommitedUntracked
        )

        if (!(Test-Path $scriptFolder)) {
            throw "Path $scriptFolder is not accessible"
        }

        $moduleName = Split-Path $moduleFolder -Leaf
        $modulePath = Join-Path $moduleFolder "$moduleName.psm1"
        $function2Export = @()
        $alias2Export = @()
        # modules that are required by some of the exported functions
        $requiredModulesList = @()
        # contains function that will be exported to the module
        # the key is name of the function and value is its text definition
        $lastCommitFileContent = @{ }
        $location = Get-Location
        Set-Location $scriptFolder
        $unfinishedFile = @()
        try {
            # uncommited changed files
            $unfinishedFile += @(git ls-files -m --full-name)
            # untracked files
            $unfinishedFile += @(git ls-files --others --exclude-standard --full-name)
        } catch {
            throw "It seems GIT isn't installed. I was unable to get list of changed files in repository $scriptFolder"
        }
        Set-Location $location

        #region get last commited content of the modified untracked or uncommited files
        if ($unfinishedFile) {
            # there are untracked and/or uncommited files
            # instead just ignoring them try to get and use previous version from GIT
            [System.Collections.ArrayList] $unfinishedFile = @($unfinishedFile)

            # helper function to be able to catch errors and all outputs
            # dont wait for exit
            function _startProcess {
                [CmdletBinding()]
                param (
                    [string] $filePath = 'notepad.exe',
                    [string] $argumentList = '/c dir',
                    [string] $workingDirectory = (Get-Location)
                )

                $p = New-Object System.Diagnostics.Process
                $p.StartInfo.UseShellExecute = $false
                $p.StartInfo.RedirectStandardOutput = $true
                $p.StartInfo.RedirectStandardError = $true
                $p.StartInfo.WorkingDirectory = $workingDirectory
                $p.StartInfo.FileName = $filePath
                $p.StartInfo.Arguments = $argumentList
                [void]$p.Start()
                # $p.WaitForExit() # cannot be used otherwise if git show HEAD:$file returned something, process stuck
                $p.StandardOutput.ReadToEnd()
                if ($err = $p.StandardError.ReadToEnd()) {
                    Write-Error $err
                }
            }

            $unfinishedScriptFile = $unfinishedFile.Clone() | ? { $_ -like "*.ps1" }

            if (!$includeUncommitedUntracked) {
                Set-Location $scriptFolder

                $unfinishedScriptFile | % {
                    $file = $_
                    $lastCommitContent = $null
                    $fName = [System.IO.Path]::GetFileNameWithoutExtension($file)

                    try {
                        $lastCommitContent = _startProcess git "show HEAD:$file" -ErrorAction Stop
                    } catch {
                        Write-Verbose "GIT error: $_"
                    }

                    if (!$lastCommitContent -or $lastCommitContent -match "^fatal: ") {
                        Write-Warning "$fName has uncommited changes. Skipping, because no previous file version was found in GIT"
                    } else {
                        Write-Warning "$fName has uncommited changes. For module generating I will use content from its last commit"
                        $lastCommitFileContent.$fName = $lastCommitContent
                        $unfinishedFile.Remove($file)
                    }
                }

                Set-Location $location
            }

            # unix / replace by \
            $unfinishedFile = $unfinishedFile -replace "/", "\"

            $unfinishedScriptFileName = $unfinishedScriptFile | % { [System.IO.Path]::GetFileName($_) }

            if ($includeUncommitedUntracked -and $unfinishedScriptFileName) {
                Write-Warning "Exporting changed but uncommited/untracked functions: $($unfinishedScriptFileName -join ', ')"
                $unfinishedFile = @()
            }
        }
        #endregion get last commited content of the modified untracked or uncommited files

        # in ps1 files to export leave just these in consistent state
        $script2Export = (Get-ChildItem (Join-Path $scriptFolder "*.ps1") -File).FullName | where {
            $partName = ($_ -split "\\")[-2..-1] -join "\"
            if ($unfinishedFile -and $unfinishedFile -match [regex]::Escape($partName)) {
                return $false
            } else {
                return $true
            }
        }

        if (!$script2Export -and $lastCommitFileContent.Keys.Count -eq 0) {
            Write-Warning "In $scriptFolder there is none usable function to export to $moduleFolder. Exiting"
            return
        }

        #region cleanup old module folder
        if (Test-Path $modulePath -ErrorAction SilentlyContinue) {
            Write-Verbose "Removing $moduleFolder"
            Remove-Item $moduleFolder -Recurse -Confirm:$false -ErrorAction Stop
            Start-Sleep 1
            [Void][System.IO.Directory]::CreateDirectory($moduleFolder)
        }
        #endregion cleanup old module folder

        Write-Verbose "Functions from the '$scriptFolder' will be converted to module '$modulePath'"

        #region fill $lastCommitFileContent hash with functions content
        $script2Export | % {
            $script = $_
            $fName = [System.IO.Path]::GetFileNameWithoutExtension($script)
            if ($fName -match "\s+") {
                throw "File $script contains space in name which is nonsense. Name of file has to be same to the name of functions it defines and functions can't contain space in it's names."
            }

            # add function content only in case it isn't added already (to avoid overwrites)
            if (!$lastCommitFileContent.containsKey($fName)) {
                # check, that file contain just one function definition and nothing else
                $ast = [System.Management.Automation.Language.Parser]::ParseFile("$script", [ref] $null, [ref] $null)
                # just END block should exist
                if ($ast.BeginBlock -or $ast.ProcessBlock) {
                    throw "File $script isn't in correct format. It has to contain just function definition (+ alias definition, comment or requires)!"
                }

                # get funtion definition
                $functionDefinition = $ast.FindAll( {
                        param([System.Management.Automation.Language.Ast] $ast)

                        $ast -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                        # Class methods have a FunctionDefinitionAst under them as well, but we don't want them.
                        ($PSVersionTable.PSVersion.Major -lt 5 -or
                        $ast.Parent -isnot [System.Management.Automation.Language.FunctionMemberAst])
                    }, $false)

                if ($functionDefinition.count -ne 1) {
                    throw "File $script doesn't contain any function or contain's more than one."
                }

                #TODO pouzivat pro jmeno funkce jeji skutecne jmeno misto nazvu souboru?.
                # $fName = $functionDefinition.name

                # define empty function body
                $content = ""

                # use function definition obtained by AST to generate module
                # this way no possible dangerous content will be added

                $requiredModules = $ast.scriptRequirements.requiredModules.name
                if ($requiredModules) {
                    $requiredModulesList += $requiredModules
                    Write-Verbose ("Function $fName has defined following module requirements: $($requiredModules -join ', ')")
                }

                if (!$dontIncludeRequires) {
                    # adding module requires
                    if ($requiredModules) {
                        $content += "#Requires -Modules $($requiredModules -join ',')`n`n"
                    }
                }
                # replace invalid chars for valid (en dash etc)
                $functionText = $functionDefinition.extent.text -replace [char]0x2013, "-" -replace [char]0x2014, "-"

                # add function text definition
                $content += $functionText

                # add aliases defined by Set-Alias
                $ast.EndBlock.Statements | ? { $_ -match "^\s*Set-Alias .+" } | % { $_.extent.text } | % {
                    $parts = $_ -split "\s+"

                    $content += "`n$_"

                    if ($_ -match "-na") {
                        # alias set by named parameter
                        # get parameter value
                        $i = 0
                        $parPosition
                        $parts | % {
                            if ($_ -match "-na") {
                                $parPosition = $i
                            }
                            ++$i
                        }

                        # save alias for later export
                        $alias2Export += $parts[$parPosition + 1]
                        Write-Verbose "- exporting alias: $($parts[$parPosition + 1])"
                    } else {
                        # alias set by positional parameter
                        # save alias for later export
                        $alias2Export += $parts[1]
                        Write-Verbose "- exporting alias: $($parts[1])"
                    }
                }

                # add aliases defined by [Alias("Some-Alias")]
                $innerAliasDefinition = $ast.FindAll( {
                        param([System.Management.Automation.Language.Ast] $ast)

                        $ast -is [System.Management.Automation.Language.AttributeAst]
                    }, $true) | ? { $_.parent.extent.text -match '^param' } | Select-Object -ExpandProperty PositionalArguments | Select-Object -ExpandProperty Value -ErrorAction SilentlyContinue # filter out aliases for function parameters

                if ($innerAliasDefinition) {
                    $innerAliasDefinition | % {
                        $alias2Export += $_
                        Write-Verbose "- exporting 'inner' alias: $_"
                    }
                }

                $lastCommitFileContent.$fName = $content
            }
        }
        #endregion fill $lastCommitFileContent hash with functions content

        if ($markAutoGenerated) {
            "# _AUTO_GENERATED_" | Out-File $modulePath $enc
            "" | Out-File $modulePath -Append $enc
        }

        #region save all functions content to the module file
        # store name of every function for later use in Export-ModuleMember
        $lastCommitFileContent.GetEnumerator() | Sort-Object Name | % {
            $fName = $_.Key
            $content = $_.Value

            Write-Verbose "- exporting function: $fName"
            $function2Export += $fName

            $content | Out-File $modulePath -Append $enc
            "" | Out-File $modulePath -Append $enc
        }
        #endregion save all functions content to the module file

        #region set what functions and aliases should be exported from module
        # explicit export is much faster than use *
        if (!$function2Export) {
            throw "There are none functions to export! Wrong path??"
        } else {
            if ($function2Export -match "#") {
                Remove-Item $modulePath -Recurse -Force -Confirm:$false
                throw "Exported function contains unnaproved character # in it's name. Module was removed."
            }

            $function2Export = $function2Export | Select-Object -Unique | Sort-Object

            "Export-ModuleMember -function $($function2Export -join ', ')" | Out-File $modulePath -Append $enc
            "" | Out-File $modulePath -Append $enc
        }

        if ($alias2Export) {
            if ($alias2Export -match "#") {
                Remove-Item $modulePath -Recurse -Force -Confirm:$false
                throw "Exported alias contains unapproved character # in it's name. Module was removed."
            }

            $alias2Export = $alias2Export | Select-Object -Unique | Sort-Object

            "Export-ModuleMember -alias $($alias2Export -join ', ')" | Out-File $modulePath -Append $enc
        }
        #endregion set what functions and aliases should be exported from module

        #region process module manifest (psd1) file
        $manifestFile = (Get-ChildItem (Join-Path $scriptFolder "*.psd1") -File).FullName

        if ($manifestFile) {
            if ($manifestFile.count -eq 1) {
                $partName = ($manifestFile -split "\\")[-2..-1] -join "\"
                if ($partName -in $unfinishedFile -and !$includeUncommitedUntracked) {
                    Write-Warning "Module manifest file '$manifestFile' is modified but not commited."

                    $choice = ""
                    while ($choice -notmatch "^[Y|N]$") {
                        $choice = Read-Host "Continue? (Y|N)"
                    }
                    if ($choice -eq "N") {
                        break
                    }
                }

                try {
                    Write-Verbose "Processing '$manifestFile' manifest file"
                    $manifestDataHash = Import-PowerShellDataFile $manifestFile -ErrorAction Stop
                } catch {
                    Write-Error "Unable to process manifest file '$manifestFile'.`n`n$_"
                }

                if ($manifestDataHash) {
                    # customize manifest data
                    Write-Verbose "Set manifest RootModule key"
                    $manifestDataHash.RootModule = "$moduleName.psm1"
                    Write-Verbose "Set manifest FunctionsToExport key"
                    $manifestDataHash.FunctionsToExport = $function2Export
                    Write-Verbose "Set manifest AliasesToExport key"
                    if ($alias2Export) {
                        $manifestDataHash.AliasesToExport = $alias2Export
                    } else {
                        $manifestDataHash.AliasesToExport = @()
                    }
                    # remove key if empty, because Update-ModuleManifest doesn't like it
                    if ($manifestDataHash.keys -contains "RequiredModules" -and !$manifestDataHash.RequiredModules) {
                        Write-Verbose "Removing manifest key RequiredModules because it is empty"
                        $manifestDataHash.Remove('RequiredModules')
                    }

                    # warn about missing required modules in manifest file
                    if ($requiredModulesList -and $manifestDataHash.RequiredModules) {
                        $reqModulesMissingInManifest = $requiredModulesList | ? { $_ -notin $manifestDataHash.RequiredModules }
                        if ($reqModulesMissingInManifest) {
                            Write-Warning "Following modules are required by some of the module function(s), but are missing from manifest file '$manifestFile' key 'RequiredModules': $($reqModulesMissingInManifest -join ', ')"
                        }
                    }

                    # create final manifest file
                    Write-Verbose "Generating module manifest file"
                    # create empty one and than update it because of the bug https://github.com/PowerShell/PowerShell/issues/5922
                    New-ModuleManifest -Path (Join-Path $moduleFolder "$moduleName.psd1")
                    Update-ModuleManifest -Path (Join-Path $moduleFolder "$moduleName.psd1") @manifestDataHash
                    if ($manifestDataHash.PrivateData.PSData) {
                        # bugfix because PrivateData parameter expect content of PSData instead of PrivateData
                        Update-ModuleManifest -Path (Join-Path $moduleFolder "$moduleName.psd1") -PrivateData $manifestDataHash.PrivateData.PSData
                    }
                }
            } else {
                Write-Warning "Module manifest file won't be processed because more then one were found."
            }
        } else {
            Write-Verbose "No module manifest file found"
        }
        #endregion process module manifest (psd1) file
    } # end of _generatePSModule

    $configHash.GetEnumerator() | % {
        $scriptFolder = $_.key
        $moduleFolder = $_.value

        $param = @{
            scriptFolder = $scriptFolder
            moduleFolder = $moduleFolder
            verbose      = $VerbosePreference
        }
        if ($includeUncommitedUntracked) {
            $param["includeUncommitedUntracked"] = $true
        }

        _generatePSModule @param

        if (!$dontCheckSyntax -and (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)) {
            # check generated module syntax
            $syntaxError = Invoke-ScriptAnalyzer $moduleFolder -Severity Error
            if ($syntaxError) {
                Write-Warning "In module $moduleFolder was found these problems:"
                $syntaxError
            }
        }
    }
}

function Get-InstalledSoftware {
    <#
    .SYNOPSIS
    Function returns installed applications.

    .DESCRIPTION
    Function returns installed applications.
    Such information is retrieved from registry keys 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\', 'SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\'.

    .PARAMETER ComputerName
    Name of the remote computer where you want to run this function.

    .PARAMETER AppName
    (optional) Name of the application(s) to look for.
    It can be just part of the app name.

    .PARAMETER DontIgnoreUpdates
    Switch for getting Windows Updates too.

    .PARAMETER Property
    What properties of the registry key should be returned.

    Default is 'DisplayVersion', 'UninstallString'.

    DisplayName will be always returned no matter what.

    .PARAMETER Ogv
    Switch for getting results in Out-GridView.

    .EXAMPLE
    Get-InstalledSoftware

    Show all installed applications on local computer

    .EXAMPLE
    Get-InstalledSoftware -DisplayName 7zip

    Check whether application with name 7zip is installed on local computer.

    .EXAMPLE
    Get-InstalledSoftware -DisplayName 7zip -Property Publisher, Contact, VersionMajor -Ogv

    Check whether application with name 7zip is installed on local computer and output results to Out-GridView with just selected properties.

    .EXAMPLE
    Get-InstalledSoftware -ComputerName PC01

    Show all installed applications on computer PC01.
    #>

    [CmdletBinding()]
    param(
        [ArgumentCompleter( {
                param ($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)

                Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\', 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\' | % { try { Get-ItemPropertyValue -Path $_.pspath -Name DisplayName -ErrorAction Stop } catch { $null } } | ? { $_ -like "*$WordToComplete*" } | % { "'$_'" }
            })]
        [string[]] $appName,

        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]] $computerName,

        [switch] $dontIgnoreUpdates,

        [ValidateNotNullOrEmpty()]
        [ValidateSet('AuthorizedCDFPrefix', 'Comments', 'Contact', 'DisplayName', 'DisplayVersion', 'EstimatedSize', 'HelpLink', 'HelpTelephone', 'InstallDate', 'InstallLocation', 'InstallSource', 'Language', 'ModifyPath', 'NoModify', 'NoRepair', 'Publisher', 'QuietUninstallString', 'UninstallString', 'URLInfoAbout', 'URLUpdateInfo', 'Version', 'VersionMajor', 'VersionMinor', 'WindowsInstaller')]
        [string[]] $property = ('DisplayName', 'DisplayVersion', 'UninstallString'),

        [switch] $ogv
    )

    PROCESS {
        $scriptBlock = {
            param ($Property, $DontIgnoreUpdates, $appName)

            # where to search for applications
            $RegistryLocation = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\', 'SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\'

            # define what properties should be outputted
            $SelectProperty = @('DisplayName') # DisplayName will be always outputted
            if ($Property) {
                $SelectProperty += $Property
            }
            $SelectProperty = $SelectProperty | select -Unique

            $RegBase = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $env:COMPUTERNAME)
            if (!$RegBase) {
                Write-Error "Unable to open registry on $env:COMPUTERNAME"
                return
            }

            foreach ($RegKey in $RegistryLocation) {
                Write-Verbose "Checking '$RegKey'"
                foreach ($appKeyName in $RegBase.OpenSubKey($RegKey).GetSubKeyNames()) {
                    Write-Verbose "`t'$appKeyName'"
                    $ObjectProperty = [ordered]@{}
                    foreach ($CurrentProperty in $SelectProperty) {
                        Write-Verbose "`t`tGetting value of '$CurrentProperty' in '$RegKey$appKeyName'"
                        $ObjectProperty.$CurrentProperty = ($RegBase.OpenSubKey("$RegKey$appKeyName")).GetValue($CurrentProperty)
                    }

                    if (!$ObjectProperty.DisplayName) {
                        # Skipping. There are some weird records in registry key that are not related to any app"
                        continue
                    }

                    $ObjectProperty.ComputerName = $env:COMPUTERNAME

                    # create final object
                    $appObj = New-Object -TypeName PSCustomObject -Property $ObjectProperty

                    if ($appName) {
                        $appNameRegex = $appName | % {
                            [regex]::Escape($_)
                        }
                        $appNameRegex = $appNameRegex -join "|"
                        $appObj = $appObj | ? { $_.DisplayName -match $appNameRegex }
                    }

                    if (!$DontIgnoreUpdates) {
                        $appObj = $appObj | ? { $_.DisplayName -notlike "*Update for Microsoft*" -and $_.DisplayName -notlike "Security Update*" }
                    }

                    $appObj
                }
            }
        }

        $param = @{
            scriptBlock  = $scriptBlock
            ArgumentList = $property, $dontIgnoreUpdates, $appName
        }
        if ($computerName) {
            $param.computerName = $computerName
            $param.HideComputerName = $true
        }

        $result = Invoke-Command @param

        if ($computerName) {
            $result = $result | select * -ExcludeProperty RunspaceId
        }
    }

    END {
        if ($ogv) {
            $comp = $env:COMPUTERNAME
            if ($computerName) { $comp = $computerName }
            $result | Out-GridView -PassThru -Title "Installed software on $comp"
        } else {
            $result
        }
    }
}

function Get-SFCLogEvent {
    <#
    .SYNOPSIS
    Function for outputting SFC related lines from CBS.log.

    .DESCRIPTION
    Function for outputting SFC related lines from CBS.log.

    .PARAMETER computerName
    Remote computer name.

    .PARAMETER justError
    Output just lines that matches regex specified in $errorRegex

    .NOTES
    https://docs.microsoft.com/en-US/troubleshoot/windows-client/deployment/analyze-sfc-program-log-file-entries
    #>

    [CmdletBinding()]
    param(
        [string] $computerName
        ,
        [switch] $justError
    )

    $cbsLog = "$env:windir\logs\cbs\cbs.log"

    if ($computerName) {
        $cbsLog = "\\$computerName\$cbsLog" -replace ":", "$"
    }

    Write-Verbose "Log path $cbsLog"

    if (Test-Path $cbsLog) {
        Get-Content $cbsLog | Select-String -Pattern "\[SR\] .*" | % {
            if (!$justError -or ($justError -and ($_ | Select-String -Pattern "verify complete|Verifying \d+|Beginning Verify and Repair transaction" -NotMatch))) {
                $match = ([regex]"^(\d{4}-\d{2}-\d{2} \d+:\d+:\d+), (\w+) \s+(.+)\[SR\] (.+)$").Match($_)

                [PSCustomObject]@{
                    Date    = Get-Date ($match.Captures.groups[1].value)
                    Type    = $match.Captures.groups[2].value
                    Message = $match.Captures.groups[4].value
                }
            }
        }

        if ($justError) {
            Write-Warning "If didn't returned anything, command 'sfc /scannow' haven't been run here or there are no errors (regex: $errorRegex)"
        } else {
            Write-Warning "If didn't returned anything, command 'sfc /scannow' probably haven't been run here"
        }
    } else {
        Write-Warning "Log $cbsLog is missing. Run 'sfc /scannow' to create it"
    }
}

function Invoke-AsLoggedUser {
    <#
    .SYNOPSIS
    Function for running specified code under all logged users (impersonate the currently logged on user).
    Common use case is when code is running under SYSTEM and you need to run something under logged users (to modify user registry etc).

    .DESCRIPTION
    Function for running specified code under all logged users (impersonate the currently logged on user).
    Common use case is when code is running under SYSTEM and you need to run something under logged users (to modify user registry etc).

    You have to run this under SYSTEM account, or ADMIN account (but in such case helper sched. task will be created, content to run will be saved to disk and called from sched. task under SYSTEM account).

    Helper files and sched. tasks are automatically deleted.

    .PARAMETER ScriptBlock
    Scriptblock that should be run under logged users.

    .PARAMETER ComputerName
    Name of computer, where to run this.
    If specified, psremoting will be used to connect, this function with scriptBlock to run will be saved to disk and run through helper scheduled task under SYSTEM account.

    .PARAMETER ReturnTranscript
    Return output of the scriptBlock being run.

    .PARAMETER NoWait
    Don't wait for scriptBlock code finish.

    .PARAMETER UseWindowsPowerShell
    Use default PowerShell exe instead of of the one, this was launched under.

    .PARAMETER NonElevatedSession
    Run non elevated.

    .PARAMETER Visible
    Parameter description

    .PARAMETER CacheToDisk
    Necessity for long scriptBlocks. Content will be saved to disk and run from there.

    .PARAMETER Argument
    If you need to pass some variables to the scriptBlock.
    Hashtable where keys will be names of variables and values will be, well values :)

    Example:
    [hashtable]$Argument = @{
        name = "John"
        cities = "Boston", "Prague"
        hash = @{var1 = 'value1','value11'; var2 = @{ key ='value' }}
    }

    Will in beginning of the scriptBlock define variables:
    $name = 'John'
    $cities = 'Boston', 'Prague'
    $hash = @{var1 = 'value1','value11'; var2 = @{ key ='value' }

    ! ONLY STRING, ARRAY and HASHTABLE variables are supported !

    .EXAMPLE
    Invoke-AsLoggedUser {New-Item C:\temp\$env:username}

    On local computer will call given scriptblock under all logged users.

    .EXAMPLE
    Invoke-AsLoggedUser {New-Item "$env:USERPROFILE\$name"} -computerName PC-01 -ReturnTranscript -Argument @{name = 'someFolder'} -Verbose

    On computer PC-01 will call given scriptblock under all logged users i.e. will create folder 'someFolder' in root of each user profile.
    Transcript of the run scriptBlock will be outputted in console too.

    .NOTES
    Based on https://github.com/KelvinTegelaar/RunAsUser
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [Parameter(Mandatory = $false)]
        [string] $ComputerName,
        [Parameter(Mandatory = $false)]
        [switch] $ReturnTranscript,
        [Parameter(Mandatory = $false)]
        [switch]$NoWait,
        [Parameter(Mandatory = $false)]
        [switch]$UseWindowsPowerShell,
        [Parameter(Mandatory = $false)]
        [switch]$NonElevatedSession,
        [Parameter(Mandatory = $false)]
        [switch]$Visible,
        [Parameter(Mandatory = $false)]
        [switch]$CacheToDisk,
        [Parameter(Mandatory = $false)]
        [hashtable]$Argument
    )

    if ($ReturnTranscript -and $NoWait) {
        throw "It is not possible to return transcript if you don't want to wait for code finish"
    }

    #region variables
    $TranscriptPath = "C:\78943728TEMP63287789\Invoke-AsLoggedUser.log"
    #endregion variables

    #region functions
    function Create-VariableTextDefinition {
        <#
        .SYNOPSIS
        Function will convert hashtable content to text definition of variables, where hash key is name of variable and hash value is therefore value of this new variable.

        .PARAMETER hashTable
        HashTable which content will be transformed to variables

        .PARAMETER returnHashItself
        Returns text representation of hashTable parameter value itself.

        .EXAMPLE
        [hashtable]$Argument = @{
            string = "jmeno"
            array = "neco", "necojineho"
            hash = @{var1 = 'value1','value11'; var2 = @{ key ='value' }}
        }

        Create-VariableTextDefinition $Argument
    #>

        [CmdletBinding()]
        [Parameter(Mandatory = $true)]
        param (
            [hashtable] $hashTable
            ,
            [switch] $returnHashItself
        )

        function _convertToStringRepresentation {
            param ($object)

            $type = $object.gettype()
            if (($type.Name -eq 'Object[]' -and $type.BaseType.Name -eq 'Array') -or ($type.Name -eq 'ArrayList')) {
                Write-Verbose "array"
                ($object | % {
                        _convertToStringRepresentation $_
                    }) -join ", "
            } elseif ($type.Name -eq 'HashTable' -and $type.BaseType.Name -eq 'Object') {
                Write-Verbose "hash"
                $hashContent = $object.getenumerator() | % {
                    '{0} = {1};' -f $_.key, (_convertToStringRepresentation $_.value)
                }
                "@{$hashContent}"
            } elseif ($type.Name -eq 'String') {
                Write-Verbose "string"
                "'$object'"
            } else {
                throw "undefined type"
            }
        }
        if ($returnHashItself) {
            _convertToStringRepresentation $hashTable
        } else {
            $hashTable.GetEnumerator() | % {
                $variableName = $_.Key
                $variableValue = _convertToStringRepresentation $_.value
                "`$$variableName = $variableValue"
            }
        }
    }

    function Get-LoggedOnUser {
        quser | Select-Object -Skip 1 | ForEach-Object {
            $CurrentLine = $_.Trim() -Replace '\s+', ' ' -Split '\s'
            $HashProps = @{
                UserName     = $CurrentLine[0]
                ComputerName = $env:COMPUTERNAME
            }

            # If session is disconnected different fields will be selected
            if ($CurrentLine[2] -eq 'Disc') {
                $HashProps.SessionName = $null
                $HashProps.Id = $CurrentLine[1]
                $HashProps.State = $CurrentLine[2]
                $HashProps.IdleTime = $CurrentLine[3]
                $HashProps.LogonTime = $CurrentLine[4..6] -join ' '
            } else {
                $HashProps.SessionName = $CurrentLine[1]
                $HashProps.Id = $CurrentLine[2]
                $HashProps.State = $CurrentLine[3]
                $HashProps.IdleTime = $CurrentLine[4]
                $HashProps.LogonTime = $CurrentLine[5..7] -join ' '
            }

            $obj = New-Object -TypeName PSCustomObject -Property $HashProps | Select-Object -Property UserName, ComputerName, SessionName, Id, State, IdleTime, LogonTime
            #insert a new type name for the object
            $obj.psobject.Typenames.Insert(0, 'My.GetLoggedOnUser')
            $obj
        }
    }

    function _Invoke-AsLoggedUser {
        if (!("RunAsUser.ProcessExtensions" -as [type])) {
            $source = @"
using Microsoft.Win32.SafeHandles;
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace RunAsUser
{
    internal class NativeHelpers
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct PROCESS_INFORMATION
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public int dwProcessId;
            public int dwThreadId;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct STARTUPINFO
        {
            public int cb;
            public String lpReserved;
            public String lpDesktop;
            public String lpTitle;
            public uint dwX;
            public uint dwY;
            public uint dwXSize;
            public uint dwYSize;
            public uint dwXCountChars;
            public uint dwYCountChars;
            public uint dwFillAttribute;
            public uint dwFlags;
            public short wShowWindow;
            public short cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct WTS_SESSION_INFO
        {
            public readonly UInt32 SessionID;

            [MarshalAs(UnmanagedType.LPStr)]
            public readonly String pWinStationName;

            public readonly WTS_CONNECTSTATE_CLASS State;
        }
    }

    internal class NativeMethods
    {
        [DllImport("kernel32", SetLastError=true)]
        public static extern int WaitForSingleObject(
          IntPtr hHandle,
          int dwMilliseconds);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(
            IntPtr hSnapshot);

        [DllImport("userenv.dll", SetLastError = true)]
        public static extern bool CreateEnvironmentBlock(
            ref IntPtr lpEnvironment,
            SafeHandle hToken,
            bool bInherit);

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool CreateProcessAsUserW(
            SafeHandle hToken,
            String lpApplicationName,
            StringBuilder lpCommandLine,
            IntPtr lpProcessAttributes,
            IntPtr lpThreadAttributes,
            bool bInheritHandle,
            uint dwCreationFlags,
            IntPtr lpEnvironment,
            String lpCurrentDirectory,
            ref NativeHelpers.STARTUPINFO lpStartupInfo,
            out NativeHelpers.PROCESS_INFORMATION lpProcessInformation);

        [DllImport("userenv.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool DestroyEnvironmentBlock(
            IntPtr lpEnvironment);

        [DllImport("advapi32.dll", SetLastError = true)]
        public static extern bool DuplicateTokenEx(
            SafeHandle ExistingTokenHandle,
            uint dwDesiredAccess,
            IntPtr lpThreadAttributes,
            SECURITY_IMPERSONATION_LEVEL ImpersonationLevel,
            TOKEN_TYPE TokenType,
            out SafeNativeHandle DuplicateTokenHandle);

        [DllImport("advapi32.dll", SetLastError = true)]
        public static extern bool GetTokenInformation(
            SafeHandle TokenHandle,
            uint TokenInformationClass,
            SafeMemoryBuffer TokenInformation,
            int TokenInformationLength,
            out int ReturnLength);

        [DllImport("wtsapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool WTSEnumerateSessions(
            IntPtr hServer,
            int Reserved,
            int Version,
            ref IntPtr ppSessionInfo,
            ref int pCount);

        [DllImport("wtsapi32.dll")]
        public static extern void WTSFreeMemory(
            IntPtr pMemory);

        [DllImport("kernel32.dll")]
        public static extern uint WTSGetActiveConsoleSessionId();

        [DllImport("Wtsapi32.dll", SetLastError = true)]
        public static extern bool WTSQueryUserToken(
            uint SessionId,
            out SafeNativeHandle phToken);
    }

    internal class SafeMemoryBuffer : SafeHandleZeroOrMinusOneIsInvalid
    {
        public SafeMemoryBuffer(int cb) : base(true)
        {
            base.SetHandle(Marshal.AllocHGlobal(cb));
        }
        public SafeMemoryBuffer(IntPtr handle) : base(true)
        {
            base.SetHandle(handle);
        }

        protected override bool ReleaseHandle()
        {
            Marshal.FreeHGlobal(handle);
            return true;
        }
    }

    internal class SafeNativeHandle : SafeHandleZeroOrMinusOneIsInvalid
    {
        public SafeNativeHandle() : base(true) { }
        public SafeNativeHandle(IntPtr handle) : base(true) { this.handle = handle; }

        protected override bool ReleaseHandle()
        {
            return NativeMethods.CloseHandle(handle);
        }
    }

    internal enum SECURITY_IMPERSONATION_LEVEL
    {
        SecurityAnonymous = 0,
        SecurityIdentification = 1,
        SecurityImpersonation = 2,
        SecurityDelegation = 3,
    }

    internal enum SW
    {
        SW_HIDE = 0,
        SW_SHOWNORMAL = 1,
        SW_NORMAL = 1,
        SW_SHOWMINIMIZED = 2,
        SW_SHOWMAXIMIZED = 3,
        SW_MAXIMIZE = 3,
        SW_SHOWNOACTIVATE = 4,
        SW_SHOW = 5,
        SW_MINIMIZE = 6,
        SW_SHOWMINNOACTIVE = 7,
        SW_SHOWNA = 8,
        SW_RESTORE = 9,
        SW_SHOWDEFAULT = 10,
        SW_MAX = 10
    }

    internal enum TokenElevationType
    {
        TokenElevationTypeDefault = 1,
        TokenElevationTypeFull,
        TokenElevationTypeLimited,
    }

    internal enum TOKEN_TYPE
    {
        TokenPrimary = 1,
        TokenImpersonation = 2
    }

    internal enum WTS_CONNECTSTATE_CLASS
    {
        WTSActive,
        WTSConnected,
        WTSConnectQuery,
        WTSShadow,
        WTSDisconnected,
        WTSIdle,
        WTSListen,
        WTSReset,
        WTSDown,
        WTSInit
    }

    public class Win32Exception : System.ComponentModel.Win32Exception
    {
        private string _msg;

        public Win32Exception(string message) : this(Marshal.GetLastWin32Error(), message) { }
        public Win32Exception(int errorCode, string message) : base(errorCode)
        {
            _msg = String.Format("{0} ({1}, Win32ErrorCode {2} - 0x{2:X8})", message, base.Message, errorCode);
        }

        public override string Message { get { return _msg; } }
        public static explicit operator Win32Exception(string message) { return new Win32Exception(message); }
    }

    public static class ProcessExtensions
    {
        #region Win32 Constants

        private const int CREATE_UNICODE_ENVIRONMENT = 0x00000400;
        private const int CREATE_NO_WINDOW = 0x08000000;

        private const int CREATE_NEW_CONSOLE = 0x00000010;

        private const uint INVALID_SESSION_ID = 0xFFFFFFFF;
        private static readonly IntPtr WTS_CURRENT_SERVER_HANDLE = IntPtr.Zero;

        #endregion

        // Gets the user token from the currently active session
        private static SafeNativeHandle GetSessionUserToken(bool elevated)
        {
            var activeSessionId = INVALID_SESSION_ID;
            var pSessionInfo = IntPtr.Zero;
            var sessionCount = 0;

            // Get a handle to the user access token for the current active session.
            if (NativeMethods.WTSEnumerateSessions(WTS_CURRENT_SERVER_HANDLE, 0, 1, ref pSessionInfo, ref sessionCount))
            {
                try
                {
                    var arrayElementSize = Marshal.SizeOf(typeof(NativeHelpers.WTS_SESSION_INFO));
                    var current = pSessionInfo;

                    for (var i = 0; i < sessionCount; i++)
                    {
                        var si = (NativeHelpers.WTS_SESSION_INFO)Marshal.PtrToStructure(
                            current, typeof(NativeHelpers.WTS_SESSION_INFO));
                        current = IntPtr.Add(current, arrayElementSize);

                        if (si.State == WTS_CONNECTSTATE_CLASS.WTSActive)
                        {
                            activeSessionId = si.SessionID;
                            break;
                        }
                    }
                }
                finally
                {
                    NativeMethods.WTSFreeMemory(pSessionInfo);
                }
            }

            // If enumerating did not work, fall back to the old method
            if (activeSessionId == INVALID_SESSION_ID)
            {
                activeSessionId = NativeMethods.WTSGetActiveConsoleSessionId();
            }

            SafeNativeHandle hImpersonationToken;
            if (!NativeMethods.WTSQueryUserToken(activeSessionId, out hImpersonationToken))
            {
                throw new Win32Exception("WTSQueryUserToken failed to get access token.");
            }

            using (hImpersonationToken)
            {
                // First see if the token is the full token or not. If it is a limited token we need to get the
                // linked (full/elevated token) and use that for the CreateProcess task. If it is already the full or
                // default token then we already have the best token possible.
                TokenElevationType elevationType = GetTokenElevationType(hImpersonationToken);

                if (elevationType == TokenElevationType.TokenElevationTypeLimited && elevated == true)
                {
                    using (var linkedToken = GetTokenLinkedToken(hImpersonationToken))
                        return DuplicateTokenAsPrimary(linkedToken);
                }
                else
                {
                    return DuplicateTokenAsPrimary(hImpersonationToken);
                }
            }
        }

        public static int StartProcessAsCurrentUser(string appPath, string cmdLine = null, string workDir = null, bool visible = true,int wait = -1, bool elevated = true)
        {
            using (var hUserToken = GetSessionUserToken(elevated))
            {
                var startInfo = new NativeHelpers.STARTUPINFO();
                startInfo.cb = Marshal.SizeOf(startInfo);

                uint dwCreationFlags = CREATE_UNICODE_ENVIRONMENT | (uint)(visible ? CREATE_NEW_CONSOLE : CREATE_NO_WINDOW);
                startInfo.wShowWindow = (short)(visible ? SW.SW_SHOW : SW.SW_HIDE);
                //startInfo.lpDesktop = "winsta0\\default";

                IntPtr pEnv = IntPtr.Zero;
                if (!NativeMethods.CreateEnvironmentBlock(ref pEnv, hUserToken, false))
                {
                    throw new Win32Exception("CreateEnvironmentBlock failed.");
                }
                try
                {
                    StringBuilder commandLine = new StringBuilder(cmdLine);
                    var procInfo = new NativeHelpers.PROCESS_INFORMATION();

                    if (!NativeMethods.CreateProcessAsUserW(hUserToken,
                        appPath, // Application Name
                        commandLine, // Command Line
                        IntPtr.Zero,
                        IntPtr.Zero,
                        false,
                        dwCreationFlags,
                        pEnv,
                        workDir, // Working directory
                        ref startInfo,
                        out procInfo))
                    {
                        throw new Win32Exception("CreateProcessAsUser failed.");
                    }

                    try
                    {
                        NativeMethods.WaitForSingleObject( procInfo.hProcess, wait);
                        return procInfo.dwProcessId;
                    }
                    finally
                    {
                        NativeMethods.CloseHandle(procInfo.hThread);
                        NativeMethods.CloseHandle(procInfo.hProcess);
                    }
                }
                finally
                {
                    NativeMethods.DestroyEnvironmentBlock(pEnv);
                }
            }
        }

        private static SafeNativeHandle DuplicateTokenAsPrimary(SafeHandle hToken)
        {
            SafeNativeHandle pDupToken;
            if (!NativeMethods.DuplicateTokenEx(hToken, 0, IntPtr.Zero, SECURITY_IMPERSONATION_LEVEL.SecurityImpersonation,
                TOKEN_TYPE.TokenPrimary, out pDupToken))
            {
                throw new Win32Exception("DuplicateTokenEx failed.");
            }

            return pDupToken;
        }

        private static TokenElevationType GetTokenElevationType(SafeHandle hToken)
        {
            using (SafeMemoryBuffer tokenInfo = GetTokenInformation(hToken, 18))
            {
                return (TokenElevationType)Marshal.ReadInt32(tokenInfo.DangerousGetHandle());
            }
        }

        private static SafeNativeHandle GetTokenLinkedToken(SafeHandle hToken)
        {
            using (SafeMemoryBuffer tokenInfo = GetTokenInformation(hToken, 19))
            {
                return new SafeNativeHandle(Marshal.ReadIntPtr(tokenInfo.DangerousGetHandle()));
            }
        }

        private static SafeMemoryBuffer GetTokenInformation(SafeHandle hToken, uint infoClass)
        {
            int returnLength;
            bool res = NativeMethods.GetTokenInformation(hToken, infoClass, new SafeMemoryBuffer(IntPtr.Zero), 0,
                out returnLength);
            int errCode = Marshal.GetLastWin32Error();
            if (!res && errCode != 24 && errCode != 122)  // ERROR_INSUFFICIENT_BUFFER, ERROR_BAD_LENGTH
            {
                throw new Win32Exception(errCode, String.Format("GetTokenInformation({0}) failed to get buffer length", infoClass));
            }

            SafeMemoryBuffer tokenInfo = new SafeMemoryBuffer(returnLength);
            if (!NativeMethods.GetTokenInformation(hToken, infoClass, tokenInfo, returnLength, out returnLength))
                throw new Win32Exception(String.Format("GetTokenInformation({0}) failed", infoClass));

            return tokenInfo;
        }
    }
}
"@
            Add-Type -TypeDefinition $source -Language CSharp
        }
        if ($CacheToDisk) {
            $ScriptGuid = New-Guid
            $null = New-Item "$($ENV:TEMP)\$($ScriptGuid).ps1" -Value $ScriptBlock -Force
            $pwshcommand = "-ExecutionPolicy Bypass -Window Normal -file `"$($ENV:TEMP)\$($ScriptGuid).ps1`""
        } else {
            $encodedcommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($ScriptBlock))
            $pwshcommand = "-ExecutionPolicy Bypass -Window Normal -EncodedCommand $($encodedcommand)"
        }
        $OSLevel = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentVersion
        if ($OSLevel -lt 6.2) { $MaxLength = 8190 } else { $MaxLength = 32767 }
        if ($encodedcommand.length -gt $MaxLength -and $CacheToDisk -eq $false) {
            Write-Error -Message "The encoded script is longer than the command line parameter limit. Please execute the script with the -CacheToDisk option."
            return
        }
        $privs = whoami /priv /fo csv | ConvertFrom-Csv | Where-Object { $_.'Privilege Name' -eq 'SeDelegateSessionUserImpersonatePrivilege' }
        if ($privs.State -eq "Disabled") {
            Write-Error -Message "Not running with correct privilege. You must run this script as system or have the SeDelegateSessionUserImpersonatePrivilege token."
            return
        } else {
            try {
                # Use the same PowerShell executable as the one that invoked the function, Unless -UseWindowsPowerShell is defined

                if (!$UseWindowsPowerShell) { $pwshPath = (Get-Process -Id $pid).Path } else { $pwshPath = "$($ENV:windir)\system32\WindowsPowerShell\v1.0\powershell.exe" }
                if ($NoWait) { $ProcWaitTime = 1 } else { $ProcWaitTime = -1 }
                if ($NonElevatedSession) { $RunAsAdmin = $false } else { $RunAsAdmin = $true }
                [RunAsUser.ProcessExtensions]::StartProcessAsCurrentUser(
                    $pwshPath, "`"$pwshPath`" $pwshcommand", (Split-Path $pwshPath -Parent), $Visible, $ProcWaitTime, $RunAsAdmin)
                if ($CacheToDisk) { $null = Remove-Item "$($ENV:TEMP)\$($ScriptGuid).ps1" -Force }
            } catch {
                Write-Error -Message "Could not execute as currently logged on user: $($_.Exception.Message)" -Exception $_.Exception
                return
            }
        }
    }
    #endregion functions

    #region prepare Invoke-Command parameters
    # export this function to remote session (so I am not dependant whether it exists there or not)
    $allFunctionDefs = "function Invoke-AsLoggedUser { ${function:Invoke-AsLoggedUser} }; function Create-VariableTextDefinition { ${function:Create-VariableTextDefinition} }; function Get-LoggedOnUser { ${function:Get-LoggedOnUser} }"

    $param = @{
        argumentList = $scriptBlock, $NoWait, $UseWindowsPowerShell, $NonElevatedSession, $Visible, $CacheToDisk, $allFunctionDefs, $VerbosePreference, $ReturnTranscript, $Argument
    }

    if ($computerName -and $computerName -notmatch "localhost|$env:COMPUTERNAME") {
        $param.computerName = $computerName
    }
    #endregion prepare Invoke-Command parameters

    #region rights checks
    $hasAdminRights = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    $hasSystemRights = whoami /priv /fo csv | ConvertFrom-Csv | Where-Object { $_.'Privilege Name' -eq 'SeDelegateSessionUserImpersonatePrivilege' -and $_.State -eq "Enabled" }
    #HACK in remote session this detection incorrectly shows that I have rights, but than function will fail anyway
    if ((Get-Host).name -eq "ServerRemoteHost") { $hasSystemRights = $false }
    Write-Verbose "ADMIN: $hasAdminRights SYSTEM: $hasSystemRights"
    #endregion rights checks

    if ($param.computerName) {
        Write-Verbose "Will be run on remote computer $computerName"

        Invoke-Command @param -ScriptBlock {
            param ($scriptBlock, $NoWait, $UseWindowsPowerShell, $NonElevatedSession, $Visible, $CacheToDisk, $allFunctionDefs, $VerbosePreference, $ReturnTranscript, $Argument)

            foreach ($functionDef in $allFunctionDefs) {
                . ([ScriptBlock]::Create($functionDef))
            }

            # check that there is someone logged
            if ((Get-LoggedOnUser).state -notcontains "Active") {
                Write-Warning "On $env:COMPUTERNAME is no user logged in"
                return
            }

            # convert passed string back to scriptblock
            $scriptBlock = [Scriptblock]::Create($scriptBlock)

            $param = @{scriptBlock = $scriptBlock }
            if ($VerbosePreference -eq "Continue") { $param.verbose = $true }
            if ($NoWait) { $param.NoWait = $NoWait }
            if ($UseWindowsPowerShell) { $param.UseWindowsPowerShell = $UseWindowsPowerShell }
            if ($NonElevatedSession) { $param.NonElevatedSession = $NonElevatedSession }
            if ($Visible) { $param.Visible = $Visible }
            if ($CacheToDisk) { $param.CacheToDisk = $CacheToDisk }
            if ($ReturnTranscript) { $param.ReturnTranscript = $ReturnTranscript }
            if ($Argument) { $param.Argument = $Argument }

            # run again "locally" on remote computer
            Invoke-AsLoggedUser @param
        }
    } elseif (!$ComputerName -and !$hasSystemRights -and $hasAdminRights) {
        # create helper sched. task, that will under SYSTEM account run given scriptblock using Invoke-AsLoggedUser
        Write-Verbose "Running locally as ADMIN"

        # create helper script, that will be called from sched. task under SYSTEM account
        if ($VerbosePreference -eq "Continue") { $VerboseParam = "-Verbose" }
        if ($ReturnTranscript) { $ReturnTranscriptParam = "-ReturnTranscript" }
        if ($NoWait) { $NoWaitParam = "-NoWait" }
        if ($UseWindowsPowerShell) { $UseWindowsPowerShellParam = "-UseWindowsPowerShell" }
        if ($NonElevatedSession) { $NonElevatedSessionParam = "-NonElevatedSession" }
        if ($Visible) { $VisibleParam = "-Visible" }
        if ($CacheToDisk) { $CacheToDiskParam = "-CacheToDisk" }
        if ($Argument) {
            $ArgumentHashText = Create-VariableTextDefinition $Argument -returnHashItself
            $ArgumentParam = "-Argument $ArgumentHashText"
        }

        $helperScriptText = @"
# define function Invoke-AsLoggedUser
$allFunctionDefs

`$scriptBlockText = @'
$($ScriptBlock.ToString())
'@

# transform string to scriptblock
`$scriptBlock = [Scriptblock]::Create(`$scriptBlockText)

# run scriptblock under all local logged users
Invoke-AsLoggedUser -ScriptBlock `$scriptblock $VerboseParam $ReturnTranscriptParam $NoWaitParam $UseWindowsPowerShellParam $NonElevatedSessionParam $VisibleParam $CacheToDiskParam $ArgumentParam
"@

        Write-Verbose "####### HELPER SCRIPT TEXT"
        Write-Verbose $helperScriptText
        Write-Verbose "####### END"

        $tmpScript = "$env:windir\Temp\$(Get-Random).ps1"
        Write-Verbose "Creating helper script $tmpScript"
        $helperScriptText | Out-File -FilePath $tmpScript -Force -Encoding utf8

        # create helper sched. task
        $taskName = "RunAsUser_" + (Get-Random)
        Write-Verbose "Creating helper scheduled task $taskName"
        $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -DontStopOnIdleEnd
        $taskAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File `"$tmpScript`""
        Register-ScheduledTask -TaskName $taskName -User "NT AUTHORITY\SYSTEM" -Action $taskAction -RunLevel Highest -Settings $taskSettings -Force | Out-Null

        # start helper sched. task
        Write-Verbose "Starting helper scheduled task $taskName"
        Start-ScheduledTask $taskName

        # wait for helper sched. task finish
        while ((Get-ScheduledTask $taskName -ErrorAction silentlyContinue).state -ne "Ready") {
            Write-Warning "Waiting for task $taskName to finish"
            Start-Sleep -Milliseconds 200
        }
        if (($lastTaskResult = (Get-ScheduledTaskInfo $taskName).lastTaskResult) -ne 0) {
            Write-Error "Task failed with error $lastTaskResult"
        }

        # delete helper sched. task
        Write-Verbose "Removing helper scheduled task $taskName"
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false

        # delete helper script
        Write-Verbose "Removing helper script $tmpScript"
        Remove-Item $tmpScript -Force

        # read & delete transcript
        if ($ReturnTranscript) {
            # return just interesting part of transcript
            if (Test-Path $TranscriptPath) {
                $transcriptContent = (Get-Content $TranscriptPath -Raw) -Split [regex]::escape('**********************')
                # return user name, under which command was run
                $runUnder = $transcriptContent[1] -split "`n" | ? { $_ -match "Username: " } | % { ($_ -replace "Username: ").trim() }
                Write-Warning "Command run under: $runUnder"
                # return command output
                ($transcriptContent[2] -split "`n" | Select-Object -Skip 2 | Select-Object -SkipLast 3) -join "`n"

                Remove-Item (Split-Path $TranscriptPath -Parent) -Recurse -Force
            } else {
                Write-Warning "There is no transcript, command probably failed!"
            }
        }
    } elseif (!$ComputerName -and !$hasSystemRights -and !$hasAdminRights) {
        throw "Insufficient rights (not ADMIN nor SYSTEM)"
    } elseif (!$ComputerName -and $hasSystemRights) {
        Write-Verbose "Running locally as SYSTEM"

        if ($Argument -or $ReturnTranscript) {
            # define passed variables
            if ($Argument) {
                # convert hash to variables text definition
                $VariableTextDef = Create-VariableTextDefinition $Argument
            }

            if ($ReturnTranscript) {
                # modify scriptBlock to contain creation of transcript
                #TODO pro kazdeho uzivatele samostatny transcript a pak je vsechny zobrazit
                $TranscriptStart = "Start-Transcript $TranscriptPath -Append" # append because code can run under more than one user at a time
                $TranscriptEnd = 'Stop-Transcript'
            }

            $ScriptBlockContent = ($TranscriptStart + "`n`n" + $VariableTextDef + "`n`n" + $ScriptBlock.ToString() + "`n`n" + $TranscriptStop)
            Write-Verbose "####### SCRIPTBLOCK TO RUN"
            Write-Verbose $ScriptBlockContent
            Write-Verbose "#######"
            $scriptBlock = [Scriptblock]::Create($ScriptBlockContent)
        }

        _Invoke-AsLoggedUser
    } else {
        throw "undefined"
    }
}

function Invoke-AsSystem {
    <#
    .SYNOPSIS
    Function for running specified code under SYSTEM account.

    .DESCRIPTION
    Function for running specified code under SYSTEM account.

    Helper files and sched. tasks are automatically deleted.

    .PARAMETER scriptBlock
    Scriptblock that should be run under SYSTEM account.

    .PARAMETER computerName
    Name of computer, where to run this.

    .PARAMETER returnTranscript
    Add creating of transcript to specified scriptBlock and returns its output.

    .PARAMETER cacheToDisk
    Necessity for long scriptBlocks. Content will be saved to disk and run from there.

    .PARAMETER argument
    If you need to pass some variables to the scriptBlock.
    Hashtable where keys will be names of variables and values will be, well values :)

    Example:
    [hashtable]$Argument = @{
        name = "John"
        cities = "Boston", "Prague"
        hash = @{var1 = 'value1','value11'; var2 = @{ key ='value' }}
    }

    Will in beginning of the scriptBlock define variables:
    $name = 'John'
    $cities = 'Boston', 'Prague'
    $hash = @{var1 = 'value1','value11'; var2 = @{ key ='value' }

    ! ONLY STRING, ARRAY and HASHTABLE variables are supported !

    .PARAMETER runAs
    Let you change if scriptBlock should be running under SYSTEM, LOCALSERVICE or NETWORKSERVICE account.

    Default is SYSTEM.

    .EXAMPLE
    Invoke-AsSystem {New-Item $env:TEMP\abc}

    On local computer will call given scriptblock under SYSTEM account.

    .EXAMPLE
    Invoke-AsSystem {New-Item "$env:TEMP\$name"} -computerName PC-01 -ReturnTranscript -Argument @{name = 'someFolder'} -Verbose

    On computer PC-01 will call given scriptblock under SYSTEM account i.e. will create folder 'someFolder' in C:\Windows\Temp.
    Transcript will be outputted in console too.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock] $scriptBlock,

        [string] $computerName,

        [switch] $returnTranscript,

        [hashtable] $argument,

        [ValidateSet('SYSTEM', 'NETWORKSERVICE', 'LOCALSERVICE')]
        [string] $runAs = "SYSTEM",

        [switch] $CacheToDisk
    )

    (Get-Variable runAs).Attributes.Clear()
    $runAs = "NT Authority\$runAs"

    #region prepare Invoke-Command parameters
    # export this function to remote session (so I am not dependant whether it exists there or not)
    $allFunctionDefs = "function Create-VariableTextDefinition { ${function:Create-VariableTextDefinition} }"

    $param = @{
        argumentList = $scriptBlock, $runAs, $CacheToDisk, $allFunctionDefs, $VerbosePreference, $ReturnTranscript, $Argument
    }

    if ($computerName -and $computerName -notmatch "localhost|$env:COMPUTERNAME") {
        $param.computerName = $computerName
    } else {
        if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            throw "You don't have administrator rights"
        }
    }
    #endregion prepare Invoke-Command parameters

    Invoke-Command @param -ScriptBlock {
        param ($scriptBlock, $runAs, $CacheToDisk, $allFunctionDefs, $VerbosePreference, $ReturnTranscript, $Argument)

        foreach ($functionDef in $allFunctionDefs) {
            . ([ScriptBlock]::Create($functionDef))
        }

        $TranscriptPath = "$ENV:TEMP\Invoke-AsSYSTEM_$(Get-Random).log"

        if ($Argument -or $ReturnTranscript) {
            # define passed variables
            if ($Argument) {
                # convert hash to variables text definition
                $VariableTextDef = Create-VariableTextDefinition $Argument
            }

            if ($ReturnTranscript) {
                # modify scriptBlock to contain creation of transcript
                $TranscriptStart = "Start-Transcript $TranscriptPath"
                $TranscriptEnd = 'Stop-Transcript'
            }

            $ScriptBlockContent = ($TranscriptStart + "`n`n" + $VariableTextDef + "`n`n" + $ScriptBlock.ToString() + "`n`n" + $TranscriptStop)
            Write-Verbose "####### SCRIPTBLOCK TO RUN"
            Write-Verbose $ScriptBlockContent
            Write-Verbose "#######"
            $scriptBlock = [Scriptblock]::Create($ScriptBlockContent)
        }

        if ($CacheToDisk) {
            $ScriptGuid = New-Guid
            $null = New-Item "$($ENV:TEMP)\$($ScriptGuid).ps1" -Value $ScriptBlock -Force
            $pwshcommand = "-ExecutionPolicy Bypass -Window Hidden -noprofile -file `"$($ENV:TEMP)\$($ScriptGuid).ps1`""
        } else {
            $encodedcommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($ScriptBlock))
            $pwshcommand = "-ExecutionPolicy Bypass -Window Hidden -noprofile -EncodedCommand $($encodedcommand)"
        }

        $OSLevel = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentVersion
        if ($OSLevel -lt 6.2) { $MaxLength = 8190 } else { $MaxLength = 32767 }
        if ($encodedcommand.length -gt $MaxLength -and $CacheToDisk -eq $false) {
            throw "The encoded script is longer than the command line parameter limit. Please execute the script with the -CacheToDisk option."
        }

        try {
            #region create&run sched. task
            $A = New-ScheduledTaskAction -Execute "$($ENV:windir)\system32\WindowsPowerShell\v1.0\powershell.exe" -Argument $pwshcommand
            if ($runAs -match "\$") {
                # pod gMSA uctem
                $P = New-ScheduledTaskPrincipal -UserId $runAs -LogonType Password
            } else {
                # pod systemovym uctem
                $P = New-ScheduledTaskPrincipal -UserId $runAs -LogonType ServiceAccount
            }
            $S = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -DontStopOnIdleEnd
            $taskName = "RunAsSystem_" + (Get-Random)
            try {
                $null = New-ScheduledTask -Action $A -Principal $P -Settings $S -ea Stop | Register-ScheduledTask -Force -TaskName $taskName -ea Stop
            } catch {
                if ($_ -match "No mapping between account names and security IDs was done") {
                    throw "Account $runAs doesn't exist or cannot be used on $env:COMPUTERNAME"
                } else {
                    throw "Unable to create helper scheduled task. Error was:`n$_"
                }
            }

            # run scheduled task
            Start-Sleep -Milliseconds 200
            Start-ScheduledTask $taskName

            # wait for sched. task to end
            Write-Verbose "waiting on sched. task end ..."
            $i = 0
            while (((Get-ScheduledTask $taskName -ErrorAction silentlyContinue).state -ne "Ready") -and $i -lt 500) {
                ++$i
                Start-Sleep -Milliseconds 200
            }

            # get sched. task result code
            $result = (Get-ScheduledTaskInfo $taskName).LastTaskResult

            # read & delete transcript
            if ($ReturnTranscript) {
                # return just interesting part of transcript
                if (Test-Path $TranscriptPath) {
                    $transcriptContent = (Get-Content $TranscriptPath -Raw) -Split [regex]::escape('**********************')
                    # return command output
                    ($transcriptContent[2] -split "`n" | Select-Object -Skip 2 | Select-Object -SkipLast 3) -join "`n"

                    Remove-Item $TranscriptPath -Force
                } else {
                    Write-Warning "There is no transcript, command probably failed!"
                }
            }

            if ($CacheToDisk) { $null = Remove-Item "$($ENV:TEMP)\$($ScriptGuid).ps1" -Force }

            try {
                Unregister-ScheduledTask $taskName -Confirm:$false -ea Stop
            } catch {
                throw "Unable to unregister sched. task $taskName. Please remove it manually"
            }

            if ($result -ne 0) {
                throw "Command wasn't successfully ended ($result)"
            }
            #endregion create&run sched. task
        } catch {
            throw $_.Exception
        }
    }
}

function Invoke-FileContentWatcher {
    <#
    .SYNOPSIS
    Function for monitoring file content.

    .DESCRIPTION
    Function for monitoring file content.
    Allows you to react on create of new line with specific content.

    Outputs line(s) that match searched string.

    .PARAMETER path
    Path to existing file that should be monitored.

    .PARAMETER searchString
    String that should be searched in newly added lines.

    .PARAMETER searchAsRegex
    Searched string is regex.

    .PARAMETER stopOnFirstMatch
    Switch for stopping search on first match.

    .EXAMPLE
    Invoke-FileContentWatcher -Path C:\temp\mylog.txt -searchString "Error occurred"

    Start monitoring of newly added lines in C:\temp\mylog.txt file. If some line should contain "Error occurred" string, whole line will be outputted into console.

    .EXAMPLE
    Invoke-FileContentWatcher -Path C:\temp\mylog.txt -searchString "Action finished" -stopOnFirstMatch

    Start monitoring of newly added lines in C:\temp\mylog.txt file. If some line should contain "Action finished" string, whole line will be outputted into console and function will end.
    #>

    [Alias("Watch-FileContent")]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $path,

        [Parameter(Mandatory = $true)]
        [string] $searchString,

        [switch] $searchAsRegex,

        [switch] $stopOnFirstMatch
    )

    $fileName = Split-Path $path -Leaf
    $jobName = "ContentWatcher_" + $fileName + "_" + (Get-Date).ToString('HH:mm.ss')

    $null = Start-Job -Name $jobName -ScriptBlock {
        param ($path, $searchString, $searchAsRegex)

        $gcParam = @{
            Path        = $path
            Wait        = $true
            Tail        = 0 # I am interested just in newly added lines
            ErrorAction = 'Stop'
        }

        if ($searchAsRegex) {
            Get-Content @gcParam | ? { $_ -match "$searchString" }
        } else {
            Get-Content @gcParam | ? { $_ -like "*$searchString*" }
        }
    } -ArgumentList $path, $searchString, $searchAsRegex

    while (1) {
        Start-Sleep -Milliseconds 300

        if ((Get-Job -Name $jobName).state -eq 'Completed') {
            $result = Get-Job -Name $jobName | Receive-Job

            Get-Job -Name $jobName | Remove-Job -Force

            throw "Watcher $jobName failed with error: $result"
        }

        if (Get-Job -Name $jobName | Receive-Job -Keep) {
            # searched string was found
            $result = Get-Job -Name $jobName | Receive-Job

            if ($stopOnFirstMatch) {
                Get-Job -Name $jobName | Remove-Job -Force

                return $result
            } else {
                $result
            }
        }
    }
}

function Invoke-FileSystemWatcher {
    <#
    .SYNOPSIS
    Function for monitoring changes made in given folder.

    .DESCRIPTION
    Function for monitoring changes made in given folder.
    Thanks to Action parameter, you can react as you wish.

    .PARAMETER PathToMonitor
    Path to folder to watch.

    .PARAMETER Filter
    How should name of file/folder to watch look like. Same syntax as for -like operator.

    Default is '*'.

    .PARAMETER IncludeSubdirectories
    Switch for monitoring also changes in subfolders.

    .PARAMETER Action
    What should happen, when change is detected. Value should be string quoted by @''@.

    Default is: @'
            $details = $event.SourceEventArgs
            $Name = $details.Name
            $FullPath = $details.FullPath
            $OldFullPath = $details.OldFullPath
            $OldName = $details.OldName
            $ChangeType = $details.ChangeType
            $Timestamp = $event.TimeGenerated
            if ($ChangeType -eq "Renamed") {
                $text = "{0} was {1} at {2} to {3}" -f $FullPath, $ChangeType, $Timestamp, $Name
            } else {
                $text = "{0} was {1} at {2}" -f $FullPath, $ChangeType, $Timestamp
            }
            Write-Host $text
    '@

    so outputting changes to console.

    .PARAMETER ChangeType
    What kind of actions should be monitored.
    Default is all i.e. "Created", "Changed", "Deleted", "Renamed"

    .PARAMETER NotifyFilter
    What kind of "sub" actions should be monitored. Can be used also to improve performance.
    More at https://docs.microsoft.com/en-us/dotnet/api/system.io.notifyfilters?view=netframework-4.8

    For example: 'FileName', 'DirectoryName', 'LastWrite'

    .EXAMPLE
    Invoke-FileSystemWatcher C:\temp "*.txt"

    Just changes to txt files in root of temp folder will be monitored.

    Just changes in name of files and folders in temp folder and its subfolders will be outputted to console and send by email.
    #>

    [CmdletBinding()]
    [Alias("Watch-FileSystem")]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript( {
                If (Test-Path -Path $_ -PathType Container) {
                    $true
                } else {
                    Throw "$_ doesn't exist or it's not a folder."
                }
            })]
        [string] $PathToMonitor
        ,
        [string] $Filter = "*"
        ,
        [switch] $IncludeSubdirectories
        ,
        [scriptblock] $Action = {
            $details = $event.SourceEventArgs
            $Name = $details.Name
            $FullPath = $details.FullPath
            $OldFullPath = $details.OldFullPath
            $OldName = $details.OldName
            $ChangeType = $details.ChangeType
            $Timestamp = $event.TimeGenerated
            if ($ChangeType -eq "Renamed") {
                $text = "{0} was {1} at {2} (previously {3})" -f $FullPath, $ChangeType, $Timestamp, $OldName
            } else {
                $text = "{0} was {1} at {2}" -f $FullPath, $ChangeType, $Timestamp
            }
            Write-Host $text
        }
        ,
        [ValidateSet("Created", "Changed", "Deleted", "Renamed")]
        [string[]] $ChangeType = ("Created", "Changed", "Deleted", "Renamed")
        ,
        [string[]] $NotifyFilter
    )

    $FileSystemWatcher = New-Object System.IO.FileSystemWatcher
    $FileSystemWatcher.Path = $PathToMonitor
    if ($IncludeSubdirectories) {
        $FileSystemWatcher.IncludeSubdirectories = $true
    }
    if ($Filter) {
        $FileSystemWatcher.Filter = $Filter
    }
    if ($NotifyFilter) {
        $NotifyFilter = $NotifyFilter -join ', '
        $FileSystemWatcher.NotifyFilter = [IO.NotifyFilters]$NotifyFilter
    }
    # Set emits events
    $FileSystemWatcher.EnableRaisingEvents = $true

    # Set event handlers
    $handlers = . {
        $changeType | % {
            Register-ObjectEvent -InputObject $FileSystemWatcher -EventName $_ -Action $Action -SourceIdentifier "FS$_"
        }
    }

    Write-Verbose "Watching for changes in $PathToMonitor where file/folder name like '$Filter'"

    try {
        do {
            Wait-Event -Timeout 1
        } while ($true)
    } finally {
        # End script actions + CTRL+C executes the remove event handlers
        $changeType | % {
            Unregister-Event -SourceIdentifier "FS$_"
        }

        # Remaining cleanup
        $handlers | Remove-Job

        $FileSystemWatcher.EnableRaisingEvents = $false
        $FileSystemWatcher.Dispose()

        Write-Warning -Message 'Event Handler completed and disabled.'
    }
}

function Invoke-MSTSC {
    <#
    .SYNOPSIS
    Function for automatization of RDP connection to computer.
    By default it tries to read LAPS password and use it for connection (using cmdkey tool, that imports such credentials to Credential Manager temporarily). But can also be used for autofill of domain credentials (using AutoIt PowerShell module).

    .DESCRIPTION
    Function for automatization of RDP connection to computer.
    By default it tries to read LAPS password and use it for connection (using cmdkey tool, that imports such credentials to Credential Manager temporarily). But can also be used for autofill of domain credentials (using AutoIt PowerShell module).

    It has to be run from PowerShell console, that is running under account with permission for reading LAPS password!

    It uses AdmPwd.PS for getting LAPS password and AutoItx PowerShell module for automatic filling of credentials into mstsc.exe app for RDP, in case LAPS password wasn't retrieved or domain account is used.

    It is working only on English OS.

    .PARAMETER computerName
    Name of remote computer/s

    .PARAMETER useDomainAdminAccount
    Instead of local admin account, your domain account will be used.

    .PARAMETER credential
    Object with credentials, which should be used to authenticate to remote computer

    .PARAMETER port
    RDP port. Default is 3389

    .PARAMETER admin
    Switch. Use admin RDP mode

    .PARAMETER restrictedAdmin
    Switch. Use restrictedAdmin mode

    .PARAMETER remoteGuard
    Switch. Use remoteGuard mode

    .PARAMETER multiMon
    Switch. Use multiMon

    .PARAMETER fullScreen
    Switch. Open in fullscreen

    .PARAMETER public
    Switch. Use public mode

    .PARAMETER width
    Width of window

    .PARAMETER height
    Heigh of windows

    .PARAMETER gateway
    What gateway to use

    .PARAMETER localAdmin
    What is the name of local administrator, that will be used for LAPS connection

    .EXAMPLE
    Invoke-MSTSC pc1

    Run remote connection to pc1 using builtin administrator account and his LAPS password.

    .EXAMPLE
    Invoke-MSTSC pc1 -useDomainAdminAccount

    Run remote connection to pc1 using adm_<username> domain account.

    .EXAMPLE
    $credentials = Get-Credential
    Invoke-MSTSC pc1 -credential $credentials

    Run remote connection to pc1 using credentials stored in $credentials

    .NOTES
    Automatic filling is working only on english operating systems.
    Author: OndĹ™ej Ĺ ebela - ztrhgf@seznam.cz
    #>

    [CmdletBinding()]
    [Alias("rdp")]
    param (
        [Parameter(Position = 0, ValueFromPipeline = $true, Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        $computerName
        ,
        [switch] $useDomainAdminAccount
        ,
        [PSCredential] $credential
        ,
        [int] $port = 3389
        ,
        [switch] $admin
        ,
        [switch] $restrictedAdmin
        ,
        [switch] $remoteGuard
        ,
        [switch] $multiMon
        ,
        [switch] $fullScreen
        ,
        [switch] $public
        ,
        [int] $width
        ,
        [int] $height
        ,
        [string] $gateway
        ,
        [string] $localAdmin = "administrator"
    )

    begin {
        # remove validation ValidateNotNullOrEmpty
        (Get-Variable computerName).Attributes.Clear()

        try {
            $null = Import-Module AdmPwd.PS -ErrorAction Stop -Verbose:$false
        } catch {
            throw "Module AdmPwd.PS isn't available"
        }

        try {
            Write-Verbose "Get list of domain DCs"
            $DC = [System.Directoryservices.Activedirectory.Domain]::GetCurrentDomain().DomainControllers | ForEach-Object { ($_.name -split "\.")[0] }
        } catch {
            throw "Unable to contact your AD domain"
        }

        Write-Verbose "Get NETBIOS domain name"
        if (!$domainNetbiosName) {
            $domainNetbiosName = $env:userdomain

            if ($domainNetbiosName -eq $env:computername) {
                # function is running under local account therefore $env:userdomain cannot be used
                $domainNetbiosName = (Get-WmiObject Win32_NTDomain).DomainName # slow but gets the correct value
            }
        }
        Write-Verbose "Get domain name"
        if (!$domainName) {
            $domainName = (Get-WmiObject Win32_ComputerSystem).Domain
        }

        $defaultRDP = Join-Path $env:USERPROFILE "Documents\Default.rdp"
        if (Test-Path $defaultRDP -ErrorAction SilentlyContinue) {
            Write-Verbose "RDP settings from $defaultRDP will be used"
        }

        if ($computerName.GetType().name -ne 'string') {
            while ($choice -notmatch "[Y|N]") {
                $choice = Read-Host "Do you really want to connect to all these computers:($($computerName.count))? (Y|N)"
            }
            if ($choice -eq "N") {
                break
            }
        }

        if ($credential) {
            $UserName = $Credential.UserName
            $Password = $Credential.GetNetworkCredential().Password
        } elseif ($useDomainAdminAccount) {
            $dAdmin = $env:USERNAME
            $userName = "$domainNetbiosName\$dAdmin"
        } else {
            # no credentials were given, try to get LAPS password
            ++$tryLaps
        }

        # set MSTSC parameters
        switch ($true) {
            { $admin } { $mstscArguments += '/admin ' }
            { $restrictedAdmin } { $mstscArguments += '/restrictedAdmin ' }
            { $remoteGuard } { $mstscArguments += '/remoteGuard ' }
            { $multiMon } { $mstscArguments += '/multimon ' }
            { $fullScreen } { $mstscArguments += '/f ' }
            { $public } { $mstscArguments += '/public ' }
            { $width } { $mstscArguments += "/w:$width " }
            { $height } { $mstscArguments += "/h:$height " }
            { $gateway } { $mstscArguments += "/g:$gateway " }
        }

        $params = @{
            filePath = "$($env:SystemRoot)\System32\mstsc.exe"
        }

        if ($mstscArguments) {
            $params.argumentList = $mstscArguments
        }
    }

    process {
        foreach ($computer in $computerName) {
            # get just hostname
            if ($computer -match "\d+\.\d+\.\d+\.\d+") {
                # it is IP
                $computerHostname = $computer
            } else {
                # it is hostname or fqdn
                $computerHostname = $computer.split('\.')[0]
            }
            $computerHostname = $computerHostname.ToLower()

            if ($tryLaps -and $computerHostname -notin $DC.ToLower()) {
                Write-Verbose "Getting LAPS password for $computerHostname"
                $password = (Get-AdmPwdPassword $computerHostname).password

                if (!$password) {
                    Write-Warning "Unable to get LAPS password for $computerHostname."
                }
            }

            if ($tryLaps) {
                if ($computerHostname -in $DC.ToLower()) {
                    # connecting to DC (there are no local accounts
                    # $userName = "$domainNetbiosName\$tier0Account"
                    $userName = "$domainNetbiosName\$Env:USERNAME"
                } else {
                    # connecting to non-DC computer
                    if ($computerName -notmatch "\d+\.\d+\.\d+\.\d+") {
                        $userName = "$computerHostname\$localAdmin"
                    } else {
                        # IP was used instead of hostname, therefore I assume there is no LAPS
                        $UserName = " "
                    }
                }
            }

            # if hostname is not in FQDN and it is a server, I will add domain suffix (because of RDP certificate that is probably generated there)
            if ($computer -notmatch "\.") {
                Write-Verbose "Adding $domainName suffix to $computer"
                $computer = $computer + "." + $domainName
            }

            $connectTo = $computer

            if ($port -ne 3389) {
                $connectTo += ":$port"
            }

            # clone mstsc parameters just in case I am connecting to more than one computer, to be able to easily add /v hostname parameter
            $fParams = $params.Clone()

            #
            # log on automatization
            if ($password) {
                # I have password, so I will use cmdkey to store it in Cred. Manager
                Write-Verbose "Saving credentials for $computer and $userName to CredMan"
                $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
                $Process = New-Object System.Diagnostics.Process
                $ProcessInfo.FileName = "$($env:SystemRoot)\system32\cmdkey.exe"
                $ProcessInfo.Arguments = "/generic:TERMSRV/$computer /user:$userName /pass:`"$password`""
                $ProcessInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                $Process.StartInfo = $ProcessInfo
                [void]$Process.Start()
                $null = $Process.WaitForExit()

                if ($Process.ExitCode -ne 0) {
                    throw "Unable to add credentials to Cred. Manageru, but just for sure, check it."
                }

                # remote computer
                $fParams.argumentList += "/v $connectTo"
            } else {
                # I don't have credentials, so I have to use AutoIt for log on automation

                Write-Verbose "I don't have credentials, so AutoIt will be used instead"

                if ([console]::CapsLock) {
                    $keyBoardObject = New-Object -ComObject WScript.Shell
                    $keyBoardObject.SendKeys("{CAPSLOCK}")
                    Write-Warning "CAPS LOCK was turned on, disabling"
                }

                $titleCred = "Windows Security"
                if (((Get-AU3WinHandle -Title $titleCred) -ne 0) -and $password) {
                    Write-Warning "There is opened window for entering credentials. It has to be closed or auto-fill of credentials will not work."
                    Write-Host 'Enter any key to continue' -NoNewline
                    $null = [Console]::ReadKey('?')
                }
            }

            #
            # running mstsc
            Write-Verbose "Running mstsc.exe with parameter: $($fParams.argumentList)"
            Start-Process @fParams

            if ($password) {
                # I have password, so cmdkey was used for automation
                # so I will now remove saved credentials from Cred. Manager
                Write-Verbose "Removing saved credentials from CredMan"
                Start-Sleep -Seconds 1.5
                $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
                $Process = New-Object System.Diagnostics.Process
                $ProcessInfo.FileName = "$($env:SystemRoot)\system32\cmdkey.exe"
                $ProcessInfo.Arguments = "/delete:TERMSRV/$computer"
                $ProcessInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                $Process.StartInfo = $ProcessInfo
                [void]$Process.Start()
                $null = $Process.WaitForExit()

                if ($Process.ExitCode -ne 0) {
                    throw "Removal of credentials failed. Remove them manually from  Cred. Manager!"
                }
            } else {
                # I don't have password, so AutoIt will be used

                Write-Verbose "Automating log on process using AutoIt"

                try {
                    $null = Get-Command Show-AU3WinActivate -ErrorAction Stop
                } catch {
                    try {
                        $null = Import-Module AutoItX -ErrorAction Stop -Verbose:$false
                    } catch {
                        throw "Module AutoItX isn't available. It is part of the AutoIt installer https://www.autoitconsulting.com/site/scripting/autoit-cmdlets-for-windows-powershell/"
                    }
                }

                # click on "Show options" in mstsc console
                $title = "Remote Desktop Connection"
                Start-Sleep -Milliseconds 300 # to get the handle on last started mstsc
                $null = Wait-AU3Win -Title $title -Timeout 1
                $winHandle = Get-AU3WinHandle -Title $title
                $null = Show-AU3WinActivate -WinHandle $winHandle
                $controlHandle = Get-AU3ControlHandle -WinHandle $winhandle -Control "ToolbarWindow321"
                $null = Invoke-AU3ControlClick -WinHandle $winHandle -ControlHandle $controlHandle
                Start-Sleep -Milliseconds 600


                # fill computer and username
                Write-Verbose "Connecting to: $connectTo as: $userName"
                Send-AU3Key -Key "{CTRLDOWN}A{CTRLUP}{DELETE}" # delete any existing text
                Send-AU3Key -Key "$connectTo{DELETE}" # delete any suffix, that could be autofilled there

                Send-AU3Key -Key "{TAB}"
                Start-Sleep -Milliseconds 400

                Send-AU3Key -Key "{CTRLDOWN}A{CTRLUP}{DELETE}" # delete any existing text
                Send-AU3Key -Key $userName
                Send-AU3Key -Key "{ENTER}"
            }

            # # accept any untrusted certificate
            # $title = "Remote Desktop Connection"
            # $null = Wait-AU3Win -Title $title -Timeout 1
            # $winHandle = ''
            # $count = 0
            # while ((!$winHandle -or $winHandle -eq 0) -and $count -le 40) {
            #     # nema smysl cekat moc dlouho, protoze certak muze byt ok nebo uz ma vyjimku
            #     $winHandle = Get-AU3WinHandle -Title $title -Text "The certificate is not from a trusted certifying authority"
            #     Start-Sleep -Milliseconds 100
            #     ++$count
            # }
            # # je potreba potvrdit nesedici certifikat
            # if ($winHandle) {
            #     $null = Show-AU3WinActivate -WinHandle $winHandle
            #     Start-Sleep -Milliseconds 100
            #     $controlHandle = Get-AU3ControlHandle -WinHandle $winhandle -Control "Button5"
            #     $null = Invoke-AU3ControlClick -WinHandle $winHandle -ControlHandle $controlHandle
            # }
        }
    }
}

function Invoke-SQL {
    <#
    .SYNOPSIS
    Function for invoke sql command on specified SQL server.

    .DESCRIPTION
    Function for invoke sql command on specified SQL server.
    Uses Integrated Security=SSPI for making connection.

    .PARAMETER dataSource
    Name of SQL server.

    .PARAMETER database
    Name of SQL database.

    .PARAMETER sqlCommand
    SQL command to invoke.
    !Beware that name of column must be in " but value in ' quotation mark!

    "SELECT * FROM query.SwInstallationEnu WHERE `"Product type`" = 'commercial' AND `"User`" = 'Pepik Karlu'"

    .PARAMETER force
    Don't ask for confirmation for SQL command that modifies data.

    .EXAMPLE
    Invoke-SQL -dataSource SQL-16 -database alvao -sqlCommand "SELECT * FROM KindRight"

    On SQL-16 server in alvao SQL database runs selected command.

    .EXAMPLE
    Invoke-SQL -dataSource "ondrejs4-test2\SOLARWINDS_ORION" -database "SolarWindsOrion" -sqlCommand "SELECT * FROM pollers"

    On "ondrejs4-test2\SOLARWINDS_ORION" server\instance in SolarWindsOrion database runs selected command.

    .EXAMPLE
    Invoke-SQL -dataSource ".\SQLEXPRESS" -database alvao -sqlCommand "SELECT * FROM KindRight"

    On local server in SQLEXPRESS instance in alvao database runs selected command.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $dataSource
        ,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $database
        ,
        [string] $sqlCommand = $(throw "Please specify a query.")
        ,
        [switch] $force
    )

    if (!$force) {
        if ($sqlCommand -match "^\s*(\bDROP\b|\bUPDATE\b|\bMODIFY\b|\bDELETE\b|\bINSERT\b)") {
            while ($choice -notmatch "^[Y|N]$") {
                $choice = Read-Host "sqlCommand will probably modify table data. Are you sure, you want to continue? (Y|N)"
            }
            if ($choice -eq "N") {
                break
            }
        }
    }

    #TODO add possibility to connect using username/password
    # $connectionString = 'Data Source={0};Initial Catalog={1};User ID={2};Password={3}' -f $dataSource, $database, $userName, $password
    $connectionString = 'Data Source={0};Initial Catalog={1};Integrated Security=SSPI' -f $dataSource, $database

    $connection = New-Object system.data.SqlClient.SQLConnection($connectionString)
    $command = New-Object system.data.sqlclient.sqlcommand($sqlCommand, $connection)
    $connection.Open()

    $adapter = New-Object System.Data.sqlclient.sqlDataAdapter $command
    $dataset = New-Object System.Data.DataSet
    $adapter.Fill($dataSet) | Out-Null

    $connection.Close()
    $adapter.Dispose()
    $dataSet.Tables
}

function Invoke-WindowsUpdate {
    <#
    .SYNOPSIS
    Function for invoking Windows Update.
    Updates will be searched, downloaded and installed.

    .DESCRIPTION
    Function for invoking Windows Update.
    Updates will be searched (only updates that would be automatically selected in WU are searched), downloaded and installed (by default only the critical ones).

    Supports only Server 2016 and 2019 and partially 2012!

    .PARAMETER computerName
    Name of computer(s) where WU should be started.

    .PARAMETER allUpdates
    Switch for installing all available updates, not just critical ones.
    But in either case, just updates that would be automatically selected in WU are searched (because of AutoSelectOnWebSites=1 filter).

    .PARAMETER restartIfRequired
    Switch for restarting the computer if reboot is pending after updates installation.
    If not used and restart is needed, warning will be outputted.

    .EXAMPLE
    Invoke-WindowsUpdate app-15

    On server app-15 will be downloaded and installed all critical updates.

    .EXAMPLE
    Invoke-WindowsUpdate app-15 -restartIfRequired

    On server app-15 will be downloaded and installed all critical updates.
    Restart will be invoked in needed.

    .EXAMPLE
    Invoke-WindowsUpdate app-15 -restartIfRequired -allUpdates

    On server app-15 will be downloaded and installed all updates.
    Restart will be invoked in needed.

    .NOTES
    Inspired by https://github.com/microsoft/WSLab/tree/master/Scenarios/Windows%20Update#apply-updates-on-2016-and-2019
    #>

    [CmdletBinding()]
    [Alias("Invoke-WU", "Install-WindowsUpdate")]
    param (
        [string[]] $computerName
        ,
        [switch] $allUpdates
        ,
        [switch] $restartIfRequired
    )

    Invoke-Command -ComputerName $computerName {
        param ($allUpdates, $restartIfRequired)

        $os = (Get-CimInstance -Class Win32_OperatingSystem).Caption
        $result = @()

        switch ($os) {
            "2012" {
                if (!$allUpdates) {
                    Write-Warning "On Server 2012 are always installed all updates"
                }

                # find & apply all updates
                wuauclt /detectnow /updatenow
            }

            "2016" {
                # find updates
                $Instance = New-CimInstance -Namespace "root/Microsoft/Windows/WindowsUpdate" -ClassName MSFT_WUOperationsSession
                $ScanResult = $instance | Invoke-CimMethod -MethodName ScanForUpdates -Arguments @{SearchCriteria = "IsInstalled=0 AND AutoSelectOnWebSites=1"; OnlineScan = $true }

                # filter just critical ones
                if (!$allUpdates) {
                    $ScanResult = $ScanResult | ? { $_.updates.MsrcSeverity -eq "Critical" }
                }

                # apply updates
                if ($ScanResult.Updates) {
                    $null = $instance | Invoke-CimMethod -MethodName DownloadUpdates -Arguments @{Updates = [ciminstance[]]$ScanResult.Updates }
                    $result = $instance | Invoke-CimMethod -MethodName InstallUpdates -Arguments @{Updates = [ciminstance[]]$ScanResult.Updates }
                }
            }

            "2019" {
                # find updates
                try {
                    $ScanResult = Invoke-CimMethod -Namespace "root/Microsoft/Windows/WindowsUpdate" -ClassName "MSFT_WUOperations" -MethodName ScanForUpdates -Arguments @{SearchCriteria = "IsInstalled=0" } -ErrorAction Stop
                } catch {
                    try {
                        $ScanResult = Invoke-CimMethod -Namespace "root/Microsoft/Windows/WindowsUpdate" -ClassName "MSFT_WUOperations" -MethodName ScanForUpdates -Arguments @{SearchCriteria = "IsInstalled=0 AND AutoSelectOnWebSites=1" }-ErrorAction Stop
                    } catch {
                        # this should work for Core server
                        $ScanResult = Invoke-CimMethod -Namespace "root/Microsoft/Windows/WindowsUpdate" -ClassName "MSFT_WUOperations" -MethodName ScanForUpdates -Arguments @{SearchCriteria = "IsInstalled=0 AND Type='Software'" } -ErrorAction Stop
                    }
                }

                # filter just critical ones
                if (!$allUpdates) {
                    $ScanResult = $ScanResult | ? { $_.updates.MsrcSeverity -eq "Critical" }
                }

                # apply updates
                if ($ScanResult.Updates) {
                    $result = Invoke-CimMethod -Namespace "root/Microsoft/Windows/WindowsUpdate" -ClassName "MSFT_WUOperations" -MethodName InstallUpdates -Arguments @{Updates = $ScanResult.Updates }
                }
            }

            default {
                throw "$os is not defined"
            }
        }

        #region inform about results
        if ($failed = $result | ? { $_.returnValue -ne 0 }) {
            $failed = " ($($failed.count) failed"
        }

        if (@($result).count) {
            "Installed $(@($result).count) updates$failed on $env:COMPUTERNAME"
        } else {
            if ($os -match "2012") {
                "You have to check manually if some updates were installed (because it's Server 2012)"
            } else {
                "No updates found on $env:COMPUTERNAME"
            }
        }
        #endregion inform about results

        #region restart system
        if ($os -notmatch "2012") {
            $pendingReboot = Invoke-CimMethod -Namespace "root/Microsoft/Windows/WindowsUpdate" -ClassName "MSFT_WUSettings" -MethodName IsPendingReboot | select -exp pendingReboot
        } else {
            "Unable to detect if restart is required (because it's Server 2012)"
        }

        if ($restartIfRequired -and $pendingReboot -eq $true) {
            Write-Warning "Restarting $env:COMPUTERNAME"
            shutdown /r /t 30 /c "restarting because of newly installed updates"
        }
        if (!$restartIfRequired -and $pendingReboot -eq $true) {
            Write-Warning "Restart is required on $env:COMPUTERNAME!"
        }
        #endregion restart system
    } -ArgumentList $allUpdates, $restartIfRequired
}

function Uninstall-ApplicationViaUninstallString {
    <#
    .SYNOPSIS
    Function for uninstalling applications using uninstall string (command) that is saved in registry for each application.

    .DESCRIPTION
    Function for uninstalling applications using uninstall string (command) that is saved in registry for each application.
    This functions cannot guarantee that uninstall process will be unattended!

    .PARAMETER name
    Name of the application(s) to uninstall.
    Can be retrieved using function Get-InstalledSoftware.

    .PARAMETER addArgument
    Argument that should be added to those from uninstall string.
    Can be helpful if you need to do unattended uninstall and know the right parameter for it.

    .EXAMPLE
    Uninstall-ApplicationViaUninstallString -name "7-Zip 22.01 (x64)"

    Uninstall 7zip application.

    .EXAMPLE
    Get-InstalledSoftware -appName Dell | Uninstall-ApplicationViaUninstallString

    Uninstall every application that has 'Dell' in its name.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias("displayName")]
        [ArgumentCompleter( {
                param ($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)

                Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\', 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\' | % { try { Get-ItemPropertyValue -Path $_.pspath -Name DisplayName -ErrorAction Stop } catch { $null } } | ? { $_ -like "*$WordToComplete*" } | % { "'$_'" }
            })]
        [string[]] $name,

        [string] $addArgument
    )

    begin {
        # without admin rights msiexec uninstall fails without any error
        if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            throw "Run with administrator rights"
        }

        if (!(Get-Command Get-InstalledSoftware)) {
            throw "Function Get-InstalledSoftware is missing"
        }
    }

    process {
        $appList = Get-InstalledSoftware -property DisplayName, UninstallString, QuietUninstallString | ? DisplayName -In $name

        if ($appList) {
            foreach ($app in $appList) {
                if ($app.QuietUninstallString) {
                    $uninstallCommand = $app.QuietUninstallString
                } else {
                    $uninstallCommand = $app.UninstallString
                }
                $name = $app.DisplayName

                if (!$uninstallCommand) {
                    Write-Warning "Uninstall command is not defined for app '$name'"
                    continue
                }

                if ($uninstallCommand -like "msiexec.exe*") {
                    # it is MSI
                    $uninstallMSIArgument = $uninstallCommand -replace "MsiExec.exe"
                    # sometimes there is /I (install) instead of /X (uninstall) parameter
                    $uninstallMSIArgument = $uninstallMSIArgument -replace "/I", "/X"
                    # add silent and norestart switches
                    $uninstallMSIArgument = "$uninstallMSIArgument /QN"
                    if ($addArgument) {
                        $uninstallMSIArgument = $uninstallMSIArgument + " " + $addArgument
                    }
                    Write-Warning "Uninstalling app '$name' via: msiexec.exe $uninstallMSIArgument"
                    Start-Process "msiexec.exe" -ArgumentList $uninstallMSIArgument -Wait
                } else {
                    # it is EXE
                    #region extract path to the EXE uninstaller
                    # path to EXE is typically surrounded by double quotes
                    $match = ([regex]'("[^"]+")(.*)').Matches($uninstallCommand)
                    if (!$match.count) {
                        # string doesn't contain ", try search for ' instead
                        $match = ([regex]"('[^']+')(.*)").Matches($uninstallCommand)
                    }
                    if ($match.count) {
                        $uninstallExe = $match.captures.groups[1].value
                    } else {
                        # string doesn't contain even '
                        # before blindly use the whole string as path to an EXE, check whether it doesn't contain common argument prefixes '/', '-' ('-' can be part of the EXE path, but it is more safe to make false positive then fail later because of faulty command)
                        if ($uninstallCommand -notmatch "/|-") {
                            $uninstallExe = $uninstallCommand
                        }
                    }
                    if (!$uninstallExe) {
                        Write-Error "Unable to extract EXE path from '$uninstallCommand'"
                        continue
                    }
                    #endregion extract path to the EXE uninstaller
                    if ($match.count) {
                        $uninstallExeArgument = $match.captures.groups[2].value
                    } else {
                        Write-Verbose "I've used whole uninstall string as EXE path"
                    }
                    if ($addArgument) {
                        $uninstallExeArgument = $uninstallExeArgument + " " + $addArgument
                    }
                    # Start-Process param block
                    $param = @{
                        FilePath = $uninstallExe
                        Wait     = $true
                    }
                    if ($uninstallExeArgument) {
                        $param.ArgumentList = $uninstallExeArgument
                    }
                    Write-Warning "Uninstalling app '$name' via: $uninstallExe $uninstallExeArgument"
                    Start-Process @param
                }
            }
        } else {
            Write-Warning "No software with name $($name -join ', ') was found. Get the correct name by running 'Get-InstalledSoftware' function."
        }
    }
}

Export-ModuleMember -function ConvertFrom-HTMLTable, ConvertFrom-XML, Create-BasicAuthHeader, Export-ScriptsToModule, Get-InstalledSoftware, Get-SFCLogEvent, Invoke-AsLoggedUser, Invoke-AsSystem, Invoke-FileContentWatcher, Invoke-FileSystemWatcher, Invoke-MSTSC, Invoke-SQL, Invoke-WindowsUpdate, Uninstall-ApplicationViaUninstallString

Export-ModuleMember -alias Install-WindowsUpdate, Invoke-WU, rdp, Watch-FileContent, Watch-FileSystem
