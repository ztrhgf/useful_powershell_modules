function Compare-Object2 {
    <#
    .SYNOPSIS
    Function for detection if two inputs are the same.
    Can be used for comparison of strings, objects, arrays of primitives/objects.
    ! doesn't work for hash tables!

    Always test before use in production, there can be glitches :)

    .DESCRIPTION
    Function for detection if two inputs are the same.
    Can be used for comparison of strings, objects, arrays of primitives/objects.
    ! doesn't work for hash tables!

    In case input is string, -eq or -ceq operator will be used.
    In case input doesn't have any property that can be used for comparison (i.e array of primitives etc), Compare-Object will be used for camparison.
    In case input object(s) has any properties, they will be used for comparison.

    Same objects are those that have same values in properties used for comparison.

    Beware, that result can be different, if you switch input1 and input2.
    It's because when comparison starts, it will cycle through items of input1, detects type of each object property and according to that choose correct compare operator.

    .PARAMETER input1
    First input to compare.

    .PARAMETER input2
    Second input to compare.

    .PARAMETER property
    List of object properties that will be used for comparison.
    If not used, all properties of object has to match.

    .PARAMETER excludeProperty
    List of object properties that will be excluded from comparison.

    .PARAMETER trimStringProperty
    Switch for trim value of string properties before comparison.

    .PARAMETER confluenceInInput2
    Switch for transforming values of string properties (of objects in input1!) to format used in Confluence.
    i.e. <URL> is transformed to `n\n<URL>\n`n etc.

    !Confluence object on contrary has to be in input2 otherwise this won't work!

    Beware, that detection of changes in spaces won't be detected! It's because when transforming plaintext html to object, multiple spaces are replaced by single space.

    .PARAMETER caseSensitive
    Switch for making comparison of string properties case sensitive.

    .PARAMETER outputItemWithoutMatch
    Switch for outputting object, that wasn't found in second input.

    .EXAMPLE
    $1 = get-process
    $2 = get-process notepad

    Compare-Object2 $1 $2 -property processname, id

    Will return $True if for each object from $1 array exists object with same processname and id from array $2.

    .EXAMPLE
    $1 = get-process
    $2 = get-process notepad

    Compare-Object2 $1 $2 -excludeProperty ws, id

    Will return $True if for each object from $1 array exists same object from array $2. For comparison of objects will be used values of all but ws and id properties.

    .OUTPUTS
    Boolean
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $input1
        ,
        [Parameter(Mandatory = $true)]
        $input2
        ,
        $property = @()
        ,
        [string[]] $excludeProperty
        ,
        [switch] $trimStringProperty
        ,
        [switch] $confluenceInInput2
        ,
        [switch] $caseSensitive
        ,
        [switch] $outputItemWithoutMatch
    )

    $operator = "-eq"
    if ($caseSensitive) { $operator = "-ceq" }

    if ($trimStringProperty) {
        $trim = ".trim()"
    }

    if (!$input1 -and !$input2) {
        return $true
    } elseif (($input1 -and !$input2) -or (!$input1 -and $input2)) {
        return $false
    }

    $input1Property = $input1 | Get-Member -MemberType CodeProperty, CodeProperty, NoteProperty, Property, ParameterizedProperty, AliasProperty | select -exp name
    $input2Property = $input2 | Get-Member -MemberType CodeProperty, CodeProperty, NoteProperty, Property, ParameterizedProperty, AliasProperty | select -exp name

    if (!($input1Property) -or !($input2Property)) {
        Write-Verbose "Input object doesn't have any property. Using Compare-Object to compare input1 and input2 as a whole"
        if (Compare-Object $input1 $input2) {
            return $false
        } else {
            return $true
        }
    }

    if (($input1.count -gt 1) -and ($input1Property.count -eq 2 -and $input1Property -contains "chars" -and $input1Property -contains "length") -or ($input2.count -gt 1) -and ($input2Property.count -eq 2 -and $input2Property -contains "chars" -and $input1Property -contains "length")) {
        Write-Verbose "Input object is array of strings. Using Compare-Object to compare input1 and input2 as a whole"
        if (Compare-Object $input1 $input2) {
            return $false
        } else {
            return $true
        }
    }

    if ($input1.gettype().name -eq "String" -or $input2.gettype().name -eq "String" ) {
        Write-Warning "Input object is a string. Using $operator operator to comparison"
        if (Invoke-Expression "'$input1'$trim $operator '$input2'$trim") {
            return $true
        } else {
            return $false
        }
    }

    function _ConvertToConfluenceFormat {
        # convert given string to format, that will be received from Confluence page
        # https://support.atlassian.com/confluence-cloud/docs/insert-confluence-wiki-markup/ etc
        [CmdletBinding()]
        param ([string] $text, $VerbosePreference = $VerbosePreference)

        # end line
        $text = $text -replace "`r`n", "`n"

        # | because we replaced it for space in scripts that fill confluence tables
        # it is used when creating tables (ConvertTo-ConfluenceTable)
        $text = $text -replace "\|", " "

        # # vyhledat vsechna slova obsahujici \, ponechat jen unikatni, pokud slovo obsahuje \\, tak udelat newline transformaci jinak zdvojit
        # $match = ([regex]"[^\s]*\\[^\s]*").matches($text)
        # $match = $match.value | select -Unique
        # if ($match) {
        #     $match | % {
        #         $_
        #         $escMatch = [regex]::Escape($_)
        #         if ($_ -match "\\\\" -and ($_ -split "\\").count -eq 3) {
        #             "###newline"
        #             # two following \ i.e. newline symbol \\
        #             # $match = "va\\"
        #             # $match = "($match)" -replace "\\\\", ")\\\\("
        #             # (va)\\\\()
        #             $a = ($_ -split "\\\\")[0]
        #             $b = ($_ -split "\\\\")[1]
        #             # $_ -replace "\\\\", "(\\\\)"
        #             $match2 = ([regex]"(^|\s+)$escMatch(\s+|$)").matches($text) # pokud je pred \\ vic mezer, nahradi se za jednu, pokud jsou mezery za \\, zahodi se
        #             if ($match2) {
        #                 $match2 | % {
        #                     Write-Verbose "Replacing $($_.value)"
        #                     $1 = $_.captures.groups[1].value -replace '\s+$', ' '
        #                     $2 = $_.groups[2].value -replace '^\s+'
        #                     $text = $text -replace [regex]::Escape($_), "$1$a`n$b$2"
        #                 }
        #             } else {
        #                 throw "$_ jsem nenasel"
        #             }
        #         } else {
        #             # one, three or more \ i.e. UNC path
        #             $match2 = ([regex]"(^|\s+)$escMatch(\s+|$)").matches($text) # pokud je pred \\ vic mezer, nahradi se za jednu, pokud jsou mezery za \\, zahodi se
        #             if ($match2) {
        #                 $match2 | % {
        #                     Write-Verbose "Doubling \\ in $_"
        #                     $doubleSlashes = $_ -replace "\\", "\\"
        #                     # musi se zpresnit, matchnout cele slovo ne jen takto!
        #                     $text = $text -replace $escMatch, $doubleSlashes
        #                 }
        #             } else {
        #                 throw "$_ jsem nenasel"
        #             }
        #         }
        #     }
        # }

        # # \\ i.e. newline
        # #FIXME v UNC to nechci
        # $match = ([regex]"(\s+|[^\\])\\\\(\s+|[^\\ ])").matches($text) # pokud je pred \\ vic mezer, nahradi se za jednu, pokud jsou mezery za \\, zahodi se
        # if ($match) {
        #     $match | % {
        #         Write-Verbose "Replacing $($_.value)"
        #         $1 = $_.captures.groups[1].value -replace '\s+$', ' '
        #         $2 = $_.groups[2].value -replace '^\s+'
        #         $text = $text -replace [regex]::Escape($_), "$1`n$2"
        #     }
        # }

        # # \
        # #FIXME v UNC ale chci taky zdvojit..i kdyz jsou tam 2 vedle sebe
        # # but only if it is single backslash (\\ means new line)
        # # https://confluence.atlassian.com/confkb/unable-to-use-some-characters-like-backslash-223904158.html
        # $match = ([regex]"(\s+|[^\\])\\(\s+|[^\\])").matches($text)
        # if ($match) {
        #     $match | % {
        #         Write-Verbose "Replacing \ for \\"
        #         $1 = $_.groups[1].value
        #         $2 = $_.groups[2].value
        #         $text = $text -replace [regex]::Escape($_), "$1\\$2"
        #     }
        # }
        $text = $text -replace "\\", "\\"

        # URL
        # Confluence transforms URL string to `n\nURL\n`n
        # z http://seznam.cz udela `n\nhttp://seznam.cz\n`n
        $match = ([regex]"\b(https?|ftps?):[^ ]+").Matches($text).value
        if ($match) {
            $match | % {
                $text = $text -replace ([regex]::Escape($_) + "\s*"), "`n\n$_\n`n"
            }
        }

        # paired tags
        # i.e. *strong* to strong
        # (there can't be space between tag and inner text, but outside tag, it has to be)
        "*", "_", "??", "-", "+", "^", "~" | % {
            $sign = $_
            $escSign = [regex]::Escape($sign)
            # $match = ([regex]"\s($escSign([^ $sign][^$sign]?[^ $sign]?)$escSign)\s").Matches($text)
            $match = ([regex]"(?:^|\s)($escSign([^ ]|[^ ]{2}|[^ ].*[^ ])$escSign)(?:\s|$)").Matches($text)
            if ($match) {
                $match | % {
                    Write-Verbose "Replacing $($_.value) because of $sign"
                    $1 = $_.captures.groups[1].value
                    $2 = $_.groups[2].value
                    $text = $text -replace [regex]::Escape($1), $2
                }
            }
        }

        # {{monospace}}
        $match = ([regex]"(?:^|\s)({{([^ ]|[^ ]{2}|[^ ].*[^ ])}})(?:\s|$)").Matches($text)
        if ($match) {
            $match | % {
                Write-Verbose "Replacing $($_.value) because of {{}}"
                $1 = $_.captures.groups[1].value
                $2 = $_.groups[2].value
                $text = $text -replace [regex]::Escape($1), $2
            }
        }

        # h1-6 heading
        $text = $text -replace "^h[1-6]{1}\s*"

        # .bq blockquotation
        $text = $text -replace "\bbq\.\s+"

        # [text]
        $text = $text -replace "\[[^]]+\]"

        # lists
        #FIXME
        # # line has to start with -, * or # or its combination and list symbol has to be followed by space
        # "-", "#", "*", "#*" | % {
        #     $sign = $_
        #     $escSign = [regex]::Escape($sign)
        #     if ($sign -in "*", "#") {
        #         # support subsequent levels
        #         $count = "{1,}"
        #     }
        #     $match = ([regex]"^\s*$escSign$count\s{1,}").Matches($text)
        #     if ($match) {
        #         $match | % {
        #             $text = $text -replace [regex]::Escape($_)
        #         }
        #     }
        # }

        # ---- i.e. horizontal line
        $text = $text -replace "^\s*----\s*$}"

        Write-Verbose "Confluence format: $text"
        return $text
    }

    if (@($input1).count -ne @($input2).count) {
        Write-Verbose "Count of the objects isn't the same ($(@($input1).count) vs $(@($input2).count))"
        return $false
    } else {
        if ($property) { $propertyGiven = 1 }

        foreach ($item1 in $input1) {
            # array can consist of different kind of object, so get property for each of them separately
            $itemProperty = $item1 | Get-Member -MemberType CodeProperty, CodeProperty, NoteProperty, Property, ParameterizedProperty, AliasProperty | select name, definition

            if (!$propertyGiven) {
                $property = $itemProperty.name
            } else {
                # check, that all given properties exists on object, otherwise compare won't be precise
                $property | % {
                    if ($_ -notin $itemProperty.name) {
                        throw "$_ property doesn't exist"
                    }
                }
            }

            if ($VerbosePreference -eq "Continue") {
                Write-Verbose "SEARCHING OBJECT WHERE: "
                $property | % {
                    $pName = $_
                    $match = $itemProperty | ? { $_.name -eq $pName }
                    Write-Verbose $match.definition
                }
            }

            $property = $property.ToLower()

            if ($excludeProperty) {
                $property = { $property }.invoke()
                $excludeProperty | % {
                    Write-Verbose "Removing $_ from properties"
                    $null = $property.Remove($_.ToLower())
                }
            }

            if (!$propertyGiven) {
                Write-Verbose "Properties: $($property -join ', ')"
            }

            # prepare Where-Object filter for search in input2
            $whereFilter = ""
            $property | % {
                $pName = $_
                if ($whereFilter) { $whereFilter += " -and " }
                # I recognize type of property from its definition by searching its name in list of all object properties
                if (($itemProperty | ? { $_.name -eq $pName -and $_.definition -match "^string |^System.String " }) -or (!$_.$pName -or !$item1.$pName)) {
                    # property is string or is empty
                    Write-Verbose "Property name: '$pName' definition: is a string"
                    if ($trimStringProperty) {
                        # replace '^\s*|\s*$' instead of trim() because of error: cannot call on null-value expression
                        # -replace '\s+',' ' because when converting plaintext HTML (Confluence page) to object (using IHTMLDocument2_write()), multiple spaces are replaced by one space
                        if ($confluenceInInput2) {
                            $whereFilter += " (`$_.'$pName' -replace '^\s*|\s*$' -replace '\s+',' ' -replace '`r`n', '`n') $operator ((_ConvertToConfluenceFormat `$item1.'$pName') -replace '^\s*|\s*$' -replace '\s+',' ') "
                        } else {
                            $whereFilter += " (`$_.'$pName' -replace '^\s*|\s*$' -replace '`r`n', '`n') $operator (`$item1.'$pName' -replace '^\s*|\s*$' -replace '`r`n', '`n') "
                        }
                    } else {
                        if ($confluenceInInput2) {
                            $whereFilter += " (`$_.'$pName' -replace '\s+',' ' -replace '`r`n', '`n') $operator ((_ConvertToConfluenceFormat `$item1.'$pName') -replace '\s+',' ') "
                        } else {
                            $whereFilter += " (`$_.'$pName' -replace '`r`n', '`n') $operator (`$item1.'$pName' -replace '`r`n', '`n')"
                        }
                    }
                } else {
                    # property isn't string
                    $pDefinition = $itemProperty | ? { $_.name -eq $pName } | select -exp definition
                    Write-Verbose "Property '$pName'`: definition: $pDefinition"
                    $whereFilter += " (!(Compare-Object `$_.'$pName' `$item1.'$pName')) "
                }
            }
            Write-Verbose "Filter: $($whereFilter -replace "`r`n",'`r`n' -replace "`n",'`n')"

            # for each object from input1 array I try to find whether second array contains exactly the same object
            if (!(Invoke-Expression "`$input2 | ? {$whereFilter}")) {
                # identical object doesn't exist in second array
                if ($outputItemWithoutMatch) {
                    Write-Verbose "First object that doesn't have identical match in the second array"
                    Write-Host $item1
                }

                return $false
            }
        }
    }

    return $true
}

function ConvertFrom-CompressedString {
    <#
    .SYNOPSIS
    Function for decompressing the given string.

    .DESCRIPTION
    Function for decompressing the given string.
    It expects the string to be compressed via ConvertTo-CompressedString.

    .PARAMETER compressedString
    String compressed via ConvertTo-CompressedString.

    .EXAMPLE
    $output = Get-Process 'PowerShell' | ConvertTo-Json -Compress

    # compress the string
    $compressedString = ConvertTo-CompressedString -string $output

    # decompress the compressed string to the original one
    $decompressedString = ConvertFrom-CompressedString -string $compressedString
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $compressedString
    )

    process {
        try {
            $inputBytes = [Convert]::FromBase64String($compressedString)
            $memoryStream = New-Object IO.MemoryStream($inputBytes, 0, $inputBytes.Length)
            $gzipStream = New-Object IO.Compression.GZipStream($memoryStream, [IO.Compression.CompressionMode]::Decompress)
            $reader = New-Object IO.StreamReader($gzipStream)
            return $reader.ReadToEnd()
        } catch {
            Write-Error "Unable to decompress the given string. Was it really created using ConvertTo-CompressedString?"
        }
    }
}

function ConvertFrom-EncryptedString {
    <#
    .SYNOPSIS
        Decrypts an AES-encrypted string back to plaintext.

    .DESCRIPTION
        This function decrypts a Base64-encoded string that was previously encrypted using the ConvertTo-EncryptedString function. It uses AES decryption with the key derived from the provided string key using SHA256 hashing.

    .PARAMETER EncryptedText
        The Base64-encoded encrypted string to decrypt, which contains both the IV and the encrypted data.

    .PARAMETER Key
        The encryption key as a string. Must be the same key that was used for encryption.
        This will be hashed using SHA256 to create a 256-bit key.

    .EXAMPLE
        $decryptedText = ConvertFrom-EncryptedString -EncryptedText "d8Q3I/AtB6oQ0LyFHAUXGwEs82FUweK+XZG22P8CQq8=" -Key "MyEncryptionKey"

        Returns the original plaintext string.

    .OUTPUTS
        [System.String]
        Returns the decrypted plaintext string.
        Returns $null if the input string is null, empty, or if decryption fails.

    .NOTES
        This function is designed to work with strings encrypted by the ConvertTo-EncryptedString function.
        The IV is expected to be in the first 16 bytes of the decoded Base64 string.
        If the wrong key is provided or if the encrypted string is corrupted, decryption will fail.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$EncryptedText,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if ([string]::IsNullOrEmpty($EncryptedText)) { return $null }

    try {
        # Create a byte array from the encryption key using SHA256
        $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($Key)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $keyBytes = $sha256.ComputeHash($keyBytes)

        # Convert the encrypted text from Base64
        $encryptedBytes = [Convert]::FromBase64String($EncryptedText)

        # Create AES object
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $keyBytes

        # Extract the IV (first 16 bytes) and the encrypted data
        $iv = $encryptedBytes[0..15]
        $aes.IV = $iv
        $encryptedData = $encryptedBytes[16..($encryptedBytes.Length - 1)]

        # Create decryptor and decrypt the data
        $decryptor = $aes.CreateDecryptor()
        $decryptedBytes = $decryptor.TransformFinalBlock($encryptedData, 0, $encryptedData.Length)

        # Convert decrypted bytes to string
        return [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
    } catch {
        throw "Decryption failed: $_"
    } finally {
        if ($aes) { $aes.Dispose() }
        if ($sha256) { $sha256.Dispose() }
    }
}

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

function ConvertTo-CompressedString {
    <#
    .SYNOPSIS
    Function compress given string.

    .DESCRIPTION
    Function compress given string using GZipStream and the results is returned as a base64 string.

    Please note that the compressed string might not be shorter than the original string if the original string is short, as the compression algorithm adds some overhead.

    .PARAMETER string
    String you want to compress.

    .PARAMETER compressCharThreshold
    (optional) minimum number of characters to actually run the compression.
    If lower, no compression will be made and original text will be returned intact.

    .EXAMPLE
    $output = Get-Process 'PowerShell' | ConvertTo-Json -Compress

    # compress the string
    $compressedString = ConvertTo-CompressedString -string $output

    # decompress the compressed string to the original one
    $decompressedString = ConvertFrom-CompressedString -string $compressedString

    # convert back
    $originalOutput = $decompressedString | ConvertFrom-Json

    .EXAMPLE
    $command = @"
        $output = Get-Process 'PowerShell' | ConvertTo-Json -Compress

        # compress the string (only if necessary a.k.a. remediation output limit of 2048 chars is hit)
        $compressedString = ConvertTo-CompressedString -string $output -compressCharThreshold 2048

        return $compressedString
    "@

    Invoke-IntuneCommand -command $command -deviceName PC-01

    Get the data from the client and compress them if string is longer than 2048 chars.
    Result will be automatically decompressed and converted back from JSON to object.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $string,

        [int] $compressCharThreshold
    )

    process {
        if ($compressCharThreshold) {
            if (($string | Measure-Object -Character).Characters -le $compressCharThreshold) {
                Write-Verbose "Threshold wasn't reached. Returning original string."
                return $string
            }
        }

        try {
            $inputBytes = [System.Text.Encoding]::UTF8.GetBytes($string)
            $outputBytes = New-Object byte[] ($inputBytes.Length)
            $memoryStream = New-Object IO.MemoryStream
            $gzipStream = New-Object IO.Compression.GZipStream($memoryStream, [IO.Compression.CompressionMode]::Compress)
            $gzipStream.Write($inputBytes, 0, $inputBytes.Length)
            $gzipStream.Close()

            return [Convert]::ToBase64String($memoryStream.ToArray())
        } catch {
            Write-Error "Unable to compress the given string"
        }
    }
}

function ConvertTo-EncryptedString {
    <#
    .SYNOPSIS
        Encrypts a string using AES encryption with a provided key.

    .DESCRIPTION
        This function takes a plaintext string and encrypts it using AES-256 encryption.
        The encryption key is derived from the provided string key using SHA256 hashing.
        The function returns a Base64-encoded string that includes the IV and encrypted data.
        Portable across any system.

    .PARAMETER textToEncrypt
        The plaintext string to be encrypted.

    .PARAMETER key
        The encryption key as a string. This will be hashed using SHA256 to create a 256-bit key.

    .EXAMPLE
        $encryptedPassword = ConvertTo-EncryptedString -textToEncrypt "SecretPassword123" -key "MyEncryptionKey"

        Encrypts the password with the provided key and returns an encrypted Base64 string.

    .OUTPUTS
        [System.String]
        Returns a Base64-encoded string containing the IV and encrypted data.
        Returns $null if the input string is null or empty.

    .NOTES
        The function uses AES encryption with a random IV for each encryption operation.
        The IV is prepended to the encrypted data in the output string.
        To decrypt the string, use the corresponding ConvertFrom-EncryptedString function with the same key.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $textToEncrypt,

        [Parameter(Mandatory = $true)]
        [string] $key
    )

    if ([string]::IsNullOrEmpty($textToEncrypt)) { return $null }

    try {
        # Create a byte array from the encryption key
        # We'll derive a 256-bit key using SHA256
        $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($key)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $keyBytes = $sha256.ComputeHash($keyBytes)

        # Create AES object
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $keyBytes
        $aes.GenerateIV() # Generate a random IV for each encryption

        # Convert the text to encrypt to bytes
        $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($textToEncrypt)

        # Create encryptor and encrypt the data
        $encryptor = $aes.CreateEncryptor()
        $encryptedData = $encryptor.TransformFinalBlock($dataBytes, 0, $dataBytes.Length)

        # Combine the IV and encrypted data for storage
        $resultBytes = $aes.IV + $encryptedData

        # Return as Base64 string
        return [Convert]::ToBase64String($resultBytes)
    } catch {
        throw "Encryption failed: $_"
    } finally {
        if ($aes) { $aes.Dispose() }
        if ($sha256) { $sha256.Dispose() }
    }
}

function Expand-ObjectProperty {
    <#
    .SYNOPSIS
    Function integrates selected object property into the main object a.k.a flattens the main object.

    .DESCRIPTION
    Function integrates selected object property into the main object a.k.a flattens the main object.

    Moreover if the integrated property contain '@odata.type' child property, ObjectType

    .PARAMETER inputObject
    Object(s) with that should be flattened.

    .PARAMETER propertyName
    Name opf the object property you want to integrate into the main object.
    Beware that any same-named existing properties in the main object will be overwritten!

    .PARAMETER addObjectType
    (make sense only for MS Graph related objects)
    Switch to add extra 'ObjectType' property in case there is '@odata.type' property in the integrated object that contains type of the object (for example 'user instead of '#microsoft.graph.user' etc).

    .EXAMPLE
    $managementGroupNameList = (Get-AzManagementGroup).Name
    New-AzureBatchRequest -url "https://management.azure.com/providers/Microsoft.Management/managementGroups/<placeholder>/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01" -placeholder $managementGroupNameList | Invoke-AzureBatchRequest | Expand-ObjectProperty -propertyName Properties

    .EXAMPLE
    Get-MgDirectoryObjectById -ids 34568a12-8861-45ff-afef-9282cd9871c6 | Expand-ObjectProperty -propertyName AdditionalProperties -addObjectType
    #>

    [CmdletBinding()]
    param(
        [parameter(ValueFromPipeline)]
        [object[]] $inputObject,

        [Parameter(Mandatory = $true)]
        [string] $propertyName,

        [switch] $addObjectType
    )

    process {
        foreach ($object in $inputObject) {
            if ($object.$propertyName) {
                $propertyType = $object.$propertyName.gettype().name

                if ($propertyType -eq 'PSCustomObject') {
                    ($object.$propertyName | Get-Member -MemberType NoteProperty).Name | % {
                        $pName = $_
                        $pValue = $object.$propertyName.$pName

                        Write-Verbose "Adding property '$pName' to the pipeline object"
                        $object | Add-Member -MemberType NoteProperty -Name $pName -Value $pValue -Force
                    }
                } elseif ($propertyType -in 'Dictionary`2', 'Hashtable') {
                    $object.$propertyName.GetEnumerator() | % {
                        $pName = $_.key
                        $pValue = $_.value

                        $object | Add-Member -MemberType NoteProperty -Name $pName -Value $pValue -Force

                        if ($addObjectType -and $pName -eq "@odata.type") {
                            Write-Verbose "Adding extra property 'ObjectType' to the pipeline object"
                            $object | Add-Member -MemberType NoteProperty -Name 'ObjectType' -Value ($pValue -replace [regex]::Escape("#microsoft.graph.")) -Force
                        }
                    }
                } else {
                    throw "Undefined property type '$propertyType'"
                }

                $object | Select-Object -Property * -ExcludeProperty $propertyName
            } else {
                Write-Warning "There is no '$propertyName' property"
                $object
            }
        }
    }
}

function Export-ScriptsToModule {
    <#
    .SYNOPSIS
        Function for generating Powershell module from ps1 scripts (that contains definition of functions) that are stored in given folder.
        Generated module will also contain function aliases (no matter if they are defined using Set-Alias or [Alias("Some-Alias")].
        Every script file has to have exactly same name as function that is defined inside it (i.e. Get-LoggedUsers.ps1 contains just function Get-LoggedUsers etc).
        If folder with ps1 script(s) contains also module manifest (any psd1 file), it will be used as a base manifest file of the generated module. Information like exported functions, aliases etc will be autogenerated though.
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

    .PARAMETER sensitiveInfoRegex
        Regex that will be searched across generated content. If match is found, execution will be stopped.

    .EXAMPLE
        Export-ScriptsToModule @{"C:\DATA\POWERSHELL\repo\scripts" = "c:\DATA\POWERSHELL\repo\modules\Scripts"}

    .EXAMPLE
        Export-ScriptsToModule @{"C:\DATA\repo\useful_powershell_modules\CommonStuff_source" = "C:\DATA\repo\useful_powershell_modules\CommonStuff"} -includeUncommitedUntracked -dontIncludeRequires

        Publish-Module -Path "C:\DATA\repo\useful_powershell_modules\CommonStuff" -NuGetApiKey "of2gxseokrlium7up2hquxqjrbd3jtfefdasrr2c52ylc4"
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
        ,
        [string] $sensitiveInfoRegex
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

        [Void][System.IO.Directory]::CreateDirectory($moduleFolder)

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

                # get function definition
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

                if ($fName -ne $functionDefinition.name) {
                    throw "Script file has to have same name as a function it contains. But '$script' defines $($functionDefinition.name) a.k.a. rename it"
                }

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
                    }, $true) | ? { $_.typeName.name -eq "Alias" -and $_.parent.extent.text -match '^param' } | Select-Object -ExpandProperty PositionalArguments | Select-Object -ExpandProperty Value -ErrorAction SilentlyContinue # filter out aliases for function parameters

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
                    if (!$manifestDataHash.CmdletsToExport -or $manifestDataHash.CmdletsToExport -eq "*") {
                        Write-Verbose "Removing manifest key CmdletsToExport because it is empty/wildcard (which could have noticeable impact on general PowerShell performance)"
                        $manifestDataHash.CmdletsToExport = @()
                    }
                    if ($manifestDataHash.keys -contains "VariablesToExport" -and !$manifestDataHash.VariablesToExport) {
                        Write-Verbose "Removing manifest key VariablesToExport because it is empty"
                        $manifestDataHash.Remove('VariablesToExport')
                    }

                    # warn about missing required modules in manifest file
                    if ($requiredModulesList -and $manifestDataHash.RequiredModules) {
                        $reqModulesMissingInManifest = $requiredModulesList | ? { $_ -notin $manifestDataHash.RequiredModules } | select -Unique
                        if ($reqModulesMissingInManifest) {
                            Write-Warning "Following modules are required by some of the module function(s), but are missing from manifest file '$manifestFile' key 'RequiredModules': $($reqModulesMissingInManifest -join ', ')"
                        }
                    }

                    # fix for Update-ModuleManifest error: The specified RequiredModules entry 'XXX' in the module manifest 'XXX.psd1' is invalid
                    # because every required module defined in the manifest file have to be in local available module list
                    # so I temporarily create dummy one if necessary
                    if ($manifestDataHash.RequiredModules) {
                        # make a backup of $env:PSModulePath
                        $bkpPSModulePath = $env:PSModulePath

                        $tempModulePath = Join-Path $env:TEMP (Get-Random)
                        # add temp module folder
                        $env:PSModulePath = "$env:PSModulePath;$tempModulePath"

                        $manifestDataHash.RequiredModules | % {
                            if ($_.gettype().Name -eq "String") {
                                # just module name
                                $mName = $_
                            } else {
                                # module name and version
                                $mName = $_.ModuleName
                            }

                            if (!(Get-Module $mName -ListAvailable)) {
                                "Generating temporary dummy required module $mName. It's mentioned in manifest file but missing from this PC available modules list"
                                [Void][System.IO.Directory]::CreateDirectory("$tempModulePath\$mName")
                                'function dummy {}' > "$tempModulePath\$mName\$mName.psm1"
                            }
                        }
                    }

                    # create final manifest file
                    Write-Verbose "Generating module manifest file"

                    # create empty one and than update it because of the bug https://github.com/PowerShell/PowerShell/issues/5922
                    New-ModuleManifest -Path (Join-Path $moduleFolder "$moduleName.psd1")

                    if (($manifestDataHash.PrivateData.PSData.Keys).count -ge 1) {
                        # bugfix because PrivateData parameter expect content of PSData instead of PrivateData
                        $manifestDataHash.PrivateData = $manifestDataHash.PrivateData.PSData
                    }

                    Update-ModuleManifest -Path (Join-Path $moduleFolder "$moduleName.psd1") @manifestDataHash

                    if ($bkpPSModulePath) {
                        # restore $env:PSModulePath from the backup
                        $env:PSModulePath = $bkpPSModulePath
                    }
                    if ($tempModulePath -and (Test-Path $tempModulePath)) {
                        Write-Verbose "Remove required temporary folder '$tempModulePath'"
                        Remove-Item $tempModulePath -Recurse -Force
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

        # convert to absolute path
        $scriptFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($scriptFolder)
        $moduleFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($moduleFolder)

        if ($sensitiveInfoRegex) {
            "Checking for sensitive data. Used regex: $sensitiveInfoRegex"
            $sensitiveSearchResult = Get-ChildItem $scriptFolder -Recurse | Select-String -Pattern $sensitiveInfoRegex
            if ($sensitiveSearchResult) {
                $sensitiveSearchResult | % {
                    Write-Warning "`nFile $($_.Filename) contains sensitive information on the line number $($_.LineNumber).`nLine content: $($_.Line.trim())"
                }

                return "Fix this and try again"
            }
        }

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
            $syntaxError = Invoke-ScriptAnalyzer $moduleFolder -Severity ParseError
            if ($syntaxError) {
                Write-Warning "In module $moduleFolder were found these problems:`n$($syntaxError | % { $_.ScriptName + " - " + $_.Message + "`n" })"
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
        [Alias("programName")]
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

function Get-PSHScriptBlockLoggingEvent {
    <#
    .SYNOPSIS
    Function returns commands that was run in PowerShell, captured using "PowerShell Script Block logging" feature. Moreover it enhances such data with context, like how the parent PowerShell process was called, by whom, when it started/ended, whether it was local/remote session, whether it was Windows PowerShell or PowerShell Core and what scripts was being run during the session.

    .DESCRIPTION
    Function returns commands that was run in PowerShell, captured using "PowerShell Script Block logging" feature. Moreover it enhances such data with context, like how the parent PowerShell process was called, by whom, when it started/ended, whether it was local/remote session, whether it was Windows PowerShell or PowerShell Core and what scripts was being run during the session.

    To get all possible context information these event logs are used:
        - 'Microsoft-Windows-PowerShell/Operational'(for Windows PowerShell)
        - 'PowerShellCore/Operational' (for PowerShell Core)
        - 'Microsoft-Windows-WinRM/Operational'
        - 'Windows PowerShell'

    How this functions works:
    - start/stop session events are gathered
        - such data contains additional context, like who and how run the PSH session
        - stop events are found using unique hostId that is same as for start event
    - Script Block logging events are gathered and grouped by machineName and ProcessId
    - For each ProcessId is found related start/stop data
        - because start/stop events doesn't contain called ProcessId, the closest one is picked
    - Merged result is returned sorted by session start time

    Function gathers these events:
    - Script Block logging events that contain content of the invoked commands:
        - log 'Microsoft-Windows-PowerShell/Operational', event '4104' (for Windows PowerShell)
        - log 'PowerShellCore/Operational', event '4104' (for PowerShell Core)
    - Script Block logging events that contain start of the invoked PSH session:
        Contains just start time without any additional information like who and how the sessions started, so additional data has to be gathered.
        - log 'Microsoft-Windows-PowerShell/Operational', event '40961' (for Windows PowerShell)
        - log 'PowerShellCore/Operational', event '40961' (for PowerShell Core)
    - WinRM events that contain winrm remote session start:
        Contains start time of the session, who and from which host started it.
        - log 'Microsoft-Windows-WinRM/Operational', event 91
    - Windows PowerShell events that contain details about started session:
        Contains how the session was invoked and by whom and is logged few milliseconds (or seconds :D) after 40961 event.
        Unfortunately doesn't contain any unique identifier to correlate this event with 40961. So the closest event is picked as the right one.
        - log 'Windows PowerShell', event 400
    - Windows PowerShell events that contain end of the invoked PSH session:
        Contains when the session ended and can be found through unique hostid that is same as for session start event (400)
        - log 'Windows PowerShell', event 403

    Unfortunately PowerShell Core doesn't log 400, 403 events at all, so there are no additional data (how it was invoked and when it ended) available.

    Function supports searching through local event logs, logs from remote computer (exported as evtx files) or forwarded events (saved in special ForwardedEvents event log).

    Function supports reading of protected (encrypted) events if decryption certificate (with private key) is stored in certificate personal store.

    Searched event logs can be defined via name or path to evtx file.

    .PARAMETER startTime
    Start time from which Script Block logging events should be searched.

    By default a day ago from now.

    .PARAMETER endTime
    End time to which Script Block logging events should be searched.

    By default now.

    .PARAMETER microsoftWindowsPowerShellOperational_LogName
    By default "Microsoft-Windows-PowerShell/Operational".

    .PARAMETER powerShellCoreOperational_LogName
    By default "PowerShellCore/Operational".

    .PARAMETER windowsPowerShell_LogName
    By default "Windows PowerShell".

    .PARAMETER microsoftWindowsWinRM_LogName
    By default "Microsoft-Windows-WinRM/Operational".

    .PARAMETER microsoftWindowsPowerShellOperational_LogPath
    Path to saved evtx file of the "Microsoft-Windows-PowerShell/Operational" event log.

    .PARAMETER powerShellCoreOperational_LogPath
    Path to saved evtx file of the "PowerShellCore/Operational" event log.

    .PARAMETER windowsPowerShell_LogPath
    Path to saved evtx file of the "Windows PowerShell" event log.

    .PARAMETER microsoftWindowsWinRM_LogPath
    Path to saved evtx file of the "Microsoft-Windows-WinRM/Operational" event log.

    .PARAMETER machineName
    Name of the computer you want to get events for.
    Make sense to use if forwarded events from multiple computers are searched.

    .PARAMETER contextEventsStartTime
    Start time for searching helper events.

    By default value of startTime parameter minus one day.

    .PARAMETER contextEventsEndTime
    End time for searching helper events.

    By default value of endTime parameter plus one day.

    .PARAMETER PSHType
    What type of sessions should be searched.

    Possible values: "WindowsPowerShell", "PowerShellCore"

    By default both PSH types are searched.

    .PARAMETER omitScriptBlockLoggingStatusCheck
    Switch for skipping check that Script Block logging is enabled & proposing enablement.

    .EXAMPLE
    Get-PSHScriptBlockLoggingEvent

    Get PSH Script Block logging events from this computer events log.
    Events for past 24 hours will be searched.

    .EXAMPLE
    Get-PSHScriptBlockLoggingEvent -startTime "7.8.2023 9:00" -endTime "10.8.2023 15:00"

    Get PSH Script Block logging events from this computer events log.
    Events for given time span will be searched.

    .EXAMPLE
    Get-PSHScriptBlockLoggingEvent -MicrosoftWindowsPowerShellOperational_LogName ForwardedEvents -WindowsPowerShell_LogName ForwardedEvents -powerShellCoreOperational_LogName ForwardedEvents -microsoftWindowsWinRM_LogName ForwardedEvents -machineName pc-01.contoso.com

    Get PSH Script Block logging events from forwarded events log (using log name) for computer 'pc-01.contoso.com'.

    .EXAMPLE
    Get-PSHScriptBlockLoggingEvent -MicrosoftWindowsPowerShellOperational_LogPath "C:\CapturedLogs\Microsoft-Windows-PowerShell%4Operational.evtx" -WindowsPowerShell_LogPath "C:\CapturedLogs\Windows PowerShell.evtx" -microsoftWindowsWinRM_LogPath "C:\CapturedLogs\Microsoft-Windows-WinRM%4Operational.evtx" -PSHType WindowsPowerShell

    Get Windows PowerShell Script Block logging events from given evtx files.

    .NOTES
    Returned data don't have to be 100% accurate! Unfortunately there is no unique identifier used across related events for grouping them, so there has to be some guessing.

    What makes this thing even more difficult is that
    - PSH start events are sometimes NOT logged at all
    - PSH session ProcessId is being reused quite often

    Commands invoked via PowerShell version older than 5.x won't be shown (because don't support Script Block logging)!
    You can search such invokes via:
    Get-WinEvent -LogName "Windows PowerShell" |
    Where-Object Id -EQ 400 |
    ForEach-Object {
        $version = [Version] (
            $_.Message -replace '(?s).*EngineVersion=([\d\.]+)*.*', '$1')
        if ($version -lt ([Version] "5.0")) { $_ }
    }

    https://nsfocusglobal.com/attack-and-defense-around-powershell-event-logging/
    #>

    [CmdletBinding(DefaultParameterSetName = 'LogName')]
    param (
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                if (($_.getType().name -eq "string" -and [DateTime]::Parse($_)) -or ($_.getType().name -eq "dateTime")) {
                    $true
                } else {
                    throw "Enter in format per your culture. For cs-CZ: 15.2.2019 15:00. For en-US: 2.15.2019 15:00."
                }
            })]
        $startTime = ([datetime]::Now).addDays(-1),

        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                if (($_.getType().name -eq "string" -and [DateTime]::Parse($_)) -or ($_.getType().name -eq "dateTime")) {
                    $true
                } else {
                    throw "Enter in format per your culture. For cs-CZ: 15.2.2019 15:00. For en-US: 2.15.2019 15:00."
                }
            })]
        $endTime = [datetime]::Now,

        [Parameter(Mandatory = $false, ParameterSetName = "LogName")]
        [string] $microsoftWindowsPowerShellOperational_LogName = "Microsoft-Windows-PowerShell/Operational",

        [Parameter(Mandatory = $false, ParameterSetName = "LogName")]
        [string] $powerShellCoreOperational_LogName = "PowerShellCore/Operational",

        [Parameter(Mandatory = $false, ParameterSetName = "LogName")]
        [string] $windowsPowerShell_LogName = "Windows PowerShell",

        [Parameter(Mandatory = $false, ParameterSetName = "LogName")]
        [string] $microsoftWindowsWinRM_LogName = "Microsoft-Windows-WinRM/Operational",

        [Parameter(Mandatory = $false, ParameterSetName = "LogPath")]
        [ValidateScript( {
                if ((Test-Path -Path $_) -and ($_ -like "*.evtx")) {
                    $true
                } else {
                    throw "$_ doesn't exist or it is not an event log EVTX file"
                }
            })]
        [string] $microsoftWindowsPowerShellOperational_LogPath,

        [Parameter(Mandatory = $false, ParameterSetName = "LogPath")]
        [ValidateScript( {
                if ((Test-Path -Path $_) -and ($_ -like "*.evtx")) {
                    $true
                } else {
                    throw "$_ doesn't exist or it is not an event log EVTX file"
                }
            })]
        [string] $powerShellCoreOperational_LogPath,

        [Parameter(Mandatory = $false, ParameterSetName = "LogPath")]
        [ValidateScript( {
                if ((Test-Path -Path $_) -and ($_ -like "*.evtx")) {
                    $true
                } else {
                    throw "$_ doesn't exist or it is not an event log EVTX file"
                }
            })]
        [string] $windowsPowerShell_LogPath,

        [Parameter(Mandatory = $false, ParameterSetName = "LogPath")]
        [ValidateScript( {
                if ((Test-Path -Path $_) -and ($_ -like "*.evtx")) {
                    $true
                } else {
                    throw "$_ doesn't exist or it is not an event log EVTX file"
                }
            })]
        [string] $microsoftWindowsWinRM_LogPath,

        [string[]] $machineName,

        [ValidateScript({
                if (($_.getType().name -eq "string" -and [DateTime]::Parse($_)) -or ($_.getType().name -eq "dateTime")) {
                    $true
                } else {
                    throw "Enter in format per your culture. For cs-CZ: 15.2.2019 15:00. For en-US: 2.15.2019 15:00."
                }
            })]
        $contextEventsStartTime,

        [ValidateScript({
                if (($_.getType().name -eq "string" -and [DateTime]::Parse($_)) -or ($_.getType().name -eq "dateTime")) {
                    $true
                } else {
                    throw "Enter in format per your culture. For cs-CZ: 15.2.2019 15:00. For en-US: 2.15.2019 15:00."
                }
            })]
        $contextEventsEndTime,

        [ValidateNotNullOrEmpty()]
        [ValidateSet("WindowsPowerShell", "PowerShellCore")]
        [string[]] $PSHType = @("WindowsPowerShell", "PowerShellCore"),

        [switch] $omitScriptBlockLoggingStatusCheck
    )

    #region prepare
    if ($startTime -and $startTime.getType().name -eq "string") { $startTime = [DateTime]::Parse($startTime) }
    if ($endTime -and $endTime.getType().name -eq "string") { $endTime = [DateTime]::Parse($endTime) }
    if ($contextEventsStartTime -and $contextEventsStartTime.getType().name -eq "string") { $contextEventsStartTime = [DateTime]::Parse($contextEventsStartTime) }
    if ($contextEventsEndTime -and $contextEventsEndTime.getType().name -eq "string") { $contextEventsEndTime = [DateTime]::Parse($contextEventsEndTime) }

    if ($startTime -and $endTime -and $startTime -gt $endTime) {
        throw "'startTime' cannot be after 'endTime'"
    }

    if ($startTime -gt [DateTime]::Now) {
        throw "'startTime' cannot be in the future"
    }

    if (!$contextEventsStartTime) {
        $contextEventsStartTime = $startTime.addDays(-1)
        Write-Verbose "'contextEventsStartTime' not defined. Set it to $contextEventsStartTime"
    }

    if (!$contextEventsEndTime) {
        $contextEventsEndTime = $endTime.addDays(1)
        Write-Verbose "'contextEventsEndTime' not defined. Set it to $contextEventsEndTime"
    }

    if ($contextEventsStartTime -ge $startTime) {
        throw "'contextEventsStartTime' has to have date older than 'startTime'"
    }

    if ($contextEventsEndTime -le $endTime) {
        throw "'contextEventsEndTime' has to have later date than 'startTime'"
    }

    if (!$startTime -or !$endTime -or !$contextEventsStartTime -or !$contextEventsEndTime) {
        throw "Some parameter value is missing! All 'startTime', 'endTime', 'contextEventsStartTime' and 'contextEventsEndTime' need to have a value."
    }
    #endregion prepare

    Write-Warning "Searching for Script Block logging events created between '$startTime' and '$endTime' and helper events between '$contextEventsEndTime' and '$contextEventsEndTime'"

    #region checks
    # check that all or none log related parameters were modified
    $logParam = "microsoftWindowsPowerShellOperational_LogName", "powerShellCoreOperational_LogName", "windowsPowerShell_LogName", "microsoftWindowsWinRM_LogName", "microsoftWindowsPowerShellOperational_LogPath", "powerShellCoreOperational_LogPath", "windowsPowerShell_LogPath", "microsoftWindowsWinRM_LogPath"
    $changedLogParam = $PSBoundParameters.Keys | ? { $_ -in $logParam }
    # $logParam/2 because *_LogName or *_LogPath params can be used but not both
    if ($changedLogParam -and $changedLogParam.count -ne ($logParam.count / 2)) {
        Write-Warning "You've defined some of the LogName/LogPath parameters but not all of them. This means that some of the events will be searched in local default logs and some in the ones you've specified. This is most probably a mistake!"
    }

    # check whether PSH Core event log exists
    # btw you must register log manifest during PSH Core installation a.k.a. you can have PSH Core installed without this event log activated!
    $PSHCoreIsAvailable = Get-WinEvent -ListLog "PowerShellCore/Operational" -ErrorAction SilentlyContinue

    # check whether the searched logs are from this or other computer
    # some checks etc don't make sense in case logs from a different computer are searched
    $logFromOtherComputer = $false
    if ($windowsPowerShell_LogName -ne "Windows PowerShell" -or $windowsPowerShell_LogPath -or $microsoftWindowsPowerShellOperational_LogName -ne "Microsoft-Windows-PowerShell/Operational" -or $microsoftWindowsPowerShellOperational_LogPath) {
        Write-Verbose "Logs seems to be from a different computer"
        $logFromOtherComputer = $true
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

    #region check that Script BlockLogging is enabled & propose enablement if it isn't
    if (!$logFromOtherComputer -and !$omitScriptBlockLoggingStatusCheck) {
        #region Windows PSH
        if ($PSHType -contains "WindowsPowerShell") {
            $regPath = "HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
            try {
                $enabledPSHScriptBlockLogging = Get-ItemPropertyValue $regPath "EnableScriptBlockLogging" -ErrorAction stop
            } catch {}

            if ($enabledPSHScriptBlockLogging -ne 1) {
                Write-Warning "Windows PowerShell Script Block logging isn't enabled on this system"

                if ($isAdmin) {
                    $choice = ""
                    while ($choice -notmatch "^[Y|N]$") {
                        $choice = Read-Host "Enable ScriptBlock logging? (Y|N)"
                    }
                    if ($choice -eq "N") {
                        # there might be old logging events, don't terminate this function
                    } else {
                        $null = New-Item -Path $regPath -Force
                        $null = Set-ItemProperty -Path $regPath -Name "EnableScriptBlockLogging" -Value 1 -Force
                        return "Script Block logging was enabled. Start a NEW Windows PowerShell console, run some code and try this function again."
                    }
                } else {
                    Write-Warning "Enable manually or run this function again as administrator"
                }
            }
        }
        #endregion Windows PSH

        # PSH Core 6.x is unsupported therefore ignored, but logging can be turned on in HKLM:\SOFTWARE\Policies\Microsoft\PowerShellCore\ScriptBlockLogging (event log manifest is incompatible with 7.x version aka events just from one version can be logged anyway)

        #region PSH Core 7.x
        if ($PSHType -contains "PowerShellCore") {
            $PSHCoreInstalledVersionKey = "HKLM:\SOFTWARE\Microsoft\PowerShellCore\InstalledVersions"
            if ((Test-Path $PSHCoreInstalledVersionKey -ea SilentlyContinue)) {
                # PSH Core is installed

                $regPath = "HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\PowerShellCore\ScriptBlockLogging"

                try {
                    $enabledPSHCoreScriptBlockLogging = Get-ItemPropertyValue $regPath "EnableScriptBlockLogging" -ErrorAction stop
                } catch {}

                if ($enabledPSHCoreScriptBlockLogging -ne 1) {
                    Write-Warning "PowerShell Core 7.x Script Block logging isn't enabled on this system"

                    if ($isAdmin) {
                        $choice = ""
                        while ($choice -notmatch "^[Y|N]$") {
                            $choice = Read-Host "Enable ScriptBlock logging? (Y|N)"
                        }
                        if ($choice -eq "N") {
                            # there might be old logging events, don't terminate this function
                        } else {
                            $null = New-Item -Path $regPath -Force
                            $null = Set-ItemProperty -Path $regPath -Name "EnableScriptBlockLogging" -Value 1 -Force
                            return "Script Block logging was enabled. Start a NEW PowerShell Core console, run some code and try this function again."
                        }
                    } else {
                        Write-Warning "Enable manually or run this function again as administrator"
                    }
                }
            }
        }
        #endregion PSH Core 7.x
    }
    #endregion check that Script BlockLogging is enabled & propose enablement if it isn't

    #region check event logs are enabled & enable
    if (!$logFromOtherComputer) {
        # "Windows Powershell" event log cannot be disabled
        "Microsoft-Windows-PowerShell/Operational", "PowerShellCore/Operational", "Microsoft-Windows-WinRM/Operational" | % {
            $logState = Get-WinEvent -ListLog $_ -ErrorAction SilentlyContinue # Core doesn't have to be installed or registered for event logging (part of installation)
            if ($logState -and (!$logState.IsEnabled)) {
                Write-Warning "Event log '$_' isn't enabled! Enabling"
                if ($isAdmin) {
                    wevtutil.exe sl "$_" /enabled:true
                } else {
                    Write-Error "Unable to enable event log '$_'. Not running as admin."
                }
            }
        }
    }
    #endregion check event logs are enabled & enable

    #region check Protected Event Logging settings
    try { $enableProtectedEventLogging = Get-ItemPropertyValue "HKLM:\Software\Policies\Microsoft\Windows\EventLog\ProtectedEventLogging" "EnableProtectedEventLogging" -ErrorAction stop } catch {}
    # check for decryption certificate in either case, because just because now PEL isn't enabled doesn't mean it wasn't enabled in the past
    $decryptionCert = Get-ChildItem -Path 'Cert:\LocalMachine\My\', 'Cert:\CurrentUser\My\' -Recurse | ? { $_.EnhancedKeyUsageList.FriendlyName -eq "Document Encryption" -and $_.HasPrivateKey -and $_.Extensions.KeyUsages -eq "DataEncipherment, KeyEncipherment" }

    if (!$decryptionCert -and $enableProtectedEventLogging -eq 1) {
        Write-Warning "Protected Event Logging (PEL) is enabled on this system, but PEL decryption certificate (with private key) isn't imported in your Personal certificate store a.k.a. called commands stays encrypted"
    }

    if (!$decryptionCert -and $logFromOtherComputer) {
        Write-Warning "Logs are from different computer and PEL decryption certificate (with private key) isn't imported in your Personal certificate store a.k.a. called commands stays encrypted (if encrypted)"
    }
    #endregion check Protected Event Logging settings
    #endregion checks

    #region get additional PSH console data
    #region helper function
    function _getPSHInvokedVia {
        param ($startEvent)

        if (!$startEvent) {
            Write-Verbose "Unable to find related PSH start event (ID 400) for ProcessId $processId. 'InvokedVia' property cannot be retrieved."
            return "<<unknown>>"
        }

        ($startEvent.Properties[2].Value.Split("`n") | Select-String "HostApplication=") -replace "^\s*HostApplication=" #"^.+?powershell.exe", "powershell.exe"
    }

    function _getInvokedScript {
        param ($eventList)

        if (!$eventList) { return }

        $invokedScript = $eventList | % {
            if ($_.Properties[-1].value) {
                $_.Properties[-1].value # last item contains invoked script
            }
        }

        $invokedScript | select -Unique
    }

    function _getSessionType {
        param ($startEvent)

        #TODO jak vypada kdyz se z core pripojim remote na stroj? kam se loguje?

        if ($startEvent.ProviderName -in 'PowerShellCore', 'Microsoft-Windows-PowerShell') {
            return "local"
        } elseif ($startEvent.ProviderName -eq 'Microsoft-Windows-WinRM') {
            $remoteConnectionInfo = ([regex]"\((.+)\)").Matches($startEvent.properties.value).groups[1].value
            return "remote ($remoteConnectionInfo)"
        } else {
            throw "Undefined ProviderName $($startEvent.ProviderName)"
        }
    }

    function _getCommandText {
        param ($eventList)

        if (!$eventList) { return }

        $eventList | % {
            if ($decryptionCert -and $_.message -like "Creating Scriptblock text*-----BEGIN CMS-----*ScriptBlock ID:*") {
                # sometimes Unprotect-CmsMessage returns zero :) bug? probably
                Unprotect-CmsMessage -Content $_.message
            } else {
                $_.properties[2].value
                # (([xml]$_.toxml()).Event.EventData.Data | ? name -EQ "ScriptBlockText").'#text'
            }
        }
    }
    #endregion helper function

    #region get Windows PowerShell basic start events (without arguments etc)
    if ($PSHType -contains "WindowsPowerShell") {
        Write-Progress -Activity "Getting helper events" -Status "Getting Windows PowerShell basic start events" -PercentComplete (20)

        $filterHashtable = @{
            id        = 40961
            startTime = $contextEventsStartTime
            endTime   = $endTime
        }
        if ($microsoftWindowsPowerShellOperational_LogPath) {
            $filterHashtable.path = $microsoftWindowsPowerShellOperational_LogPath
        } else {
            $filterHashtable.logname = $microsoftWindowsPowerShellOperational_LogName
        }

        try {
            $PSHBasicStartEvent = Get-WinEvent -FilterHashtable $filterHashtable -ErrorAction Stop | ? ProviderName -EQ "Microsoft-Windows-PowerShell" | ? { if (!$machineName -or ($machineName -and $_.MachineName -in $machineName)) { $_ } }
        } catch {
            if ($_ -like "*No events were found that match the specified selection criteria*") {
                Write-Warning "No events (ID: 40961) were found in Windows PowerShell Operational event log (from $contextEventsStartTime to $endTime)"
            } else {
                throw $_
            }
        }
    }
    #endregion get Windows PowerShell basic start events (without arguments etc)

    #region get PowerShell Core basic start events (without arguments etc)
    if ($PSHType -contains "PowerShellCore" -and ($PSHCoreIsAvailable -or $logFromOtherComputer)) {
        Write-Progress -Activity "Getting helper events" -Status "Getting PowerShell Core basic start events" -PercentComplete (40)

        $filterHashtable = @{
            id        = 40961
            startTime = $contextEventsStartTime
            endTime   = $endTime
        }
        if ($powerShellCoreOperational_LogPath) {
            $filterHashtable.path = $powerShellCoreOperational_LogPath
        } else {
            $filterHashtable.logname = $powerShellCoreOperational_LogName
        }

        try {
            $PSHCoreBasicStartEvent = Get-WinEvent -FilterHashtable $filterHashtable -ErrorAction Stop | ? ProviderName -EQ "PowerShellCore" | ? { if (!$machineName -or ($machineName -and $_.MachineName -in $machineName)) { $_ } }
        } catch {
            if ($_ -like "*No events were found that match the specified selection criteria*") {
                Write-Warning "No events (ID: 40961) were found in PowerShell Core Operational event log (from $contextEventsStartTime to $endTime)"
            } else {
                throw $_
            }
        }
    }
    #endregion get PowerShell Core basic start events (without arguments etc)

    #region get Windows PowerShell start events with additional data (with arguments etc)
    Write-Progress -Activity "Getting helper events" -Status "Getting Windows PowerShell start events with additional data" -PercentComplete (60)

    $filterHashtable = @{
        id        = 400
        startTime = $contextEventsStartTime
        endTime   = $endTime
    }
    if ($windowsPowerShell_LogPath) {
        $filterHashtable.path = $windowsPowerShell_LogPath
    } else {
        $filterHashtable.logname = $windowsPowerShell_LogName
    }

    try {
        $PSHEnhancedStartEvent = Get-WinEvent -FilterHashtable $filterHashtable -ErrorAction stop | ? ProviderName -EQ "PowerShell" | ? { if (!$machineName -or ($machineName -and $_.MachineName -in $machineName)) { $_ } }
    } catch {
        if ($_ -like "*No events were found that match the specified selection criteria*") {
            Write-Warning "No events (ID: 400) were found in Windows PowerShell event log (from $contextEventsStartTime to $endTime)"
        } else {
            throw $_
        }
    }
    #endregion get Windows PowerShell start events with additional data (with arguments etc)

    #region get Windows PowerShell end events
    # Script Block logging event log doesn't contain console termination events, therefore this log have to be searched
    Write-Progress -Activity "Getting helper events" -Status "Getting Windows PowerShell end events" -PercentComplete (80)

    $filterHashtable = @{
        id        = 403
        startTime = $startTime
        endTime   = $contextEventsEndTime
    }
    if ($windowsPowerShell_LogPath) {
        $filterHashtable.path = $windowsPowerShell_LogPath
    } else {
        $filterHashtable.logname = $windowsPowerShell_LogName
    }

    try {
        $PSHEnhancedEndEvent = Get-WinEvent -FilterHashtable $filterHashtable -ErrorAction stop | ? ProviderName -EQ "PowerShell" | ? { if (!$machineName -or ($machineName -and $_.MachineName -in $machineName)) { $_ } }
    } catch {
        if ($_ -like "*No events were found that match the specified selection criteria*") {
            Write-Warning "No events (ID: 403) were found in Windows PowerShell event log (from $startTime to $contextEventsEndTime)"
        } else {
            throw $_
        }
    }
    #endregion get Windows PowerShell end events

    #region get Windows PowerShell remote session start events
    # Script Block logging event log doesn't contain remote session start events
    Write-Progress -Activity "Getting helper events" -Status "Getting Windows PowerShell remote session start events" -PercentComplete (100)

    $filterHashtable = @{
        id        = 91
        startTime = $contextEventsStartTime
        endTime   = $contextEventsEndTime
    }
    if ($microsoftWindowsWinRM_LogPath) {
        $filterHashtable.path = $microsoftWindowsWinRM_LogPath
    } else {
        $filterHashtable.logname = $microsoftWindowsWinRM_LogName
    }

    try {
        $PSHRemoteSessionStartEvent = Get-WinEvent -FilterHashtable $filterHashtable -ErrorAction stop | ? ProviderName -EQ "Microsoft-Windows-WinRM" | ? { if (!$machineName -or ($machineName -and $_.MachineName -in $machineName)) { $_ } }
    } catch {
        if ($_ -like "*No events were found that match the specified selection criteria*") {
            Write-Warning "No events (ID: 91) were found in WinRM event log (from $contextEventsStartTime to $contextEventsEndTime)"
        } else {
            throw $_
        }
    }
    #endregion get Windows PowerShell remote session start events
    #endregion get additional PSH console data

    #region get PSH start/stop data
    # this data are particularly helpful when more separate events, but with same processId are processed
    $startStopList = New-Object System.Collections.ArrayList

    # get all START events
    $PSHStartEventList = New-Object System.Collections.ArrayList

    $PSHBasicStartEvent | ? { $_ } | % { $null = $PSHStartEventList.Add($_) }
    $PSHRemoteSessionStartEvent | ? { $_ } | % { $null = $PSHStartEventList.Add($_) }
    $PSHCoreBasicStartEvent | ? { $_ } | % { $null = $PSHStartEventList.Add($_) }

    # from oldest to newest so I can easily pick the correct helper events later
    $PSHStartEventList = $PSHStartEventList | sort TimeCreated

    $problematicEventCount = 0
    $i = 0

    # get corresponding END events and merge it all together
    foreach ($PSHStartEvent in $PSHStartEventList) {
        $timeCreated = $PSHStartEvent.TimeCreated
        $processId = $PSHStartEvent.processId
        $eventMachineName = $PSHStartEvent.machineName
        $PSHHostId = $null
        $stopTime = ""
        $startEventWithDetails = $null
        $stopEvent = $null

        Write-Progress -Activity "Merging START&STOP events" -Status "Processing start event created at $timeCreated" -PercentComplete ((++$i / $PSHStartEventList.count) * 100)

        # it can take time before helper event occurs, therefore check time range
        # all available events
        $startEventWithDetailsList = $PSHEnhancedStartEvent | ? { $_.machineName -eq $eventMachineName -and $_.TimeCreated -ge $timeCreated -and $_.TimeCreated -le $timeCreated.AddMilliseconds(10000) } | sort TimeCreated

        if ($startEventWithDetailsList.count -gt 1 -and ($startEventWithDetailsList[0].TimeCreated -eq $startEventWithDetailsList[1].TimeCreated)) {
            if ($lastProcessedStartEventWithDetails.TimeCreated -eq $startEventWithDetailsList[0].TimeCreated) {
                # this is second or more event where helper event has to be guessed, because of same creation time
                # pick the next one
                Write-Warning "ProcessId $processId (start $timeCreated) is $($problematicEventCount + 1). in a row where there are multiple helper events with exactly the same creation time. The $($problematicEventCount + 1). will be used, but it is just a GUESS!"
                $startEventWithDetails = $startEventWithDetailsList[$problematicEventCount]
                ++$problematicEventCount
            } else {
                # this is first event where helper event has to be guessed, because of same creation time
                # pick the first one
                Write-Warning "For ProcessId $processId (start $timeCreated) events there are multiple helper events with exactly the SAME creation time. The one to use will be therefore GUESSED! So there is chance that properties gathered thanks to this helper event (InvokedVia, StopTime, who & how invoked this, ...) won't be correct!!!"
                $startEventWithDetails = $startEventWithDetailsList[0]
                ++$problematicEventCount
            }
        } else {
            # pick the closest not-yet-used one
            # because it with highest probability corresponds to the processed one
            $startEventWithDetails = $startEventWithDetailsList | select -First 1
            $problematicEventCount = 0
        }

        $lastProcessedStartEventWithDetails = $startEventWithDetails

        # ProcessID can be reused, but with filtering via ProcessName and StartTime (in case there are multiple PSH sessions with same ProcessId) it should be fine
        if ($eventMachineName -like "$env:COMPUTERNAME*" -and (Get-Process -Id $processId -ErrorAction SilentlyContinue | ? { $_.ProcessName -match "powershell|pwsh" -and ($_.StartTime -ge $timeCreated.AddMilliseconds(-3000) -or $_.StartTime -le $timeCreated.AddMilliseconds(3000)) })) {
            $stopTime = "<<still running>>"
        } else {
            if (!$startEventWithDetails) {
                $stopTime = "<<unknown>>"
            } else {
                # get HostId from the console start event
                $PSHHostId = ((($startEventWithDetails.Message) -split "`n" | Select-String "^\s+HostId=") -replace "^\s+HostId=").trim()

                # find out when PSH console with given HostId ended
                $stopEvent = $PSHEnhancedEndEvent | ? { $_.machineName -eq $eventMachineName -and $_.TimeCreated -ge $timeCreated -and $_.Message -like "*HostId=$PSHHostId*" } | select -Last 1

                if ($stopEvent) {
                    $stopTime = $stopEvent.TimeCreated
                } else {
                    $stopTime = "<<unknown>>"
                }
            }
        }

        $r = [PSCustomObject]@{
            ProcessId             = $processId
            HostId                = $PSHHostId
            StartTime             = $timeCreated
            StopTime              = $stopTime
            StartEvent            = $PSHStartEvent
            StartEventWithDetails = $startEventWithDetails
            StopEvent             = $stopEvent
            MachineName           = $PSHStartEvent.MachineName
        }

        $null = $startStopList.add($r)
    }
    #endregion get PSH start/stop data

    $result = New-Object System.Collections.ArrayList

    #region get PowerShell Core Script Block logging events
    if ($PSHType -contains "PowerShellCore" -and ($PSHCoreIsAvailable -or $logFromOtherComputer)) {
        Write-Progress -Activity "Retrieving Core Script Block Logging events"

        $filterHashtable = @{
            id    = 4104
            level = 3, 5 # just warning and verbose events contain command lines
        }
        if ($powerShellCoreOperational_LogPath) {
            $filterHashtable.path = $powerShellCoreOperational_LogPath
        } else {
            $filterHashtable.logname = $powerShellCoreOperational_LogName
        }
        if ($startTime) {
            $filterHashtable.startTime = $startTime
        }
        if ($endTime) {
            $filterHashtable.endTime = $endTime
        }

        # ProviderName filtering via Where-Object and not directly in Get-WinEvent, because of error "The specified providers do not write events to the forwardedevents log" in case Forwarded event log is searched
        try {
            $PSHCoreEvent = Get-WinEvent -FilterHashtable $filterHashtable -ErrorAction Stop |
                ? ProviderName -EQ "PowerShellCore" |
                ? { if (!$machineName -or ($machineName -and $_.MachineName -in $machineName)) { $_ } }
        } catch {
            if ($_ -like "*No events were found that match the specified selection criteria*") {
                Write-Warning "No PowerShell Core invocations were found"
            } else {
                throw $_
            }
        }

        if ($PSHCoreEvent) {
            # oldest events first
            [array]::Reverse($PSHCoreEvent)
            # group events
            $PSHCoreEvent = $PSHCoreEvent | Group-Object MachineName, ProcessId

            $i = 0

            # process grouped PowerShell Core script block logging events
            $PSHCoreEvent | % {
                $eventMachineName = ($_.Name -split ",")[0].trim()
                [int]$processId = ($_.Name -split ",")[1].trim()
                $groupedEvent = $_.Group
                $firstEventTimeCreated = $groupedEvent[0].TimeCreated
                $lastEventTimeCreated = $groupedEvent[-1].TimeCreated

                Write-Progress -Activity "Processing Core Script Block Logging events" -Status "Processing events with processId $processId" -PercentComplete ((++$i / $PSHCoreEvent.count) * 100)

                $scriptBlockPart = ([regex]"Creating Scriptblock text \((\d+) of \d+\)").Matches($groupedEvent[0].message).captures.groups[1].value
                if ($scriptBlockPart -and $scriptBlockPart -ne 1) {
                    Write-Warning "Invoked commands for processid: $processId are trimmed (events were probably overwriten). Commands starts from capture script block number $scriptBlockPart"
                }

                $processStartStopData = $startStopList | ? { $_.machineName -eq $eventMachineName -and $_.processId -eq $processId -and ($_.StartTime -le $lastEventTimeCreated -and ($_.StopTime -in "<<unknown>>", "<<still running>>" -or $_.StopTime -ge $firstEventTimeCreated)) }

                if (!$processStartStopData) {
                    # context data about start/stop are missing
                    Write-Warning "Unable to find start/stop events for $eventMachineName processid: $processId, first event: $firstEventTimeCreated, last event: $lastEventTimeCreated.`nCreate time of the first/last event will be used instead"
                    $null = $result.Add(
                        [PSCustomObject]@{
                            ProcessId     = $processId
                            ProcessStart  = $firstEventTimeCreated
                            ProcessEnd    = "<<unknown (such event is not logged for PSH Core)>>"
                            InvokedVia    = "<<unknown (such event is not logged for PSH Core)>>"
                            CommandCount  = $groupedEvent.count
                            # decrypt only if message is really encrypted (encrypting certificate can be missing, encryption could be enabled recently so some events are still not-encrypted)
                            CommandList   = _getCommandText -eventList $groupedEvent
                            UserId        = $groupedEvent.UserId | select -Unique
                            EventList     = $groupedEvent
                            InvokedScript = _getInvokedScript -eventList $groupedEvent
                            SessionType   = "local (probably)" # start event is missing so I am just guessing
                            PSHType       = 'PowerShell Core'
                            MachineName   = $eventMachineName
                        }
                    )
                } elseif (@($processStartStopData).count -eq 1) {
                    # there is just one start/stop event for events with same processid, no need to split
                    $null = $result.Add(
                        [PSCustomObject]@{
                            ProcessId     = $processId
                            ProcessStart  = $processStartStopData.StartTime
                            ProcessEnd    = "<<unknown (such event is not logged for PSH Core)>>"
                            InvokedVia    = "<<unknown (such event is not logged for PSH Core)>>"
                            CommandCount  = $groupedEvent.count
                            CommandList   = _getCommandText -eventList $groupedEvent
                            UserId        = @($groupedEvent.UserId)[0]
                            EventList     = $groupedEvent
                            InvokedScript = _getInvokedScript -eventList $groupedEvent
                            SessionType   = _getSessionType -startEvent $processStartStopData.StartEvent
                            PSHType       = 'PowerShell Core'
                            MachineName   = $eventMachineName
                        }
                    )
                } else {
                    # there are multiple start/stop events for events with same processid
                    $i = 0
                    foreach ($startStopData in $processStartStopData) {
                        Write-Verbose "Splitting events for $eventMachineName processid: $processId"
                        $start = $startStopData.startTime
                        $stop = $startStopData.stopTime
                        if ($stop -eq "<<unknown>>") {
                            if ($processStartStopData[$i + 1]) {
                                # use next round start as this round stop time
                                $stop = ($processStartStopData[$i + 1].startTime).AddMilliseconds(-1)
                                Write-Verbose "`t- unknown process end time, using startime of the next start/stop round"
                            } else {
                                # super future aka get all events till the end
                                $stop = Get-Date -Year 2100
                            }
                        }
                        if ($stop -eq "<<still running>>") {
                            # super future aka get all events till the end
                            $stop = Get-Date -Year 2100
                        }

                        if ($stop -le $startTime) {
                            Write-Verbose "`t- this start/stop ($start - $stop) data are outside of the required scope ($startTime - $endTime), skipping"
                            continue
                        }

                        Write-Verbose "`t- process events created from: $start to: $stop"

                        $eventList = $groupedEvent | ? { $_.TimeCreated -ge $start -and $_.TimeCreated -le $stop }
                        if (!$eventList) {
                            Write-Error "There are no events for processId $processId between found start ($start) and stop ($stop) events. Processed first events are from $firstEventTimeCreated to $lastEventTimeCreated and number of all events is $($groupedEvent.count)). This shouldn't happen and is caused by BUG in the function logic probably!"
                        }

                        $null = $result.Add(
                            [PSCustomObject]@{
                                ProcessId     = $processId
                                ProcessStart  = $startStopData.startTime
                                ProcessEnd    = "<<unknown (such event is not logged for PSH Core)>>"
                                InvokedVia    = "<<unknown (such event is not logged for PSH Core)>>"
                                CommandCount  = $eventList.count
                                CommandList   = _getCommandText -eventList $eventList
                                UserId        = @($eventList.UserId)[0]
                                EventList     = $eventList
                                InvokedScript = _getInvokedScript -eventList $eventList
                                SessionType   = _getSessionType -startEvent $startStopData.startEvent
                                PSHType       = 'PowerShell Core'
                                MachineName   = $eventMachineName
                            })

                        ++$i
                    }
                }
            }
        }
    }
    #endregion get Core PowerShell Script Block logging events

    #region get Windows PowerShell Script Block logging events
    if ($PSHType -contains "WindowsPowerShell") {
        Write-Progress -Activity "Retrieving Windows PowerShell Script Block Logging events"

        $filterHashtable = @{
            id    = 4104
            level = 3, 5 # just warning and verbose events contain invoked commands
        }
        if ($microsoftWindowsPowerShellOperational_LogPath) {
            $filterHashtable.path = $microsoftWindowsPowerShellOperational_LogPath
        } else {
            $filterHashtable.logname = $microsoftWindowsPowerShellOperational_LogName
        }
        if ($startTime) {
            $filterHashtable.startTime = $startTime
        }
        if ($endTime) {
            $filterHashtable.endTime = $endTime
        }

        # ProviderName filtering via Where-Object and not directly in Get-WinEvent, because of error "The specified providers do not write events to the forwardedevents log" in case Forwarded event log is searched
        try {
            $PSHEvent = Get-WinEvent -FilterHashtable $filterHashtable -ErrorAction Stop |
                ? ProviderName -EQ "Microsoft-Windows-PowerShell" |
                ? { if (!$machineName -or ($machineName -and $_.MachineName -in $machineName)) { $_ } }
        } catch {
            if ($_ -like "*No events were found that match the specified selection criteria*") {
                Write-Warning "No Windows PowerShell invocations were found"
            } else {
                throw $_
            }
        }

        if ($PSHEvent) {
            # oldest events first
            [array]::Reverse($PSHEvent)
            # group events
            $PSHEvent = $PSHEvent | Group-Object MachineName, ProcessId

            $i = 0

            # process grouped Windows PowerShell script block logging events
            $PSHEvent | % {
                $eventMachineName = ($_.Name -split ",")[0].trim()
                [int]$processId = ($_.Name -split ",")[1].trim()
                $groupedEvent = $_.Group
                $firstEventTimeCreated = $groupedEvent[0].TimeCreated
                $lastEventTimeCreated = $groupedEvent[-1].TimeCreated

                Write-Progress -Activity "Processing Windows PowerShell Script Block Logging events" -Status "Processing events with processId $processId" -PercentComplete (($i++ / $PSHEvent.count) * 100)

                if ($groupedEvent) {
                    $scriptBlockPart = ([regex]"Creating Scriptblock text \((\d+) of \d+\)").Matches($groupedEvent[0].message).captures.groups[1].value
                    if ($scriptBlockPart -and $scriptBlockPart -ne 1) {
                        Write-Warning "Invoked commands for processid: $processId are trimmed (events were probably overwriten). Commands starts from capture script block number $scriptBlockPart"
                    }
                }

                $processStartStopData = $startStopList | ? { $_.machineName -eq $eventMachineName -and $_.processId -eq $processId -and ($_.StartTime -le $lastEventTimeCreated -and ($_.StopTime -in "<<unknown>>", "<<still running>>" -or $_.StopTime -ge $firstEventTimeCreated)) }

                if (!$processStartStopData) {
                    # context data about start/stop are missing
                    Write-Warning "Unable to find start/stop events for $eventMachineName processid: $processId, first event: $firstEventTimeCreated, last event: $lastEventTimeCreated.`nCreate time of the first/last event will be used instead"
                    $null = $result.Add(
                        [PSCustomObject]@{
                            ProcessId     = $processId
                            ProcessStart  = $firstEventTimeCreated
                            ProcessEnd    = $lastEventTimeCreated
                            InvokedVia    = _getPSHInvokedVia
                            CommandCount  = $groupedEvent.count
                            # decrypt only if message is really encrypted (encrypting certificate can be missing, encryption could be enabled recently so some events are still not-encrypted)
                            CommandList   = _getCommandText -eventList $groupedEvent
                            UserId        = $groupedEvent.UserId | select -Unique
                            EventList     = $groupedEvent
                            InvokedScript = _getInvokedScript -eventList $groupedEvent
                            SessionType   = "local (probably)" # start event is missing so I am just guessing
                            PSHType       = 'Windows PowerShell'
                            MachineName   = $eventMachineName
                        }
                    )
                } elseif (@($processStartStopData).count -eq 1) {
                    # there is just one start/stop event for events with same processid, no need to split
                    $null = $result.Add(
                        [PSCustomObject]@{
                            ProcessId     = $processId
                            ProcessStart  = $processStartStopData.StartTime
                            ProcessEnd    = $processStartStopData.StopTime
                            InvokedVia    = _getPSHInvokedVia -startEvent $processStartStopData.StartEventWithDetails
                            CommandCount  = $groupedEvent.count
                            CommandList   = _getCommandText -eventList $groupedEvent
                            UserId        = @($groupedEvent.UserId)[0]
                            EventList     = $groupedEvent
                            InvokedScript = _getInvokedScript -eventList $groupedEvent
                            SessionType   = _getSessionType -startEvent $processStartStopData.StartEvent
                            PSHType       = 'Windows PowerShell'
                            MachineName   = $eventMachineName
                        }
                    )
                } else {
                    # there are multiple start/stop events for events with same processid
                    $i = 0
                    foreach ($startStopData in $processStartStopData) {
                        Write-Verbose "Splitting events for $eventMachineName processid: $processId"
                        $start = $startStopData.startTime
                        $stop = $startStopData.stopTime
                        if ($stop -eq "<<unknown>>") {
                            if ($processStartStopData[$i + 1]) {
                                # use next round start as this round stop time
                                $stop = ($processStartStopData[$i + 1].startTime).AddMilliseconds(-1)
                                Write-Verbose "`t- unknown process end time, using startime of the next start/stop round"
                            } else {
                                # super future aka get all events till the end
                                $stop = Get-Date -Year 2100
                            }
                        }
                        if ($stop -eq "<<still running>>") {
                            # super future aka get all events till the end
                            $stop = Get-Date -Year 2100
                        }

                        if ($stop -le $startTime) {
                            Write-Verbose "`t- this start/stop ($start - $stop) data are outside of the required scope ($startTime - $endTime), skipping"
                            continue
                        }

                        if ($stop -lt $firstEventTimeCreated) {
                            Write-Verbose "`t- this start/stop ($start - $stop) data misses first event creation time ($firstEventTimeCreated), skipping"
                            continue
                        }

                        Write-Verbose "`t- process events created from: $start to: $stop"

                        $eventList = $groupedEvent | ? { $_.TimeCreated -ge $start -and $_.TimeCreated -le $stop }
                        if (!$eventList) {
                            Write-Error "There are no events for processId $processId between found start ($start) and stop ($stop) events. Processed first events are from $firstEventTimeCreated to $lastEventTimeCreated and number of all events is $($groupedEvent.count)). This shouldn't happen and is caused by BUG in the function logic probably!"
                        }

                        $null = $result.Add(
                            [PSCustomObject]@{
                                ProcessId     = $processId
                                ProcessStart  = $startStopData.startTime
                                ProcessEnd    = $startStopData.stopTime
                                InvokedVia    = _getPSHInvokedVia -startEvent $startStopData.StartEventWithDetails
                                CommandCount  = $eventList.count
                                CommandList   = _getCommandText -eventList $eventList
                                UserId        = @($eventList.UserId)[0]
                                EventList     = $eventList
                                InvokedScript = _getInvokedScript -eventList $eventList
                                SessionType   = _getSessionType -startEvent $startStopData.startEvent
                                PSHType       = 'Windows PowerShell'
                                MachineName   = $eventMachineName
                            }
                        )

                        ++$i
                    }
                }
            }
        }
    }
    #endregion get Windows PowerShell Script Block logging events

    # output the results
    $result | Sort-Object ProcessStart
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

    .PARAMETER scriptFile
    Script that should be run under SYSTEM account.

    .PARAMETER usePSHCore
    Switch for running the code using PowerShell Core instead of Windows PowerShell.

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
    [hashtable]$argument = @{
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

    .PARAMETER PSHCorePath
    Path to PowerShell Core executable you want to use.

    By default Core 7 is used ("$env:ProgramFiles\PowerShell\7\pwsh.exe").

    .EXAMPLE
    Invoke-AsSystem -scriptBlock {New-Item $env:TEMP\abc}

    On local computer will call given scriptblock under SYSTEM account.

    .EXAMPLE
    Invoke-AsSystem -scriptBlock {New-Item "$env:TEMP\$name"} -computerName PC-01 -ReturnTranscript -Argument @{name = 'someFolder'} -Verbose

    On computer PC-01 will call given scriptblock under SYSTEM account i.e. will create folder 'someFolder' in C:\Windows\Temp.
    Transcript will be outputted in console too.

    .EXAMPLE
    Invoke-AsSystem -scriptFile C:\Scripts\dosomestuff.ps1 -ReturnTranscript

    On local computer will run given script under SYSTEM account and return the captured output.

    .EXAMPLE
    Invoke-AsSystem -scriptFile C:\Scripts\dosomestuff.ps1 -ReturnTranscript -usePSHCore

    On local computer will run given script under SYSTEM account using PowerShell Core 7 and return the captured output.
    #>

    [CmdletBinding(DefaultParameterSetName = 'scriptBlock')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "scriptBlock")]
        [scriptblock] $scriptBlock,

        [Parameter(Mandatory = $true, ParameterSetName = "scriptFile")]
        [ValidateScript( {
                if ((Test-Path -Path $_ ) -and $_ -like "*.ps1") {
                    $true
                } else {
                    throw "$_ is not a path to ps1 script file"
                }
            })]
        [string] $scriptFile,

        [switch] $usePSHCore,

        [string] $computerName,

        [switch] $returnTranscript,

        [hashtable] $argument,

        [ValidateSet('SYSTEM', 'NETWORKSERVICE', 'LOCALSERVICE')]
        [string] $runAs = "SYSTEM",

        [switch] $cacheToDisk,

        [ValidateScript( {
                if ((Test-Path -Path $_ ) -and $_ -like "*.exe") {
                    $true
                } else {
                    throw "$_ is not a path to executable"
                }
            })]
        [string] $PSHCorePath
    )

    (Get-Variable runAs).Attributes.Clear()
    $runAs = "NT Authority\$runAs"

    if ($PSHCorePath -and !$usePSHCore) {
        $usePSHCore = $true
    }

    #region prepare Invoke-Command parameters
    # export this function to remote session (so I am not dependant whether it exists there or not)
    $allFunctionDefs = "function Create-VariableTextDefinition { ${function:Create-VariableTextDefinition} }"

    $param = @{
        argumentList = $scriptBlock, $scriptFile, $usePSHCore, $PSHCorePath, $runAs, $cacheToDisk, $allFunctionDefs, $VerbosePreference, $returnTranscript, $argument
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
        param ($scriptBlock, $scriptFile, $usePSHCore, $PSHCorePath, $runAs, $cacheToDisk, $allFunctionDefs, $VerbosePreference, $returnTranscript, $argument)

        foreach ($functionDef in $allFunctionDefs) {
            . ([ScriptBlock]::Create($functionDef))
        }

        $transcriptPath = "$ENV:TEMP\Invoke-AsSYSTEM_$(Get-Random).log"
        $encodedCommand, $temporaryScript = $null

        if ($argument -or $returnTranscript) {
            # define passed variables
            if ($argument) {
                # convert hash to variables text definition
                $variableTextDef = Create-VariableTextDefinition $argument
            }

            if ($returnTranscript) {
                # modify scriptBlock to contain creation of transcript
                $transcriptStart = "Start-Transcript $transcriptPath"
                $transcriptEnd = 'Stop-Transcript'
            }

            if ($scriptBlock) {
                $codeText = $scriptBlock.ToString()
            } else {
                $codeText = Get-Content $scriptFile -Raw
            }

            $scriptBlockContent = ($transcriptStart + "`n`n" + $variableTextDef + "`n`n" + $codeText + "`n`n" + $transcriptEnd)
            Write-Verbose "####### SCRIPTBLOCK TO RUN"
            Write-Verbose $scriptBlockContent
            Write-Verbose "#######"
            $scriptBlock = [Scriptblock]::Create($scriptBlockContent)
        }

        if ($cacheToDisk) {
            $temporaryScript = "$env:temp\$(New-Guid).ps1"
            $null = New-Item $temporaryScript -Value $scriptBlock -Force
            $pshCommand = "-ExecutionPolicy Bypass -Window Hidden -noprofile -file `"$temporaryScript`""
        } else {
            $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($scriptBlock))
            $pshCommand = "-ExecutionPolicy Bypass -Window Hidden -noprofile -EncodedCommand $($encodedCommand)"
        }

        if ($encodedCommand) {
            $OSLevel = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentVersion

            if ($OSLevel -lt 6.2) { $maxLength = 8190 } else { $maxLength = 32767 }

            if ($encodedCommand.length -gt $maxLength -and $cacheToDisk -eq $false) {
                throw "The encoded script is longer than the command line parameter limit. Please execute the script with the -CacheToDisk option."
            }
        }

        try {
            #region create&run sched. task
            if ($usePSHCore) {
                if ($PSHCorePath) {
                    $pshPath = $PSHCorePath
                } else {
                    $pshPath = "$env:ProgramFiles\PowerShell\7\pwsh.exe"

                    if (!(Test-Path $pshPath -ErrorAction SilentlyContinue)) {
                        throw "PSH Core isn't installed at '$pshPath' use 'PSHCorePath' parameter to specify correct path"
                    }
                }
            } else {
                $pshPath = "$($env:windir)\system32\WindowsPowerShell\v1.0\powershell.exe"
            }

            $taskAction = New-ScheduledTaskAction -Execute $pshPath -Argument $pshCommand

            if ($runAs -match "\$") {
                # run as gMSA account
                $taskPrincipal = New-ScheduledTaskPrincipal -UserId $runAs -LogonType Password
            } else {
                # run as system account
                $taskPrincipal = New-ScheduledTaskPrincipal -UserId $runAs -LogonType ServiceAccount
            }

            $taskSetting = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -DontStopOnIdleEnd

            $taskName = "RunAsSystem_" + (Get-Random)

            try {
                $null = New-ScheduledTask -Action $taskAction -Principal $taskPrincipal -Settings $taskSetting -ErrorAction Stop | Register-ScheduledTask -Force -TaskName $taskName -ErrorAction Stop
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
            if ($returnTranscript) {
                # return just interesting part of transcript
                if (Test-Path $transcriptPath) {
                    $transcriptContent = (Get-Content $transcriptPath -Raw) -Split [regex]::escape('**********************')
                    # return command output
                    ($transcriptContent[2] -split "`n" | Select-Object -Skip 2 | Select-Object -SkipLast 3) -join "`n"

                    Remove-Item $transcriptPath -Force
                } else {
                    Write-Warning "There is no transcript, command probably failed!"
                }
            }

            if ($temporaryScript) { $null = Remove-Item $temporaryScript -Force }

            try {
                Unregister-ScheduledTask $taskName -Confirm:$false -ErrorAction Stop
            } catch {
                throw "Unable to unregister sched. task $taskName. Please remove it manually"
            }

            if ($result -ne 0) {
                throw "Command wasn't successfully ended ($result)"
            }
            #endregion create&run sched. task
        } catch {
            throw $_.Exception
        } finally {
            Unregister-ScheduledTask $taskName -Confirm:$false -ErrorAction SilentlyContinue
            if ($temporaryScript) { $null = Remove-Item $temporaryScript -Force -ErrorAction SilentlyContinue }
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

    It uses an official LAPS module for getting LAPS password and AutoItx PowerShell module for automatic filling of credentials into mstsc.exe app for RDP, in case LAPS password wasn't retrieved or domain account is used for connection instead of local admin one.

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

    Run remote connection to pc1 using <domain>\<username> domain account.

    .EXAMPLE
    $credentials = Get-Credential
    Invoke-MSTSC pc1 -credential $credentials

    Run remote connection to pc1 using credentials stored in $credentials

    .NOTES
    Automatic filling is working only on english operating systems.
    Author: Ondřej Šebela - ztrhgf@seznam.cz

    Requires builtin Windows LAPS module.
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
                $domainNetbiosName = (Get-CimInstance Win32_NTDomain).DomainName # slow but gets the correct value
            }
        }
        Write-Verbose "Get domain name"
        if (!$domainName) {
            $domainName = (Get-CimInstance Win32_ComputerSystem).Domain
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
                $password = Get-LapsADPassword -Identity $computerName -AsPlainText | select -ExpandProperty Password

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
                $ProcessInfo.RedirectStandardOutput = ".\NUL"
                $ProcessInfo.UseShellExecute = $false
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

                try {
                    $null = Get-Command Get-AU3WinHandle -ErrorAction Stop
                } catch {
                    try {
                        if ($PSVersionTable.PSEdition -eq "Core") {
                            $null = Import-Module AutoItX -SkipEditionCheck -ErrorAction Stop -Verbose:$false
                        } else {
                            $null = Import-Module AutoItX -ErrorAction Stop -Verbose:$false
                        }
                    } catch {
                        throw "Module AutoItX isn't available"
                    }
                }

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
                $ProcessInfo.UseShellExecute = $false
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
                        if ($PSVersionTable.PSEdition -eq "Core") {
                            $null = Import-Module AutoItX -SkipEditionCheck -ErrorAction Stop -Verbose:$false
                        } else {
                            $null = Import-Module AutoItX -ErrorAction Stop -Verbose:$false
                        }
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

function Invoke-RestMethod2 {
    <#
    .SYNOPSIS
    Proxy function for Invoke-RestMethod.

    Adds support for:
     - pagination (by detecting '@odata.nextLink')
     - throttling (by adding sleep time before giving another try)

    .DESCRIPTION
    Proxy function for Invoke-RestMethod.

    Adds support for:
     - pagination (by detecting '@odata.nextLink')
     - throttling (by adding sleep time before giving another try)

    .PARAMETER uri
    URL.

    .PARAMETER method
    Request method.

    Possible values: GET, POST, PATCH, PUT, DELETE

    By default GET.

    .PARAMETER headers
    Authentication header etc.

    .PARAMETER body
    Request body.

    .PARAMETER waitTime
    Number of seconds to wait if error "too many requests" is detected.

    By default 30.

    .EXAMPLE
    $header = New-M365DefenderAuthHeader

    $url = "https://api-eu.securitycenter.microsoft.com/api/vulnerabilities/machinesVulnerabilities"

    Invoke-RestMethod2 -uri $url -headers $header
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $uri,

        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [string] $method = "GET",

        $headers,

        $body,

        [ValidateRange(1, 999)]
        [int] $waitTime = 30
    )

    function _result {
        param ($response)

        if ($response | Get-Member -MemberType NoteProperty | select -ExpandProperty name | ? { $_ -notin '@odata.context', '@odata.nextLink', '@odata.count', 'Value', 'nextlink' }) {
            # only one item was returned, no expand is needed
            $response
        } else {
            # its more than one result, I need to expand the Value property
            $response.Value
        }
    }

    $uriLink = $uri
    $responseObj = $null

    do {
        try {
            Write-Verbose $uriLink

            $param = @{
                ErrorAction = 'Stop'
                Method      = $method
                Uri         = $uriLink
            }
            if ($headers) {
                $param.Headers = $headers
            }
            if ($body) {
                $param.Body = $body
            }
            $responseObj = Invoke-RestMethod @param

            _result $responseObj

            # loop through '@odata.nextLink' to get all results
            if ($responseObj.'@odata.nextLink') {
                # MS Graph Api uses '@odata.nextLink' property
                $uriLink = $responseObj.'@odata.nextLink'
            } elseif ($responseObj.nextLink) {
                # Azure Automation Api uses 'nextlink' property
                $uriLink = $responseObj.nextLink
            } else {
                $uriLink = $null
            }
        } catch {
            switch ($_) {
                #TODO https://learn.microsoft.com/en-us/defender-endpoint/api/common-errors?view=o365-worldwide#throttling tzn vycitat sleep z Retry-After
                { $_ -like "*Too Many Requests*" -or $_ -like "*TooManyRequests*" } {
                    Write-Warning "Too Many Requests. Waiting $waitTime seconds to avoid further throttling before trying again"
                    Start-Sleep $waitTime
                }

                { $_ -like "*Gateway Time-out*" } {
                    Write-Warning "Gateway Time-out. Waiting $waitTime seconds before trying again"
                    Start-Sleep $waitTime
                }

                { $_ -like "*(400)*" } { throw "(400) Bad Request. There has to be some syntax/logic mistake in this request ($uri)" }

                { $_ -like "*(401)*" } { throw "(401) Unauthorized Request (new auth header has to be created?)" }

                { $_ -like "*(408)*" } {
                    Write-Warning "(408) Request Time-out. Waiting $waitTime seconds before trying again"
                    Start-Sleep $waitTime
                }

                { $_ -like "*Forbidden*" } { throw "Forbidden access. Use account with correct API permissions for this request ($uri)" }

                default {
                    Write-Error $_
                    # break the loop (break command wasn't working)
                    $uriLink = $null
                }
            }
        }
    } while ($uriLink)
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
    Invoke-SQL -dataSource "admin-test2\SOLARWINDS_ORION" -database "SolarWindsOrion" -sqlCommand "SELECT * FROM pollers"

    On "admin-test2\SOLARWINDS_ORION" server\instance in SolarWindsOrion database runs selected command.

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

function New-BasicAuthHeader {
    <#
    .SYNOPSIS
    Function returns basic authentication header that can be used for web requests.

    .DESCRIPTION
    Function returns basic authentication header that can be used for web requests.

    .PARAMETER credential
    Credentials object that will be used to create auth. header.

    .EXAMPLE
    $header = New-BasicAuthHeader -credential (Get-Credential)
    $response = Invoke-RestMethod -Uri "https://example.com/api" -Headers $header
    #>

    [CmdletBinding()]
    [Alias("Create-BasicAuthHeader")]
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential] $credential
    )

    @{
        "Authorization" = "Basic " + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($Credential.UserName + ":" + [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($Credential.Password)) )))
    }
}

function Publish-Module2 {
    <#
    .SYNOPSIS
    Proxy function for original Publish-Module that fixes error: "Test-ModuleManifest : The specified RequiredModules entry 'xxx' In the module manifest 'xxx.psd1' is invalid. Try again after updating this entry with valid values" by creating temporary dummy modules for the missing ones that causes this error.

    .DESCRIPTION
    Proxy function for original Publish-Module that fixes error: "Test-ModuleManifest : The specified RequiredModules entry 'xxx' In the module manifest 'xxx.psd1' is invalid. Try again after updating this entry with valid values" by creating temporary dummy modules for the missing ones that causes this error.

    The thing is that Test-ModuleManifest that is called behind the scenes checks that each required module defined in published module manifest exists in $env:PSModulePath and if not, throws an error.

    .PARAMETER path
    Path to the module directory.

    .PARAMETER nugetApiKey
    Your nugetApiKey for PowerShell gallery.

    .EXAMPLE
    Publish-Module2 -Path "C:\repo\useful_powershell_modules\IntuneStuff" -NuGetApiKey oyjidshdnsdksjkdsqz2al4bu3ihkevj2qmxu3ksflmy -Verbose

    Creates dummy modules for each required module defined in IntuneStuff manifest file that is missing, then calls original Publish-Module and returns environment to the default state again.

    #>

    [CmdletBinding()]
    param (
        [string] $path,

        [string] $nugetApiKey
    )

    $manifestFile = (Get-ChildItem (Join-Path $path "*.psd1") -File).FullName

    if ($manifestFile) {
        if ($manifestFile.count -eq 1) {
            try {
                Write-Verbose "Processing '$manifestFile' manifest file"
                $manifestDataHash = Import-PowerShellDataFile $manifestFile -ErrorAction Stop
            } catch {
                Write-Error "Unable to process manifest file '$manifestFile'.`n`n$_"
            }

            if ($manifestDataHash) {
                # fix for Microsoft.PowerShell.Core\Test-ModuleManifest : The specified RequiredModules entry 'xxx' In the module manifest 'xxx.psd1' is invalid. Try again after updating this entry with valid values.
                # because every required module defined in the manifest file have to be in local available module list
                # so I temporarily create dummy one if necessary
                if ($manifestDataHash.RequiredModules) {
                    # make a backup of $env:PSModulePath
                    $bkpPSModulePath = $env:PSModulePath

                    $tempModulePath = Join-Path $env:TEMP (Get-Random)
                    # add temp module folder
                    $env:PSModulePath = "$env:PSModulePath;$tempModulePath"

                    $manifestDataHash.RequiredModules | % {
                        if ($_.gettype().Name -eq "String") {
                            # just module name
                            $mName = $_
                        } else {
                            # module name and version
                            $mName = $_.ModuleName
                        }

                        if (!(Get-Module $mName -ListAvailable)) {
                            Write-Warning "Generating temporary dummy required module $mName. It's mentioned in manifest file but missing from this PC available modules list"
                            [Void][System.IO.Directory]::CreateDirectory("$tempModulePath\$mName")
                            'function dummy {}' > "$tempModulePath\$mName\$mName.psm1"
                        }
                    }
                }
            }
        } else {
            Write-Warning "Module manifest file won't be processed because more then one were found."
        }
    } else {
        Write-Verbose "No module manifest file found"
    }

    try {
        Publish-Module -Path $path -NuGetApiKey $nugetApiKey
    } catch {
        throw $_
    } finally {
        if ($bkpPSModulePath) {
            # restore $env:PSModulePath from the backup
            $env:PSModulePath = $bkpPSModulePath
        }
        if ($tempModulePath -and (Test-Path $tempModulePath)) {
            Write-Verbose "Removing temporary folder '$tempModulePath'"
            Remove-Item $tempModulePath -Recurse -Force
        }
    }
}

function Quote-String {
    <#
    .SYNOPSIS
    Function for splitting given text by delimiter and enclosing the resulting items into quotation marks.

    .DESCRIPTION
    Function for splitting given text by delimiter and enclosing the resulting items into quotation marks.

    Input can be taken from pipeline, parameter or clipboard.

    Result can be returned into console or clipboard. Can be returned joined (as string) or as array.

    .PARAMETER string
    Optional parameter.
    String(s) that should be split and enclosed by quotation marks.

    If none is provided, clipboard content is used.

    .PARAMETER delimiter
    Delimiter value.

    Default is ','.

    .PARAMETER joinUsing
    String that will be used to join the resultant items.

    Default is value in 'delimiter' parameter.

    .PARAMETER outputToConsole
    Switch for outputting result to the console instead of clipboard.

    .PARAMETER dontJoin
    Switch for omitting final join operation.
    When 'outputToConsole' is used, you will get array.
    When 'outputToConsole' is NOT used, clipboard will contain string with quoted item per line.

    .PARAMETER quoteBy
    String that will be used to enclose resultant items.

    Default is '.

    .EXAMPLE
    Quote-String -string "John, Amy"

    Result (saved into clipboard) will be quoted strings joined by comma: 'John', 'Amy'

    .EXAMPLE
    (image that clipboard contains string "John, Amy")

    Quote-String

    Result (saved into clipboard) will be quoted strings joined by comma: 'John', 'Amy'

    .EXAMPLE
    Quote-String -string "John, Amy" -outputToConsole -joinUsing ";"

    Result (in console) will be quoted strings joined by semicolon:
    'John';'Amy'

    .EXAMPLE
    "John", "Amy" | Quote-String -outputToConsole -dontJoin

    Result (in console) will be array containing quoted strings:
    'John'
    'Amy'
    #>

    [CmdletBinding()]
    [Alias("ConvertTo-QuotedString")]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [string[]] $string,

        [string] $delimiter = ",",

        [string] $joinUsing,

        [switch] $outputToConsole,

        [switch] $dontJoin,

        [string] $quoteBy = "'"
    )

    if (!$joinUsing -and !$dontJoin) {
        $joinUsing = $delimiter
    }

    # I need to take pipeline input as a whole (because of final save into clipboard)
    if ($Input) {
        Write-Verbose "Using automatic variable 'Input' content"
        $string = $Input
    }

    if (!$string) {
        Write-Verbose "Using clipboard content"
        $string = Get-Clipboard -Raw
    }
    if (!$string) {
        throw "'String' parameter and even clipboard are empty."
    }

    Write-Verbose "'String' parameter contains:`n$string"

    if ($delimiter -eq "`n") {
        # sometimes `n generates weird results, because `r`n is needed
        $result = $string.Split([Environment]::NewLine, [StringSplitOptions]::RemoveEmptyEntries)
    } else {
        $result = $string.Split($delimiter, [StringSplitOptions]::RemoveEmptyEntries)
    }
    $result = $result | % {
        $quoteBy + $_.trim() + $quoteBy
    }

    if ($outputToConsole) {
        if ($joinUsing) {
            $result -join $joinUsing
        } else {
            $result
        }
    } else {
        Write-Warning "Result was copied to clipboard"
        if ($joinUsing) {
            Set-Clipboard ($result -join $joinUsing)
        } else {
            Set-Clipboard $result
        }
    }
}

function Read-FromClipboard {
    <#
    .SYNOPSIS
    Read text from clipboard and tries to convert it to OBJECT.

    .DESCRIPTION
    Read text from clipboard and tries to convert it to OBJECT.

    At first it tries to convert clipboard data as XML, then JSON and as a last resort as a CSV (delimited text).

    Content is trimmed! Because text can be indent etc.

    .PARAMETER delimiter
    Default is '`t' i.e. TABULATOR.

    If delimiter wont be found in header, you will be asked to provide the correct one.

    .PARAMETER headerCount
    Number of header columns.

    Can be used if processed content doesn't contain header itself and you don't want to specify header names.

    Will create numbered header columns starting from 1.
    In case you specify 'header' parameter too but count of such headers will be lesser than 'headerCount', missing headers will be numbers.
    - So for: -header name, age -headerCount 5
      Resultant header will be: name, age, 3, 4, 5

    In case you use -headerCount 1, the result will be array of items instead of object with one property ('1').

    .PARAMETER header
    List of column names that will be set.

    Use if clipboard content doesn't contain header on its own. Or if you want to replace clipboards content header with your own, but in such case don't forget to use skipFirstLine parameter!

    .PARAMETER skipFirstLine
    Switch for skipping first clipboard content line.

    When combined with 'header' parameter, original header names can be replaced with your own custom ones.

    .PARAMETER regexDelimiter
    Switch for letting function know that used delimiter is regex.

    .EXAMPLE
    Clipboard contains:
    name, age, city
    Carl, 14, Prague
    John, 30, Boston

    You run:
    Read-FromClipboard -delimiter ","

    You get:
    name  age  city
    ---- ---- -----
    Carl  14   Prague
    John  30   Boston

    .EXAMPLE
    Clipboard contains:
    string, number, string
    Carl, 14, Prague
    John, 30, Boston

    You run:
    Read-FromClipboard -delimiter "," -skipFirstLine -header name, age, city

    You get:
    name  age  city
    ---- ---- -----
    Carl  14   Prague
    John  30   Boston

    I.e. you have object with replaced original header names.

    .EXAMPLE
    Clipboard contains:
    N4-01-NTB
    NG-06-NTB
    NG-07-NTB
    NG-18-NTB
    NG-30-NTB

    You run:
    Read-FromClipboard -headerCount 1

    You get:
    array of strings

    .EXAMPLE
    Clipboard contains:
    2002      89   144588      62016   1 893,42  33732   1 EXCEL
    5207     195   286136     109264  10 376,50  29220   1 explorer
    426    19     6552      10560      43,13  23356  20 1 FileCoAuth

    You run:
    Read-FromClipboard -delimiter "\s+" -regexDelimiter -headerCount 9 | Format-Table

    You get:
    1    2   3      4      5     6      7     8          9
    -    -   -      -      -     -      -     -          -
    2002 89  144588 62016  1     893,42 33732 1          EXCEL
    5207 195 286136 109264 10    376,50 29220 1          explorer
    426  19  6552   10560  43,13 23356  20    1          FileCoAuth

    .EXAMPLE
    Clipboard contains:
    2002      89   144588      62016   1 893,42  33732   1 EXCEL
    5207     195   286136     109264  10 376,50  29220   1 explorer
    426      19     6552      10560      43,13  23356   1 FileCoAuth

    You run:
    Read-FromClipboard -delimiter "\s+" -regexDelimiter -header handles, npm, pm, ws, cpu, id -headerCount 9 | Format-Table

    You get:
    handles npm pm     ws     cpu   id     7     8          9
    ------- --- --     --     ---   --     -     -          -
    2002    89  144588 62016  1     893,42 33732 1          EXCEL
    5207    195 286136 109264 10    376,50 29220 1          explorer
    426     19  6552   10560  43,13 23356  1     FileCoAuth

    .NOTES
    Inspired by Read-Clipboard from https://www.powershellgallery.com/packages/ImportExcel.
    #>

    [CmdletBinding()]
    [Alias("ConvertFrom-Clipboard")]
    param (
        $delimiter = "`t",

        [ValidateRange(1, 999)]
        [int] $headerCount,

        [string[]] $header,

        [switch] $skipFirstLine,

        [switch] $regexDelimiter
    )

    # get clipboard as a text
    $data = Get-Clipboard -Raw

    if (!$data) { return }

    if ($regexDelimiter) {
        try {
            $regex = New-Object Regex $regexDelimiter -ErrorAction Stop
        } catch {
            throw "'$regexDelimiter' isn't valid regex"
        }
    }

    #region helper functions
    function _delimiter {
        param ($d)

        if (!$regexDelimiter) {
            if ($d -match "^\s+$") {
                # bug? [regex]::escape() transform space to \
                $d
            } else {
                [regex]::escape($d)
            }
        } else {
            $d
        }
    }

    function _readableDelimiter {
        param ($d)

        if ($regexDelimiter) {
            return "`"$d`""
        }

        switch ($d) {
            "`n" { '"`n"' }
            "`t" { '"`t"' }
            default { "`"$d`"" }
        }
    }
    #endregion helper functions

    # add numbers instead of missing headers column names
    if ($headerCount -and $headerCount -gt $header.count) {
        [int]($header.count + 1)..$headerCount | % {
            Write-Verbose "$_ was added instead of missing column name"
            $header += $_
        }
    }

    #region consider data as XML
    try {
        [xml]$data
        return
    } catch {
        Write-Verbose "It isn't XML"
    }
    #endregion consider data as XML

    #region consider data as JSON
    try {
        # at first try convert clipboard text as a JSON
        ConvertFrom-Json $data -ErrorAction Stop
        return
    } catch {
        Write-Verbose "It isn't JSON"
    }
    #endregion consider data as JSON

    #region consider data as CSV
    # split content line by line
    $data = $data.Split([Environment]::NewLine) | ? { $_ }

    if ($skipFirstLine) {
        Write-Verbose "Skipping first line of clipboard data ($($data[0]))"
        $data = $data | select -Skip 1
    }

    $firstLine = $data[0]

    $substringIndex = 20
    if ($firstLine.length -lt $substringIndex) { $substringIndex = $firstLine.length }

    # get correct delimiter
    if ($headerCount -ne 1) {
        while ($firstLine -notmatch (_delimiter $delimiter)) {
            $delimiter = Read-Host "Delimiter $(_readableDelimiter $delimiter) isn't used in clipboard text ($($firstLine.substring(0, $substringIndex))...). What delimiter should be used?"

            $delimiter = _delimiter $delimiter
        }
    } else {
        # only one property should be returned i.e. I will return array of strings instead of object with one property
        # and therefore none delimiter is needed
    }

    if (!$header) {
        # fix case when first line (header) ends with delimiter
        if ($firstLine[-1] -match (_delimiter $delimiter)) {
            $firstLine = $firstLine -replace ((_delimiter $delimiter) + "$")
        }

        # get header from first line of the clipboard text
        $header = $firstLine.trim() -split (_delimiter $delimiter)
        Write-Verbose "Header is $($header -join ', ') (count $($header.count))"
        # the rest of the lines is actual content
        $dataContent = $data.trim() | select -Skip 1
    } else {
        # I have header, so even first line of the clipboard text is content
        $dataContent = $data.trim()
    }

    $dataContent | % {
        $row = $_
        Write-Verbose "Processing row $row"
        # prepare empty object
        $property = [Ordered]@{}
        $header | % {
            Write-Verbose "Adding property $_"
            $property.$_ = $null
        }
        $object = New-Object -TypeName PSObject -Property $property

        # fill object properties
        $i = 0
        $row -split (_delimiter $delimiter) | % {
            if (($i + 1) -gt $header.count) {
                # number of splitted values is greater than number of columns in header
                # remaining values will be added to the last column
                $key = $header[($header.count - 1)]
                $object.$key += (_delimiter $delimiter) + $_
            } else {
                $key = $header[$i]
                $object.$key = $_
            }
            ++$i
        }

        if ($headerCount -eq 1) {
            # return objects property content (string) instead of object itself
            $object.1
        } else {
            # return object
            $object
        }
    }
    #endregion consider data as CSV
}

function Send-EmailViaSendGrid {
    <#
    .SYNOPSIS
    Function for sending email using SendGrid service.

    .DESCRIPTION
    Function for sending email using SendGrid service.

    Supports retrieval of the api token from Azure Keyvault or from given credentials object.

    .PARAMETER to
    Email address(es) of recipient(s).

    .PARAMETER subject
    Email subject.

    .PARAMETER body
    Email body.

    .PARAMETER asHTML
    Switch for sending email body as HTML instead of plaintext.

    .PARAMETER from
    Sender email address.

    .PARAMETER credentials
    PSCredential object that contains SendGrid authentication token in the password field.

    If not provided, token will be retrieved from Azure vault if possible.

    .EXAMPLE
    $cr = Get-Credential -UserName "whatever" -Message "Enter SendGrid token to the password field"

    $param = @{
        to = 'johnd@contoso.com'
        from = 'marie@contoso.com'
        subject = 'greetings'
        body = "Hi,`nhow are you?"
        credentials = $cr
    }
    Send-EmailViaSendGrid @param

    Will send plaintext email using given token to johnd@contoso.com.

    .EXAMPLE
    Connect-AzAccount

    $param = @{
        to = 'johnd@contoso.com'
        from = 'marie@contoso.com'
        subject = 'greetings'
        body = 'Hi,<br>how are you?'
        asHTML = $true
        vaultSubscription = 'production'
        vaultName = 'secrets'
        secretName = 'sendgrid'
    }
    Send-EmailViaSendGrid @param

    Will send HTML email (using token retrieved from Azure Keyvault) to johnd@contoso.com.
    To be able to automatically retrieve token from Azure Vault, you have to be authenticated (Connect-AzAccount).
#>

[CmdletBinding(DefaultParameterSetName = 'credentials')]
    param (
        [ValidateScript( {
            if ($_ -like "*@*") {
                $true
            } else {
                throw "$_ is not a valid email address (johnd@contoso.com)"
            }
        })]
        [string[]] $to = $_sendTo,

        [Parameter(Mandatory = $true)]
        [string] $subject,

        [Parameter(Mandatory = $true)]
        [string] $body,

        [switch] $asHTML,

        [ValidateScript( {
            if ($_ -like "*@*") {
                $true
            } else {
                throw "$_ is not a valid email address (johnd@contoso.com)"
            }
        })]
        [string] $from = $_sendFrom,

        [Parameter(Mandatory = $true, ParameterSetName = "credentials")] 
        [System.Management.Automation.PSCredential] $credentials,

        [Parameter(Mandatory = $false, ParameterSetName = "keyvault")] 
        [string] $vaultSubscription = $_vaultSubscription,

        [Parameter(Mandatory = $false, ParameterSetName = "keyvault")] 
        [string] $vaultName = $_vaultName,

        [Parameter(Mandatory = $false, ParameterSetName = "keyvault")] 
        [string] $secretName = $_secretName
    )

    #region checks
    if (!(Get-Command Send-PSSendGridMail -ea SilentlyContinue)) {
        throw "Command Send-PSSendGridMail is missing (part of module PSSendGrid)"
    }

    if (!$to) {
        throw "$($MyInvocation.MyCommand) has to have 'to' parameter defined"
    }
    if (!$from) {
        throw "$($MyInvocation.MyCommand) has to have 'from' parameter defined"
    }

    if ($credentials -and !($credentials.GetNetworkCredential().password)) {
            throw "Credentials doesn't contain password"
    } elseif (!$credentials) {
        if (!$vaultSubscription) {
            throw "$($MyInvocation.MyCommand) has to have 'vaultSubscription' parameter defined"
        }
        if (!$vaultName) {
            throw "$($MyInvocation.MyCommand) has to have 'vaultName' parameter defined"
        }
        if (!$secretName) {
            throw "$($MyInvocation.MyCommand) has to have 'secretName' parameter defined"
        } 
    }
    #endregion checks

    #region retrieve token
    if (!$credentials) {
        try {
            $currentSubscription = (Get-AzContext).Subscription.Name
            if ($currentSubscription -ne $vaultSubscription) {
                Write-Verbose "Switching subscription to $vaultSubscription"
                $null = Select-AzSubscription $vaultSubscription
            }

            Write-Verbose "Retrieving sendgrid token (vault: $vaultName, secret: $secretName)"
            $token = Get-AzKeyVaultSecret -VaultName $vaultName -Name $secretName -AsPlainText -ErrorAction Stop

            Write-Verbose "Switching subscription back to $currentSubscription"
            $null = Select-AzSubscription $currentSubscription
        } catch {
            if ($_ -match "Run Connect-AzAccount to login") {
                throw "Unable to obtain sendgrid token from Azure Vault, because you are not authenticated. Use Connect-AzAccount to fix this"
            } else {
                throw "Unable to obtain sendgrid token from Azure Vault.`n`n$_"
            }
        }
    } else {
        $token = $credentials.GetNetworkCredential().password
        if (!$token) {
            throw "Token parameter doesn't contain token"
        }
    }
    #endregion retrieve token

    $param = @{
        FromAddress = $from
        ToAddress   = $to
        Subject     = $subject
        Token       = $token
    }
    if ($asHTML) {
        $param.BodyAsHTML = $body
    } else {
        $param.Body = $body
    }

    Write-Verbose "Sending email"
    Send-PSSendGridMail @param
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

Export-ModuleMember -function Compare-Object2, ConvertFrom-CompressedString, ConvertFrom-EncryptedString, ConvertFrom-HTMLTable, ConvertFrom-XML, ConvertTo-CompressedString, ConvertTo-EncryptedString, Expand-ObjectProperty, Export-ScriptsToModule, Get-InstalledSoftware, Get-PSHScriptBlockLoggingEvent, Get-SFCLogEvent, Invoke-AsLoggedUser, Invoke-AsSystem, Invoke-FileContentWatcher, Invoke-FileSystemWatcher, Invoke-MSTSC, Invoke-RestMethod2, Invoke-SQL, Invoke-WindowsUpdate, New-BasicAuthHeader, Publish-Module2, Quote-String, Read-FromClipboard, Send-EmailViaSendGrid, Uninstall-ApplicationViaUninstallString

Export-ModuleMember -alias ConvertFrom-Clipboard, ConvertTo-QuotedString, Create-BasicAuthHeader, Install-WindowsUpdate, Invoke-WU, rdp, Watch-FileContent, Watch-FileSystem
