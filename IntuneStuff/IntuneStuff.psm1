#Requires -Modules Microsoft.Graph.Intune,WindowsAutoPilotIntune

function Connect-MSGraph2 {
    <#
    .SYNOPSIS
    Function for connecting to Microsoft Graph.

    .DESCRIPTION
    Function for connecting to Microsoft Graph.
    Support (interactive) user or application authentication
    Without specifying any parameters, interactive user auth. will be used.

    To use app. auth. tenantId, appId and appSecret parameters have to be specified!
    TIP: you can use credential parameter to pass appId and appSecret securely

    .PARAMETER TenantId
    ID of your tenant.

    Default is $_tenantId.

    .PARAMETER AppId
    Azure AD app ID (GUID) for the application that will be used to authenticate

    .PARAMETER AppSecret
    Specifies the Azure AD app secret corresponding to the app ID that will be used to authenticate.
    Can be generated in Azure > 'App Registrations' > SomeApp > 'Certificates & secrets > 'Client secrets'.

    .PARAMETER Credential
    Credential object that can be used both for user and app authentication.

    .PARAMETER Beta
    Set schema to beta.

    .PARAMETER returnConnection
    Switch for returning connection info (like original Connect-AzureAD command do).

    .EXAMPLE
    Connect-MSGraph2

    Connect to MS Graph interactively using user authentication.

    .EXAMPLE
    Connect-MSGraph2 -TenantId 1111 -AppId 1234 -AppSecret 'pass'

    Connect to MS Graph using app. authentication.

    .EXAMPLE
    Connect-MSGraph2 -TenantId 1111 -credential (Get-Credential)

    Connect to MS Graph using app. authentication. AppId and AppSecret will be extracted from credential object.

    .EXAMPLE
    Connect-MSGraph2 -credential (Get-Credential)

    Connect to MS Graph using user authentication.

    .NOTES
    Requires module Microsoft.Graph.Intune
    #>

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [Alias("Connect-MSGraphApp2")]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "AppAuth")]
        [Parameter(Mandatory = $true, ParameterSetName = "App2Auth")]
        [string] $tenantId = $_tenantId
        ,
        [Parameter(Mandatory = $true, ParameterSetName = "AppAuth")]
        [string] $appId
        ,
        [Parameter(Mandatory = $true, ParameterSetName = "AppAuth")]
        [string] $appSecret
        ,
        [Parameter(Mandatory = $true, ParameterSetName = "App2Auth")]
        [Parameter(Mandatory = $true, ParameterSetName = "UserAuth")]
        [System.Management.Automation.PSCredential] $credential,

        [switch] $beta,

        [switch] $returnConnection
    )

    if (!(Get-Command Connect-MSGraph -ea silent)) {
        throw "Module Microsoft.Graph.Intune is missing"
    }
    if (!(Get-Command Connect-MSGraphApp -ea silent)) {
        throw "Module WindowsAutoPilotIntune is missing"
    }

    if ($beta) {
        if ((Get-MSGraphEnvironment).SchemaVersion -ne "beta") {
            $null = Update-MSGraphEnvironment -SchemaVersion beta
        }
    }

    if ($tenantId -and (($appId -and $appSecret) -or $credential)) {
        Write-Verbose "Authenticating using app auth."

        if (!$appId -and $credential) {
            $appId = $credential.UserName
        }
        if (!$appSecret -and $credential) {
            $appSecret = $credential.GetNetworkCredential().password
        }

        $param = @{
            Tenant      = $tenantId
            AppId       = $appId
            AppSecret   = $appSecret
            ErrorAction = 'Stop'
        }

        if ($returnConnection) {
            Connect-MSGraphApp @param
        } else {
            $null = Connect-MSGraphApp @param
        }
        Write-Verbose "Connected to Intune tenant $tenantId"
    } else {
        Write-Verbose "Authenticating using user auth."

        $param = @{
            ErrorAction = 'Stop'
        }
        if ($credential) {
            $param.Credential = $credential
        }

        if ($returnConnection) {
            Connect-MSGraph @param
        } else {
            $null = Connect-MSGraph @param
        }
        Write-Verbose "Connected to Intune tenant using user authentication"
    }
}

function ConvertFrom-MDMDiagReport {
    <#
    .SYNOPSIS
    Function for converting MDMDiagReport.html to PowerShell object.

    .DESCRIPTION
    Function for converting MDMDiagReport.html to PowerShell object.

    .PARAMETER MDMDiagReport
    Path to MDMDiagReport.html file.
    It will be created if doesn't exist.

    By default "C:\Users\Public\Documents\MDMDiagnostics\MDMDiagReport.html" is checked.

    .PARAMETER showKnobs
    Switch for including knobs results in "Managed Policies" and "Enrolled configuration sources and target resources" tables.
    Knobs seems to be just some internal power related diagnostic data, therefore hidden by default.

    .EXAMPLE
    ConvertFrom-MDMDiagReport

    Converts content of "C:\Users\Public\Documents\MDMDiagnostics\MDMDiagReport.html" (if it doesn't exists, generates first) to PowerShell object.
    #>

    [CmdletBinding()]
    param (
        [ValidateScript( {
                If ($_ -match "\.html$") {
                    $true
                } else {
                    Throw "$_ is not a valid path to MDM html report"
                }
            })]
        [string] $MDMDiagReport = "C:\Users\Public\Documents\MDMDiagnostics\MDMDiagReport.html",

        [switch] $showKnobs
    )

    if (!(Test-Path $MDMDiagReport -PathType Leaf)) {
        Write-Warning "'$MDMDiagReport' doesn't exist, generating..."
        $MDMDiagReportFolder = Split-Path $MDMDiagReport -Parent
        Start-Process MdmDiagnosticsTool.exe -Wait -ArgumentList "-out `"$MDMDiagReportFolder`"" -NoNewWindow
    }

    # hardcoded titles from MDMDiagReport.html report
    $MDMDiagReportTable = @{
        1  = "Device Info"
        2  = "Connection Info"
        3  = "Device Management Account"
        4  = "Certificates"
        5  = "Enrolled configuration sources and target resources"
        6  = "Managed Policies"
        7  = "Managed applications"
        8  = "GPCSEWrapper Policies"
        9  = "Blocked Group Policies"
        10 = "Unmanaged policies"
    }

    $result = [ordered]@{}
    $tableOrder = 1

    $Source = Get-Content $MDMDiagReport -Raw
    $HTML = New-Object -Com "HTMLFile"
    $HTML.IHTMLDocument2_write($Source)
    $HTML.body.getElementsByTagName('table') | % {
        $tableName = $MDMDiagReportTable.$tableOrder -replace " ", "_"
        if (!$tableName) { throw "Undefined tableName" }

        $result.$tableName = ConvertFrom-HTMLTable $_ -tableName $tableName

        if ($tableName -eq "Managed_Policies" -and !$showKnobs) {
            $result.$tableName = $result.$tableName | ? { $_.Area -ne "knobs" }
        } elseif ($tableName -eq "Enrolled_configuration_sources_and_target_resources" -and !$showKnobs) {
            # all provisioning sources are knobs
            $result.$tableName = $result.$tableName | ? { $_.'Configuration source' -ne "Provisioning" }
        }

        ++$tableOrder
    }

    New-Object -TypeName PSObject -Property $result
}

function ConvertFrom-MDMDiagReportXML {
    <#
    .SYNOPSIS
    Function for converting Intune XML report generated by MdmDiagnosticsTool.exe to a PowerShell object.

    .DESCRIPTION
    Function for converting Intune XML report generated by MdmDiagnosticsTool.exe to a PowerShell object.
    There is also option to generate HTML report instead.

    .PARAMETER computerName
    (optional) Computer name from which you want to get data from.

    .PARAMETER MDMDiagReport
    Path to MDMDiagReport.xml.

    If not specified, new report will be generated and used.

    .PARAMETER asHTML
    Switch for outputting results as a HTML page instead of PowerShell object.
    PSWriteHtml module is required!

    .PARAMETER HTMLReportPath
    Path to html file where HTML report should be stored.

    Default is '<yourUserProfile>\IntuneReport.html'.

    .PARAMETER showEnrollmentIDs
    Switch for adding EnrollmentID property i.e. property containing Enrollment ID of given policy.
    From my point of view its useless :).

    .PARAMETER showURLs
    Switch for adding PolicyURL and PolicySettingsURL properties i.e. properties containing URL with Microsoft documentation for given CSP.

    Make running the function slower! Because I test each URL and shows just existing ones.

    .PARAMETER showConnectionData
    Switch for showing Intune connection data.
    Beware that this will add new object type to the output (but it doesn't matter if you use asHTML switch).

    .EXAMPLE
    $intuneReport = ConvertFrom-MDMDiagReportXML
    $intuneReport | Out-GridView

    Generates new Intune report, converts it into PowerShell object and output it using Out-GridView.

    .EXAMPLE
    ConvertFrom-MDMDiagReportXML -asHTML -showURLs

    Generates new Intune report (policies documentation URL included), converts it into HTML web page and opens it.
    #>

    [CmdletBinding()]
    param (
        [string] $computerName,

        [ValidateScript( {
                if ($_ -match "\.xml$") {
                    $true
                } else {
                    throw "$_ is not a valid path to MDM xml report"
                }
            })]
        [string] $MDMDiagReport,

        [switch] $asHTML,

        [ValidateScript( {
                if ($_ -match "\.html$") {
                    $true
                } else {
                    throw "$_ is not a valid path to html file. Enter something like 'C:\destination\intune.html'"
                }
            })]
        [string] $HTMLReportPath = (Join-Path $env:USERPROFILE "IntuneReport.html"),

        [switch] $showEnrollmentIDs,

        [switch] $showURLs,

        [switch] $showConnectionData
    )

    if ($asHTML) {
        # array of results that will be in the end transformed into HTML report
        $results = @()

        if (!(Get-Module 'PSWriteHtml') -and (!(Get-Module 'PSWriteHtml' -ListAvailable))) {
            throw "Module PSWriteHtml is missing. To get it use command: Install-Module PSWriteHtml -Scope CurrentUser"
        }

        # create parent directory if not exists
        [Void][System.IO.Directory]::CreateDirectory((Split-Path $HTMLReportPath -Parent))
    }

    if ($computerName) {
        $session = New-PSSession -ComputerName $computerName -ErrorAction Stop
    }

    if (!$MDMDiagReport) {
        ++$reportNotSpecified
        $MDMDiagReport = "$env:PUBLIC\Documents\MDMDiagnostics\MDMDiagReport.xml"
    }

    $MDMDiagReportFolder = Split-Path $MDMDiagReport -Parent

    # generate XML report if necessary
    if ($reportNotSpecified) {
        if ($computerName) {
            # XML report is on remote computer, transform to UNC path
            $MDMDiagReport = "\\$computerName\$($MDMDiagReport -replace ":", "$")"
            Write-Verbose "Generating '$MDMDiagReport'..."

            try {
                Invoke-Command -Session $session {
                    param ($MDMDiagReportFolder)

                    Start-Process MdmDiagnosticsTool.exe -Wait -ArgumentList "-out `"$MDMDiagReportFolder`"" -NoNewWindow -ErrorAction Stop
                } -ArgumentList $MDMDiagReportFolder -ErrorAction Stop
            } catch {
                throw "Unable to generate XML report`nError: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)"
            }
        } else {
            Write-Verbose "Generating '$MDMDiagReport'..."
            Start-Process MdmDiagnosticsTool.exe -Wait -ArgumentList "-out `"$MDMDiagReportFolder`"" -NoNewWindow
        }
    }
    if (!(Test-Path $MDMDiagReport -PathType Leaf)) {
        Write-Verbose "'$MDMDiagReport' doesn't exist, generating..."
        Start-Process MdmDiagnosticsTool.exe -Wait -ArgumentList "-out `"$MDMDiagReportFolder`"" -NoNewWindow
    }

    Write-Verbose "Converting '$MDMDiagReport' to XML object"
    [xml]$xml = Get-Content $MDMDiagReport -Raw -ErrorAction Stop

    #region get enrollmentID
    Write-Verbose "Getting EnrollmentID"

    $scriptBlock = {
        Get-ScheduledTask -TaskName "*pushlaunch*" -TaskPath "\Microsoft\Windows\EnterpriseMgmt\*" | Select-Object -ExpandProperty TaskPath | Split-Path -Leaf
    }
    $param = @{
        scriptBlock = $scriptBlock
    }
    if ($computerName) {
        $param.session = $session
    }

    $userEnrollmentID = Invoke-Command @param

    Write-Verbose "Your EnrollmentID is $userEnrollmentID"
    #endregion get enrollmentID

    #region connection data
    if ($showConnectionData) {
        Write-Verbose "Getting connection data"
        $connectionInfo = $xml.MDMEnterpriseDiagnosticsReport.DeviceManagementAccount.Enrollment | ? EnrollmentId -EQ $userEnrollmentID

        if ($connectionInfo) {
            [PSCustomObject]@{
                "EnrollmentId"          = $connectionInfo.EnrollmentId
                "MDMServerName"         = $connectionInfo.ProtectedInformation.MDMServerName
                "LastSuccessConnection" = [DateTime]::ParseExact(($connectionInfo.ProtectedInformation.ConnectionInformation.ServerLastSuccessTime -replace "Z$"), 'yyyyMMddTHHmmss', $null)
                "LastFailureConnection" = [DateTime]::ParseExact(($connectionInfo.ProtectedInformation.ConnectionInformation.ServerLastFailureTime -replace "Z$"), 'yyyyMMddTHHmmss', $null)
            }
        } else {
            Write-Verbose "Unable to get connection data from $MDMDiagReport"
        }
    }
    #endregion connection data

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
                if ($computerName) {
                    Invoke-Command -Session $session {
                        param ($id)

                        $ErrorActionPreference = "Stop"
                        try {
                            return ((New-Object System.Security.Principal.SecurityIdentifier($id)).Translate([System.Security.Principal.NTAccount])).Value
                        } catch {
                            throw 1
                        }
                    } -ArgumentList $id
                } else {
                    return ((New-Object System.Security.Principal.SecurityIdentifier($id)).Translate([System.Security.Principal.NTAccount])).Value
                }
            } else {
                # it is AzureAD account
                if ($getDataFromIntune) {
                    return (Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/users/$id").userPrincipalName
                } else {
                    # unable to translate ID to name because there is no connection to the Intune Graph API
                    return $id
                }
            }
        } catch {
            Write-Verbose "Unable to translate $id account name"
            $ErrorActionPreference = $errPref
            return $id
        }
    }

    function Test-URLStatus {
        param ($URL)

        try {
            $response = [System.Net.WebRequest]::Create($URL).GetResponse()
            $status = $response.StatusCode
            $response.Close()
            if ($status -eq 'OK') { return $true } else { return $false }
        } catch {
            return $false
        }
    }

    function _translateStatus {
        param ([int] $statusCode)

        $statusMessage = ""

        switch ($statusCode) {
            '10' { $statusMessage = "Initialized" }
            '20' { $statusMessage = "Download In Progress" }
            '25' { $statusMessage = "Pending Download Retry" }
            '30' { $statusMessage = "Download Failed" }
            '40' { $statusMessage = "Download Completed" }
            '48' { $statusMessage = "Pending User Session" }
            '50' { $statusMessage = "Enforcement In Progress" }
            '55' { $statusMessage = "Pending Enforcement Retry" }
            '60' { $statusMessage = "Enforcement Failed" }
            '70' { $statusMessage = "Enforcement Completed" }
            default { $statusMessage = $statusCode }
        }

        return $statusMessage
    }
    #endregion helper functions

    if ($showURLs) {
        $clientIsOnline = Test-URLStatus 'https://google.com'
    }

    #region enrollments
    Write-Verbose "Getting Enrollments (MDMEnterpriseDiagnosticsReport.Resources.Enrollment)"
    $enrollment = $xml.MDMEnterpriseDiagnosticsReport.Resources.Enrollment | % { ConvertFrom-XML $_ }

    if ($enrollment) {
        Write-Verbose "Processing Enrollments"

        $enrollment | % {
            <#
            <Resources>
                <Enrollment>
                    <EnrollmentID>5AFCD0A0-321F-4635-B3EB-2EBD28A0FD9A</EnrollmentID>
                    <Scope>
                    <ResourceTarget>device</ResourceTarget>
                    <Resources>
                        <Type>default</Type>
                        <ResourceName>./device/Vendor/MSFT/DeviceManageability/Provider/WMI_Bridge_Server</ResourceName>
                        <ResourceName>2</ResourceName>
                        <ResourceName>./device/Vendor/MSFT/VPNv2/K_AlwaysOn_VPN</ResourceName>
                    </Resources>
                    </Scope>
            #>
            $policy = $_
            $enrollmentId = $_.EnrollmentId

            $policy.Scope | % {
                $scope = _getTargetName $_.ResourceTarget

                foreach ($policyAreaName in $_.Resources.ResourceName) {
                    # some policies have just number instead of any name..I don't know what it means so I ignore them
                    if ($policyAreaName -match "^\d+$") {
                        continue
                    }
                    # get rid of MSI installations (I have them with details in separate section)
                    if ($policyAreaName -match "/Vendor/MSFT/EnterpriseDesktopAppManagement/MSI") {
                        continue
                    }
                    # get rid of useless data
                    if ($policyAreaName -match "device/Vendor/MSFT/DeviceManageability/Provider/WMI_Bridge_Server") {
                        continue
                    }

                    Write-Verbose "`nEnrollment '$enrollmentId' applied to '$scope' configures resource '$policyAreaName'"

                    #region get policy settings details
                    $settingDetails = $null
                    #TODO zjistit co presne to nastavuje
                    # - policymanager.configsource.policyscope.Area

                    <#
                    <ErrorLog>
                        <Component>ConfigManager</Component>
                        <SubComponent>
                            <Name>BitLocker</Name>
                            <Error>-2147024463</Error>
                            <Metadata1>CmdType_Set</Metadata1>
                            <Metadata2>./Device/Vendor/MSFT/BitLocker/RequireDeviceEncryption</Metadata2>
                            <Time>2021-09-23 07:07:05.463</Time>
                        </SubComponent>
                    #>
                    Write-Verbose "Getting Errors (MDMEnterpriseDiagnosticsReport.Diagnostics.ErrorLog)"
                    # match operator used for metadata2 because for example WIFI networks are saved there as ./Vendor/MSFT/WiFi/Profile/<wifiname> instead of ./Vendor/MSFT/WiFi/Profile
                    foreach ($errorRecord in $xml.MDMEnterpriseDiagnosticsReport.Diagnostics.ErrorLog) {
                        $component = $errorRecord.component
                        $errorRecord.subComponent | % {
                            $subComponent = $_

                            if ($subComponent.name -eq $policyAreaName -or $subComponent.Metadata2 -match [regex]::Escape($policyAreaName)) {
                                $settingDetails = $subComponent | Select-Object @{n = 'Component'; e = { $component } }, @{n = 'SubComponent'; e = { $subComponent.Name } }, @{n = 'SettingName'; e = { $policyAreaName } }, Error, @{n = 'Time'; e = { Get-Date $subComponent.Time } }
                                break
                            }
                        }
                    }

                    if (!$settingDetails) {
                        # try more "relaxed" search
                        if ($policyAreaName -match "/") {
                            # it is just common setting, try to find it using last part of the policy name
                            $policyAreaNameID = ($policyAreaName -split "/")[-1]
                            Write-Verbose "try to find just ID part ($policyAreaNameID) of the policy name in MDMEnterpriseDiagnosticsReport.Diagnostics.ErrorLog"
                            # I don't search substring of policy name in Metadata2 because there can be multiple similar policies (./user/Vendor/MSFT/VPNv2/VPN_Backup vs ./device/Vendor/MSFT/VPNv2/VPN_Backup)
                            foreach ($errorRecord in $xml.MDMEnterpriseDiagnosticsReport.Diagnostics.ErrorLog) {
                                $component = $errorRecord.component
                                $errorRecord.subComponent | % {
                                    $subComponent = $_

                                    if ($subComponent.name -eq $policyAreaNameID) {
                                        $settingDetails = $subComponent | Select-Object @{n = 'Component'; e = { $component } }, @{n = 'SubComponent'; e = { $subComponent.Name } }, @{n = 'SettingName'; e = { $policyAreaName } }, Error, @{n = 'Time'; e = { Get-Date $subComponent.Time } }
                                        break
                                    }
                                }
                            }
                        } else {
                            Write-Verbose "'$policyAreaName' doesn't contains '/'"
                        }

                        if (!$settingDetails) {
                            Write-Verbose "No additional data was found for '$policyAreaName' (it means it was successfully applied)"
                        }
                    }
                    #endregion get policy settings details

                    # get CSP policy URL if available
                    if ($showURLs) {
                        if ($policyAreaName -match "/") {
                            $pName = ($policyAreaName -split "/")[-2]
                        } else {
                            $pName = $policyAreaName
                        }
                        $policyURL = "https://docs.microsoft.com/en-us/windows/client-management/mdm/$pName-csp"
                        # check that URL exists
                        if ($clientIsOnline) {
                            if (!(Test-URLStatus $policyURL)) {
                                # URL doesn't exist
                                if ($policyAreaName -match "/") {
                                    # sometimes name of the CSP is not second from the end but third
                                    $pName = ($policyAreaName -split "/")[-3]
                                    $policyURL = "https://docs.microsoft.com/en-us/windows/client-management/mdm/$pName-csp"
                                    if (!(Test-URLStatus $policyURL)) {
                                        $policyURL = $null
                                    }
                                } else {
                                    $policyURL = "https://docs.microsoft.com/en-us/windows/client-management/mdm/policy-csp-$pName"
                                    if (!(Test-URLStatus $policyURL)) {
                                        $policyURL = $null
                                    }
                                }
                            }
                        }
                    }

                    #region return retrieved data
                    $property = [ordered] @{
                        Scope          = $scope
                        PolicyName     = $policyAreaName
                        SettingName    = $policyAreaName
                        SettingDetails = $settingDetails
                    }
                    if ($showEnrollmentIDs) { $property.EnrollmentId = $enrollmentId }
                    if ($showURLs) { $property.PolicyURL = $policyURL }
                    $result = New-Object -TypeName PSObject -Property $property

                    if ($asHTML) {
                        $results += $result
                    } else {
                        $result
                    }
                    #endregion return retrieved data
                }
            }
        }
    }
    #endregion enrollments

    #region policies
    Write-Verbose "Getting Policies (MDMEnterpriseDiagnosticsReport.PolicyManager.ConfigSource)"
    $policyManager = $xml.MDMEnterpriseDiagnosticsReport.PolicyManager.ConfigSource | % { ConvertFrom-XML $_ }
    # filter out useless knobs
    $policyManager = $policyManager | ? { $_.policyScope.Area.PolicyAreaName -ne 'knobs' }

    if ($policyManager) {
        Write-Verbose "Processing Policies"

        # get policies metadata
        Write-Verbose "Getting Policies Area metadata (MDMEnterpriseDiagnosticsReport.PolicyManager.AreaMetadata)"
        $policyAreaNameMetadata = $xml.MDMEnterpriseDiagnosticsReport.PolicyManager.AreaMetadata
        # get admx policies metadata
        # there are duplicities, so pick just last one
        Write-Verbose "Getting Policies ADMX metadata (MDMEnterpriseDiagnosticsReport.PolicyManager.IngestedAdmxPolicyMetadata)"
        $admxPolicyAreaNameMetadata = $xml.MDMEnterpriseDiagnosticsReport.PolicyManager.IngestedAdmxPolicyMetadata | % { ConvertFrom-XML $_ }

        Write-Verbose "Getting Policies winning provider (MDMEnterpriseDiagnosticsReport.PolicyManager.CurrentPolicies.CurrentPolicyValues)"
        $winningProviderPolicyAreaNameMetadata = $xml.MDMEnterpriseDiagnosticsReport.PolicyManager.CurrentPolicies.CurrentPolicyValues | % {
            $_.psobject.properties | ? { $_.Name -Match "_WinningProvider$" } | Select-Object Name, Value
        }

        $policyManager | % {
            $policy = $_
            $enrollmentId = $_.EnrollmentId

            $policy.policyScope | % {
                $scope = _getTargetName $_.PolicyScope
                $_.Area | % {
                    <#
                    <ConfigSource>
                        <EnrollmentId>AB068787-67D2-4F7C-AA87-A9127A87411F</EnrollmentId>
                        <PolicyScope>
                            <PolicyScope>Device</PolicyScope>
                            <Area>
                                <PolicyAreaName>BitLocker</PolicyAreaName>
                                <AllowWarningForOtherDiskEncryption>0</AllowWarningForOtherDiskEncryption>
                                <AllowWarningForOtherDiskEncryption_LastWrite>1</AllowWarningForOtherDiskEncryption_LastWrite>
                                <RequireDeviceEncryption>1</RequireDeviceEncryption>
                    #>

                    $policyAreaName = $_.PolicyAreaName
                    Write-Verbose "`nEnrollment '$enrollmentId' applied to '$scope' configures area '$policyAreaName'"
                    $policyAreaSetting = $_ | Select-Object -Property * -ExcludeProperty 'PolicyAreaName', "*_LastWrite"
                    $policyAreaSettingName = $policyAreaSetting | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty name
                    if ($policyAreaSettingName.count -eq 1 -and $policyAreaSettingName -eq "*") {
                        # bug? when there is just PolicyAreaName and none other object than probably because of exclude $policyAreaSettingName instead of be null returns one empty object '*'
                        $policyAreaSettingName = $null
                        $policyAreaSetting = $null
                    }

                    #region get policy settings details
                    $settingDetails = @()

                    if ($policyAreaSetting) {
                        Write-Verbose "`tIt configures these settings:"

                        # $policyAreaSetting is object, so I have to iterate through its properties
                        foreach ($setting in $policyAreaSetting.PSObject.Properties) {
                            $settingName = $setting.Name
                            $settingValue = $setting.Value

                            # PolicyAreaName property was already picked up so now I will ignore it
                            if ($settingName -eq "PolicyAreaName") { continue }

                            Write-Verbose "`t`t- $settingName ($settingValue)"

                            # makes test of url slow
                            # if ($clientIsOnline) {
                            #     if (!(Test-URLStatus $policyDetailsURL)) {
                            #         # URL doesn't exist
                            #         $policyDetailsURL = $null
                            #     }
                            # }

                            if ($showURLs) {
                                if ($policyAreaName -match "~Policy~OneDriveNGSC") {
                                    # doesn't have policy csp url
                                    $policyDetailsURL = $null
                                } else {
                                    $policyDetailsURL = "https://docs.microsoft.com/en-us/windows/client-management/mdm/policy-csp-$policyAreaName#$(($policyAreaName).tolower())-$(($settingName).tolower())"
                                }
                            }

                            # define base object
                            $property = [ordered]@{
                                "SettingName"     = $settingName
                                "Value"           = $settingValue
                                "DefaultValue"    = $null
                                "PolicyType"      = '*unknown*'
                                "RegKey"          = '*unknown*'
                                "RegValueName"    = '*unknown*'
                                "SourceAdmxFile"  = $null
                                "WinningProvider" = $null
                            }
                            if ($showURLs) { $property.PolicyDetailsURL = $policyDetailsURL }

                            $additionalData = $policyAreaNameMetadata | ? PolicyAreaName -EQ $policyAreaName | Select-Object -ExpandProperty PolicyMetadata | ? PolicyName -EQ $settingName | Select-Object PolicyType, Value, RegKeyPathRedirect, RegValueNameRedirect

                            if ($additionalData) {
                                Write-Verbose "Additional data for '$settingName' was found in policyAreaNameMetadata"
                                <#
                                <PolicyMetadata>
                                    <PolicyName>RecoveryEnvironmentAuthentication</PolicyName>
                                    <Behavior>49</Behavior>
                                    <highrange>2</highrange>
                                    <lowrange>0</lowrange>
                                    <mergealgorithm>3</mergealgorithm>
                                    <policytype>4</policytype>
                                    <RegKeyPathRedirect>Software\Policies\Microsoft\WinRE</RegKeyPathRedirect>
                                    <RegValueNameRedirect>WinREAuthenticationRequirement</RegValueNameRedirect>
                                    <value>0</value>
                                </PolicyMetadata>
                                #>
                                $property.DefaultValue = $additionalData.Value
                                $property.PolicyType = $additionalData.PolicyType
                                $property.RegKey = $additionalData.RegKeyPathRedirect
                                $property.RegValueName = $additionalData.RegValueNameRedirect
                            } else {
                                # no additional data was found in policyAreaNameMetadata
                                # trying to get them from admxPolicyAreaNameMetadata

                                <#
                                <IngestedADMXPolicyMetaData>
                                    <EnrollmentId>11120759-7CE3-4683-AB59-46C27FF40D35</EnrollmentId>
                                    <AreaName>
                                        <ADMXIngestedAreaName>OneDriveNGSCv2~Policy~OneDriveNGSC</ADMXIngestedAreaName>
                                        <PolicyMetadata>
                                            <PolicyName>BlockExternalSync</PolicyName>
                                            <SourceAdmxFile>OneDriveNGSCv2</SourceAdmxFile>
                                            <Behavior>224</Behavior>
                                            <MergeAlgorithm>3</MergeAlgorithm>
                                            <RegKeyPathRedirect>SOFTWARE\Policies\Microsoft\OneDrive</RegKeyPathRedirect>
                                            <RegValueNameRedirect>BlockExternalSync</RegValueNameRedirect>
                                            <PolicyType>1</PolicyType>
                                            <AdmxMetadataDevice>30313D0100000000323D000000000000</AdmxMetadataDevice>
                                        </PolicyMetadata>
                                #>
                                $additionalData = ($admxPolicyAreaNameMetadata.AreaName | ? { $_.ADMXIngestedAreaName -eq $policyAreaName }).PolicyMetadata | ? { $_.PolicyName -EQ $settingName } | select -First 1 # sometimes there are duplicities in results

                                if ($additionalData) {
                                    Write-Verbose "Additional data for '$settingName' was found in admxPolicyAreaNameMetadata"
                                    $property.PolicyType = $additionalData.PolicyType
                                    $property.RegKey = $additionalData.RegKeyPathRedirect
                                    $property.RegValueName = $additionalData.RegValueNameRedirect
                                    $property.SourceAdmxFile = $additionalData.SourceAdmxFile
                                } else {
                                    Write-Verbose "No additional data found for $settingName"
                                }
                            }

                            $winningProvider = $winningProviderPolicyAreaNameMetadata | ? Name -EQ "$settingName`_WinningProvider" | Select-Object -ExpandProperty Value
                            if ($winningProvider) {
                                if ($winningProvider -eq $userEnrollmentID) {
                                    $winningProvider = 'Intune'
                                }

                                $property.WinningProvider = $winningProvider
                            }

                            $settingDetails += New-Object -TypeName PSObject -Property $property
                        }
                    } else {
                        Write-Verbose "`tIt doesn't contain any settings"
                    }
                    #endregion get policy settings details

                    # get CSP policy URL if available
                    if ($showURLs) {
                        if ($policyAreaName -match "/") {
                            $pName = ($policyAreaName -split "/")[-2]
                        } else {
                            $pName = $policyAreaName
                        }
                        $policyURL = "https://docs.microsoft.com/en-us/windows/client-management/mdm/$pName-csp"
                        # check that URL exists
                        if ($clientIsOnline) {
                            if (!(Test-URLStatus $policyURL)) {
                                # URL doesn't exist
                                if ($policyAreaName -match "/") {
                                    # sometimes name of the CSP is not second from the end but third
                                    $pName = ($policyAreaName -split "/")[-3]
                                    $policyURL = "https://docs.microsoft.com/en-us/windows/client-management/mdm/$pName-csp"
                                    if (!(Test-URLStatus $policyURL)) {
                                        $policyURL = $null
                                    }
                                } else {
                                    $policyURL = "https://docs.microsoft.com/en-us/windows/client-management/mdm/policy-csp-$pName"
                                    if (!(Test-URLStatus $policyURL)) {
                                        $policyURL = $null
                                    }
                                }
                            }
                        }
                    }

                    #region return retrieved data
                    $property = [ordered] @{
                        Scope          = $scope
                        PolicyName     = $policyAreaName
                        SettingName    = $policyAreaSettingName
                        SettingDetails = $settingDetails
                    }
                    if ($showEnrollmentIDs) { $property.EnrollmentId = $enrollmentId }
                    if ($showURLs) { $property.PolicyURL = $policyURL }
                    $result = New-Object -TypeName PSObject -Property $property

                    if ($asHTML) {
                        $results += $result
                    } else {
                        $result
                    }
                    #endregion return retrieved data
                }
            }
        }
    }
    #endregion policies

    #region installations
    Write-Verbose "Getting MSI installations (MDMEnterpriseDiagnosticsReport.EnterpriseDesktopAppManagementinfo.MsiInstallations)"
    $installation = $xml.MDMEnterpriseDiagnosticsReport.EnterpriseDesktopAppManagementinfo.MsiInstallations | % { ConvertFrom-XML $_ }
    if ($installation) {
        Write-Verbose "Processing MSI installations"

        $settingDetails = @()

        $installation.TargetedUser | % {
            <#
            <MsiInstallations>
                <TargetedUser>
                <UserSid>S-0-0-00-0000000000-0000000000-000000000-000</UserSid>
                <Package>
                    <Type>MSI</Type>
                    <Details>
                    <PackageId>{23170F69-40C1-2702-1900-000001000000}</PackageId>
                    <DownloadInstall>Ready</DownloadInstall>
                    <ProductCode>{23170F69-40C1-2702-1900-000001000000}</ProductCode>
                    <ProductVersion>19.00.00.0</ProductVersion>
                    <ActionType>1</ActionType>
                    <Status>70</Status>
                    <JobStatusReport>1</JobStatusReport>
                    <LastError>0</LastError>
                    <BITSJobId></BITSJobId>
                    <DownloadLocation></DownloadLocation>
                    <CurrentDownloadUrlIndex>0</CurrentDownloadUrlIndex>
                    <CurrentDownloadUrl></CurrentDownloadUrl>
                    <FileHash>A7803233EEDB6A4B59B3024CCF9292A6FFFB94507DC998AA67C5B745D197A5DC</FileHash>
                    <CommandLine>ALLUSERS=1</CommandLine>
                    <AssignmentType>1</AssignmentType>
                    <EnforcementTimeout>30</EnforcementTimeout>
                    <EnforcementRetryIndex>0</EnforcementRetryIndex>
                    <EnforcementRetryCount>5</EnforcementRetryCount>
                    <EnforcementRetryInterval>3</EnforcementRetryInterval>
                    <LocURI>./Device/Vendor/MSFT/EnterpriseDesktopAppManagement/MSI/{23170F69-40C1-2702-1900-000001000000}/DownloadInstall</LocURI>
                    <ServerAccountID>11120759-7CE3-4683-FB59-46C27FF40D35</ServerAccountID>
                    </Details>
            #>

            $userSID = $_.UserSid
            $type = $_.Package.Type
            $details = $_.Package.details

            $details | % {
                Write-Verbose "`t$($_.PackageId) of type $type"

                # define base object
                $property = [ordered]@{
                    "Scope"          = _getTargetName $userSID
                    "Type"           = $type
                    "Status"         = _translateStatus $_.Status
                    "LastError"      = $_.LastError
                    "ProductVersion" = $_.ProductVersion
                    "CommandLine"    = $_.CommandLine
                    "RetryIndex"     = $_.EnforcementRetryIndex
                    "MaxRetryCount"  = $_.EnforcementRetryCount
                    "PackageId"      = $_.PackageId -replace "{" -replace "}"
                }
                $settingDetails += New-Object -TypeName PSObject -Property $property
            }
        }

        #region return retrieved data
        $property = [ordered] @{
            Scope          = $null
            PolicyName     = "SoftwareInstallation" # made up!
            SettingName    = $null
            SettingDetails = $settingDetails
        }
        if ($showEnrollmentIDs) { $property.EnrollmentId = $null }
        if ($showURLs) { $property.PolicyURL = $null } # this property only to have same properties for all returned objects
        $result = New-Object -TypeName PSObject -Property $property

        if ($asHTML) {
            $results += $result
        } else {
            $result
        }
        #endregion return retrieved data
    }
    #endregion installations

    #region convert results to HTML and output
    if ($asHTML -and $results) {
        Write-Verbose "Converting to HTML"

        # split the results
        $resultsWithSettings = @()
        $resultsWithoutSettings = @()
        $results | % {
            if ($_.settingDetails) {
                $resultsWithSettings += $_
            } else {
                $resultsWithoutSettings += $_
            }
        }

        New-HTML -TitleText "Intune Report" -Online -FilePath $HTMLReportPath -ShowHTML {
            # it looks better to have headers and content in center
            New-HTMLTableStyle -TextAlign center

            New-HTMLSection -HeaderText 'Intune Report' -Direction row -HeaderBackGroundColor Black -HeaderTextColor White -HeaderTextSize 20 {
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
                    New-HTMLSection -HeaderText "Policies with settings details" -HeaderTextAlignment left -CanCollapse -BackgroundColor DeepSkyBlue -HeaderBackGroundColor DeepSkyBlue -HeaderTextSize 10 -HeaderTextColor EgyptianBlue -Direction row {
                        # sort
                        $resultsWithSettings = $resultsWithSettings | Sort-Object -Property Scope, PolicyName

                        $resultsWithSettings | % {
                            $policy = $_
                            $policySetting = $_.settingDetails

                            #region prepare data
                            # exclude some not significant or needed properties
                            # SettingName is useless in HTML report from my point of view
                            # settingDetails will be shown in separate table, omit here
                            if ($showEnrollmentIDs) {
                                $excludeProperty = 'SettingName', 'SettingDetails'
                            } else {
                                $excludeProperty = 'SettingName', 'SettingDetails', 'EnrollmentId'
                            }

                            $policy = $policy | Select-Object -Property * -ExcludeProperty $excludeProperty
                            #endregion prepare data

                            New-HTMLSection -HeaderText $policy.PolicyName -HeaderTextAlignment left -CanCollapse -BackgroundColor White -HeaderBackGroundColor White -HeaderTextSize 12 -HeaderTextColor EgyptianBlue {
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
                                        }
                                    }
                                }
                            }

                            # hack for getting new line between sections
                            New-HTMLText -Text '.' -Color DeepSkyBlue
                        }
                    }
                }
            } # end of main HTML section
        }
    }
    #endregion convert results to HTML and output

    if ($computerName) {
        Remove-PSSession $session
    }
}

#Requires -Modules AzureRM.Profile

function Get-BitlockerEscrowStatusForAzureADDevices {
    <#
      .SYNOPSIS
      Retrieves bitlocker key upload status for all azure ad devices

      .DESCRIPTION
      Use this report to determine which of your devices have backed up their bitlocker key to AzureAD (and find those that haven't and are at risk of data loss!).
      Report will be stored in current folder.

      .PARAMETER Credential
      Optional, pass a credential object to automatically sign in to Azure AD. Global Admin permissions required

      .PARAMETER showBitlockerKeysInReport
      Switch, is supplied, will show the actual recovery keys in the report. Be careful where you distribute the report to if you use this

      .PARAMETER showAllOSTypesInReport
      By default, only the Windows OS is reported on, if for some reason you like the additional information this report gives you about devices in general, you can add this switch to show all OS types

      .EXAMPLE
      Get-BitlockerEscrowStatusForAzureADDevices | ? {$_.DeviceAccountEnabled -and $_.'OS Drive encrypted' -and $_.OS -eq "Windows" -and !$_.lastKeyUploadDate}

      Returns devices with enabled Bitlocker but no recovery key in Azure

      .NOTES
      filename: get-bitlockerEscrowStatusForAzureADDevices.ps1
      author: Jos Lieben
      blog: www.lieben.nu
      created: 9/4/2019
    #>

    [cmdletbinding()]
    Param(
        $Credential,

        [Switch]$showBitlockerKeysInReport,

        [Switch]$showAllOSTypesInReport
    )

    Import-Module AzureRM.Profile -ErrorAction Stop
    if (!(Get-Module -Name "AzureADPreview", "AzureAD" -ListAvailable)) {
        throw "AzureADPreview nor AzureAD module is available"
    }
    if (Get-Module -Name "AzureADPreview" -ListAvailable) {
        Import-Module AzureADPreview
    } elseif (Get-Module -Name "AzureAD" -ListAvailable) {
        Import-Module AzureAD
    }

    if ($Credential) {
        Try {
            Connect-AzureAD -Credential $Credential -ErrorAction Stop | Out-Null
        } Catch {
            Write-Warning "Couldn't connect to Azure AD non-interactively, trying interactively."
            Connect-AzureAD -TenantId $(($Credential.UserName.Split("@"))[1]) -ErrorAction Stop | Out-Null
        }

        Try {
            Login-AzureRmAccount -Credential $Credential -ErrorAction Stop | Out-Null
        } Catch {
            Write-Warning "Couldn't connect to Azure RM non-interactively, trying interactively."
            Login-AzureRmAccount -TenantId $(($Credential.UserName.Split("@"))[1]) -ErrorAction Stop | Out-Null
        }
    } else {
        Login-AzureRmAccount -ErrorAction Stop | Out-Null
    }
    $context = Get-AzureRmContext
    $tenantId = $context.Tenant.Id
    $refreshToken = @($context.TokenCache.ReadItems() | where { $_.tenantId -eq $tenantId -and $_.ExpiresOn -gt (Get-Date) })[0].RefreshToken
    $body = "grant_type=refresh_token&refresh_token=$($refreshToken)&resource=74658136-14ec-4630-ad9b-26e160ff0fc6"
    $apiToken = Invoke-RestMethod "https://login.windows.net/$tenantId/oauth2/token" -Method POST -Body $body -ContentType 'application/x-www-form-urlencoded'
    $restHeader = @{
        'Authorization'          = 'Bearer ' + $apiToken.access_token
        'X-Requested-With'       = 'XMLHttpRequest'
        'x-ms-client-request-id' = [guid]::NewGuid()
        'x-ms-correlation-id'    = [guid]::NewGuid()
    }
    Write-Verbose "Connected, retrieving devices..."
    $restResult = Invoke-RestMethod -Method GET -UseBasicParsing -Uri "https://main.iam.ad.ext.azure.com/api/Devices?nextLink=&queryParams=%7B%22searchText%22%3A%22%22%7D&top=15" -Headers $restHeader
    $allDevices = @()
    $allDevices += $restResult.value
    while ($restResult.nextLink) {
        $restResult = Invoke-RestMethod -Method GET -UseBasicParsing -Uri "https://main.iam.ad.ext.azure.com/api/Devices?nextLink=$([System.Web.HttpUtility]::UrlEncode($restResult.nextLink))&queryParams=%7B%22searchText%22%3A%22%22%7D&top=15" -Headers $restHeader
        $allDevices += $restResult.value
    }

    Write-Verbose "Retrieved $($allDevices.Count) devices from AzureAD, processing information..."

    $csvEntries = @()
    foreach ($device in $allDevices) {
        if (!$showAllOSTypesInReport -and $device.deviceOSType -notlike "Windows*") {
            Continue
        }
        $keysKnownToAzure = $False
        $osDriveEncrypted = $False
        $lastKeyUploadDate = $Null
        if ($device.deviceOSType -eq "Windows" -and $device.bitLockerKey.Count -gt 0) {
            $keysKnownToAzure = $True
            $keys = $device.bitLockerKey | Sort-Object -Property creationTime -Descending
            if ($keys.driveType -contains "Operating system drive") {
                $osDriveEncrypted = $True
            }
            $lastKeyUploadDate = $keys[0].creationTime
            if ($showBitlockerKeysInReport) {
                $bitlockerKeys = ""
                foreach ($key in $device.bitlockerKey) {
                    $bitlockerKeys += "$($key.creationTime)|$($key.driveType)|$($key.recoveryKey)|"
                }
            } else {
                $bitlockerKeys = "HIDDEN FROM REPORT: READ INSTRUCTIONS TO REVEAL KEYS"
            }
        } else {
            $bitlockerKeys = "NOT UPLOADED YET OR N/A"
        }

        $csvEntries += [PSCustomObject]@{"Name" = $device.displayName; "BitlockerKeysUploadedToAzureAD" = $keysKnownToAzure; "OS Drive encrypted" = $osDriveEncrypted; "lastKeyUploadDate" = $lastKeyUploadDate; "DeviceAccountEnabled" = $device.accountEnabled; "managed" = $device.isManaged; "ManagedBy" = $device.managedBy; "lastLogon" = $device.approximateLastLogonTimeStamp; "Owner" = $device.Owner.userPrincipalName; "bitlockerKeys" = $bitlockerKeys; "OS" = $device.deviceOSType; "OSVersion" = $device.deviceOSVersion; "Trust Type" = $device.deviceTrustType; "dirSynced" = $device.dirSyncEnabled; "Compliant" = $device.isCompliant; "trustTypeDisplayValue" = $device.trustTypeDisplayValue; "creationTimeStamp" = $device.creationTimeStamp }
    }
    $csvEntries
}

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

    [Alias("ipresult", "Get-IntunePolicyResult")]
    [CmdletBinding()]
    param (
        [string] $computerName,

        [ValidateScript( { $_.GetType().Name -eq 'Object[]' } )]
        $intuneXMLReport,

        [switch] $asHTML,

        [string] $HTMLReportPath = (Join-Path $env:USERPROFILE "IntunePolicyReport.html"),

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
        $allFunctionDefs = "function _getTargetName { ${function:_getTargetName} }; function _getIntuneScript { ${function:_getIntuneScript} }; function _getIntuneApp { ${function:_getIntuneApp} }; ; function _getRemediationScript { ${function:_getRemediationScript} }"
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
    # https://oliverkieselbach.com/2018/10/02/part-3-deep-dive-microsoft-intune-management-extension-win32-apps/
    # HKLM\SOFTWARE\Microsoft\IntuneManagementExtension\Apps\ doesn't exists?
    Write-Verbose "Processing 'Win32App' section"
    #region get data
    $scriptBlock = {
        param($verbosePref, $getDataFromIntune, $intuneApp, $intuneUser, $allFunctionDefs)

        # inherit verbose settings from host session
        $VerbosePreference = $verbosePref

        # recreate functions from their text definitions
        . ([ScriptBlock]::Create($allFunctionDefs))

        Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps" -ErrorAction SilentlyContinue | % {
            $userAzureObjectID = Split-Path $_.Name -Leaf

            $userWin32AppRoot = $_.PSPath
            $win32AppIDList = Get-ChildItem $userWin32AppRoot | select -ExpandProperty PSChildName | % { $_ -replace "_\d+$" } | select -Unique

            $win32AppIDList | % {
                $win32AppID = $_

                Write-Verbose "`tID $win32AppID"

                $newestWin32AppRecord = Get-ChildItem $userWin32AppRoot | ? PSChildName -Match ([regex]::escape($win32AppID)) | Sort-Object -Descending -Property PSChildName | select -First 1

                $lastUpdatedTimeUtc = Get-ItemPropertyValue $newestWin32AppRecord.PSPath -Name LastUpdatedTimeUtc
                try {
                    $complianceStateMessage = Get-ItemPropertyValue "$($newestWin32AppRecord.PSPath)\ComplianceStateMessage" -Name ComplianceStateMessage -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Write-Verbose "`tUnable to get Compliance State Message data"
                }
                try {
                    $enforcementStateMessage = Get-ItemPropertyValue "$($newestWin32AppRecord.PSPath)\EnforcementStateMessage" -Name EnforcementStateMessage -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Write-Verbose "`tUnable to get Enforcement State Message data"
                }

                $lastError = $complianceStateMessage.ErrorCode
                if (!$lastError) { $lastError = 0 } # because of HTML conditional formatting ($null means that cell will have red background)

                if ($getDataFromIntune) {
                    $property = [ordered]@{
                        "Scope"              = _getTargetName $userAzureObjectID
                        "DisplayName"        = (_getIntuneApp $win32AppID).DisplayName
                        "Id"                 = $win32AppID
                        "LastUpdatedTimeUtc" = $lastUpdatedTimeUtc
                        # "Status"            = $complianceStateMessage.ComplianceState
                        "ProductVersion"     = $complianceStateMessage.ProductVersion
                        "LastError"          = $lastError
                    }
                } else {
                    # no 'DisplayName' property
                    $property = [ordered]@{
                        "Scope"              = _getTargetName $userAzureObjectID
                        "Id"                 = $win32AppID
                        "LastUpdatedTimeUtc" = $lastUpdatedTimeUtc
                        # "Status"            = $complianceStateMessage.ComplianceState
                        "ProductVersion"     = $complianceStateMessage.ProductVersion
                        "LastError"          = $lastError
                    }
                }

                if ($showURLs) {
                    $property.IntuneWin32AppURL = "https://endpoint.microsoft.com/#blade/Microsoft_Intune_Apps/SettingsMenu/0/appId/$win32AppID"
                }

                New-Object -TypeName PSObject -Property $property
            }
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
        param($verbosePref, $getDataFromIntune, $intuneScript, $intuneUser, $allFunctionDefs)

        # inherit verbose settings from host session
        $VerbosePreference = $verbosePref

        # recreate functions from their text definitions
        . ([ScriptBlock]::Create($allFunctionDefs))

        Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Policies" -ErrorAction SilentlyContinue | % {
            $userAzureObjectID = Split-Path $_.Name -Leaf

            Get-ChildItem $_.PSPath | % {
                $scriptRegPath = $_.PSPath
                $scriptID = Split-Path $_.Name -Leaf

                Write-Verbose "`tID $scriptID"

                $scriptRegData = Get-ItemProperty $scriptRegPath

                # get output of the invoked script
                if ($scriptRegData.ResultDetails) {
                    try {
                        $resultDetails = $scriptRegData.ResultDetails | ConvertFrom-Json -ErrorAction Stop | select -ExpandProperty ExecutionMsg
                    } catch {
                        Write-Verbose "`tUnable to get Script Output data"
                    }
                } else {
                    $resultDetails = $null
                }

                if ($getDataFromIntune) {
                    $property = [ordered]@{
                        "Scope"                   = _getTargetName $userAzureObjectID
                        "DisplayName"             = (_getIntuneScript $scriptID).DisplayName
                        "Id"                      = $scriptID
                        "Result"                  = $scriptRegData.Result
                        "ErrorCode"               = $scriptRegData.ErrorCode
                        "DownloadAndExecuteCount" = $scriptRegData.DownloadCount
                        "LastUpdatedTimeUtc"      = $scriptRegData.LastUpdatedTimeUtc
                        "RunAsAccount"            = $scriptRegData.RunAsAccount
                        "ResultDetails"           = $resultDetails
                    }
                } else {
                    # no 'DisplayName' property
                    $property = [ordered]@{
                        "Scope"                   = _getTargetName $userAzureObjectID
                        "Id"                      = $scriptID
                        "Result"                  = $scriptRegData.Result
                        "ErrorCode"               = $scriptRegData.ErrorCode
                        "DownloadAndExecuteCount" = $scriptRegData.DownloadCount
                        "LastUpdatedTimeUtc"      = $scriptRegData.LastUpdatedTimeUtc
                        "RunAsAccount"            = $scriptRegData.RunAsAccount
                        "ResultDetails"           = $resultDetails
                    }
                }

                if ($showURLs) {
                    $property.IntuneScriptURL = "https://endpoint.microsoft.com/#blade/Microsoft_Intune_DeviceSettings/ConfigureWMPolicyMenuBlade/properties/policyId/$scriptID/policyType/0"
                }

                New-Object -TypeName PSObject -Property $property
            }
        }
    }

    $param = @{
        scriptBlock  = $scriptBlock
        argumentList = ($VerbosePreference, $getDataFromIntune, $intuneScript, $intuneUser, $allFunctionDefs)
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

        Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts\Reports" -ErrorAction SilentlyContinue | % {
            $userAzureObjectID = Split-Path $_.Name -Leaf
            $userRemScriptRoot = $_.PSPath

            # $lastFullReportTimeUTC = Get-ItemPropertyValue $userRemScriptRoot -Name LastFullReportTimeUTC
            $remScriptIDList = Get-ChildItem $userRemScriptRoot | select -ExpandProperty PSChildName | % { $_ -replace "_\d+$" } | select -Unique

            $remScriptIDList | % {
                $remScriptID = $_

                Write-Verbose "`tID $remScriptID"

                $newestRemScriptRecord = Get-ChildItem $userRemScriptRoot | ? PSChildName -Match ([regex]::escape($remScriptID)) | Sort-Object -Descending -Property PSChildName | select -First 1

                try {
                    $result = Get-ItemPropertyValue "$($newestRemScriptRecord.PSPath)\Result" -Name Result | ConvertFrom-Json
                } catch {
                    Write-Verbose "`tUnable to get Remediation Script Result data"
                }

                $lastExecution = Get-ItemPropertyValue "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts\Execution\$userAzureObjectID\$($newestRemScriptRecord.PSChildName)" -Name LastExecution

                if ($getDataFromIntune) {
                    $property = [ordered]@{
                        "Scope"                             = _getTargetName $userAzureObjectID
                        "DisplayName"                       = (_getRemediationScript $remScriptID).DisplayName
                        "Id"                                = $remScriptID
                        "LastError"                         = $result.ErrorCode
                        "LastExecution"                     = $lastExecution
                        # LastFullReportTimeUTC               = $lastFullReportTimeUTC
                        "InternalVersion"                   = $result.InternalVersion
                        "PreRemediationDetectScriptOutput"  = $result.PreRemediationDetectScriptOutput
                        "PreRemediationDetectScriptError"   = $result.PreRemediationDetectScriptError
                        "RemediationScriptErrorDetails"     = $result.RemediationScriptErrorDetails
                        "PostRemediationDetectScriptOutput" = $result.PostRemediationDetectScriptOutput
                        "PostRemediationDetectScriptError"  = $result.PostRemediationDetectScriptError
                        "RemediationExitCode"               = $result.Info.RemediationExitCode
                        "FirstDetectExitCode"               = $result.Info.FirstDetectExitCode
                        "LastDetectExitCode"                = $result.Info.LastDetectExitCode
                        "ErrorDetails"                      = $result.Info.ErrorDetails
                    }
                } else {
                    # no 'DisplayName' property
                    $property = [ordered]@{
                        "Scope"                             = _getTargetName $userAzureObjectID
                        "Id"                                = $remScriptID
                        "LastError"                         = $result.ErrorCode
                        "LastExecution"                     = $lastExecution
                        # LastFullReportTimeUTC               = $lastFullReportTimeUTC
                        "InternalVersion"                   = $result.InternalVersion
                        "PreRemediationDetectScriptOutput"  = $result.PreRemediationDetectScriptOutput
                        "PreRemediationDetectScriptError"   = $result.PreRemediationDetectScriptError
                        "RemediationScriptErrorDetails"     = $result.RemediationScriptErrorDetails
                        "PostRemediationDetectScriptOutput" = $result.PostRemediationDetectScriptOutput
                        "PostRemediationDetectScriptError"  = $result.PostRemediationDetectScriptError
                        "RemediationExitCode"               = $result.Info.RemediationExitCode
                        "FirstDetectExitCode"               = $result.Info.FirstDetectExitCode
                        "LastDetectExitCode"                = $result.Info.LastDetectExitCode
                        "ErrorDetails"                      = $result.Info.ErrorDetails
                    }
                }

                New-Object -TypeName PSObject -Property $property
            }
        }
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

function Get-HybridADJoinStatus {
    <#
    .SYNOPSIS
    Function returns computer's Hybrid AD Join status.

    .DESCRIPTION
    Function returns computer's Hybrid AD Join status.

    .PARAMETER computerName
    Name of the computer you want to get status of.

    .PARAMETER wait
    How many seconds should function wait when checking AAD certificates creation.

    .EXAMPLE
    Get-HybridADJoinStatus
    #>

    [CmdletBinding()]
    param (
        [string] $computerName,

        [int] $wait = 0
    )

    $param = @{
        scriptBlock  = {
            param ($wait)

            # check certificates
            Write-Verbose "Two valid certificates should exist in Computer Personal cert. store (issuer: MS-Organization-Access, MS-Organization-P2P-Access [$(Get-Date -Format yyyy)]"

            while (!($hybridJoinCert = Get-ChildItem 'Cert:\LocalMachine\My\' | ? { $_.Issuer -match "MS-Organization-Access|MS-Organization-P2P-Access \[\d+\]" }) -and $wait -gt 0) {
                Start-Sleep 1
                --$wait
                Write-Verbose $wait
            }

            # check certificate validity
            if ($hybridJoinCert) {
                $validHybridJoinCert = $hybridJoinCert | ? { $_.NotAfter -gt [datetime]::Now -and $_.NotBefore -lt [datetime]::Now }
            }

            # check AzureAd join status
            $dsreg = dsregcmd.exe /status
            if (($dsreg | Select-String "AzureAdJoined :") -match "YES") {
                ++$AzureAdJoined
            }

            if ($AzureAdJoined -and $validHybridJoinCert -and @($validHybridJoinCert).count -ge 2 ) {
                return $true
            } else {
                if (!$AzureAdJoined) {
                    Write-Warning "$env:COMPUTERNAME is not AzureAD joined"
                } elseif (!$hybridJoinCert) {
                    Write-Warning "AzureAD certificates doesn't exist"
                } elseif ($hybridJoinCert -and !$validHybridJoinCert) {
                    Write-Warning "AzureAD certificates exists but are expired"
                } elseif ($hybridJoinCert -and @($validHybridJoinCert).count -lt 2) {
                    Write-Warning "AzureAD certificates exists but one of them is expired"
                }

                return $false
            }
        }

        argumentList = $wait
    }

    if ($computerName -and $computerName -notin "localhost", $env:COMPUTERNAME) {
        $param.computerName = $computerName
    }

    Invoke-Command @param
}

function Get-IntuneDeviceComplianceStatus {
    <#
    .SYNOPSIS
    Function for getting device compliance status from Intune.

    .DESCRIPTION
    Function for getting device compliance status from Intune.
    Devices can be selected by name or id. If omitted, all devices will be processed.

    .PARAMETER deviceName
    Name of device(s).

    Can be combined with deviceId parameter.

    .PARAMETER deviceId
    Id(s) of device(s).

    Can be combined with deviceName parameter.

    .PARAMETER header
    Authentication header.

    Can be created via New-GraphAPIAuthHeader.

    .PARAMETER justProblematic
    Switch for outputting only non-compliant items.

    .EXAMPLE
    $header = New-GraphAPIAuthHeader
    Get-IntuneDeviceComplianceStatus -header $header

    Will return compliance information for all devices in your Intune.

    .EXAMPLE
    $header = New-GraphAPIAuthHeader
    Get-IntuneDeviceComplianceStatus -header $header -deviceName PC-1, PC-2

    Will return compliance information for PC-1, PC-2 from Intune.
    #>

    [CmdletBinding()]
    param (
        [string[]] $deviceName,

        [string[]] $deviceId,

        [hashtable] $header,

        [switch] $justProblematic
    )

    $ErrorActionPreference = "Stop"

    if (!$header) {
        # authenticate
        Import-Module Variables
        $header = New-GraphAPIAuthHeader -ErrorAction Stop
    }

    if (!$deviceName -and !$deviceId) {
        # all devices will be processed
        Write-Warning "You haven't specified device name or id, all devices will be processed"
        $deviceId = (Invoke-RestMethod -Headers $header -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=id" -Method Get).value | select -ExpandProperty Id
    } elseif ($deviceName) {
        $deviceName | % {
            #TODO limit returned properties using select filter
            $id = (Invoke-RestMethod -Headers $header -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=deviceName eq '$_'" -Method Get).value | select -ExpandProperty Id
            if ($id) {
                Write-Verbose "$_ was translated to $id"
                $deviceId += $id
            } else {
                Write-Warning "Device $_ wasn't found"
            }
        }
    }

    $deviceId = $deviceId | select -Unique

    foreach ($devId in $deviceId) {
        Write-Verbose "Processing device $devId"
        # get list of all compliance policies of this particular device
        $deviceCompliancePolicy = (Invoke-RestMethod -Headers $header -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$devId')/deviceCompliancePolicyStates" -Method Get).value

        if ($deviceCompliancePolicy) {
            # get detailed information for each compliance policy (mainly errorDescription)
            $deviceCompliancePolicy | % {
                $deviceComplianceId = $_.id
                $deviceComplianceStatus = (Invoke-RestMethod -Headers $header -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$devId')/deviceCompliancePolicyStates('$deviceComplianceId')/settingStates" -Method Get).value

                if ($justProblematic) {
                    $deviceComplianceStatus = $deviceComplianceStatus | ? { $_.state -ne "compliant" }
                }

                $name = (Invoke-RestMethod -Headers $header -Uri "https://graph.microsoft.com/beta/deviceManagement/manageddevices('$devId')?`$select=deviceName" -Method Get).deviceName

                $deviceComplianceStatus | select @{n = 'deviceName'; e = { $name } }, state, errorDescription, userPrincipalName , setting, sources
            }
        } else {
            Write-Warning "There are no compliance policies for $devId device"
        }
    }
}

function Get-IntuneEnrollmentStatus {
    <#
    .SYNOPSIS
    Function for checking whether computer is managed by Intune (fulfill all requirements).

    .DESCRIPTION
    Function for checking whether computer is managed by Intune (fulfill all requirements).
    What is checked:
     - device is AAD joined
     - device is joined to Intune
     - device has valid Intune certificate
     - device has Intune sched. tasks
     - device has Intune registry keys
     - Intune service exists

    Returns true or false.

    .PARAMETER computerName
    (optional) name of the computer to check.

    .PARAMETER checkIntuneToo
    Switch for checking Intune part too (if device is listed there).

    .PARAMETER wait
    Number of seconds function should wait when checking Intune certificate existence.

    Default is 0.

    .EXAMPLE
    Get-IntuneEnrollmentStatus

    Check Intune status on local computer.

    .EXAMPLE
    Get-IntuneEnrollmentStatus -computerName ae-50-pc

    Check Intune status on computer ae-50-pc.

    .EXAMPLE
    Get-IntuneEnrollmentStatus -computerName ae-50-pc -checkIntuneToo

    Check Intune status on computer ae-50-pc, plus connects to Intune and check whether ae-50-pc exists there.
    #>

    [CmdletBinding()]
    [Alias("Get-IntuneJoinStatus")]
    param (
        [string] $computerName,

        [switch] $checkIntuneToo,

        [int] $wait = 0
    )

    if (!$computerName) { $computerName = $env:COMPUTERNAME }

    #region get Intune data
    if ($checkIntuneToo) {
        $ErrActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Stop"

        try {
            if (Get-Command Get-ADComputer -ErrorAction SilentlyContinue) {
                $ADObj = Get-ADComputer -Filter "Name -eq '$computerName'" -Properties Name, ObjectGUID
            } else {
                Write-Verbose "Get-ADComputer command is missing, unable to get device GUID"
            }

            Connect-MSGraph2

            $intuneObj = @()

            $intuneObj += Get-IntuneManagedDevice -Filter "DeviceName eq '$computerName'"

            if ($ADObj.ObjectGUID) {
                # because of bug? computer can be listed under guid_date name in cloud
                $intuneObj += Get-IntuneManagedDevice -Filter "azureADDeviceId eq '$($ADObj.ObjectGUID)'" | ? DeviceName -NE $computerName
            }
        } catch {
            Write-Warning "Unable to get information from Intune. $_"

            # to avoid errors that device is missing from Intune
            $intuneObj = 1
        }

        $ErrorActionPreference = $ErrActionPreference
    }
    #endregion get Intune data

    $scriptBlock = {
        param ($checkIntuneToo, $intuneObj, $wait)

        $intuneNotJoined = 0

        #region Intune checks
        if ($checkIntuneToo) {
            if (!$intuneObj) {
                ++$intuneNotJoined
                Write-Warning "Device is missing from Intune!"
            }

            if ($intuneObj.count -gt 1) {
                Write-Warning "Device is listed $($intuneObj.count) times in Intune"
            }

            $wrongIntuneName = $intuneObj.DeviceName | ? { $_ -ne $env:COMPUTERNAME }
            if ($wrongIntuneName) {
                Write-Warning "Device is named as $wrongIntuneName in Intune"
            }

            $correctIntuneName = $intuneObj.DeviceName | ? { $_ -eq $env:COMPUTERNAME }
            if ($intuneObj -and !$correctIntuneName) {
                ++$intuneNotJoined
                Write-Warning "Device has no record in Intune with correct device name"
            }
        }
        #endregion Intune checks

        #region dsregcmd checks
        $dsregcmd = dsregcmd.exe /status
        $azureAdJoined = $dsregcmd | Select-String "AzureAdJoined : YES"
        if (!$azureAdJoined) {
            ++$intuneNotJoined
            Write-Warning "Device is NOT AAD joined"
        }

        $tenantName = $dsregcmd | Select-String "TenantName : .+"
        if (!$tenantName) {
            Write-Verbose "TenantName is missing in 'dsregcmd.exe /status' output"
        }
        $MDMUrl = $dsregcmd | Select-String "MdmUrl : .+"
        if (!$MDMUrl) {
            ++$intuneNotJoined
            Write-Warning "Device is NOT Intune joined"
        }
        #endregion dsregcmd checks

        #region certificate checks
        while (!($MDMCert = Get-ChildItem 'Cert:\LocalMachine\My\' | ? Issuer -EQ "CN=Microsoft Intune MDM Device CA") -and $wait -gt 0) {
            Start-Sleep 1
            --$wait
            Write-Verbose $wait
        }
        if (!$MDMCert) {
            ++$intuneNotJoined
            Write-Warning "Intune certificate is missing"
        } elseif ($MDMCert.NotAfter -lt (Get-Date) -or $MDMCert.NotBefore -gt (Get-Date)) {
            ++$intuneNotJoined
            Write-Warning "Intune certificate isn't valid"
        }
        #endregion certificate checks

        #region sched. task checks
        $MDMSchedTask = Get-ScheduledTask | ? { $_.TaskPath -like "*Microsoft*Windows*EnterpriseMgmt\*" -and $_.TaskName -eq "PushLaunch" }
        $enrollmentGUID = $MDMSchedTask | Select-Object -ExpandProperty TaskPath -Unique | ? { $_ -like "*-*-*" } | Split-Path -Leaf
        if (!$enrollmentGUID) {
            ++$intuneNotJoined
            Write-Warning "Synchronization sched. task is missing"
        }
        #endregion sched. task checks

        #region registry checks
        if ($enrollmentGUID) {
            $missingRegKey = @()
            $registryKeys = "HKLM:\SOFTWARE\Microsoft\Enrollments", "HKLM:\SOFTWARE\Microsoft\Enrollments\Status", "HKLM:\SOFTWARE\Microsoft\EnterpriseResourceManager\Tracked", "HKLM:\SOFTWARE\Microsoft\PolicyManager\AdmxInstalled", "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers", "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts", "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Logger", "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Sessions"
            foreach ($key in $registryKeys) {
                if (!(Get-ChildItem -Path $key -ea SilentlyContinue | Where-Object { $_.Name -match $enrollmentGUID })) {
                    Write-Warning "Registry key $key is missing"
                    ++$intuneNotJoined
                }
            }
        }
        #endregion registry checks

        #region service checks
        $MDMService = Get-Service -Name IntuneManagementExtension -ErrorAction SilentlyContinue
        if (!$MDMService) {
            ++$intuneNotJoined
            Write-Warning "Intune service IntuneManagementExtension is missing"
        }
        if ($MDMService -and $MDMService.Status -ne "Running") {
            Write-Warning "Intune service IntuneManagementExtension is not running"
        }
        #endregion service checks

        if ($intuneNotJoined) {
            return $false
        } else {
            return $true
        }
    }

    $param = @{
        scriptBlock  = $scriptBlock
        argumentList = $checkIntuneToo, $intuneObj, $wait
    }
    if ($computerName -and $computerName -notin "localhost", $env:COMPUTERNAME) {
        $param.computerName = $computerName
    }

    Invoke-Command @param
}

function Get-IntuneOverallComplianceStatus {
    <#
    .SYNOPSIS
    Function for getting overall device compliance status from Intune.

    .DESCRIPTION
    Function for getting overall device compliance status from Intune.

    .PARAMETER header
    Authentication header.

    Can be created via New-GraphAPIAuthHeader.

    .PARAMETER justProblematic
    Switch for outputting only non-compliant items.

    .EXAMPLE
    $header = New-GraphAPIAuthHeader -credential $cred
    Get-IntuneOverallComplianceStatus -header $header

    Will return compliance information for all devices in your Intune.

    .EXAMPLE
    $header = New-GraphAPIAuthHeader -credential $cred
    Get-IntuneOverallComplianceStatus -header $header -justProblematic

    Will return just information about non-compliant devices in your Intune.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable] $header
        ,
        [switch] $justProblematic
    )

    # helper hashtable for storing devices compliance data
    # just for performance optimization
    $deviceComplianceData = @{}

    # get compliant devices
    $URI = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$select=id&`$filter=complianceState eq 'compliant'"
    $compliantDevice = (Invoke-RestMethod -Headers $header -Uri $URI -Method Get).value

    # get overall compliance policies per-setting status
    $URI = 'https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicySettingStateSummaries'
    $complianceSummary = (Invoke-RestMethod -Headers $header -Uri $URI -Method Get).value
    $complianceSummary = $complianceSummary | select @{n = 'Name'; e = { ($_.settingName -split "\.")[-1] } }, nonCompliantDeviceCount, errorDeviceCount, conflictDeviceCount, id

    if ($justProblematic) {
        # preserve just problematic ones
        $complianceSummary = $complianceSummary | ? { $_.nonCompliantDeviceCount -or $_.errorDeviceCount -or $_.conflictDeviceCount }
    }

    if ($complianceSummary) {
        $complianceSummary | % {
            $complianceSettingId = $_.id

            Write-Verbose $complianceSettingId
            Write-Warning "Processing $($_.name)"

            # add help text, to help understand, what this compliance setting validates
            switch ($_.name) {
                'RequireRemainContact' { Write-Warning "`t- devices that haven't contacted Intune for last 30 days" }
                'RequireDeviceCompliancePolicyAssigned' { Write-Warning "`t- devices without any compliance policy assigned" }
                'ConfigurationManagerComplianceRequired' { Write-Warning "`t- devices that are not compliant in SCCM" }
            }

            # get devices, where this particular compliance setting is not ok
            $URI = "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicySettingStateSummaries/$complianceSettingId/deviceComplianceSettingStates?`$filter=NOT(state eq 'compliant')"
            $complianceStatus = (Invoke-RestMethod -Headers $header -Uri $URI -Method Get).value

            if ($justProblematic) {
                # preserve just problematic ones
                # omit devices that have some non compliant items but overall device status is compliant (i.e. ignore typically old, per user non-compliant statuses)
                $complianceStatus = $complianceStatus | ? { $_.state -ne "compliant" -and $_.DeviceId -notin $compliantDevice.Id }
            }

            # loop through all devices that are not compliant (get details) and output the result
            $deviceDetails = $complianceStatus | % {
                $deviceId = $_.deviceId
                $deviceName = $_.deviceName
                $userPrincipalName = $_.userPrincipalName

                Write-Verbose "Processing $deviceName with id: $deviceId and UPN: $userPrincipalName"

                #region get error details (if exists) for this particular device and compliance setting
                if (!($deviceComplianceData.$deviceName)) {
                    Write-Verbose "Getting compliance data for $deviceName"
                    $deviceComplianceData.$deviceName = Get-IntuneDeviceComplianceStatus -deviceId $deviceId -justProblematic -header $header
                }

                if ($deviceComplianceData.$deviceName) {
                    # get error details for this particular compliance setting
                    $errorDescription = $deviceComplianceData.$deviceName | ? { $_.setting -eq $complianceSettingId -and $_.userPrincipalName -eq $userPrincipalName -and $_.errorDescription -ne "No error code" } | select -ExpandProperty errorDescription -Unique
                }
                #endregion get error details (if exists) for this particular device and compliance setting

                # output result
                $_ | select deviceName, userPrincipalName, state, @{n = 'errDetails'; e = { $errorDescription } } | sort state, deviceName
            }

            # output result for this compliance setting
            [PSCustomObject]@{
                Name                    = $_.name
                NonCompliantDeviceCount = $_.nonCompliantDeviceCount
                ErrorDeviceCount        = $_.errorDeviceCount
                ConflictDeviceCount     = $_.conflictDeviceCount
                DeviceDetails           = $deviceDetails
            }
        }
    }
}

function Get-IntuneReport {
    <#
    .SYNOPSIS
    Function for getting Intune Reports data. As zip file (csv) or PS object.

    .DESCRIPTION
    Function for getting Intune Reports data. As zip file (csv) or PS object.
    It uses Graph API for connection.

    In case selected report needs additional information, like what application you want report for, GUI with available options will be outputted for you to choose.

    .PARAMETER reportName
    Name of the report you want to get.

    POSSIBLE VALUES:
    https://docs.microsoft.com/en-us/mem/intune/fundamentals/reports-export-graph-available-reports

    reportName	                            Associated Report in Microsoft Endpoint Manager
    DeviceCompliance	                    Device Compliance Org
    DeviceNonCompliance	                    Non-compliant devices
    Devices	                                All devices list
    DetectedAppsAggregate	                Detected Apps report
    FeatureUpdatePolicyFailuresAggregate	Under Devices > Monitor > Failure for feature updates
    DeviceFailuresByFeatureUpdatePolicy	    Under Devices > Monitor > Failure for feature updates > click on error
    FeatureUpdateDeviceState	            Under Reports > Window Updates > Reports > Windows Feature Update Report 
    UnhealthyDefenderAgents	                Under Endpoint Security > Antivirus > Win10 Unhealthy Endpoints
    DefenderAgents	                        Under Reports > MicrosoftDefender > Reports > Agent Status
    ActiveMalware	                        Under Endpoint Security > Antivirus > Win10 detected malware
    Malware	                                Under Reports > MicrosoftDefender > Reports > Detected malware
    AllAppsList	                            Under Apps > All Apps
    AppInstallStatusAggregate	            Under Apps > Monitor > App install status
    DeviceInstallStatusByApp	            Under Apps > All Apps > Select an individual app
    UserInstallStatusAggregateByApp	        Under Apps > All Apps > Select an individual app

    .PARAMETER header
    Authentication header.

    Can be created via New-GraphAPIAuthHeader.

    .PARAMETER filter
    String that represents Graph request API filter.

    For example: PolicyId eq 'a402829f-8ba2-4413-969b-077a97ba218c'

    PS: Some reports (FeatureUpdateDeviceState, DeviceInstallStatusByApp, UserInstallStatusAggregateByApp) requires filter to target the update/application. In case you don't specify it, list of available values will be given to choose.

    .PARAMETER exportPath
    Path to folder, where report should be stored.

    Default is working folder.

    .PARAMETER asObject
    Switch for getting results as PS object instead of zip file.

    .EXAMPLE
    $header = New-GraphAPIAuthHeader -ErrorAction Stop
    $reportData = Get-IntuneReport -header $header -reportName Devices -asObject

    Return object with 'All devices list' report data.

    .EXAMPLE
    $header = New-GraphAPIAuthHeader -ErrorAction Stop
    Get-IntuneReport -header $header -reportName DeviceNonCompliance

    Download zip archive to current working folder containing csv file with 'Non-compliant devices' report.

    .EXAMPLE
    $header = New-GraphAPIAuthHeader -ErrorAction Stop
    Get-IntuneReport -header $header -reportName FeatureUpdateDeviceState -filter "PolicyId eq 'a402829f-8ba2-4413-969b-077a97ba218c'"

    .NOTES
    You need to have Azure App registration with appropriate API permissions for Graph API for unattended usage!

    With these API permissions all reports work (but maybe not all are really needed!)
    Application.Read.All
    Device.Read.All
    DeviceManagementApps.Read.All
    DeviceManagementConfiguration.Read.All
    DeviceManagementManagedDevices.Read.All
    ProgramControl.Read.All
    Reports.Read.All

    .LINK
    https://docs.microsoft.com/en-us/mem/intune/fundamentals/reports-export-graph-apis
    https://docs.microsoft.com/en-us/mem/intune/fundamentals/reports-export-graph-available-reports
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('DeviceCompliance', 'DeviceNonCompliance', 'Devices', 'DetectedAppsAggregate', 'FeatureUpdatePolicyFailuresAggregate', 'DeviceFailuresByFeatureUpdatePolicy', 'FeatureUpdateDeviceState', 'UnhealthyDefenderAgents', 'DefenderAgents', 'ActiveMalware', 'Malware', 'AllAppsList', 'AppInstallStatusAggregate', 'DeviceInstallStatusByApp', 'UserInstallStatusAggregateByApp')]
        [string] $reportName
        ,
        [hashtable] $header
        ,
        [string] $filter
        ,
        [ValidateScript( {
                If (Test-Path $_ -PathType Container) {
                    $true
                } else {
                    Throw "$_ has to be existing folder"
                }
            })]
        [string] $exportPath = (Get-Location)
        ,
        [switch] $asObject
    )

    begin {
        $ErrorActionPreference = "Stop"

        if (!$header) {
            # authenticate
            Import-Module Variables
            $header = New-GraphAPIAuthHeader -ErrorAction Stop
        }

        #region prepare filter for FeatureUpdateDeviceState report if not available
        if ($reportName -eq 'FeatureUpdateDeviceState' -and (!$filter -or $filter -notmatch "^PolicyId eq ")) {
            Write-Warning "Report FeatureUpdateDeviceState requires special filter in form: `"PolicyId eq '<somePolicyId>'`""
            $body = @{
                name = "FeatureUpdatePolicy"
            }
            $filterResponse = Invoke-RestMethod -Headers $header -Uri "https://graph.microsoft.com/beta/deviceManagement/reports/getReportFilters" -Body $body -Method Post
            $column = $filterResponse.schema.column
            $filterList = $filterResponse.values | % {
                $filterItem = $_

                $property = @{}
                $o = 0
                $column | % {
                    $property.$_ = $filterItem[$o]
                    ++$o
                }
                New-Object -TypeName PSObject -Property $property
            }

            $filter = $filterList | Out-GridView -Title "Select Update type you want the report for" -OutputMode Single | % { "PolicyId eq '$($_.PolicyId)'" }
            Write-Verbose "Filter will be: $filter"
        }
        #endregion prepare filter for FeatureUpdateDeviceState report if not available

        #region prepare filter for DeviceInstallStatusByApp/UserInstallStatusAggregateByApp report if not available
        if ($reportName -in ('DeviceInstallStatusByApp', 'UserInstallStatusAggregateByApp') -and (!$filter -or $filter -notmatch "^PolicyId eq ")) {
            Write-Warning "Report $reportName requires filter in form: `"ApplicationId eq '<someApplicationId>'`""
            # get list of all available applications
            $allApps = (Invoke-RestMethod -Headers $header -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$filter=(microsoft.graph.managedApp/appAvailability%20eq%20null%20or%20microsoft.graph.managedApp/appAvailability%20eq%20%27lineOfBusiness%27%20or%20isAssigned%20eq%20true)&`$orderby=displayName&" -Method Get).Value | select displayName, isAssigned, productVersion, id

            $filter = $allApps | Out-GridView -Title "Select Application you want the report for" -OutputMode Single | % { "ApplicationId eq '$($_.Id)'" }
            Write-Verbose "Filter will be: $filter"
        }
        #endregion prepare filter for DeviceInstallStatusByApp/UserInstallStatusAggregateByApp report if not available
    }

    process {
        #region request the report
        $body = @{
            reportName = $reportName
            format     = "csv"
            # select     = 'PolicyId', 'PolicyName', 'DeviceId'
        }
        if ($filter) { $body.filter = $filter }
        Write-Warning "Requesting the report $reportName"
        try {
            $result = Invoke-RestMethod -Headers $header -Uri "https://graph.microsoft.com/beta/deviceManagement/reports/exportJobs" -Body $body -Method Post
        } catch {
            switch ($_) {
                ($_ -like "*(400) Bad Request*") { throw "Faulty request. There has to be some mistake in this request" }
                ($_ -like "*(401) Unauthorized*") { throw "Unauthorized request (try different credentials?)" }
                ($_ -like "*Forbidden*") { throw "Forbidden access. Use account with correct API permissions for this request" }
                default { throw $_ }
            }
        }
        #endregion request the report

        #region wait for generating of the report to finish
        Write-Warning "Waiting for the report to finish generating"
        do {
            $export = Invoke-RestMethod -Headers $header -Uri "https://graph.microsoft.com/beta/deviceManagement/reports/exportJobs('$($result.id)')" -Method Get

            Start-Sleep 1
        } while ($export.status -eq "inProgress")
        #endregion wait for generating of the report to finish

        #region download generated report
        if ($export.status -eq "completed") {
            $originalFileName = $export.id + ".csv"
            $reportArchive = Join-Path $exportPath "$reportName`_$(Get-Date -Format dd-MM-HH-ss).zip"
            Write-Warning "Downloading the report to $reportArchive"
            $null = Invoke-WebRequest -Uri $export.url -Method Get -OutFile $reportArchive

            if ($asObject) {
                Write-Warning "Expanding $reportArchive to $env:TEMP"
                Expand-Archive $reportArchive -DestinationPath $env:TEMP -Force

                $reportCsv = Join-Path $env:TEMP $originalFileName
                Write-Warning "Importing $reportCsv"
                Import-Csv $reportCsv

                # delete zip and also extracted csv files
                Write-Warning "Removing zip and csv files"
                Remove-Item $reportArchive, $reportCsv -Force
            }
        } else {
            throw "Export of $reportName failed.`n`n$export"
        }
        #endregion download generated report
    }
}

#Requires -Modules ActiveDirectory

function Get-MDMClientData {
    <#
    .SYNOPSIS
    Function for getting client management information from AD, Intune, AAD and SCCM and combine them together.

    .DESCRIPTION
    Function for getting client management information from AD, Intune, AAD and SCCM and combine them together.
    Resultant object will have several properties with prefix AD, INTUNE, AAD or SCCM according to source of such data.

    .PARAMETER computer
    Computer(s) you want to get data about from AD, AAD, SCCM and Intune.
    As object(s) with name, sid and ObjectGUID of AD computers OR just list of computer names (in case of duplicity records, additional data to uniquely identify the correct one will be gathered from AD).

    .PARAMETER combineDataFrom
    List of sources you want to gather data from.

    Possible values are: Intune, SCCM, AAD, AD

    By default all values are selected.

    .PARAMETER graphCredential
    AppID and AppSecret for Azure App registration that has permissions needed to read Azure and Intune clients data.

    .PARAMETER sccmAdminServiceCredential
    Credentials for SCCM Admin Service API authentication. Needed only if current user doesn't have correct permissions.

    .EXAMPLE
    # active AD Windows clients that belongs to some user
    $activeADClients = Get-ADComputer -Filter "enabled -eq 'True' -and description -like '*'" -Properties description 

    $problematic = Get-MDMClientData -computer $activeADClients -graphCredential $cred

    .NOTES
    Requires functions: New-GraphAPIAuthHeader, Invoke-CMAdminServiceQuery
    #>

    [CmdletBinding()]
    param (
        $computer = (Get-ADComputer -Filter "enabled -eq 'True' -and description -like '*'" -Properties 'Name', 'sid', 'LastLogonDate', 'Enabled', 'DistinguishedName', 'Description', 'PasswordLastSet', 'ObjectGUID' | ? { $_.LastLogonDate -ge [datetime]::Today.AddDays(-90) }),

        [ValidateSet('Intune', 'SCCM', 'AAD', 'AD')]
        [string[]] $combineDataFrom = ('Intune', 'SCCM', 'AAD', 'AD'),

        [Alias("intuneCredential")]
        [System.Management.Automation.PSCredential] $graphCredential,

        [System.Management.Automation.PSCredential] $sccmAdminServiceCredential
    )

    #region checks
    if (!$computer) { throw "Computer parameter is missing" }

    if ($combineDataFrom -contains "Intune") {
        try {
            $null = Get-Command New-GraphAPIAuthHeader -ErrorAction Stop
        } catch {
            throw "New-GraphAPIAuthHeader command isn't available"
        }
    }

    if ($combineDataFrom -contains "SCCM") {
        try {
            $null = Get-Command Invoke-CMAdminServiceQuery -ErrorAction Stop
        } catch {
            throw "Invoke-CMAdminServiceQuery command isn't available"
        }
    }

    # it needs originally installed ActiveDirectory module, NOT copied/hacked one!
    if (!(Get-Module ActiveDirectory -ListAvailable)) {
        if ((Get-WmiObject win32_operatingsystem -Property caption).caption -match "server") {
            throw "Module ActiveDirectory is missing. Use: Install-WindowsFeature RSAT-AD-PowerShell -IncludeManagementTools"
        } else {
            throw "Module ActiveDirectory is missing. Use: Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online"
        }
    }
    #endregion checks

    #region helper functions
    function _ClientCheckPass {
        # translates number code to message
        param ($ClientCheckPass)

        switch ($ClientCheckPass) {
            1 { return "Passed" }
            2 { return "Failed" }
            3 { return "No results" }
            default { return "Not evaluated" }
        }
    }

    function _computerHasValidHybridJoinCertificate {
        # extracted from Export-ADSyncToolsHybridAzureADjoinCertificateReport.ps1
        # https://github.com/azureautomation/export-hybrid-azure-ad-join-computer-certificates-report--updated-

        [CmdletBinding()]
        param ([string]$computerName)

        $searcher = [adsisearcher]"(&(objectCategory=computer)(name=$computerName))"
        $searcher.PageSize = 500
        $searcher.PropertiesToLoad.AddRange(('usercertificate', 'name'))
        # $searcher.searchRoot = [adsi]"LDAP://OU=Computer_Accounts,DC=contoso,DC=com"
        $obj = $searcher.FindOne()
        $searcher.Dispose()
        if (!$obj) { throw "Unable to get $computerName" }

        $userCertificateList = @($obj.properties.usercertificate)
        $validEntries = @()
        $totalEntriesCount = $userCertificateList.Count
        Write-Verbose "'$computerName' has $totalEntriesCount entries in UserCertificate property."
        If ($totalEntriesCount -eq 0) {
            Write-Warning "'$computerName' has no Certificates - Skipped."
            return $false
        }
        # Check each UserCertificate entry and build array of valid certs
        ForEach ($entry in $userCertificateList) {
            Try {
                $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2] $entry
            } Catch {
                Write-Verbose "'$computerName' has an invalid Certificate!"
                Continue
            }
            Write-Verbose "'$computerName' has a Certificate with Subject: $($cert.Subject); Thumbprint:$($cert.Thumbprint)."
            $validEntries += $cert

        }

        $validEntriesCount = $validEntries.Count
        Write-Verbose "'$computerName' has a total of $validEntriesCount certificates (shown above)."

        # Get non-expired Certs (Valid Certificates)
        $validCerts = @($validEntries | Where-Object { $_.NotAfter -ge (Get-Date) })
        $validCertsCount = $validCerts.Count
        Write-Verbose "'$computerName' has $validCertsCount valid certificates (not-expired)."

        # Check for AAD Hybrid Join Certificates
        $hybridJoinCerts = @()
        $hybridJoinCertsThumbprints = [string] "|"
        ForEach ($cert in $validCerts) {
            $certSubjectName = $cert.Subject
            If ($certSubjectName.StartsWith($("CN=$objectGuid")) -or $certSubjectName.StartsWith($("CN={$objectGuid}"))) {
                $hybridJoinCerts += $cert
                $hybridJoinCertsThumbprints += [string] $($cert.Thumbprint) + '|'
            }
        }

        $hybridJoinCertsCount = $hybridJoinCerts.Count
        if ($hybridJoinCertsCount -gt 0) {
            Write-Verbose "'$computerName' has $hybridJoinCertsCount AAD Hybrid Join Certificates with Thumbprints: $hybridJoinCertsThumbprints"
            if ($hybridJoinCertsCount.count -lt 15) {
                # more than 15 certificates would cause fail
                return $true
            } else {
                return $false
            }
        } else {
            Write-Verbose "'$computerName' has no AAD Hybrid Join Certificates"
            return $false
        }
    }
    #endregion helper functions

    #region get data
    if ($combineDataFrom -contains "Intune" -or $combineDataFrom -contains "AAD") {
        $header = New-GraphAPIAuthHeader -credential $graphCredential -ErrorAction Stop
    }

    if ($combineDataFrom -contains "Intune") {
        $intuneDevice = (Invoke-RestMethod -Headers $header -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices" -Method Get).Value | select deviceName, deviceEnrollmentType, lastSyncDateTime, aadRegistered, azureADRegistered, deviceRegistrationState, azureADDeviceId, emailAddress

        # interactive user auth example
        # Connect-MSGraph
        # Get-DeviceManagement_ManagedDevices | select deviceName, deviceEnrollmentType, lastSyncDateTime, @{n = 'aadRegistered'; e = { $_.azureADRegistered } }, azureADRegistered, deviceRegistrationState, azureADDeviceId, emailAddress
    }

    if ($combineDataFrom -contains "SCCM") {
        $properties = 'Name', 'Domain', 'IsClient', 'IsActive', 'ClientCheckPass', 'ClientActiveStatus', 'LastActiveTime', 'ADLastLogonTime', 'CoManaged', 'IsMDMActive', 'PrimaryUser', 'SerialNumber', 'MachineId', 'UserName'
        $param = @{
            source = "v1.0/Device"
            select = $properties
        }
        if ($sccmAdminServiceCredential) {
            $param.credential = $sccmAdminServiceCredential
        }
        $sccmDevice = Invoke-CMAdminServiceQuery @param | select $properties

        # add more information
        $properties = 'ResourceID', 'InstallDate'
        $param = @{
            source = "wmi/SMS_G_System_OPERATING_SYSTEM"
            select = $properties
        }
        if ($sccmAdminServiceCredential) {
            $param.credential = $sccmAdminServiceCredential
        }
        $additionalData = Invoke-CMAdminServiceQuery @param | select $properties

        $sccmDevice = $sccmDevice | % {
            $deviceAdtData = $additionalData | ?  ResourceID -EQ $_.MachineId
            $_ | select *, @{n = 'InstallDate'; e = { if ($deviceAdtData.InstallDate) { Get-Date $deviceAdtData.InstallDate } } }, @{n = 'LastBootUpTime'; e = { if ($deviceAdtData.LastBootUpTime) { Get-Date $deviceAdtData.LastBootUpTime } } }
        }
    }

    if ($combineDataFrom -contains "AAD") {
        $aadDevice = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/v1.0/devices" -header $header | select displayName, accountEnabled, approximateLastSignInDateTime, deviceOwnership, enrollmentType, isCompliant, isManaged, managementType, onPremisesSyncEnabled, onPremisesLastSyncDateTime, profileType, deviceId
    }
    #endregion get data

    # fill object properties
    foreach ($cmp in $computer) {
        if ($cmp.name) {
            # it is object
            $name = $cmp.name
        } elseif ($cmp.gettype().Name -eq "String") {
            # it is string
            $name = $cmp
        } else {
            $cmp
            throw "THIS OBJECT DOESN'T CONTAIN NAME PROPERTY"
        }

        Write-Verbose $name

        $deviceGUID = $deviceSID = $null

        $deviceProperty = [ordered]@{
            Name                   = $name
            hasValidHybridJoinCert = _computerHasValidHybridJoinCertificate $name
        }

        if ($combineDataFrom -contains "AD") {
            $property = 'Enabled', 'LastLogonDate', 'DistinguishedName', 'Description', 'Sid', 'ObjectGUID', 'PasswordLastSet'
            $missingProperty = @()

            # try to get the value from input
            $property | % {
                $propertyName = "AD_$_"
                if ($cmp.$_) {
                    switch ($_) {
                        "SID" {
                            $deviceProperty.$propertyName = $cmp.$_.value
                        }
                        "ObjectGUID" {
                            $deviceProperty.$propertyName = $cmp.$_.guid
                        }
                        default {
                            $deviceProperty.$propertyName = $cmp.$_
                        }
                    }
                } else {
                    $missingProperty += $_
                }
            }

            if ($missingProperty) {
                Write-Verbose "Getting missing property: $($missingProperty -join ', ')"
                $deviceADData = Get-ADComputer -Filter "name -eq '$name'" -Property $missingProperty
                $missingProperty | % {
                    $propertyName = "AD_$_"
                    switch ($_) {
                        "SID" {
                            $deviceProperty.$propertyName = $deviceADData.$_.value
                        }
                        "ObjectGUID" {
                            $deviceProperty.$propertyName = $deviceADData.$_.guid
                        }
                        default {
                            $deviceProperty.$propertyName = $deviceADData.$_
                        }
                    }
                }
            }
        }

        # getting SCCM data has to be before Intune because of comparing co-managed status
        if ($combineDataFrom -contains "SCCM") {

            $deviceSCCMRecord = @($sccmDevice | ? Name -EQ $name)

            if (!$deviceSCCMRecord) {
                $deviceProperty.SCCM_InDatabase = $false
            } else {
                # device is in SCCM
                $deviceProperty.SCCM_InDatabase = $true

                if ($deviceSCCMRecord.count -gt 1) {
                    # more records with the same name

                    $deviceProperty.SCCM_MultipleRecords = $deviceSCCMRecord.count

                    Write-Verbose "Device $name is $($deviceSCCMRecord.count)x in SCCM database!"

                    # get the correct one by using SID
                    $deviceSID = $cmp.sid.value
                    if (!$deviceSID) {
                        $deviceSID = $deviceProperty.AD_SID
                    }
                    if (!$deviceSID) {
                        $deviceSID = (Get-ADComputer -Filter "name -eq '$name'" -Property SID).SID.Value
                    }
                    if ($deviceSID) {
                        Write-Verbose "Search for the $name with $deviceSID SID in SCCM database"

                        $param = @{
                            source = "wmi/SMS_R_SYSTEM"
                            select = 'ResourceId'
                            filter = "SID eq '$deviceSID'"
                        }
                        if ($sccmAdminServiceCredential) {
                            $param.credential = $sccmAdminServiceCredential
                        }
                        $resourceId = Invoke-CMAdminServiceQuery @param | select -ExpandProperty ResourceId
                        Write-Verbose "$name has resourceId $resourceId"

                        $deviceSCCMRecord = @($sccmDevice | ? MachineId -EQ $resourceId)
                    }

                    if ($deviceSCCMRecord.count -gt 1) {
                        # unable to narrow down the results

                        if (!$deviceSID) {
                            $erMsg = "No SID property was provided to identify the correct one, nor was found in AD."
                        } else {
                            $erMsg = "Unable to identify the correct one."
                        }
                        Write-Warning "Device $name is $($deviceSCCMRecord.count)x in SCCM database.`n$erMsg Therefore setting property deviceSCCMRecord as `$null"
                        $deviceSCCMRecord = $null
                    }
                } else {
                    $deviceProperty.SCCM_MultipleRecords = $false
                }

                if ($deviceSCCMRecord.count -eq 1) {
                    if (!$deviceSCCMRecord.IsClient) {
                        $deviceProperty.SCCM_ClientInstalled = $false
                    } else {
                        # SCCM client is installed

                        $deviceProperty.SCCM_ClientInstalled = $true
                        if ($deviceSCCMRecord.LastActiveTime) {
                            $deviceProperty.SCCM_LastActiveTime = (Get-Date $deviceSCCMRecord.LastActiveTime)
                        } else {
                            $deviceProperty.SCCM_LastActiveTime = $null
                        }
                        $deviceProperty.SCCM_IsActive = $deviceSCCMRecord.IsActive
                        $deviceProperty.SCCM_clientCheckPass = _ClientCheckPass $deviceSCCMRecord.ClientCheckPass
                        $deviceProperty.SCCM_clientActiveStatus = $deviceSCCMRecord.ClientActiveStatus
                        if ($deviceSCCMRecord.CoManaged -ne 1) {
                            $deviceProperty.SCCM_CoManaged = $false
                        } else {
                            $deviceProperty.SCCM_CoManaged = $true
                        }
                        $deviceProperty.SCCM_User = $deviceSCCMRecord.UserName
                        $deviceProperty.SCCM_SerialNumber = $deviceSCCMRecord.SerialNumber
                        $deviceProperty.SCCM_MachineId = $deviceSCCMRecord.MachineId
                        $deviceProperty.SCCM_OSInstallDate = $deviceSCCMRecord.InstallDate
                    }
                }
            }
        }

        if ($combineDataFrom -contains "Intune") {

            $deviceIntuneRecord = @($intuneDevice | ? DeviceName -EQ $name)

            if (!$deviceIntuneRecord) {
                Write-Verbose "$name wasn't found in Intune database, trying to get its GUID"

                # try to search for it using its GUID
                if (!$deviceGUID) {
                    $deviceGUID = $cmp.ObjectGUID.Guid
                }
                if (!$deviceGUID) {
                    $deviceGUID = $deviceProperty.AD_ObjectGUID
                }
                if (!$deviceGUID) {
                    $deviceGUID = (Get-ADComputer -Filter "name -eq '$name'" -Property ObjectGUID).ObjectGUID.Guid
                }
                if ($deviceGUID) {
                    Write-Verbose "Search for the $name using its $deviceGUID GUID in Intune database"
                    # search for Intune device with GUID instead of name
                    $deviceIntuneRecord = @($intuneDevice | ? { $_.AzureADDeviceId -eq $deviceGUID })
                }
            }

            if (!$deviceIntuneRecord) {
                $deviceProperty.INTUNE_InDatabase = $false
            } else {
                # device is in Intune
                $deviceProperty.INTUNE_InDatabase = $true

                if ($deviceIntuneRecord.count -gt 1) {
                    # more records with the same name

                    $deviceProperty.INTUNE_MultipleRecords = $deviceIntuneRecord.count

                    Write-Verbose "Device $name is $($deviceIntuneRecord.count)x in Intune database!"

                    # get the correct one by using GUID
                    if (!$deviceGUID) {
                        $deviceGUID = $cmp.ObjectGUID.Guid
                    }
                    if (!$deviceGUID) {
                        $deviceGUID = $deviceProperty.AD_ObjectGUID
                    }
                    if (!$deviceGUID) {
                        $deviceGUID = (Get-ADComputer -Filter "name -eq '$name'" -Property ObjectGUID).ObjectGUID.Guid
                    }
                    if ($deviceGUID) {
                        Write-Verbose "Search for the $name with $deviceGUID GUID in Intune database"
                        $deviceIntuneRecord = @($intuneDevice | ? azureADDeviceId -EQ $deviceGUID)
                    }

                    if ($deviceIntuneRecord.count -gt 1) {
                        # unable to narrow down the results

                        if (!$deviceGUID) {
                            $erMsg = "No GUID property was provided to identify the correct one, nor was found in AD."
                        } else {
                            $erMsg = "Unable to identify the correct one."
                        }
                        Write-Warning "Device $name is $($deviceIntuneRecord.count)x in Intune database.`n$erMsg Therefore setting property deviceIntuneRecord as `$null"
                        $deviceIntuneRecord = $null
                    }
                } else {
                    $deviceProperty.INTUNE_MultipleRecords = $false
                }

                if ($deviceIntuneRecord.count -eq 1) {
                    $deviceProperty.INTUNE_Name = $deviceIntuneRecord.deviceName
                    $deviceProperty.INTUNE_DeviceId = $deviceIntuneRecord.azureADDeviceId
                    $deviceProperty.INTUNE_LastSyncDateTime = $deviceIntuneRecord.lastSyncDateTime
                    $deviceProperty.INTUNE_DeviceRegistrationState = $deviceIntuneRecord.deviceRegistrationState

                    if ($deviceIntuneRecord.deviceEnrollmentType -ne "windowsCoManagement") {
                        $deviceProperty.INTUNE_CoManaged = $false
                    } else {
                        $deviceProperty.INTUNE_CoManaged = $true
                        if (!$deviceProperty.SCCM_CoManaged -and $deviceProperty.SCCM_InDatabase -and $deviceProperty.SCCM_ClientInstalled) {
                            Write-Verbose "According to Intune, $name is co-managed even though SCCM says otherwise"
                        }
                    }

                    if (!$deviceIntuneRecord.aadRegistered -or !$deviceIntuneRecord.azureADRegistered) {
                        $deviceProperty.INTUNE_Registered = $false
                    } else {
                        $deviceProperty.INTUNE_Registered = $true
                    }

                    $deviceProperty.INTUNE_User = $deviceIntuneRecord.emailAddress
                }
            }
        }

        if ($combineDataFrom -contains "AAD") {

            $deviceAADRecord = @($aadDevice | ? DisplayName -EQ $name)

            if (!$deviceAADRecord) {
                Write-Verbose "$name wasn't found in Intune database, trying to get its GUID"

                # try to search for it using its GUID
                if (!$deviceGUID) {
                    $deviceGUID = $cmp.ObjectGUID.Guid
                }
                if (!$deviceGUID) {
                    $deviceGUID = $deviceProperty.AD_ObjectGUID
                }
                if (!$deviceGUID) {
                    $deviceGUID = (Get-ADComputer -Filter "name -eq '$name'" -Property ObjectGUID).ObjectGUID.Guid
                }
                if ($deviceGUID) {
                    Write-Verbose "Search for the $name using its $deviceGUID GUID in AAD database"
                    # search for AAD device with GUID instead of name
                    $deviceAADRecord = @($aadDevice | ? { $_.deviceId -eq $deviceGUID })
                }
            }

            if (!$deviceAADRecord) {
                $deviceProperty.AAD_InDatabase = $false
            } else {
                # device is in AAD
                $deviceProperty.AAD_InDatabase = $true

                if ($deviceAADRecord.count -gt 1) {
                    # more records with the same name

                    $deviceProperty.AAD_MultipleRecords = $deviceAADRecord.count

                    Write-Verbose "Device $name is $($deviceAADRecord.count)x in AAD database!"

                    # get the correct one using GUID
                    if (!$deviceGUID) {
                        $deviceGUID = $cmp.ObjectGUID.Guid
                    }
                    if (!$deviceGUID) {
                        $deviceGUID = $deviceProperty.AD_ObjectGUID
                    }
                    if (!$deviceGUID) {
                        $deviceGUID = (Get-ADComputer -Filter "name -eq '$name'" -Property ObjectGUID).ObjectGUID.Guid
                    }
                    if ($deviceGUID) {
                        Write-Verbose "Search for the $name with $deviceGUID GUID in AAD database"
                        $deviceAADRecord = @($aadDevice | ? deviceID -EQ $deviceGUID)
                    }

                    if ($deviceAADRecord.count -gt 1) {
                        # unable to narrow down the results

                        if (!$deviceGUID) {
                            $erMsg = "No GUID property was provided to identify the correct one, nor was found in AD."
                        } else {
                            $erMsg = "Unable to identify the correct one."
                        }
                        Write-Warning "Device $name is $($deviceAADRecord.count)x in AAD database.`n$erMsg Therefore setting property deviceAADRecord as `$null"
                        $deviceAADRecord = $null
                    }
                } else {
                    $deviceProperty.AAD_MultipleRecords = $false
                }

                if ($deviceAADRecord.count -eq 1) {
                    $deviceProperty.AAD_Name = $deviceAADRecord.displayName
                    $deviceProperty.AAD_LastActiveTime = $deviceAADRecord.approximateLastSignInDateTime
                    $deviceProperty.AAD_Owner = $deviceAADRecord.deviceOwnership
                    $deviceProperty.AAD_IsCompliant = $deviceAADRecord.isCompliant
                    $deviceProperty.AAD_DeviceId = $deviceAADRecord.deviceId
                    $deviceProperty.AAD_EnrollmentType = $deviceAADRecord.enrollmentType
                    $deviceProperty.AAD_IsManaged = $deviceAADRecord.isManaged
                    $deviceProperty.AAD_ManagementType = $deviceAADRecord.managementType
                    $deviceProperty.AAD_OnPremisesSyncEnabled = $deviceAADRecord.onPremisesSyncEnabled
                    $deviceProperty.AAD_ProfileType = $deviceAADRecord.profileType
                }
            }
        }

        New-Object -TypeName PSObject -Property $deviceProperty
    } # end of foreach
}

function Invoke-IntuneScriptRedeploy {
    <#
    .SYNOPSIS
    Function for forcing redeploy of selected Script(s) deployed from Intune.
    Scripts and Remediation scripts can be redeployed.

    .DESCRIPTION
    Function for forcing redeploy of selected Script(s) deployed from Intune.
    Scripts and Remediation scripts can be redeployed.

    OutGridView is used to output found Scripts.

    Redeploy means that corresponding registry keys will be deleted from registry and service IntuneManagementExtension will be restarted.

    .PARAMETER computerName
    Name of remote computer where you want to force the redeploy.

    .PARAMETER scriptType
    Mandatory parameter for selecting type of the script you want to show&redeploy.
    Possible values are script, remediationScript.

    .PARAMETER getDataFromIntune
    Switch for getting Scripts and User names from Intune, so locally used IDs can be translated to them.

    .PARAMETER credential
    Credential object used for Intune authentication.

    .PARAMETER tenantId
    Azure Tenant ID.
    Requirement for Intune App authentication.

    .EXAMPLE
    Invoke-IntuneScriptRedeploy -scriptType script

    Get and show common Script(s) deployed from Intune to this computer. Selected ones will be then redeployed.

    .EXAMPLE
    Invoke-IntuneScriptRedeploy -scriptType remediationScript

    Get and show Remediation Script(s) deployed from Intune to this computer. Selected ones will be then redeployed.

    .EXAMPLE
    Invoke-IntuneScriptRedeploy -scriptType remediationScript -computerName PC-01 -getDataFromIntune credential $creds

    Get and show Script(s) deployed from Intune to computer PC-01. IDs of scripts and targeted users will be translated to corresponding names. Selected ones will be then redeployed.

    .EXAMPLE
    Invoke-IntuneScriptRedeploy -scriptType remediationScript -computerName PC-01 -getDataFromIntune credential $creds -tenantId 123456789

    Get and show Script(s) deployed from Intune to computer PC-01. App authentication will be used instead of user auth.
    IDs of scripts and targeted users will be translated to corresponding names. Selected ones will be then redeployed.
    #>

    [CmdletBinding()]
    param (
        [string] $computerName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('script', 'remediationScript')]
        [string] $scriptType,

        [switch] $getDataFromIntune,

        [System.Management.Automation.PSCredential] $credential,

        [string] $tenantId
    )

    #region helper function
    function _getIntuneScript {
        param ([string] $scriptID)

        $intuneScript | ? id -EQ $scriptID
    }

    function _getRemediationScript {
        param ([string] $scriptID)
        $intuneRemediationScript | ? id -EQ $scriptID
    }
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

    # create helper functions text definition for usage in remote sessions
    if ($computerName) {
        $allFunctionDefs = "function _getTargetName { ${function:_getTargetName} }; function _getIntuneScript { ${function:_getIntuneScript} }; function _getRemediationScript { ${function:_getRemediationScript} }"
    }
    #endregion helper function

    #region prepare
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
        if ($scriptType -eq "remediationScript") {
            $intuneRemediationScript = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts?select=id,displayname" | Get-MSGraphAllPages
        }
        if ($scriptType -eq "script") {
            $intuneScript = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts?select=id,displayname" | Get-MSGraphAllPages
        }
        $intuneUser = Invoke-MSGraphRequest -Url 'https://graph.microsoft.com/beta/users?select=id,userPrincipalName' | Get-MSGraphAllPages
    }

    if ($computerName) {
        $session = New-PSSession -ComputerName $computerName -ErrorAction Stop
    } else {
        if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            throw "Run as administrator"
        }
    }
    #endregion prepare

    #region get data
    if ($scriptType -eq 'script') {
        #region script
        $scriptBlock = {
            param($verbosePref, $getDataFromIntune, $intuneScript, $intuneUser, $allFunctionDefs)

            # inherit verbose settings from host session
            $VerbosePreference = $verbosePref

            # recreate functions from their text definitions
            . ([ScriptBlock]::Create($allFunctionDefs))

            Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Policies" -ErrorAction SilentlyContinue | % {
                $userAzureObjectID = Split-Path $_.Name -Leaf

                Get-ChildItem $_.PSPath | % {
                    $scriptRegPath = $_.PSPath
                    $scriptID = Split-Path $_.Name -Leaf

                    Write-Verbose "`tID $scriptID"

                    $scriptRegData = Get-ItemProperty $scriptRegPath

                    # get output of the invoked script
                    if ($scriptRegData.ResultDetails) {
                        try {
                            $resultDetails = $scriptRegData.ResultDetails | ConvertFrom-Json -ErrorAction Stop | select -ExpandProperty ExecutionMsg
                        } catch {
                            Write-Verbose "`tUnable to get Script Output data"
                        }
                    } else {
                        $resultDetails = $null
                    }

                    if ($getDataFromIntune) {
                        $property = [ordered]@{
                            "Scope"                   = _getTargetName $userAzureObjectID
                            "DisplayName"             = (_getIntuneScript $scriptID).DisplayName
                            "Id"                      = $scriptID
                            "Result"                  = $scriptRegData.Result
                            "ErrorCode"               = $scriptRegData.ErrorCode
                            "DownloadAndExecuteCount" = $scriptRegData.DownloadCount
                            "LastUpdatedTimeUtc"      = $scriptRegData.LastUpdatedTimeUtc
                            "RunAsAccount"            = $scriptRegData.RunAsAccount
                            "ResultDetails"           = $resultDetails
                        }
                    } else {
                        # no 'DisplayName' property
                        $property = [ordered]@{
                            "Scope"                   = _getTargetName $userAzureObjectID
                            "Id"                      = $scriptID
                            "Result"                  = $scriptRegData.Result
                            "ErrorCode"               = $scriptRegData.ErrorCode
                            "DownloadAndExecuteCount" = $scriptRegData.DownloadCount
                            "LastUpdatedTimeUtc"      = $scriptRegData.LastUpdatedTimeUtc
                            "RunAsAccount"            = $scriptRegData.RunAsAccount
                            "ResultDetails"           = $resultDetails
                        }
                    }

                    New-Object -TypeName PSObject -Property $property
                }
            }
        }

        $param = @{
            scriptBlock  = $scriptBlock
            argumentList = ($VerbosePreference, $getDataFromIntune, $intuneScript, $intuneUser, $allFunctionDefs)
        }
        if ($computerName) {
            $param.session = $session
        }

        $script = Invoke-Command @param | select -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName
        #region script
    }

    #region remediation script
    if ($scriptType -eq 'remediationScript') {
        $scriptBlock = {
            param($verbosePref, $getDataFromIntune, $intuneRemediationScript, $intuneUser, $allFunctionDefs)

            # inherit verbose settings from host session
            $VerbosePreference = $verbosePref

            # recreate functions from their text definitions
            . ([ScriptBlock]::Create($allFunctionDefs))

            Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts\Reports" -ErrorAction SilentlyContinue | % {
                $userAzureObjectID = Split-Path $_.Name -Leaf
                $userRemScriptRoot = $_.PSPath

                # $lastFullReportTimeUTC = Get-ItemPropertyValue $userRemScriptRoot -Name LastFullReportTimeUTC
                $remScriptIDList = Get-ChildItem $userRemScriptRoot | select -ExpandProperty PSChildName | % { $_ -replace "_\d+$" } | select -Unique

                $remScriptIDList | % {
                    $remScriptID = $_

                    Write-Verbose "`tID $remScriptID"

                    $newestRemScriptRecord = Get-ChildItem $userRemScriptRoot | ? PSChildName -Match ([regex]::escape($remScriptID)) | Sort-Object -Descending -Property PSChildName | select -First 1

                    try {
                        $result = Get-ItemPropertyValue "$($newestRemScriptRecord.PSPath)\Result" -Name Result | ConvertFrom-Json
                    } catch {
                        Write-Verbose "`tUnable to get Remediation Script Result data"
                    }

                    $lastExecution = Get-ItemPropertyValue "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts\Execution\$userAzureObjectID\$($newestRemScriptRecord.PSChildName)" -Name LastExecution

                    if ($getDataFromIntune) {
                        $property = [ordered]@{
                            "Scope"                             = _getTargetName $userAzureObjectID
                            "DisplayName"                       = (_getRemediationScript $remScriptID).DisplayName
                            "Id"                                = $remScriptID
                            "LastError"                         = $result.ErrorCode
                            "LastExecution"                     = $lastExecution
                            # LastFullReportTimeUTC               = $lastFullReportTimeUTC
                            "InternalVersion"                   = $result.InternalVersion
                            "PreRemediationDetectScriptOutput"  = $result.PreRemediationDetectScriptOutput
                            "PreRemediationDetectScriptError"   = $result.PreRemediationDetectScriptError
                            "RemediationScriptErrorDetails"     = $result.RemediationScriptErrorDetails
                            "PostRemediationDetectScriptOutput" = $result.PostRemediationDetectScriptOutput
                            "PostRemediationDetectScriptError"  = $result.PostRemediationDetectScriptError
                            "RemediationExitCode"               = $result.Info.RemediationExitCode
                            "FirstDetectExitCode"               = $result.Info.FirstDetectExitCode
                            "LastDetectExitCode"                = $result.Info.LastDetectExitCode
                            "ErrorDetails"                      = $result.Info.ErrorDetails
                        }
                    } else {
                        # no 'DisplayName' property
                        $property = [ordered]@{
                            "Scope"                             = _getTargetName $userAzureObjectID
                            "Id"                                = $remScriptID
                            "LastError"                         = $result.ErrorCode
                            "LastExecution"                     = $lastExecution
                            # LastFullReportTimeUTC               = $lastFullReportTimeUTC
                            "InternalVersion"                   = $result.InternalVersion
                            "PreRemediationDetectScriptOutput"  = $result.PreRemediationDetectScriptOutput
                            "PreRemediationDetectScriptError"   = $result.PreRemediationDetectScriptError
                            "RemediationScriptErrorDetails"     = $result.RemediationScriptErrorDetails
                            "PostRemediationDetectScriptOutput" = $result.PostRemediationDetectScriptOutput
                            "PostRemediationDetectScriptError"  = $result.PostRemediationDetectScriptError
                            "RemediationExitCode"               = $result.Info.RemediationExitCode
                            "FirstDetectExitCode"               = $result.Info.FirstDetectExitCode
                            "LastDetectExitCode"                = $result.Info.LastDetectExitCode
                            "ErrorDetails"                      = $result.Info.ErrorDetails
                        }
                    }

                    New-Object -TypeName PSObject -Property $property
                }
            }
        }

        $param = @{
            scriptBlock  = $scriptBlock
            argumentList = ($VerbosePreference, $getDataFromIntune, $intuneRemediationScript, $intuneUser, $allFunctionDefs)
        }
        if ($computerName) {
            $param.session = $session
        }

        $script = Invoke-Command @param | select -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName
    }
    #endregion remediation script

    #endregion get data

    #region let user redeploy chosen app
    if ($script) {
        $scriptToRedeploy = $script | Out-GridView -PassThru -Title "Pick script(s) for redeploy"

        if ($scriptToRedeploy) {
            $scriptBlock = {
                param ($verbosePref, $scriptToRedeploy, $scriptType)

                # inherit verbose settings from host session
                $VerbosePreference = $verbosePref

                if ($scriptType -eq 'script') {
                    $scriptKeys = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Policies" -Recurse -Depth 2 | select PSChildName, PSPath, PSParentPath
                } elseif ($scriptType -eq 'remediationScript') {
                    # from Reports the key is deleted to be consistent (to have report without last execution can be weird)
                    $scriptKeys = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts\Execution", "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts\Reports" -Recurse -Depth 2 | select PSChildName, PSPath, PSParentPath
                }

                $scriptToRedeploy | % {
                    $scriptId = $_.id
                    $scopeId = $_.scope
                    if ($scopeId -eq 'device') { $scopeId = "00000000-0000-0000-0000-000000000000" }
                    Write-Warning "Preparing redeploy for script $scriptId (scope $scopeId)"

                    $win32AppKeyToDelete = $scriptKeys | ? { $_.PSChildName -Match "^$scriptId(_\d+)?" -and $_.PSParentPath -Match "\\$scopeId$" }

                    if ($win32AppKeyToDelete) {
                        $win32AppKeyToDelete | % {
                            Write-Verbose "Deleting $($_.PSPath)"
                            Remove-Item $_.PSPath -Force -Recurse
                        }
                    } else {
                        throw "BUG??? Script $scriptId with scope $scopeId wasn't found in the registry"
                    }
                }

                Write-Warning "Invoking redeploy (by restarting service IntuneManagementExtension). Redeploy can take several minutes!"
                Restart-Service IntuneManagementExtension -Force
            }

            $param = @{
                scriptBlock  = $scriptBlock
                argumentList = ($VerbosePreference, $scriptToRedeploy, $scriptType)
            }
            if ($computerName) {
                $param.session = $session
            }

            Invoke-Command @param
        }
    } else {
        Write-Warning "No deployed script detected"
    }
    #endregion let user redeploy chosen app

    if ($computerName) {
        Remove-PSSession $session
    }
}

function Invoke-IntuneWin32AppRedeploy {
    <#
    .SYNOPSIS
    Function for forcing redeploy of selected Win32App deployed from Intune.

    .DESCRIPTION
    Function for forcing redeploy of selected Win32App deployed from Intune.

    OutGridView is used to output found Apps.

    Redeploy means that corresponding registry keys will be deleted from registry and service IntuneManagementExtension will be restarted.

    .PARAMETER computerName
    Name of remote computer where you want to force the redeploy.

    .PARAMETER getDataFromIntune
    Switch for getting Apps and User names from Intune, so locally used IDs can be translated to them.

    .PARAMETER credential
    Credential object used for Intune authentication.

    .PARAMETER tenantId
    Azure Tenant ID.
    Requirement for Intune App authentication.

    .PARAMETER excludeSystemApp
    Switch for excluding Apps targeted to SYSTEM.

    .EXAMPLE
    Invoke-IntuneWin32AppRedeploy

    Get and show Win32App(s) deployed from Intune to this computer. Selected ones will be then redeployed.

    .EXAMPLE
    Invoke-IntuneWin32AppRedeploy -computerName PC-01 -getDataFromIntune credential $creds

    Get and show Win32App(s) deployed from Intune to computer PC-01. IDs of apps and targeted users will be translated to corresponding names. Selected ones will be then redeployed.
    #>

    [CmdletBinding()]
    param (
        [string] $computerName,

        [switch] $getDataFromIntune,

        [System.Management.Automation.PSCredential] $credential,

        [string] $tenantId,

        [switch] $excludeSystemApp
    )

    #region helper function
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

    function _getIntuneApp {
        param ([string] $appID)

        $intuneApp | ? id -EQ $appID
    }

    # create helper functions text definition for usage in remote sessions
    if ($computerName) {
        $allFunctionDefs = "function _getTargetName { ${function:_getTargetName} }; function _getIntuneApp { ${function:_getIntuneApp} }"
    }
    #endregion helper function

    #region prepare
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
        $intuneApp = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?select=id,displayname" | Get-MSGraphAllPages
        $intuneUser = Invoke-MSGraphRequest -Url 'https://graph.microsoft.com/beta/users?select=id,userPrincipalName' | Get-MSGraphAllPages
    }

    if ($computerName) {
        $session = New-PSSession -ComputerName $computerName -ErrorAction Stop
    } else {
        if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            throw "Run as administrator"
        }
    }
    #endregion prepare

    #region get data
    $scriptBlock = {
        param($verbosePref, $excludeSystemApp, $getDataFromIntune, $intuneApp, $intuneUser, $allFunctionDefs)

        # inherit verbose settings from host session
        $VerbosePreference = $verbosePref

        # recreate functions from their text definitions
        . ([ScriptBlock]::Create($allFunctionDefs))

        foreach ($app in (Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps" -ErrorAction SilentlyContinue)) {
            $userAzureObjectID = Split-Path $app.Name -Leaf

            if ($excludeSystemApp -and $userAzureObjectID -eq "00000000-0000-0000-0000-000000000000") {
                Write-Verbose "Skipping system deployments"
                continue
            }

            $userWin32AppRoot = $app.PSPath
            $win32AppIDList = Get-ChildItem $userWin32AppRoot | select -ExpandProperty PSChildName | % { $_ -replace "_\d+$" } | select -Unique

            $win32AppIDList | % {
                $win32AppID = $_

                Write-Verbose "Processing App ID $win32AppID"

                $newestWin32AppRecord = Get-ChildItem $userWin32AppRoot | ? PSChildName -Match ([regex]::escape($win32AppID)) | Sort-Object -Descending -Property PSChildName | select -First 1

                $lastUpdatedTimeUtc = Get-ItemPropertyValue $newestWin32AppRecord.PSPath -Name LastUpdatedTimeUtc
                try {
                    $complianceStateMessage = Get-ItemPropertyValue "$($newestWin32AppRecord.PSPath)\ComplianceStateMessage" -Name ComplianceStateMessage -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Write-Verbose "`tUnable to get Compliance State Message data"
                }
                try {
                    $enforcementStateMessage = Get-ItemPropertyValue "$($newestWin32AppRecord.PSPath)\EnforcementStateMessage" -Name EnforcementStateMessage -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Write-Verbose "`tUnable to get Enforcement State Message data"
                }

                $lastError = $complianceStateMessage.ErrorCode
                if (!$lastError) { $lastError = 0 } # because of HTML conditional formatting ($null means that cell will have red background)

                if ($getDataFromIntune) {
                    $property = [ordered]@{
                        "Scope"              = _getTargetName $userAzureObjectID
                        "DisplayName"        = (_getIntuneApp $win32AppID).DisplayName
                        "Id"                 = $win32AppID
                        "LastUpdatedTimeUtc" = $lastUpdatedTimeUtc
                        # "Status"            = $complianceStateMessage.ComplianceState
                        "ProductVersion"     = $complianceStateMessage.ProductVersion
                        "LastError"          = $lastError
                        "ScopeId"            = $userAzureObjectID
                    }
                } else {
                    # no 'DisplayName' property
                    $property = [ordered]@{
                        "ScopeId"            = _getTargetName $userAzureObjectID
                        "Id"                 = $win32AppID
                        "LastUpdatedTimeUtc" = $lastUpdatedTimeUtc
                        # "Status"            = $complianceStateMessage.ComplianceState
                        "ProductVersion"     = $complianceStateMessage.ProductVersion
                        "LastError"          = $lastError
                    }
                }

                New-Object -TypeName PSObject -Property $property
            }
        }
    }

    $param = @{
        scriptBlock  = $scriptBlock
        argumentList = ($VerbosePreference, $excludeSystemApp, $getDataFromIntune, $intuneApp, $intuneUser, $allFunctionDefs)
    }
    if ($computerName) {
        $param.session = $session
    }

    $win32App = Invoke-Command @param | select -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName
    #endregion get data

    #region let user redeploy chosen app
    if ($win32App) {
        $hasDisplayNameProp = $win32App | Get-Member -Name DisplayName
        $appToRedeploy = $win32App | ? { if ($hasDisplayNameProp) { if ($_.DisplayName) { $true } } else { $true } } | Out-GridView -PassThru -Title "Pick app(s) for redeploy"

        if ($appToRedeploy) {
            $scriptBlock = {
                param ($verbosePref, $appToRedeploy)

                # inherit verbose settings from host session
                $VerbosePreference = $verbosePref

                $win32AppKeys = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps" -Recurse -Depth 2 | select PSChildName, PSPath, PSParentPath

                $appToRedeploy | % {
                    $appId = $_.id
                    $scopeId = $_.scopeId
                    if ($scopeId -eq 'device') { $scopeId = "00000000-0000-0000-0000-000000000000" }
                    Write-Warning "Preparing redeploy for app $appId (scope $scopeId)"

                    $win32AppKeyToDelete = $win32AppKeys | ? { $_.PSChildName -Match "^$appId`_\d+" -and $_.PSParentPath -Match "\\$scopeId$" }

                    if ($win32AppKeyToDelete) {
                        $win32AppKeyToDelete | % {
                            Write-Verbose "Deleting $($_.PSPath)"
                            Remove-Item $_.PSPath -Force -Recurse
                        }
                    } else {
                        throw "BUG??? App $appId with scope $scopeId wasn't found in the registry"
                    }
                }

                Write-Warning "Invoking redeploy (by restarting service IntuneManagementExtension). Redeploy can take several minutes!"
                Restart-Service IntuneManagementExtension -Force
            }

            $param = @{
                scriptBlock  = $scriptBlock
                argumentList = ($VerbosePreference, $appToRedeploy)
            }
            if ($computerName) {
                $param.session = $session
            }

            Invoke-Command @param
        }
    } else {
        Write-Warning "No deployed Win32App detected"
    }
    #endregion let user redeploy chosen app

    if ($computerName) {
        Remove-PSSession $session
    }
}

function Invoke-MDMReenrollment {
    <#
    .SYNOPSIS
    Function for resetting device Intune management connection.

    .DESCRIPTION
	Force re-enrollment of Intune managed devices.

    It will:
     - remove Intune certificates
     - remove Intune scheduled tasks & registry keys
     - force re-enrollment via DeviceEnroller.exe

    .PARAMETER computerName
    (optional) Name of the remote computer, which you want to re-enroll.

    .PARAMETER asSystem
    Switch for invoking re-enroll as a SYSTEM instead of logged user.

    .EXAMPLE
    Invoke-MDMReenrollment

    Invoking re-enroll to Intune on local computer under logged user.

    .EXAMPLE
    Invoke-MDMReenrollment -computerName PC-01 -asSystem

    Invoking re-enroll to Intune on computer PC-01 under SYSTEM account.

	.NOTES
    https://www.maximerastello.com/manually-re-enroll-a-co-managed-or-hybrid-azure-ad-join-windows-10-pc-to-microsoft-intune-without-loosing-current-configuration/

	Based on work of MauriceDaly.
    #>

    [Alias("Invoke-IntuneReenrollment")]
    [CmdletBinding()]
    param (
        [string] $computerName,

        [switch] $asSystem
    )

    if ($computerName -and $computerName -in "localhost", $env:COMPUTERNAME) {
        if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            throw "You don't have administrator rights"
        }
    }

    $allFunctionDefs = "function Invoke-AsSystem { ${function:Invoke-AsSystem} }"

    $scriptBlock = {
        param ($allFunctionDefs, $asSystem)

        try {
            foreach ($functionDef in $allFunctionDefs) {
                . ([ScriptBlock]::Create($functionDef))
            }

            Write-Host "Checking for MDM certificate in computer certificate store"

            # Check&Delete MDM device certificate
            Get-ChildItem 'Cert:\LocalMachine\My\' | ? Issuer -EQ "CN=Microsoft Intune MDM Device CA" | % {
                Write-Host " - Removing Intune certificate $($_.DnsNameList.Unicode)"
                Remove-Item $_.PSPath
            }

            # Obtain current management GUID from Task Scheduler
            $EnrollmentGUID = Get-ScheduledTask | Where-Object { $_.TaskPath -like "*Microsoft*Windows*EnterpriseMgmt\*" } | Select-Object -ExpandProperty TaskPath -Unique | Where-Object { $_ -like "*-*-*" } | Split-Path -Leaf

            # Start cleanup process
            if ($EnrollmentGUID) {
                $EnrollmentGUID | % {
                    $GUID = $_

                    Write-Host "Current enrollment GUID detected as $GUID"

                    # Stop Intune Management Exention Agent and CCM Agent services
                    Write-Host "Stopping MDM services"
                    if (Get-Service -Name IntuneManagementExtension -ErrorAction SilentlyContinue) {
                        Write-Host " - Stopping IntuneManagementExtension service..."
                        Stop-Service -Name IntuneManagementExtension
                    }
                    if (Get-Service -Name CCMExec -ErrorAction SilentlyContinue) {
                        Write-Host " - Stopping CCMExec service..."
                        Stop-Service -Name CCMExec
                    }

                    # Remove task scheduler entries
                    Write-Host "Removing task scheduler Enterprise Management entries for GUID - $GUID"
                    Get-ScheduledTask | Where-Object { $_.Taskpath -match $GUID } | Unregister-ScheduledTask -Confirm:$false
                    # delete also parent folder
                    Remove-Item -Path "$env:WINDIR\System32\Tasks\Microsoft\Windows\EnterpriseMgmt\$GUID" -Force

                    $RegistryKeys = "HKLM:\SOFTWARE\Microsoft\Enrollments", "HKLM:\SOFTWARE\Microsoft\Enrollments\Status", "HKLM:\SOFTWARE\Microsoft\EnterpriseResourceManager\Tracked", "HKLM:\SOFTWARE\Microsoft\PolicyManager\AdmxInstalled", "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers", "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts", "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Logger", "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Sessions"
                    foreach ($Key in $RegistryKeys) {
                        Write-Host "Processing registry key $Key"
                        # Remove registry entries
                        if (Test-Path -Path $Key) {
                            # Search for and remove keys with matching GUID
                            Write-Host " - GUID entry found in $Key. Removing..."
                            Get-ChildItem -Path $Key | Where-Object { $_.Name -match $GUID } | Remove-Item -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
                        }
                    }
                }

                # Start Intune Management Extension Agent service
                Write-Host "Starting MDM services"
                if (Get-Service -Name IntuneManagementExtension -ErrorAction SilentlyContinue) {
                    Write-Host " - Starting IntuneManagementExtension service..."
                    Start-Service -Name IntuneManagementExtension
                }
                if (Get-Service -Name CCMExec -ErrorAction SilentlyContinue) {
                    Write-Host " - Starting CCMExec service..."
                    Start-Service -Name CCMExec
                }

                # Sleep
                Write-Host "Waiting for 30 seconds prior to running DeviceEnroller"
                Start-Sleep -Seconds 30

                # Start re-enrollment process
                Write-Host "Calling: DeviceEnroller.exe /C /AutoenrollMDM"
                if ($asSystem) {
                    Invoke-AsSystem -runAs SYSTEM -scriptBlock { Start-Process -FilePath "$env:WINDIR\System32\DeviceEnroller.exe" -ArgumentList "/C /AutoenrollMDM" -NoNewWindow -Wait -PassThru }
                } else {
                    Start-Process -FilePath "$env:WINDIR\System32\DeviceEnroller.exe" -ArgumentList "/C /AutoenrollMDM" -NoNewWindow -Wait -PassThru
                }
            } else {
                throw "Unable to obtain enrollment GUID value from task scheduler. Aborting"
            }
        } catch [System.Exception] {
            throw "Error message: $($_.Exception.Message)"
        }
    }

    $param = @{
        scriptBlock  = $scriptBlock
        argumentList = $allFunctionDefs, $asSystem
    }

    if ($computerName -and $computerName -notin "localhost", $env:COMPUTERNAME) {
        $param.computerName = $computerName
    }

    Invoke-Command @param
}

function Invoke-ReRegisterDeviceToIntune {
    <#
    .SYNOPSIS
    Function for repairing Intune join connection. Useful if you delete device from AAD etc.

    .DESCRIPTION
    Function for repairing Intune join connection. Useful if you delete device from AAD etc.

    .PARAMETER joinType
    Possible values are: 'hybridAADJoined', 'AADJoined', 'AADRegistered'

    .EXAMPLE
    Invoke-ReRegisterDeviceToIntune -joinType 'hybridAADJoined'

    .NOTES
    # https://docs.microsoft.com/en-us/azure/active-directory/devices/faq
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('hybridAADJoined', 'AADJoined', 'AADRegistered')]
        [string] $joinType
    )

    if ($joinType -eq 'hybridAADJoined') {
        dsregcmd.exe /debug /leave

        Write-Warning "Now manually synchronize device to Azure by running: Sync-ADtoAzure"
        $choice = ""
        while ($choice -notmatch "^[Y|N]$") {
            $choice = Read-Host "Continue? (Y|N)"
        }
        if ($choice -eq "N") {
            break
        }

        $result = dsregcmd.exe /debug /join
        if ($result -match "Join error subcode: error_missing_device") {
            throw "Join wasn't successful because device is not synchronized in AAD. Run Sync-ADtoAzure command, wait 10 minutes and than on client run: dsregcmd.exe /debug /join"
        } else {
            $result
        }
    } elseif ($joinType -eq 'AADJoined') {
        if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            throw "You don't have administrator rights"
        }

        dsregcmd.exe /forcerecovery

        "Sign out and sign in back to the device to complete the recovery"
    } else {
        "Go to Settings > Accounts > Access Work or School.`nSelect the account and select Disconnect.`nClick on '+ Connect' and register the device again by going through the sign in process."
    }
}

function New-GraphAPIAuthHeader {
    <#
    .SYNOPSIS
    Function for generating header that can be used for authentication of Graph API requests.

    .DESCRIPTION
    Function for generating header that can be used for authentication of Graph API requests.
    Credentials can be given or existing AzureAD session can be reused to obtain auth. header.

    .PARAMETER credential
    Credentials for Graph API authentication (AppID + AppSecret) that will be used to obtain auth. header.

    .PARAMETER reuseExistingAzureADSession
    Switch for using existing AzureAD session (created via Connect-AzureAD) to obtain auth. header.

    .PARAMETER TenantDomainName
    Name of your Azure tenant.

    .PARAMETER showDialogType
    Modify behavior of auth. dialog window.

    Possible values are: auto, always, never.

    Default is 'never'.

    .EXAMPLE
    $header = New-GraphAPIAuthHeader -credential $cred
    $URI = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/'
    $managedDevices = (Invoke-RestMethod -Headers $header -Uri $URI -Method Get).value

    .EXAMPLE
    (there is existing AzureAD session already (made via Connect-AzureAD))
    $header = New-GraphAPIAuthHeader -reuseExistingAzureADSession
    $URI = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/'
    $managedDevices = (Invoke-RestMethod -Headers $header -Uri $URI -Method Get).value

    .NOTES
    https://adamtheautomator.com/powershell-graph-api/#AppIdSecret
    https://thesleepyadmins.com/2020/10/24/connecting-to-microsoft-graphapi-using-powershell/
    https://github.com/microsoftgraph/powershell-intune-samples
    https://tech.nicolonsky.ch/explaining-microsoft-graph-access-token-acquisition/
    https://gist.github.com/psignoret/9d73b00b377002456b24fcb808265c23
    #>

    [CmdletBinding()]
    [Alias("New-IntuneAuthHeader", "Get-IntuneAuthHeader")]
    param (
        [Parameter(ParameterSetName = "authenticate")]
        [System.Management.Automation.PSCredential] $credential,

        [Parameter(ParameterSetName = "reuseSession")]
        [switch] $reuseExistingAzureADSession,

        [ValidateNotNullOrEmpty()]
        $tenantDomainName = $_tenantDomain,

        [ValidateSet('auto', 'always', 'never')]
        [string] $showDialogType = 'never'
    )

    if (!$credential -and !$reuseExistingAzureADSession) {
        $credential = (Get-Credential -Message "Enter AppID as UserName and AppSecret as Password")
    }
    if (!$credential -and !$reuseExistingAzureADSession) { throw "Credentials for creating Graph API authentication header is missing" }

    if (!$tenantDomainName -and !$reuseExistingAzureADSession) { throw "TenantDomainName is missing" }

    Write-Verbose "Getting token"

    if ($reuseExistingAzureADSession) {
        # get auth. token using the existing session created by the AzureAD PowerShell module
        try {
            # test if connection already exists
            $c = Get-AzureADCurrentSessionInfo -ea Stop
        } catch {
            throw "There is no active session to AzureAD. Omit reuseExistingAzureADSession parameter or call this function after Connect-AzureAD."
        }

        try {
            $ErrorActionPreference = "Stop"

            $context = [Microsoft.Open.Azure.AD.CommonLibrary.AzureRmProfileProvider]::Instance.Profile.Context
            $authenticationFactory = [Microsoft.Open.Azure.AD.CommonLibrary.AzureSession]::AuthenticationFactory
            $msGraphEndpointResourceId = "MsGraphEndpointResourceId"
            $msGraphEndpoint = $context.Environment.Endpoints[$msGraphEndpointResourceId]
            $auth = $authenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id.ToString(), $null, [Microsoft.Open.Azure.AD.CommonLibrary.ShowDialog]::$showDialogType, $null, $msGraphEndpointResourceId)

            $token = $auth.AuthorizeRequest($msGraphEndpointResourceId)

            return @{ Authorization = $token }
        } catch {
            throw "Unable to obtain auth. token:`n`n$($_.exception.message)`n`n$($_.invocationInfo.PositionMessage)`n`nTry change of showDialogType parameter?"
        }
    } else {
        # authenticate to obtain the token
        $body = @{
            Grant_Type    = "client_credentials"
            Scope         = "https://graph.microsoft.com/.default"
            Client_Id     = $credential.username
            Client_Secret = $credential.GetNetworkCredential().password
        }

        $connectGraph = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantDomainName/oauth2/v2.0/token" -Method POST -Body $body

        $token = $connectGraph.access_token

        if ($token) {
            return @{ Authorization = "Bearer $($token)" }
        } else {
            throw "Unable to obtain token"
        }
    }
}

function Reset-HybridADJoin {
    <#
    .SYNOPSIS
    Function for resetting Hybrid AzureAD join connection.

    .DESCRIPTION
    Function for resetting Hybrid AzureAD join connection.
    It will:
     - un-join computer from AzureAD (using dsregcmd.exe)
     - remove leftover certificates
     - invoke rejoin (using sched. task 'Automatic-Device-Join')
     - inform user about the result

    .PARAMETER computerName
    (optional) name of the computer you want to rejoin.

    .EXAMPLE
    Reset-HybridADJoin

    Un-join and re-join this computer to AzureAD

    .NOTES
    https://www.maximerastello.com/manually-re-register-a-windows-10-or-windows-server-machine-in-hybrid-azure-ad-join/
    #>

    [CmdletBinding()]
    param (
        [string] $computerName
    )

    Write-Warning "For join AzureAD process to work. Computer account has to exists in AzureAD already (should be synchronized via 'AzureAD Connect')!"

    $allFunctionDefs = "function Invoke-AsSystem { ${function:Invoke-AsSystem} }; function Get-HybridADJoinStatus { ${function:Get-HybridADJoinStatus} }"

    $param = @{
        scriptblock  = {
            param ($allFunctionDefs)

            $ErrorActionPreference = "Stop"

            foreach ($functionDef in $allFunctionDefs) {
                . ([ScriptBlock]::Create($functionDef))
            }

            $dsreg = dsregcmd.exe /status
            if (($dsreg | Select-String "DomainJoined :") -match "NO") {
                throw "Computer is NOT domain joined"
            }

            #region unjoin computer from AzureAD & remove leftover certificates
            "Un-joining $env:COMPUTERNAME from Azure"
            Write-Verbose "by running: Invoke-AsSystem { dsregcmd.exe /leave /debug } -returnTranscript"
            Invoke-AsSystem { dsregcmd.exe /leave /debug } #-returnTranscript

            Start-Sleep 5
            Get-ChildItem 'Cert:\LocalMachine\My\' | ? { $_.Issuer -match "MS-Organization-Access|MS-Organization-P2P-Access \[\d+\]" } | % {
                Write-Host "Removing leftover Hybrid-Join certificate $($_.DnsNameList.Unicode)" -ForegroundColor Cyan
                Remove-Item $_.PSPath
            }
            #endregion unjoin computer from AzureAD & remove leftover certificates

            $dsreg = dsregcmd.exe /status
            if (!(($dsreg | Select-String "AzureAdJoined :") -match "NO")) {
                throw "$env:COMPUTERNAME is still joined to Azure. Run again"
            }

            #region join computer to Azure again
            "Joining $env:COMPUTERNAME to Azure"
            Write-Verbose "by running: Get-ScheduledTask -TaskName Automatic-Device-Join | Start-ScheduledTask"
            Get-ScheduledTask -TaskName "Automatic-Device-Join" | Start-ScheduledTask
            while ((Get-ScheduledTask "Automatic-Device-Join" -ErrorAction silentlyContinue).state -ne "Ready") {
                Start-Sleep 3
                "Waiting for sched. task 'Automatic-Device-Join' to complete"
            }
            if ((Get-ScheduledTask -TaskName "Automatic-Device-Join" | Get-ScheduledTaskInfo | select -exp LastTaskResult) -ne 0) {
                throw "Sched. task Automatic-Device-Join failed. Is $env:COMPUTERNAME synchronized to AzureAD?"
            }
            #endregion join computer to Azure again

            #region check join status
            $hybridADJoinStatus = Get-HybridADJoinStatus -wait 30

            if ($hybridADJoinStatus) {
                "$env:COMPUTERNAME was successfully joined to AAD again. Now you should restart it and run Start-AzureADSync"
            } else {
                Write-Error "Join wasn't successful"
                Write-Warning "Check if device $env:COMPUTERNAME exists in AAD"
                Write-Warning "Run:`ngpupdate /force /target:computer`nSync-ADtoAzure"
                Write-Warning "You can get failure reason via manual join by running: Invoke-AsSystem -scriptBlock {dsregcmd /join /debug} -returnTranscript"
                throw 1
            }
            #endregion check join status
        }

        argumentList = $allFunctionDefs
    }

    if ($computerName -and $computerName -notin "localhost", $env:COMPUTERNAME) {
        $param.computerName = $computerName
    } else {
        if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            throw "You don't have administrator rights"
        }
    }

    Invoke-Command @param
}

function Reset-IntuneEnrollment {
    <#
    .SYNOPSIS
    Function for resetting device Intune management enrollment.

    .DESCRIPTION
    Function for resetting device Intune management enrollment.

    It will:
     - check actual Intune status on device
     - reset Hybrid AzureAD join
     - remove device records from Intune
     - remove Intune enrollment data and invoke re-enrollment

    .PARAMETER computerName
    (optional) Name of the computer.

    .EXAMPLE
    Reset-IntuneEnrollment

    .EXAMPLE
    Reset-IntuneEnrollment -computerName PC-01

    .NOTES
    # How MDM (Intune) enrollment works https://techcommunity.microsoft.com/t5/intune-customer-success/support-tip-understanding-auto-enrollment-in-a-co-managed/ba-p/834780
    #>

    [CmdletBinding()]
    [Alias("Repair-IntuneEnrollment", "Reset-IntuneJoin", "Invoke-IntuneEnrollmentReset", "Invoke-IntuneEnrollmentRepair")]
    param (
        [string] $computerName = $env:COMPUTERNAME
    )

    $ErrorActionPreference = "Stop"

    if (!(Get-Module "Microsoft.Graph.Intune" -ListAvailable)) {
        throw "Module Microsoft.Graph.Intune is missing (use Install-Module Microsoft.Graph.Intune to get it)"
    }

    #region check Intune enrollment result
    Write-Host "Checking actual Intune enrollment status" -ForegroundColor Cyan
    if (Get-IntuneEnrollmentStatus -computerName $computerName) {
        $choice = ""
        while ($choice -notmatch "^[Y|N]$") {
            $choice = Read-Host "It seems computer $computerName is correctly enrolled to Intune. Continue? (Y|N)"
        }
        if ($choice -eq "N") {
            break
        }
    }
    #endregion check Intune enrollment result

    #region reset Hybrid AzureAD if necessary
    if (!(Get-HybridADJoinStatus -computerName $computerName)) {
        Write-Host "Resetting Hybrid AzureAD connection, because there is some problem" -ForegroundColor Cyan
        Reset-HybridADJoin -computerName $computerName

        Write-Host "Waiting" -ForegroundColor Cyan
        Start-Sleep 10
    } else {
        Write-Verbose "Hybrid Join status of the $computerName is OK"
    }
    #endregion reset Hybrid AzureAD if necessary

    #region remove computer record from Intune
    Write-Host "Removing $computerName records from Intune" -ForegroundColor Cyan
    # to discover cases when device is in Intune named as GUID_date
    if (Get-Command Get-ADComputer -ErrorAction SilentlyContinue) {
        $ADObj = Get-ADComputer -Filter "Name -eq '$computerName'" -Properties Name, ObjectGUID
    } else {
        Write-Verbose "AD module is missing, unable to obtain computer GUID"
    }

    #region get Intune data
    Connect-MSGraph2

    $IntuneObj = @()

    # search device by name
    $IntuneObj += Get-IntuneManagedDevice -Filter "DeviceName eq '$computerName'"

    # search device by GUID
    if ($ADObj.ObjectGUID) {
        # because of bug? computer can be listed under guid_date name in cloud
        $IntuneObj += Get-IntuneManagedDevice -Filter "azureADDeviceId eq '$($ADObj.ObjectGUID)'" | ? DeviceName -NE $computerName
    }
    #endregion get Intune data

    if ($IntuneObj) {
        $IntuneObj | ? { $_ } | % {
            Write-Host "Removing $($_.DeviceName) ($($_.id)) from Intune" -ForegroundColor Cyan
            Remove-IntuneManagedDevice -managedDeviceId $_.id
        }
    } else {
        Write-Host "$computerName nor its guid exists in Intune. Skipping removal." -ForegroundColor DarkCyan
    }
    #endregion remove computer record from Intune

    Write-Host "Invoking re-enrollment of Intune connection" -ForegroundColor Cyan
    Invoke-MDMReenrollment -computerName $computerName -asSystem

    #region check Intune enrollment result
    Write-Host "Waiting 15 seconds before checking the result" -ForegroundColor Cyan
    Start-Sleep 15

    $intuneEnrollmentStatus = Get-IntuneEnrollmentStatus -computerName $computerName -wait 30

    if ($intuneEnrollmentStatus) {
        Write-Host "DONE :)" -ForegroundColor Green
    } else {
        "Opening Intune logs on $computerName"
        Get-IntuneLog -computerName $computerName
    }
    #endregion check Intune enrollment result
}

Export-ModuleMember -function Connect-MSGraph2, ConvertFrom-MDMDiagReport, ConvertFrom-MDMDiagReportXML, Get-BitlockerEscrowStatusForAzureADDevices, Get-ClientIntunePolicyResult, Get-HybridADJoinStatus, Get-IntuneDeviceComplianceStatus, Get-IntuneEnrollmentStatus, Get-IntuneOverallComplianceStatus, Get-IntuneReport, Get-MDMClientData, Invoke-IntuneScriptRedeploy, Invoke-IntuneWin32AppRedeploy, Invoke-MDMReenrollment, Invoke-ReRegisterDeviceToIntune, New-GraphAPIAuthHeader, Reset-HybridADJoin, Reset-IntuneEnrollment

Export-ModuleMember -alias Connect-MSGraphApp2, Get-IntuneAuthHeader, Get-IntuneJoinStatus, Get-IntunePolicyResult, Invoke-IntuneEnrollmentRepair, Invoke-IntuneEnrollmentReset, Invoke-IntuneReenrollment, ipresult, New-IntuneAuthHeader, Repair-IntuneEnrollment, Reset-IntuneJoin
