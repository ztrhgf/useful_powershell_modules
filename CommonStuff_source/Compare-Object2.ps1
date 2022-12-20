#FIXME nefunguje pro porovnani hashtable
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
        [ValidateNotNullOrEmpty()]
        $input1
        ,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
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