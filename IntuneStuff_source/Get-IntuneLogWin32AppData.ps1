function Get-IntuneLogWin32AppData {
    <#
    .SYNOPSIS
    Function for getting Intune Win32Apps information from clients log files ($env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension*.log).

    .DESCRIPTION
    Function for getting Intune Win32Apps information from clients log files ($env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension*.log).

    Finds data about processing of Win32Apps and outputs them into console as an PowerShell object.

    Returns various information like app requirements, install/uninstall command, detection and requirement scripts etc.

    .PARAMETER allOccurrences
    Switch for getting all Win32App processings.
    By default just newest processing is returned from the newest Intune log.

    .PARAMETER excludeProperty
    List of properties to exclude.

    By default: 'Intent', 'TargetType', 'ToastState', 'Targeted', 'MetadataVersion', 'RelationVersion', 'DOPriority', 'SupportState', 'InstallContext', 'InstallerData'

    Reason for exclude is readability and the fact that I didn't find any documentation that would help me interpret their values.

    .EXAMPLE
    $win32AppData = Get-IntuneLogWin32AppData

    $myApp = ($win32AppData | ? Name -eq 'MyApp')

    "Output complete object"
    $myApp

    "Detection script content for application 'MyApp'"
    $myApp.DetectionRule.DetectionText.ScriptBody

    "Requirement script content for application 'MyApp'"
    $myApp.RequirementRulesExtended.RequirementText.ScriptBody

    "Installation script content for application 'MyApp'"
    $myApp.InstallCommandLine

    Show various interesting information for MyApp application deployment.

    .NOTES
    Run on Windows client managed using Intune MDM.
    #>

    [CmdletBinding()]
    param (
        [switch] $allOccurrences,

        [string[]] $excludeProperty = ('Intent', 'TargetType', 'ToastState', 'Targeted', 'MetadataVersion', 'RelationVersion', 'DOPriority', 'SupportState', 'InstallContext', 'InstallerData')
    )

    #region helper functions
    function ConvertFrom-Base64 {
        param ($encodedString)
        [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($encodedString))
    }

    # transforms default JSON object into more readable one
    function _enhanceObject {
        param ($object, $excludeProperty)

        #region helper functions
        function _ruleSubType {
            param ($type, $subType, $value)

            switch ($type) {
                'File' {
                    switch ($subType) {
                        1 { "File or folder exist" }
                        2 { "Date Modified" }
                        3 { "Date Created" }
                        4 { "File version" }
                        5 { "Size in MB" }
                        6 { "File or folder does not exist" }
                        default { $subType }
                    }
                }

                'Registry' {
                    switch ($subType) {
                        1 { if ($value) { "Value exists" } else { "Key exists" } }
                        2 { if ($value) { "Value does not exist" } else { "Key does not exist" } }
                        3 { "String comparison" }
                        4 { "Integer comparison" }
                        5 { "Version comparison" }
                        default { $subType }
                    }
                }

                'Script' {
                    switch ($subType) {
                        1 { "String" }
                        2 { "Date and Time" }
                        3 { "Integer" }
                        4 { "Floating Point" }
                        5 { "Version" }
                        6 { "Boolean" }
                        default { $subType }
                    }
                }

                default {
                    Write-Warning "Undefined operator type $type"
                    $subType
                }
            }
        }

        function _operator {
            param ($operator)

            switch ($operator) {
                0 { "Does not exist" }
                1 { "Equals" }
                2 { "Not equal to" }
                4 { "Greater than" }
                5 { "Greater than or equal" }
                8 { "Less than" }
                9 { "Less than or equal" }
                default { $operator }
            }
        }

        function _detectionRule {
            param ($detectionRules)

            function _detectionType {
                param ($detectionType)

                switch ($detectionType) {
                    0 { "Registry" }
                    1 { "MSI" }
                    2 { "File" }
                    3 { "Script" }
                    default { $detectionType }
                }
            }

            $detectionRules = $detectionRules | ConvertFrom-Json

            # enhance the object properties
            $detectionRules | % {
                $detectionRule = $_

                $type = _detectionType $detectionRule.DetectionType

                $property = [ordered]@{
                    Type = $type
                }

                $detectionText = $_.DetectionText | ConvertFrom-Json # convert from JSON and select-object in two lines otherwise it behaves strangely
                if ($detectionText.ScriptBody) {
                    # it is a script detection check
                    $detectionText = $detectionText | select -Property `
                    @{n = 'EnforceSignatureCheck'; e = { if ($_.EnforceSignatureCheck -ne 0) { $true } else { $false } } },
                    @{n = 'RunAs32Bit'; e = { if ($_.RunAs32Bit -ne 0) { $true } else { $false } } },
                    @{n = 'ScriptBody'; e = { ConvertFrom-Base64 ($_.ScriptBody -replace "^77u/") } } `
                        -ExcludeProperty 'ScriptBody', 'RunAs32Bit', 'EnforceSignatureCheck'
                } elseif ($detectionText.ProductCode) {
                    # it is a MSI detection check
                    $detectionText = $detectionText | select -Property @{n = 'ProductVersionOperator'; e = { _operator $_.ProductVersionOperator } }, '*' -ExcludeProperty 'ProductVersionOperator'
                } else {
                    # it is a file or registry detection check
                    $detectionText = $detectionText | select -Property `
                    @{n = 'DetectionType'; e = { _ruleSubType -type $type -subtype $_.detectionType -value $_.KeyName } },
                    @{n = 'Operator'; e = { _operator -operator $_.operator -type $type } },
                    '*',
                    @{n = 'Check32BitOn64System'; e = { if ($_.Check32BitOn64System -ne 0) { $true } else { $false } } }`
                        -ExcludeProperty 'DetectionType', 'Operator', 'Check32BitOn64System'

                    if ($detectionText.DetectionType -in "File or folder exist", "File or folder does not exist", "Value exists", "Value does not exist") {
                        # Operator and DetectionValue properties are not used for these types, remove them
                        $detectionText = $detectionText | select -Property * -ExcludeProperty Operator, DetectionValue
                    }

                    if ($detectionText.DetectionType -in "Key exists", "Key does not exist") {
                        # Operator, DetectionValue and KeyName properties are not used for these types, remove them
                        $detectionText = $detectionText | select -Property * -ExcludeProperty Operator, DetectionValue, KeyName
                    }
                }

                # add object ($detectionText) properties to the parent object ($detectionRule) a.k.a flatten object structure
                $newProperty = $detectionText.psobject.properties | select name

                $newProperty | % {
                    $propertyName = $_.Name
                    $propertyValue = $detectionText.$propertyName

                    $property.$propertyName = $propertyValue
                }

                New-Object -TypeName PSObject -Property $property
            }
        }

        function _extendedRequirementRules {
            param ($extendedRequirementRules)

            function _requirementType {
                param ($type)

                switch ($type) {
                    0 { "Registry" }
                    2 { "File" }
                    3 { "Script" }
                    default { $type }
                }
            }

            $extendedRequirementRules = $extendedRequirementRules | ConvertFrom-Json

            # enhance the object properties
            $extendedRequirementRules | % {
                $extendedRequirementRule = $_

                $type = _requirementType $extendedRequirementRule.Type

                $property = [ordered]@{
                    Type = $type
                }

                $requirementText = $extendedRequirementRule.RequirementText | ConvertFrom-Json # convert from JSON and select-object in two lines otherwise it behaves strangely

                if ($requirementText.ScriptBody) {
                    # it is a script requirement check
                    $requirementText = $requirementText | select -Property `
                    @{n = 'ReqType'; e = { _ruleSubType -type $type -subtype $_.type -value $_.value } },
                    @{n = 'Operator'; e = { _operator $_.operator } },
                    '*',
                    @{n = 'RunAsLoggedUser'; e = { if ($_.RunAsAccount -ne 0) { $true } else { $false } } },
                    @{n = 'RunAs32Bit'; e = { if ($_.RunAs32Bit -ne 0) { $true } else { $false } } },
                    @{n = 'EnforceSignatureCheck'; e = { if ($_.EnforceSignatureCheck -ne 0) { $true } else { $false } } },
                    @{n = 'ScriptBody'; e = { ConvertFrom-Base64 $_.ScriptBody } } `
                        -ExcludeProperty 'Type', 'Operator', 'ScriptBody', 'RunAs32Bit', 'EnforceSignatureCheck', 'RunAsAccount'
                } else {
                    # it is a file or registry requirement check
                    $requirementText = $requirementText | select -Property `
                    @{n = 'ReqType'; e = { _ruleSubType -type $type -subtype $_.type -value $(if ($_.value) { $_.value } else { $_.keyname }) } },
                    @{n = 'Operator'; e = { _operator $_.operator } },
                    '*',
                    @{n = 'Check32BitOn64System'; e = { if ($_.Check32BitOn64System -ne 0) { $true } else { $false } } }`
                        -ExcludeProperty 'Type', 'Operator', 'Check32BitOn64System'

                    if ($requirementText.ReqType -in "File or folder exist", "File or folder does not exist", "Value exists", "Value does not exist") {
                        # operator and value properties are not used for these types, remove them
                        $requirementText = $requirementText | select -Property * -ExcludeProperty Operator, Value
                    }

                    if ($requirementText.ReqType -in "Key exists", "Key does not exist") {
                        # operator, value and keyname properties are not used for these types, remove them
                        $requirementText = $requirementText | select -Property * -ExcludeProperty Operator, Value, KeyName
                    }
                }

                # add object ($requirementText) properties to the parent object ($extendedRequirementRule) a.k.a flatten object structure
                $newProperty = $requirementText.psobject.properties | select name
                $newProperty | % {
                    $propertyName = $_.Name
                    $propertyValue = $requirementText.$propertyName

                    $property.$propertyName = $propertyValue
                }

                New-Object -TypeName PSObject -Property $property
            }
        }

        function _returnCodes {
            param ($returnCodes)

            function _type {
                param ($type)

                switch ($type) {
                    0 { "Failed" }
                    1 { "Success" }
                    2 { "SoftReboot" }
                    3 { "HardReboot" }
                    4 { "Retry" }
                    default { $type }
                }
            }

            $returnCodes = $returnCodes | ConvertFrom-Json # convert from JSON and select-object in two lines otherwise it behaves strangely

            $returnCodes | select 'ReturnCode', @{n = 'Type'; e = { _type $_.Type } }
        }

        function _installEx {
            param ($installEx)

            function _deviceRestartBehavior {
                param ($deviceRestartBehavior)

                switch ($deviceRestartBehavior) {
                    0 { 'Determine behavior based on return codes' }
                    1 { "App install may force a device restart" }
                    2 { 'No specific action' }
                    3 { 'Intune will force a mandatory device restart' }
                    default { $deviceRestartBehavior }
                }
            }

            $installEx = $installEx | ConvertFrom-Json # convert from JSON and select-object in two lines otherwise it behaves strangely

            $installEx | select -Property `
            @{n = 'RunAs'; e = { if ($_.RunAs -eq 1) { 'System' } else { 'User' } } },
            '*',
            @{n = 'DeviceRestartBehavior'; e = { _deviceRestartBehavior $_.DeviceRestartBehavior } }`
                -ExcludeProperty RunAs, DeviceRestartBehavior
        }

        function _requirementRules {
            param ($requirementRules)

            $requirementRules = $requirementRules | ConvertFrom-Json # convert from JSON and select-object in two lines otherwise it behaves strangely

            $requirementRules | select -Property `
            @{n = 'RequiredOSArchitecture'; e = { if ($_.RequiredOSArchitecture -eq 1) { 'x86' } else { 'x64' } } },
            '*'`
                -ExcludeProperty RequiredOSArchitecture
        }

        function _flatDependencies {
            param ($flatDependencies)

            $flatDependencies | select @{n = 'AutoInstall'; e = { if ($_.Action -eq 10) { $true } else { $false } } }, @{n = 'AppId'; e = { $_.ChildId } }
        }
        #endregion helper functions

        # add properties that gets customized/replaced
        $excludeProperty += 'DetectionRule', 'RequirementRules', 'ExtendedRequirementRules', 'InstallEx', 'ReturnCodes', 'FlatDependencies', 'RebootEx', 'StartDeadlineEx'

        $object | select -Property '*',
        @{n = 'DetectionRule'; e = { _detectionRule $_.DetectionRule } },
        @{n = 'RequirementRules'; e = { _requirementRules $_.RequirementRules } },
        @{n = 'RequirementRulesExtended'; e = { _extendedRequirementRules $_.ExtendedRequirementRules } },
        @{n = 'InstallExtended'; e = { _installEx $_.InstallEx } },
        @{n = 'FlatDependencies'; e = { _flatDependencies $_.FlatDependencies } },
        @{n = 'RebootExtended'; e = { $_.RebootEx } },
        @{n = 'ReturnCodes'; e = { _returnCodes $_.ReturnCodes } },
        @{n = 'StartDeadlineExtended'; e = { $_.StartDeadlineEx } }`
            -ExcludeProperty $excludeProperty
    }
    #endregion helper functions

    # get list of available Intune logs
    $intuneLogList = Get-ChildItem -Path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs" -Filter "IntuneManagementExtension*.log" -File | sort LastWriteTime -Descending | select -ExpandProperty FullName

    if (!$intuneLogList) {
        Write-Error "Unable to find any Intune log files. Unable to get script content."
        return
    }

    :outerForeach foreach ($intuneLog in $intuneLogList) {
        # how content of the log can looks like
        # <![LOG[Get policies = [{"Id":"56695a77-925a-4....

        Write-Verbose "Searching for Win32Apps processing in '$intuneLog'"

        # get line text where win32apps processing is mentioned
        $param = @{
            Path       = $intuneLog
            Pattern    = ("^" + [regex]::escape('<![LOG[Get policies = [{"Id":'))
            AllMatches = $true
        }

        $matchList = Select-String @param | select -ExpandProperty Line

        if ($matchList.count -gt 1) {
            # get the newest events first
            [array]::Reverse($matchList)
        }

        if ($matchList) {
            foreach ($match in $matchList) {
                # get rid of non-JSON prefix/suffix
                $jsonList = $match -replace [regex]::Escape("<![LOG[Get policies = [") -replace ([regex]::Escape("]]LOG]!>") + ".*")
                # ugly but working solution :D
                $i = 0
                $jsonListSplitted = $jsonList -split '},{"Id":'
                if ($jsonListSplitted.count -gt 1) {
                    # there are multiple JSONs divided by comma, I have to process them one by one
                    $jsonListSplitted | % {
                        # split replaces text that was used to split, I have to recreate it
                        $json = ""
                        if ($i -eq 0) {
                            # first item
                            $json = $_ + '}'
                        } elseif ($i -ne ($jsonListSplitted.count - 1)) {
                            $json = '{"Id":' + $_ + '}'
                        } else {
                            # last item
                            $json = '{"Id":' + $_
                        }

                        ++$i

                        Write-Verbose "Processing:`n$json"

                        # customize converted object (convert base64 to text and JSON to object)
                        _enhanceObject -object ($json | ConvertFrom-Json) -excludeProperty $excludeProperty
                    }
                } else {
                    # there is just one JSON, I can directly convert it to an object
                    # customize converted object (convert base64 to text and JSON to object)

                    Write-Verbose "Processing:`n$jsonList"

                    _enhanceObject -object ($jsonList | ConvertFrom-Json) -excludeProperty $excludeProperty
                }

                if (!$allOccurrences) {
                    # don't continue the search when you already have match
                    break outerForeach
                }
            }
        } else {
            Write-Verbose "There is no data related processing of Win32App. Trying next log."
        }
    }
}