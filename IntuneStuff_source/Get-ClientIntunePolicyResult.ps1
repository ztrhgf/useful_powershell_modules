function Get-ClientIntunePolicyResult {
    <#
        .SYNOPSIS
        Function for getting gpresult/rsop like report but for local client Intune policies.
        Result can be PowerShell object or HTML report.

        .DESCRIPTION
        Function for getting gpresult/rsop like report but for local client Intune policies.
        Result can be PowerShell object or HTML report.

        .PARAMETER computerName
        (optional) Computer name from which you want to get data from.

        .PARAMETER intuneXMLReport
        (optional) PowerShell object returned by ConvertFrom-MDMDiagReportXML function.

        .PARAMETER asHTML
        Switch for returning HTML report instead of PowerShell object.
        PSWriteHTML module is needed!

        .PARAMETER HTMLReportPath
        (optional) Where the HTML report should be stored.

        Default is "IntunePolicyReport.html" in user profile.

        .PARAMETER includeScriptContent
        Switch for including Intune scripts content.

        This will need administrator rights and lead to redeploy of all such scripts to the client!

        .PARAMETER force
        Switch for skipping Intune script(s) redeploy confirmation (caused when 'includeScriptContent' parameter is used).

        .PARAMETER getDataFromIntune
        Switch for getting additional data (policy names and account names instead of IDs) from Intune itself.
        Microsoft.Graph.Intune module is required!

        Account with READ permission for: Applications, Scripts, RemediationScripts, Users will be needed i.e.:
        - DeviceManagementApps.Read.All
        - DeviceManagementManagedDevices.Read.All
        - DeviceManagementConfiguration.Read.All
        - User.Read.All

        .PARAMETER credential
        Credentials for connecting to Intune.
        Account that has at least READ permissions has to be used.

        .PARAMETER tenantId
        String with your TenantID.
        Use only if you want use application authentication (instead of user authentication).
        You can get your TenantID at https://portal.azure.com/#blade/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/Overview.

        .PARAMETER showEnrollmentIDs
        Switch for showing EnrollmentIDs in the result.

        .PARAMETER showURLs
        Switch for showing policy/setting URLs in the result.
        Makes this function a little slower, because every URL is tested that it exists.

        .PARAMETER showConnectionData
        Switch for showing data related to client's connection to the Intune.

        .EXAMPLE
        Get-ClientIntunePolicyResult

        Will return PowerShell object containing Intune policy processing report data.

        .EXAMPLE
        Get-ClientIntunePolicyResult -showURLs -asHTML

        Will return HTML page containing Intune policy processing report data.
        URLs to policies/settings will be included.

        .EXAMPLE
        $intuneREADCred = Get-Credential
        Get-ClientIntunePolicyResult -showURLs -asHTML -getDataFromIntune -showConnectionData -credential $intuneREADCred

        Will return HTML page containing Intune policy processing report data and connection data.
        URLs to policies/settings and Intune policies names (if available) will be included.

        .EXAMPLE
        $intuneREADAppCred = Get-Credential
        Get-ClientIntunePolicyResult -showURLs -asHTML -getDataFromIntune -credential $intuneREADAppCred -tenantId 123456789

        Will return HTML page containing Intune policy processing report data.
        URLs to policies/settings will be included same as Intune policies names (if available).
        For authentication to Intune registered application secret will be used (AppID and secret stored in credentials object).
        #>

    [Alias("ipresult", "Get-IntunePolicyResult", "Get-IntuneClientPolicyResult")]
    [CmdletBinding()]
    param (
        [string] $computerName,

        [ValidateScript( { $_.GetType().Name -eq 'Object[]' } )]
        $intuneXMLReport,

        [switch] $asHTML,

        [string] $HTMLReportPath = (Join-Path $env:USERPROFILE "IntunePolicyReport.html"),

        [switch] $includeScriptContent,

        [switch] $force,

        [switch] $getDataFromIntune,

        [System.Management.Automation.PSCredential] $credential,

        [string] $tenantId,

        [switch] $showEnrollmentIDs,

        [switch] $showURLs,

        [switch] $showConnectionData
    )

    # remove property validation
    (Get-Variable intuneXMLReport).Attributes.Clear()

    #region prepare
    if ($computerName) {
        $session = New-PSSession -ComputerName $computerName -ErrorAction Stop
    }

    if ($asHTML) {
        if (!(Get-Module 'PSWriteHtml') -and (!(Get-Module 'PSWriteHtml' -ListAvailable))) {
            throw "Module PSWriteHtml is missing. To get it use command: Install-Module PSWriteHtml -Scope CurrentUser"
        }
        [Void][System.IO.Directory]::CreateDirectory((Split-Path $HTMLReportPath -Parent))
    }

    if ($getDataFromIntune) {
        if (!(Get-Module 'Microsoft.Graph.Intune') -and !(Get-Module 'Microsoft.Graph.Intune' -ListAvailable)) {
            throw "Module 'Microsoft.Graph.Intune' is required. To install it call: Install-Module 'Microsoft.Graph.Intune' -Scope CurrentUser"
        }

        if ($tenantId) {
            # app logon
            if (!$credential) {
                $credential = Get-Credential -Message "Enter AppID and AppSecret for connecting to Intune tenant" -ErrorAction Stop
            }
            Update-MSGraphEnvironment -AppId $credential.UserName -Quiet
            Update-MSGraphEnvironment -AuthUrl "https://login.windows.net/$tenantId" -Quiet
            $null = Connect-MSGraph -ClientSecret $credential.GetNetworkCredential().Password -ErrorAction Stop
        } else {
            # user logon
            if ($credential) {
                $null = Connect-MSGraph -Credential $credential -ErrorAction Stop
                # $header = New-GraphAPIAuthHeader -credential $credential -ErrorAction Stop
            } else {
                $null = Connect-MSGraph -ErrorAction Stop
                # $header = New-GraphAPIAuthHeader -ErrorAction Stop
            }
        }

        Write-Verbose "Getting Intune data"
        # filtering by ID is as slow as getting all data
        # Invoke-MSGraphRequest -Url 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?$filter=(id%20eq%20%2756695a77-925a-4df0-be79-24ed039afa86%27)'
        $intuneRemediationScript = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts?select=id,displayname" | Get-MSGraphAllPages
        $intuneScript = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts?select=id,displayname" | Get-MSGraphAllPages
        $intuneApp = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?select=id,displayname" | Get-MSGraphAllPages
        $intuneUser = Invoke-MSGraphRequest -Url 'https://graph.microsoft.com/beta/users?select=id,userPrincipalName' | Get-MSGraphAllPages
    }

    # get the core Intune data
    if (!$intuneXMLReport) {
        $param = @{}
        if ($showEnrollmentIDs) { $param.showEnrollmentIDs = $true }
        if ($showURLs) { $param.showURLs = $true }
        if ($showConnectionData) { $param.showConnectionData = $true }
        if ($computerName) { $param.computerName = $computerName }

        Write-Verbose "Getting client Intune data via ConvertFrom-MDMDiagReportXML"
        $intuneXMLReport = ConvertFrom-MDMDiagReportXML @param
    }
    #endregion prepare

    #region helper functions
    function _getTargetName {
        param ([string] $id)

        Write-Verbose "Translating $id"

        if (!$id) {
            Write-Verbose "id was null"
            return
        } elseif ($id -eq 'device') {
            # xml nodes contains 'device' instead of 'Device'
            return 'Device'
        }

        $errPref = $ErrorActionPreference
        $ErrorActionPreference = "Stop"
        try {
            if ($id -eq '00000000-0000-0000-0000-000000000000' -or $id -eq 'S-0-0-00-0000000000-0000000000-000000000-000') {
                return 'Device'
            } elseif ($id -match "^S-1-5-21") {
                # it is local account
                return ((New-Object System.Security.Principal.SecurityIdentifier($id)).Translate([System.Security.Principal.NTAccount])).Value
            } else {
                # it is AzureAD account
                if ($getDataFromIntune) {
                    return ($intuneUser | ? id -EQ $id).userPrincipalName
                } else {
                    # unable to translate ID to name because there is no connection to the Intune Graph API
                    return $id
                }
            }
        } catch {
            Write-Warning "Unable to translate $id to account name ($_)"
            $ErrorActionPreference = $errPref
            return $id
        }
    }
    function _getIntuneScript {
        param ([string] $scriptID)

        $intuneScript | ? id -EQ $scriptID
    }

    function _getIntuneApp {
        param ([string] $appID)

        $intuneApp | ? id -EQ $appID
    }

    function _getRemediationScript {
        param ([string] $scriptID)
        $intuneRemediationScript | ? id -EQ $scriptID
    }

    # create helper functions text definition for usage in remote sessions
    if ($computerName) {
        $allFunctionDefs = "function _getTargetName { ${function:_getTargetName} }; function _getIntuneScript { ${function:_getIntuneScript} }; function _getIntuneApp { ${function:_getIntuneApp} }; ; function _getRemediationScript { ${function:_getRemediationScript} }; function Get-IntuneWin32AppLocally { ${function:Get-IntuneWin32AppLocally} }; function Get-IntuneScriptLocally { ${function:Get-IntuneScriptLocally} }; function Get-IntuneRemediationScriptLocally { ${function:Get-IntuneRemediationScriptLocally} }"
    }
    #endregion helper functions

    #region enrich SoftwareInstallation section
    if ($intuneXMLReport | ? PolicyName -EQ 'SoftwareInstallation') {
        Write-Verbose "Modifying 'SoftwareInstallation' section"
        # list of installed MSI applications
        $scriptBlock = {
            Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\', 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\' -ErrorAction SilentlyContinue -Recurse | % {
                Get-ItemProperty -Path $_.PSPath | select -Property DisplayName, DisplayVersion, UninstallString
            }
        }

        $param = @{
            scriptBlock  = $scriptBlock
            argumentList = ($VerbosePreference, $allFunctionDefs)
        }
        if ($computerName) {
            $param.session = $session
        }

        $installedMSI = Invoke-Command @param

        if ($installedMSI) {
            $intuneXMLReport = $intuneXMLReport | % {
                if ($_.PolicyName -EQ 'SoftwareInstallation') {
                    $softwareInstallation = $_

                    $softwareInstallationSettingDetails = $softwareInstallation.SettingDetails | ? { $_ } | % {
                        $item = $_
                        $packageId = $item.PackageId

                        Write-Verbose "`tPackageId $packageId"

                        Add-Member -InputObject $item -MemberType NoteProperty -Force -Name DisplayName -Value ($installedMSI | ? UninstallString -Match ([regex]::Escape($packageId)) | select -Last 1 -ExpandProperty DisplayName)

                        #return modified MSI object (put Displayname as a second property)
                        $item | select -Property Scope, DisplayName, Type, Status, LastError, ProductVersion, CommandLine, RetryIndex, MaxRetryCount, PackageId
                    }

                    # save results back to original object
                    $softwareInstallation.SettingDetails = $softwareInstallationSettingDetails

                    # return modified object
                    $softwareInstallation
                } else {
                    # no change necessary
                    $_
                }
            }
        }
    }
    #endregion enrich SoftwareInstallation section

    #region Win32App
    Write-Verbose "Processing 'Win32App' section"
    #region get data
    $scriptBlock = {
        param($verbosePref, $getDataFromIntune, $intuneApp, $intuneUser, $allFunctionDefs)

        # inherit verbose settings from host session
        $VerbosePreference = $verbosePref

        # recreate functions from their text definitions
        . ([ScriptBlock]::Create($allFunctionDefs))

        $win32App = Get-IntuneWin32AppLocally

        if ($showURLs) {
            $win32App | % {
                $_ | Add-Member -MemberType NoteProperty -Name "IntuneWin32AppURL" -Value "https://endpoint.microsoft.com/#blade/Microsoft_Intune_Apps/SettingsMenu/0/appId/$($_.id)"
            }
        } else {
            $win32App
        }
    }

    $param = @{
        scriptBlock  = $scriptBlock
        argumentList = ($VerbosePreference, $getDataFromIntune, $intuneApp, $intuneUser, $allFunctionDefs)
    }
    if ($computerName) {
        $param.session = $session
    }

    $settingDetails = Invoke-Command @param
    #endregion get data

    if ($settingDetails) {
        $property = [ordered]@{
            "Scope"          = $null # scope is specified at the particular items level
            "PolicyName"     = 'SoftwareInstallation Win32App' # my custom made
            # SettingName    = 'Win32App' # my custom made
            "SettingDetails" = $settingDetails
        }

        if ($showURLs) {
            $property.PolicyURL = "https://endpoint.microsoft.com/#blade/Microsoft_Intune_DeviceSettings/AppsWindowsMenu/windowsApps"
        }

        $intuneXMLReport += New-Object -TypeName PSObject -Property $property
    }
    #endregion Win32App

    #region add Scripts section
    # https://oliverkieselbach.com/2018/02/12/part-2-deep-dive-microsoft-intune-management-extension-powershell-scripts/
    Write-Verbose "Processing 'Script' section"
    $scriptBlock = {
        param($verbosePref, $getDataFromIntune, $includeScriptContent, $force, $intuneScript, $intuneUser, $allFunctionDefs)

        # inherit verbose settings from host session
        $VerbosePreference = $verbosePref

        # recreate functions from their text definitions
        . ([ScriptBlock]::Create($allFunctionDefs))

        $param = @{}
        if ($includeScriptContent) {
            $param.includeScriptContent = $true
        }
        if ($force) {
            $param.force = $true
        }

        $script = Get-IntuneScriptLocally @param

        if ($showURLs) {
            $script | % {
                $_ | Add-Member -MemberType NoteProperty -Name IntuneScriptURL -Value "https://endpoint.microsoft.com/#blade/Microsoft_Intune_DeviceSettings/ConfigureWMPolicyMenuBlade/properties/policyId/$($_.ID)/policyType/0"
            }
        } else {
            $script
        }
    }

    $param = @{
        scriptBlock  = $scriptBlock
        argumentList = ($VerbosePreference, $getDataFromIntune, $includeScriptContent, $force, $intuneScript, $intuneUser, $allFunctionDefs)
    }
    if ($computerName) {
        $param.session = $session
    }

    $settingDetails = Invoke-Command @param

    if ($settingDetails) {
        $property = [ordered]@{
            "Scope"          = $null # scope is specified at the particular items level
            "PolicyName"     = 'Script' # my custom made
            "SettingName"    = $null
            "SettingDetails" = $settingDetails
        }

        if ($showURLs) {
            $property.PolicyURL = "https://endpoint.microsoft.com/#blade/Microsoft_Intune_DeviceSettings/DevicesMenu/powershell"
        }

        $intuneXMLReport += New-Object -TypeName PSObject -Property $property
    }
    #endregion add Scripts section

    #region remediation script
    Write-Verbose "Processing 'Remediation Script' section"
    $scriptBlock = {
        param($verbosePref, $getDataFromIntune, $intuneRemediationScript, $intuneUser, $allFunctionDefs)

        # inherit verbose settings from host session
        $VerbosePreference = $verbosePref

        # recreate functions from their text definitions
        . ([ScriptBlock]::Create($allFunctionDefs))

        Get-IntuneRemediationScriptLocally
    }

    $param = @{
        scriptBlock  = $scriptBlock
        argumentList = ($VerbosePreference, $getDataFromIntune, $intuneRemediationScript, $intuneUser, $allFunctionDefs)
    }
    if ($computerName) {
        $param.session = $session
    }

    $settingDetails = Invoke-Command @param

    if ($settingDetails) {
        $property = [ordered]@{
            "Scope"          = $null # scope is specified at the particular items level
            "PolicyName"     = 'RemediationScript' # my custom made
            "SettingName"    = $null # my custom made
            "SettingDetails" = $settingDetails
        }

        if ($showURLs) {
            $property.PolicyURL = "https://endpoint.microsoft.com/#blade/Microsoft_Intune_Enrollment/UXAnalyticsMenu/proactiveRemediations"
        }

        $intuneXMLReport += New-Object -TypeName PSObject -Property $property
    }
    #endregion remediation script

    if ($computerName) {
        Remove-PSSession $session
    }

    #region output the results (as object or HTML report)
    if ($asHTML -and $intuneXMLReport) {
        Write-Verbose "Converting to '$HTMLReportPath'"

        # split the results
        $resultsWithSettings = @()
        $resultsWithoutSettings = @()
        $resultsConnectionData = $null
        $intuneXMLReport | % {
            if ($_.settingDetails) {
                $resultsWithSettings += $_
            } elseif ($_.MDMServerName) {
                # MDMServerName property is only in object representing connection data
                $resultsConnectionData = $_
            } else {
                $resultsWithoutSettings += $_
            }
        }

        if ($computerName) { $title = "Intune Report - $($computerName.toupper())" }
        else { $title = "Intune Report - $($env:COMPUTERNAME.toupper())" }

        New-HTML -TitleText $title -Online -FilePath $HTMLReportPath -ShowHTML {
            # it looks better to have headers and content in center
            New-HTMLTableStyle -TextAlign center

            New-HTMLSection -HeaderText $title -Direction row -HeaderBackGroundColor Black -HeaderTextColor White -HeaderTextSize 20 {
                if ($resultsConnectionData) {
                    New-HTMLSection -HeaderText "Intune connection information" -HeaderTextAlignment left -CanCollapse -BackgroundColor DeepSkyBlue -HeaderBackGroundColor DeepSkyBlue -HeaderTextSize 10 -HeaderTextColor EgyptianBlue -Direction row {
                        # render policies
                        New-HTMLSection -BackgroundColor White {
                            New-HTMLTable -DataTable $resultsConnectionData -WordBreak 'break-all' -DisableInfo -HideButtons -DisablePaging -HideFooter -DisableSearch -DisableOrdering
                        }
                    }
                }

                if ($resultsWithoutSettings) {
                    New-HTMLSection -HeaderText "Policies without settings details" -HeaderTextAlignment left -CanCollapse -BackgroundColor DeepSkyBlue -HeaderBackGroundColor DeepSkyBlue -HeaderTextSize 10 -HeaderTextColor EgyptianBlue -Direction row {
                        #region prepare data
                        # exclude some not significant or needed properties
                        # SettingName is empty (or same as PolicyName)
                        # settingDetails is empty
                        $excludeProperty = @('SettingName', 'SettingDetails')
                        if (!$showEnrollmentIDs) { $excludeProperty += 'EnrollmentId' }
                        if (!$showURLs) { $excludeProperty += 'PolicyURL' }
                        $resultsWithoutSettings = $resultsWithoutSettings | Select-Object -Property * -exclude $excludeProperty
                        # sort
                        $resultsWithoutSettings = $resultsWithoutSettings | Sort-Object -Property Scope, PolicyName
                        #endregion prepare data

                        # render policies
                        New-HTMLSection -HeaderText 'Policy' -HeaderBackGroundColor Wedgewood -BackgroundColor White {
                            New-HTMLTable -DataTable $resultsWithoutSettings -WordBreak 'break-all' -DisableInfo -HideButtons -DisablePaging -FixedHeader -FixedFooter
                        }
                    }
                }

                if ($resultsWithSettings) {
                    # sort
                    $resultsWithSettings = $resultsWithSettings | Sort-Object -Property Scope, PolicyName

                    # modify inner sections margins
                    $innerSectionStyle = New-HTMLSectionStyle -RequestConfiguration
                    Add-HTMLStyle -Css @{
                        "$($innerSectionStyle.Section)" = @{
                            'margin-bottom' = '20px'
                        }
                    } -SkipTags

                    New-HTMLSection -HeaderText "Policies with settings details" -HeaderTextAlignment left -CanCollapse -BackgroundColor DeepSkyBlue -HeaderBackGroundColor DeepSkyBlue -HeaderTextSize 10 -HeaderTextColor EgyptianBlue -Direction row {
                        $resultsWithSettings | % {
                            $policy = $_
                            $policySetting = $_.settingDetails

                            #region prepare data
                            # exclude some not significant or needed properties
                            # SettingName is useless in HTML report from my point of view
                            # settingDetails will be shown in separate table, omit here
                            $excludeProperty = @('SettingName', 'SettingDetails')
                            if (!$showEnrollmentIDs) { $excludeProperty += 'EnrollmentId' }
                            if (!$showURLs) { $excludeProperty += 'PolicyURL' }

                            $policy = $policy | Select-Object -Property * -ExcludeProperty $excludeProperty
                            #endregion prepare data

                            New-HTMLSection -HeaderText $policy.PolicyName -HeaderTextAlignment left -CanCollapse -BackgroundColor White -HeaderBackGroundColor White -HeaderTextSize 12 -HeaderTextColor EgyptianBlue -StyleSheetsConfiguration $innerSectionStyle {
                                # render main policy
                                New-HTMLSection -HeaderText 'Policy' -HeaderBackGroundColor Wedgewood -BackgroundColor White {
                                    New-HTMLTable -DataTable $policy -WordBreak 'break-all' -HideFooter -DisableInfo -HideButtons -DisablePaging -DisableSearch -DisableOrdering
                                }

                                # render policy settings details
                                if ($policySetting) {
                                    if (@($policySetting).count -eq 1) {
                                        $detailsHTMLTableParam = @{
                                            DisableSearch   = $true
                                            DisableOrdering = $true
                                        }
                                    } else {
                                        $detailsHTMLTableParam = @{}
                                    }
                                    New-HTMLSection -HeaderText 'Policy settings' -HeaderBackGroundColor PictonBlue -BackgroundColor White {
                                        New-HTMLTable @detailsHTMLTableParam -DataTable $policySetting -WordBreak 'break-all' -AllProperties -FixedHeader -HideFooter -DisableInfo -HideButtons -DisablePaging -WarningAction SilentlyContinue {
                                            New-HTMLTableCondition -Name 'WinningProvider' -ComparisonType string -Operator 'ne' -Value 'Intune' -BackgroundColor Red -Color White #-Row
                                            New-HTMLTableCondition -Name 'LastError' -ComparisonType number -Operator 'ne' -Value 0 -BackgroundColor Red -Color White # -Row
                                            New-HTMLTableCondition -Name 'Error' -ComparisonType number -Operator 'ne' -Value 0 -BackgroundColor Red -Color White # -Row
                                            New-HTMLTableCondition -Name 'ErrorCode' -ComparisonType number -Operator 'ne' -Value 0 -BackgroundColor Red -Color White # -Row
                                            New-HTMLTableCondition -Name 'RemediationScriptErrorDetails' -ComparisonType string -Operator 'ne' -Value '' -BackgroundColor Red -Color White # -Row
                                            New-HTMLTableCondition -Name 'RemediationScriptErrorDetails' -ComparisonType string -Operator 'ne' -Value '' -BackgroundColor Red -Color White # -Row
                                            New-HTMLTableCondition -Name 'PreRemediationDetectScriptError' -ComparisonType string -Operator 'ne' -Value '' -BackgroundColor Red -Color White # -Row
                                            New-HTMLTableCondition -Name 'PostRemediationDetectScriptError' -ComparisonType string -Operator 'ne' -Value '' -BackgroundColor Red -Color White # -Row
                                            New-HTMLTableCondition -Name 'RemediationExitCode' -ComparisonType number -Operator 'ne' -Value 0 -BackgroundColor Red -Color White # -Row
                                            New-HTMLTableCondition -Name 'FirstDetectExitCode' -ComparisonType number -Operator 'ne' -Value 0 -BackgroundColor Red -Color White # -Row
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } # end of main HTML section
        }
    } else {
        Write-Verbose "Returning PowerShell object"
        return $intuneXMLReport
    }
    #endregion output the results (as object or HTML report)
}