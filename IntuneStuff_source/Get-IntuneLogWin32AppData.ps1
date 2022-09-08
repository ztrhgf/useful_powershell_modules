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
    $myApp.ExtendedRequirementRules.RequirementText.ScriptBody

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

    function _enhanceObject {
        param ($object, $excludeProperty)

        #region helper functions
        function _detectionRule {
            param ($detectionRule)

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

            $detectionRule | ConvertFrom-Json | select `
            @{n = 'DetectionType'; e = { _detectionType $_.DetectionType } },
            @{n = 'DetectionText'; e = {
                    $r = $_.DetectionText | ConvertFrom-Json # convert from JSON and select-object in two lines otherwise it behaves strangely

                    $r | select -Property '*', @{n = 'ScriptBody'; e = { ConvertFrom-Base64 ($_.ScriptBody -replace "^77u/") } }`
                        -ExcludeProperty 'ScriptBody'
                }
            }
        }

        function _extendedRequirementRules {
            param ($extendedRequirementRules)

            function _type {
                param ($type)

                switch ($type) {
                    0 { "File" }
                    2 { "Registry" }
                    3 { "Script" }
                    default { $type }
                }
            }

            #TODO RequirementText: Type a Operator

            $r = $extendedRequirementRules | ConvertFrom-Json

            $r | select -Property `
            @{n = 'Type'; e = { _type $_.Type } },
            @{n = 'RequirementText'; e = {
                    $r = $_.RequirementText | ConvertFrom-Json # convert from JSON and select-object in two lines otherwise it behaves strangely
                    $r | select -Property '*', @{n = 'ScriptBody'; e = { ConvertFrom-Base64 $_.ScriptBody } } -ExcludeProperty 'ScriptBody'
                }
            }`
                -ExcludeProperty 'Type', 'RequirementText'
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

            $r = $returnCodes | ConvertFrom-Json # convert from JSON and select-object in two lines otherwise it behaves strangely

            $r | select 'ReturnCode', @{n = 'Type'; e = { _type $_.Type } }

        }

        function _installEx {
            param ($installEx)

            function _deviceRestartBehavior {
                param ($deviceRestartBehavior)

                switch ($deviceRestartBehavior) {
                    # 'App install may force a device restart'
                    # 'Intune will force a mandatory device restart'
                    0 { 'Determine behavior based on return codes' }
                    1 {}
                    2 { 'No specific action' }
                    3 {}
                    default { $deviceRestartBehavior }
                }
            }

            $r = $installEx | ConvertFrom-Json # convert from JSON and select-object in two lines otherwise it behaves strangely

            $r | select -Property `
            @{n = 'RunAs'; e = { if ($_.RunAs -eq 1) { 'System' } else { 'User' } } },
            '*',
            @{n = 'DeviceRestartBehavior'; e = { _deviceRestartBehavior $_.DeviceRestartBehavior } }`
                -ExcludeProperty RunAs, DeviceRestartBehavior
        }

        function _requirementRules {
            param ($requirementRules)

            $r = $requirementRules | ConvertFrom-Json # convert from JSON and select-object in two lines otherwise it behaves strangely

            $r | select -Property `
            @{n = 'RequiredOSArchitecture'; e = { if ($_.RequiredOSArchitecture -eq 1) { 'x86' } else { 'x64' } } },
            '*'`
                -ExcludeProperty RequiredOSArchitecture
        }
        #endregion helper functions

        # add properties that gets customized/replaced
        $excludeProperty += 'DetectionRule', 'RequirementRules', 'ExtendedRequirementRules', 'InstallEx', 'ReturnCodes'

        $object | select -Property '*',
        @{n = 'DetectionRule'; e = { _detectionRule $_.DetectionRule } },
        @{n = 'RequirementRules'; e = { _requirementRules $_.RequirementRules } },
        @{n = 'ExtendedRequirementRules'; e = { _extendedRequirementRules $_.ExtendedRequirementRules } },
        @{n = 'InstallEx'; e = { _installEx $_.InstallEx } },
        @{n = 'ReturnCodes'; e = { _returnCodes $_.ReturnCodes } }`
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
            Path    = $intuneLog
            Pattern = ("^" + [regex]::escape('<![LOG[Get policies = [{"Id":'))
        }
        if ($allOccurrences) {
            $param.AllMatches = $true
        } else {
            $param.List = $true
        }

        $matchList = Select-String @param | select -ExpandProperty Line

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

                        # customize converted object (convert base64 to text and JSON to object)
                        _enhanceObject -object ($json | ConvertFrom-Json) -excludeProperty $excludeProperty
                    }
                } else {
                    # there is just one JSON, I can directly convert it to an object
                    # customize converted object (convert base64 to text and JSON to object)
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