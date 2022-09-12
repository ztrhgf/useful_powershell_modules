function Get-IntuneLogWin32AppReportingResultData {
    <#
    .SYNOPSIS
    Function for getting Intune Win32Apps reporting data from clients log files ($env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension*.log).

    .DESCRIPTION
    Function for getting Intune Win32Apps reporting data from clients log files ($env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension*.log).

    Finds data about results reporting of Win32Apps and outputs them into console as an PowerShell object.

    Shows data about application that won't be installed on the client because requirements are not met (such app won't be seen in registry, only in log file).

    .PARAMETER allOccurrences
    Switch for getting all Win32App reportings.
    By default just newest report is returned from the newest Intune log.

    .PARAMETER excludeProperty
    List of properties to exclude.

    .EXAMPLE
    Get-IntuneLogWin32AppReportingResultData

    Get newest reporting data for Win32Apps.

    .NOTES
    Run on Windows client managed using Intune MDM.
    #>

    [CmdletBinding()]
    param (
        [switch] $allOccurrences,

        [string[]] $excludeProperty = ('')
    )

    #region helper functions
    function _enhanceObject {
        param ($object, $excludeProperty)

        #region helper functions
        function _complianceStateMessage {
            param ($complianceStateMessage)

            function _complianceState {
                param ($complianceState)

                switch ($complianceState) {
                    0 { "Unknown" }
                    1 { "Compliant" }
                    2 { "Not compliant" }
                    3 { "Conflict (Not applicable for app deployment)" }
                    4 { "Error" }
                    default { $complianceState }
                }
            }

            function _desiredState {
                param ($desiredState)

                switch ($desiredState) {
                    0	{ "None" }
                    1	{ "NotPresent" }
                    2	{ "Present" }
                    3	{ "Unknown" }
                    4	{ "Available" }
                    default { $desiredState }
                }
            }

            $complianceStateMessage | select Applicability, @{n = 'ComplianceState'; e = { _complianceState $_.ComplianceState } }, @{n = 'DesiredState'; e = { _desiredState $_.DesiredState } }, @{n = 'ErrorCode'; e = { _translateErrorCode  $_.ErrorCode } }, TargetingMethod, InstallContext, TargetType, ProductVersion, AssignmentFilterIds
        }

        function _enforcementStateMessage {
            param ($enforcementStateMessage)

            function _enforcementState {
                param ($enforcementState)

                switch ($enforcementState) {
                    1000	{ "Succeeded" }
                    1003	{ "Received command to install" }
                    2000	{ "Enforcement action is in progress" }
                    2007	{ "App enforcement will be attempted once all dependent apps have been installed" }
                    2008	{ "App has been installed but is not usable until device has rebooted" }
                    2009	{ "App has been downloaded but no installation has been attempted" }
                    3000	{ "Enforcement action aborted due to requirements not being met" }
                    4000	{ "Enforcement action could not be completed due to unknown reason" }
                    5000	{ "Enforcement action failed due to error.  Error code needs to be checked to determine detailed status" }
                    5003	{ "Client was unable to download app content." }
                    5999	{ "Enforcement action failed due to error, will retry immediately." }
                    6000	{ "Enforcement action has not been attempted.  No reason given." }
                    6001	{ "App install is blocked because one or more of the app's dependencies failed to install." }
                    6002	{ "App install is blocked on the machine due to a pending hard reboot." }
                    6003	{ "App install is blocked because one or more of the app's dependencies have requirements which are not met." }
                    6004	{ "App is a dependency of another application and is configured to not automatically install." }
                    6005	{ "App install is blocked because one or more of the app's dependencies are configured to not automatically install." }
                    default { $enforcementState }
                }
            }

            $enforcementStateMessage | select @{n = 'EnforcementState'; e = { _enforcementState $_.EnforcementState } }, @{n = 'ErrorCode'; e = { _translateErrorCode  $_.ErrorCode } }, TargetingMethod
        }

        function _translateErrorCode {
            param ($errorCode)

            if (!$errorCode) { return }

            $errMsg = [ComponentModel.Win32Exception]$errorCode
            if ($errMsg -match "^Unknown error") {
                $errorCode
            } else {
                $errMsg.Message + " ($errorCode)"
            }
        }
        #endregion helper functions

        # add properties that gets customized/replaced
        $excludeProperty += 'ApplicationName', 'AppId', 'ComplianceStateMessage', 'EnforcementStateMessage'

        $object | select -Property @{n = 'Name'; e = { $_.ApplicationName } }, @{n = 'Id'; e = { $_.AppId } }, @{n = 'ComplianceStateMessage'; e = { _complianceStateMessage $_.ComplianceStateMessage } }, @{n = 'EnforcementStateMessage'; e = { _enforcementStateMessage $_.EnforcementStateMessage } }, '*'`
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
        # how content of the log looks like
        # [Win32App] Sending results to service. session RequestPayload: [{.....

        Write-Verbose "Searching for Win32Apps results in '$intuneLog'"

        # get line text where win32apps results send is mentioned
        $param = @{
            Path       = $intuneLog
            Pattern    = ("^" + [regex]::escape('<![LOG[[Win32App] Sending results to service. session RequestPayload:'))
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
                $jsonList = $match -replace [regex]::Escape("<![LOG[[Win32App] Sending results to service. session RequestPayload: [") -replace ([regex]::Escape("]]LOG]!>") + ".*")
                # ugly but working solution :D
                $i = 0
                $jsonListSplitted = $jsonList -split '},{"AppId":'
                if ($jsonListSplitted.count -gt 1) {
                    # there are multiple JSONs divided by comma, I have to process them one by one
                    $jsonListSplitted | % {
                        # split replaces text that was used to split, I have to recreate it
                        $json = ""
                        if ($i -eq 0) {
                            # first item
                            $json = $_ + '}'
                        } elseif ($i -ne ($jsonListSplitted.count - 1)) {
                            $json = '{"AppId":' + $_ + '}'
                        } else {
                            # last item
                            $json = '{"AppId":' + $_
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