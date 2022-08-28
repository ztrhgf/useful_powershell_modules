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
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]] $name,

        [string] $addArgument
    )

    # without admin rights msiexec uninstall fails without any error
    if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        throw "Run with administrator rights"
    }

    if (!(Get-Command Get-InstalledSoftware)) {
        throw "Function Get-InstalledSoftware is missing"
    }

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
                Write-Warning "Uninstalling app '$name'"
                Write-Verbose "Uninstall command is: msiexec.exe $uninstallMSIArgument"
                Start-Process "msiexec.exe" -ArgumentList $uninstallMSIArgument -Wait
            } else {
                # it is EXE
                # add silent and norestart switches
                $match = ([regex]'("[^"]+")(.*)').Matches($uninstallCommand)
                $uninstallExe = $match.captures.groups[1].value
                if (!$uninstallExe) {
                    Write-Error "Unable to extract EXE path from '$uninstallCommand'"
                    continue
                }
                $uninstallExeArgument = $match.captures.groups[2].value
                if ($addArgument) {
                    $uninstallExeArgument = $uninstallExeArgument + " " + $addArgument
                }
                Write-Warning "Uninstalling app '$name'"
                Write-Verbose "Uninstall command is: $uninstallCommand"

                $param = @{
                    FilePath = $uninstallExe
                    Wait     = $true
                }
                if ($uninstallExeArgument) {
                    $param.ArgumentList = $uninstallExeArgument
                }
                Start-Process @param
            }
        }
    } else {
        Write-Warning "No software with name $($name -join ', ') was found. Get the correct name by running 'Get-InstalledSoftware' function."
    }
}

Export-ModuleMember -function ConvertFrom-XML, Export-ScriptsToModule, Get-InstalledSoftware, Invoke-AsLoggedUser, Invoke-AsSystem, Invoke-SQL, Uninstall-ApplicationViaUninstallString

