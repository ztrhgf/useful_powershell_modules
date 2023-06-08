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

    #region helper functions
    function _ConvertFrom-HTMLTable {
        <#
        .SYNOPSIS
        Function for converting ComObject HTML object to common PowerShell object.

        .DESCRIPTION
        Function for converting ComObject HTML object to common PowerShell object.
        ComObject can be retrieved by (Invoke-WebRequest).parsedHtml or IHTMLDocument2_write methods.

        In case table is missing column names and number of columns is:
        - 2
            - Value in the first column will be used as object property 'Name'. Value in the second column will be therefore 'Value' of such property.
        - more than 2
            - Column names will be numbers starting from 1.

        .PARAMETER table
        ComObject representing HTML table.

        .PARAMETER tableName
        (optional) Name of the table.
        Will be added as TableName property to new PowerShell object.
        #>

        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [System.__ComObject] $table,

            [string] $tableName
        )

        $twoColumnsWithoutName = 0

        if ($tableName) { $tableNameTxt = "'$tableName'" }

        $columnName = $table.getElementsByTagName("th") | % { $_.innerText -replace "^\s*|\s*$" }

        if (!$columnName) {
            $numberOfColumns = @($table.getElementsByTagName("tr")[0].getElementsByTagName("td")).count
            if ($numberOfColumns -eq 2) {
                ++$twoColumnsWithoutName
                Write-Verbose "Table $tableNameTxt has two columns without column names. Resultant object will use first column as objects property 'Name' and second as 'Value'"
            } elseif ($numberOfColumns) {
                Write-Warning "Table $tableNameTxt doesn't contain column names, numbers will be used instead"
                $columnName = 1..$numberOfColumns
            } else {
                throw "Table $tableNameTxt doesn't contain column names and summarization of columns failed"
            }
        }

        if ($twoColumnsWithoutName) {
            # table has two columns without names
            $property = [ordered]@{ }

            $table.getElementsByTagName("tr") | % {
                # read table per row and return object
                $columnValue = $_.getElementsByTagName("td") | % { $_.innerText -replace "^\s*|\s*$" }
                if ($columnValue) {
                    # use first column value as object property 'Name' and second as a 'Value'
                    $property.($columnValue[0]) = $columnValue[1]
                } else {
                    # row doesn't contain <td>
                }
            }
            if ($tableName) {
                $property.TableName = $tableName
            }

            New-Object -TypeName PSObject -Property $property
        } else {
            # table doesn't have two columns or they are named
            $table.getElementsByTagName("tr") | % {
                # read table per row and return object
                $columnValue = $_.getElementsByTagName("td") | % { $_.innerText -replace "^\s*|\s*$" }
                if ($columnValue) {
                    $property = [ordered]@{ }
                    $i = 0
                    $columnName | % {
                        $property.$_ = $columnValue[$i]
                        ++$i
                    }
                    if ($tableName) {
                        $property.TableName = $tableName
                    }

                    New-Object -TypeName PSObject -Property $property
                } else {
                    # row doesn't contain <td>, its probably row with column names
                }
            }
        }
    }
    #endregion helper functions

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
        if (!$tableName) { throw "Undefined tableName for $tableOrder. table" }

        $result.$tableName = _ConvertFrom-HTMLTable $_ -tableName $tableName

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

    if (!(Get-Module 'CommonStuff') -and (!(Get-Module 'CommonStuff' -ListAvailable))) {
        throw "Module CommonStuff is missing. To get it use command: Install-Module CommonStuff -Scope CurrentUser"
    }

    Import-Module CommonStuff -Force # to override ConvertFrom-XML function in case user has module PoshFunctions 

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
        $admxPolicyAreaNameMetadata = $xml.MDMEnterpriseDiagnosticsReport.PolicyManager.IngestedAdmxPolicyMetadata | ? { $_ } | % { ConvertFrom-XML $_ }

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
                    if ($policyAreaSetting) {
                        $policyAreaSettingName = $policyAreaSetting | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty name
                    }
                    if ($policyAreaSettingName.count -eq 1 -and $policyAreaSettingName -eq "*") {
                        # bug? when there is just PolicyAreaName and none other object then probably because of exclude $policyAreaSettingName instead of be null returns one empty object '*'
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
                Write-Verbose "Get-ADComputer command is missing, unable to get device GUID. Install RSAT to fix this."
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

function Get-IntuneLog {
    <#
    .SYNOPSIS
    Function for Intune policies debugging on client.
    - opens Intune logs
    - opens event viewer with Intune log
    - generates & open MDMDiagReport.html report

    .DESCRIPTION
    Function for Intune policies debugging on client.
    - opens Intune logs
    - opens event viewer with Intune log
    - generates & open MDMDiagReport.html report

    .PARAMETER computerName
    Name of remote computer.

    .EXAMPLE
    Get-IntuneLog
    #>

    [CmdletBinding()]
    param (
        [string] $computerName
    )

    if ($computerName -and $computerName -in "localhost", $env:COMPUTERNAME) {
        $computerName = $null
    }

    function _openLog {
        param (
            [string[]] $logs
        )

        if (!$logs) { return }

        # use best possible log viewer
        $cmLogViewer = "C:\Program Files (x86)\Microsoft Endpoint Manager\AdminConsole\bin\CMLogViewer.exe"
        $cmTrace = "$env:windir\CCM\CMTrace.exe"
        if (Test-Path $cmLogViewer) {
            $viewer = $cmLogViewer
        } elseif (Test-Path $cmTrace) {
            $viewer = $cmTrace
        }

        if ($viewer -and $viewer -match "CMLogViewer\.exe$") {
            # open all logs in one CMLogViewer instance
            $quotedLog = ($logs | % {
                    "`"$_`""
                }) -join " "
            Start-Process $viewer -ArgumentList $quotedLog
        } else {
            # cmtrace (or notepad) don't support opening multiple logs in one instance, so open each log in separate viewer process
            foreach ($log in $logs) {
                if (!(Test-Path $log -ErrorAction SilentlyContinue)) {
                    Write-Warning "Log $log wasn't found"
                    continue
                }

                Write-Verbose "Opening $log"
                if ($viewer -and $viewer -match "CMTrace\.exe$") {
                    # in case CMTrace viewer exists, use it
                    Start-Process $viewer -ArgumentList "`"$log`""
                } else {
                    # use associated viewer
                    & $log
                }
            }
        }
    }

    # open main Intune logs
    $log = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
    if ($computerName) {
        $log = "\\$computerName\" + ($log -replace ":", "$")
    }
    "opening logs in '$log'"
    _openLog (Get-ChildItem $log -File | select -exp fullname)

    # When a PowerShell script is run on the client from Intune, the scripts and the script output will be stored here, but only until execution is complete
    $log = "C:\Program files (x86)\Microsoft Intune Management Extension\Policies\Scripts"
    if ($computerName) {
        $log = "\\$computerName\" + ($log -replace ":", "$")
    }
    "opening logs in '$log'"
    _openLog (Get-ChildItem $log -File -ea SilentlyContinue | select -exp fullname)

    $log = "C:\Program files (x86)\Microsoft Intune Management Extension\Policies\Results"
    if ($computerName) {
        $log = "\\$computerName\" + ($log -replace ":", "$")
    }
    "opening logs in '$log'"
    _openLog (Get-ChildItem $log -File -ea SilentlyContinue | select -exp fullname)

    # open Event Viewer with Intune Log
    "opening event log 'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin'"
    if ($computerName) {
        Write-Warning "Opening remote Event Viewer can take significant time!"
        mmc.exe eventvwr.msc /computer:$computerName /c:"Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin"
    } else {
        mmc.exe eventvwr.msc /c:"Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin"
    }

    # generate & open MDMDiagReport
    "generating & opening MDMDiagReport"
    if ($computerName) {
        Write-Warning "TODO (zatim delej tak, ze spustis tuto fci lokalne pod uzivatelem, jehoz vysledky chces zjistit"
    } else {
        Start-Process MdmDiagnosticsTool.exe -Wait -ArgumentList "-out $env:TEMP\MDMDiag" -NoNewWindow
        & "$env:TEMP\MDMDiag\MDMDiagReport.html"
    }

    # vygeneruje spoustu bordelu do jednoho zip souboru vhodneho k poslani mailem (bacha muze mit vic jak 5MB)
    # Start-Process MdmDiagnosticsTool.exe -ArgumentList "-area Autopilot;DeviceEnrollment;DeviceProvisioning;TPM -zip C:\temp\aaa.zip" -Verb runas

    # show DM info
    $param = @{
        scriptBlock = { Get-ChildItem -Path HKLM:SOFTWARE\Microsoft\Enrollments -Recurse | where { $_.Property -like "*UPN*" } }
    }
    if ($computerName) {
        $param.computerName = $computerName
    }
    Invoke-Command @param | Format-Table

    # $regKey = "Computer\HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts"
    # if (!(Get-Process regedit)) {
    #     # set starting location for regedit
    #     Set-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit LastKey $regKey
    #     # open regedit
    # } else {
    #     "To check script last run time and result check $regKey in regedit or logs located in C:\Program files (x86)\Microsoft Intune Management Extension\Policies"
    # }
    # regedit.exe
}

function Get-IntuneLogRemediationScriptData {
    <#
    .SYNOPSIS
    Function for getting Intune Remediation Scripts information from clients log files ($env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension*.log).

    .DESCRIPTION
    Function for getting Intune Remediation Scripts information from clients log files ($env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension*.log).

    Finds data about processing of Remediation Scripts and outputs them into console as an PowerShell object.

    .PARAMETER allOccurrences
    Switch for getting all Remediation Scripts processings.
    By default just newest processing is returned from the newest Intune log.

    .PARAMETER excludeProperty
    List of properties to exclude.

    By default: 'EncryptedPolicyBody', 'EncryptedRemediationScript', 'PolicyBodySize', 'PolicyHash', 'RemediateScriptHash', 'ContentSignature'

    Reason for exclude is readability and the fact that I didn't find any documentation that would help me interpret their values or are always empty.

    .EXAMPLE
    Get-IntuneLogRemediationScriptData

    Show various interesting information about Remediation scripts processing.

    .NOTES
    Run on Windows client managed using Intune MDM.
    #>

    [CmdletBinding()]
    param (
        [switch] $allOccurrences,

        [string[]] $excludeProperty = ('EncryptedPolicyBody', 'EncryptedRemediationScript', 'PolicyBodySize', 'PolicyHash', 'RemediateScriptHash', 'ContentSignature')
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
        function _lastPolicyRun {
            #TODO always returns newest run time a.k.a. will be confusing when allOccurrences will be used
            param ($policyId)

            # get line text where script run is mentioned
            # line can look like this
            # <![LOG[[HS] Daily handler: last execution time for 29455f83-3916-4069-88ba-a8e51633e34a is 21.09.2022 6:55:46]
            $param = @{
                Path       = $intuneLog
                Pattern    = ("^" + [regex]::escape('<![LOG[[HS] Daily handler: last execution time for ') + $policyId)
                AllMatches = $true
            }

            $match = Select-String @param | select -ExpandProperty Line -Last 1

            if ($match) {
                Get-Date (([regex]"$policyId is ([0-9.: ]+)").Match($match).groups[1].value)
            } else {
                Write-Verbose "No run of remediation policy $policyId was found"
            }
        }
        #endregion helper functions

        # add properties that gets customized/replaced
        $excludeProperty += 'PolicyBody', 'RemediationScript', 'ExecutionContext'

        $object | select -Property '*',
        @{n = 'LastPolicyRun'; e = { _lastPolicyRun $_.PolicyId } },
        @{n = 'RunAsLoggedUser'; e = { if ($_.ExecutionContext -eq 1) { $true } else { $false } } },
        @{n = 'DetectionScript'; e = { ConvertFrom-Base64 $_.PolicyBody } },
        @{n = 'RemediationScript'; e = { ConvertFrom-Base64 $_.RemediationScript } }`
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
        # <![LOG[[HS] Get policies = [{"AccountId":"db89...0e0ea", "PolicyId":"29455f80...51633e34a", "PolicyType":6, "DocumentSchemaVersion":"1.0", "PolicyHash":"46669E9D4716AD19626DAEECE85B05F1E1F2A7B8C0716109F9F8B10EFA3CF447", "PolicyBody":"PCMNCgkuTk9URV.........

        Write-Verbose "Searching for Script processing in '$intuneLog'"

        # get line text where win32apps processing is mentioned
        $param = @{
            Path       = $intuneLog
            Pattern    = ("^" + [regex]::escape('<![LOG[[HS] Get policies = [{"AccountId":'))
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
                $jsonList = $match -replace [regex]::Escape("<![LOG[[HS] Get policies = [") -replace ([regex]::Escape("]]LOG]!>") + ".*")
                # ugly but working solution :D
                $i = 0
                $jsonListSplitted = $jsonList -split '},{"AccountId":'
                if ($jsonListSplitted.count -gt 1) {
                    # there are multiple JSONs divided by comma, I have to process them one by one
                    $jsonListSplitted | % {
                        # split replaces text that was used to split, I have to recreate it
                        $json = ""
                        if ($i -eq 0) {
                            # first item
                            $json = $_ + '}'
                        } elseif ($i -ne ($jsonListSplitted.count - 1)) {
                            $json = '{"AccountId":' + $_ + '}'
                        } else {
                            # last item
                            $json = '{"AccountId":' + $_
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

function Get-IntunePolicy {
    <#
    .SYNOPSIS
    Function for getting all/subset of Intune (assignable) policies using Graph API.

    .DESCRIPTION
    Function for getting all/subset of Intune (assignable) policies using Graph API.

    These policies can be retrieved:
     - Apps
     - App Configuration policies
     - App Protection policies
     - Compliance policies
     - Configuration policies
      - Administrative Templates
      - Settings Catalog
      - Templates
     - MacOS Custom Attribute Shell Scripts
     - Device Enrollment Configurations
     - Device Management PowerShell scripts
     - Device Management Shell scripts
     - Endpoint Security
        - Account Protection policies
        - Antivirus policies
        - Attack Surface Reduction policies
        - Defender policies
        - Disk Encryption policies
        - Endpoint Detection and Response policies
        - Firewall policies
        - Security baselines
     - iOS App Provisioning profiles
     - iOS Update Configurations
     - MacOS Software Update Configurations
     - Policy Sets
     - Remediation Scripts
     - S Mode Supplemental policies
     - Windows Autopilot Deployment profiles
     - Windows Feature Update profiles
     - Windows Quality Update profiles
     - Windows Update Rings

    .PARAMETER policyType
    What type of policies should be gathered.

    Possible values are:
    'ALL' to get all policies.

    'app','appConfigurationPolicy','appProtectionPolicy','compliancePolicy','configurationPolicy','customAttributeShellScript','deviceEnrollmentConfiguration','deviceManagementPSHScript','deviceManagementShellScript','endpointSecurity','iosAppProvisioningProfile','iosUpdateConfiguration','macOSSoftwareUpdateConfiguration','policySet','remediationScript','sModeSupplementalPolicy','windowsAutopilotDeploymentProfile','windowsFeatureUpdateProfile','windowsQualityUpdateProfile','windowsUpdateRing' to get just some policies subset.

    By default 'ALL' policies are selected.

    .PARAMETER basicOverview
    Switch. Just some common subset of available policy properties will be gathered (id, displayName, lastModifiedDateTime, assignments).
    Makes the result more human readable.

    .PARAMETER flatOutput
    Switch. All Intune policies will be outputted as array instead of one psobject with policies divided into separate sections/object properties.
    Policy parent "type" is added as new property 'PolicyType' to each policy for filtration purposes.

    .EXAMPLE
    Connect-MSGraph
    Get-IntunePolicy

    Get all Intune policies.

    .EXAMPLE
    Connect-MSGraph
    Get-IntunePolicy -policyType 'app', 'compliancePolicy'

    Get just Apps and Compliance Intune policies.

    .EXAMPLE
    Connect-MSGraph
    Get-IntunePolicy -policyType 'app', 'compliancePolicy' -basicOverview

    Get just Apps and Compliance Intune policies with subset of available properties (id, displayName, lastModifiedDateTime, assignments) for each policy.

    .EXAMPLE
    Connect-MSGraph
    Get-IntunePolicy -flatOutput

    Get all Intune policies, but not as one psobject, but as array of all policies.
    #>

    [CmdletBinding()]
    param (
        # if policyType values changes, don't forget to modify 'Search-IntuneAccountPolicyAssignment' accordingly!
        [ValidateSet('ALL', 'app', 'appConfigurationPolicy', 'appProtectionPolicy', 'compliancePolicy', 'configurationPolicy', 'customAttributeShellScript', 'deviceEnrollmentConfiguration', 'deviceManagementPSHScript', 'deviceManagementShellScript', 'endpointSecurity', 'iosAppProvisioningProfile', 'iosUpdateConfiguration', 'macOSSoftwareUpdateConfiguration', 'policySet', 'remediationScript', 'sModeSupplementalPolicy', 'windowsAutopilotDeploymentProfile', 'windowsFeatureUpdateProfile', 'windowsQualityUpdateProfile', 'windowsUpdateRing')]
        [string[]] $policyType = 'ALL',

        [switch] $basicOverview,

        [switch] $flatOutput
    )

    if (!(Get-Module Microsoft.Graph.Intune) -and !(Get-Module Microsoft.Graph.Intune -ListAvailable)) {
        throw "Module Microsoft.Graph.Intune is missing"
    }

    if ($policyType -contains 'ALL') {
        Write-Verbose "ALL policies will be gathered"
        $all = $true
    } else {
        $all = $false
    }

    # create parameters hash for sub-functions and uri parameters for api calls
    if ($basicOverview) {
        Write-Verbose "Just subset of available policy properties will be gathered"
        $selectFilter = '&$select=id,displayName,lastModifiedDateTime,assignments' # these properties are common across all intune policies, so it is safe to use them
        $selectParam = @{select = ('id', 'displayName', 'lastModifiedDateTime', 'assignments') }
        $expandFilter = $null
        $expandParam = @{}
    } else {
        $selectFilter = $null
        $selectParam = @{}
        $expandFilter = '&$expand=assignments'
        $expandParam = @{expand = 'assignments' }
    }

    # progress variables
    $i = 0
    $policyTypeCount = $policyType.Count
    if ($policyType -eq 'ALL') {
        $policyTypeCount = (Get-Variable "policyType").Attributes.ValidValues.count - 1
    }
    $progressActivity = "Getting Intune policies"

    #region get Intune policies
    # define main PS object property hash
    $resultProperty = [ordered]@{}

    # Apps
    if ($all -or $policyType -contains 'app') {
        # https://graph.microsoft.com/beta/deviceAppManagement/mobileApps
        Write-Verbose "Processing Apps"
        Write-Progress -Activity $progressActivity -Status "Processing Apps" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = ("https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$filter=(microsoft.graph.managedApp/appAvailability eq null or microsoft.graph.managedApp/appAvailability eq 'lineOfBusiness' or isAssigned eq true)$expandFilter$selectFilter" -replace "\s+", "%20")
        $app = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.App = $app
    }

    # App Configuration policies
    if ($all -or $policyType -contains 'appConfigurationPolicy') {
        Write-Verbose "Processing App Configuration policies"
        Write-Progress -Activity $progressActivity -Status "Processing App Configuration policies" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $appConfigurationPolicy = @()

        # targetedManagedAppConfigurations
        Write-Verbose "`t- processing 'targetedManagedAppConfigurations'"
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/targetedManagedAppConfigurations?$expandFilter$selectFilter"
        $targetedManagedAppConfigurations = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'
        $targetedManagedAppConfigurations | ? { $_ } | % { $appConfigurationPolicy += $_ }

        # mobileAppConfigurations
        Write-Verbose "`t- processing 'mobileAppConfigurations'"
        $uri = "https://graph.microsoft.com//beta/deviceAppManagement/mobileAppConfigurations?`$filter=(microsoft.graph.androidManagedStoreAppConfiguration/appSupportsOemConfig eq false or isof('microsoft.graph.androidManagedStoreAppConfiguration') eq false)$expandFilter$selectFilter" -replace "\s+", "%20"
        $mobileAppConfigurations = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'
        $mobileAppConfigurations | ? { $_ } | % { $appConfigurationPolicy += $_ }

        if ($appConfigurationPolicy) {
            $resultProperty.AppConfigurationPolicy = $appConfigurationPolicy
        } else {
            $resultProperty.AppConfigurationPolicy = $null
        }
    }

    # App Protection policies
    if ($all -or $policyType -contains 'appProtectionPolicy') {
        Write-Verbose "Processing App Protection policies"
        Write-Progress -Activity $progressActivity -Status "Processing App Protection policies" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $appProtectionPolicy = @()

        # iosManagedAppProtections
        Write-Verbose "`t- processing 'iosManagedAppProtections'"
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/iosManagedAppProtections?$expandFilter$selectFilter"
        $iosManagedAppProtections = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'
        $iosManagedAppProtections | ? { $_ } | % { $appProtectionPolicy += $_ }

        # androidManagedAppProtections
        Write-Verbose "`t- processing 'androidManagedAppProtections'"
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/androidManagedAppProtections?$expandFilter$selectFilter"
        $androidManagedAppProtections = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'
        $androidManagedAppProtections | ? { $_ } | % { $appProtectionPolicy += $_ }

        # targetedManagedAppConfigurations
        Write-Verbose "`t- processing 'targetedManagedAppConfigurations'"
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/targetedManagedAppConfigurations?$expandFilter$selectFilter"
        $targetedManagedAppConfigurations = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'
        $targetedManagedAppConfigurations | ? { $_ } | % { $appProtectionPolicy += $_ }

        # windowsInformationProtectionPolicies
        Write-Verbose "`t- processing 'windowsInformationProtectionPolicies'"
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/windowsInformationProtectionPolicies?$expandFilter$selectFilter"
        $windowsInformationProtectionPolicies = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'
        $windowsInformationProtectionPolicies | ? { $_ } | % { $appProtectionPolicy += $_ }

        # mdmWindowsInformationProtectionPolicies
        Write-Verbose "`t- processing 'mdmWindowsInformationProtectionPolicies'"
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mdmWindowsInformationProtectionPolicies?$expandFilter$selectFilter"
        $mdmWindowsInformationProtectionPolicies = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'
        $mdmWindowsInformationProtectionPolicies | ? { $_ } | % { $appProtectionPolicy += $_ }

        if ($appProtectionPolicy) {
            $resultProperty.AppProtectionPolicy = $appProtectionPolicy
        } else {
            $resultProperty.AppProtectionPolicy = $null
        }
    }

    # Device Compliance
    if ($all -or $policyType -contains 'compliancePolicy') {
        Write-Verbose "Processing Compliance policies"
        Write-Progress -Activity $progressActivity -Status "Processing Compliance policies" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies?$expandFilter$selectFilter"
        $compliancePolicy = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.CompliancePolicy = $compliancePolicy
    }

    # Device Configuration
    # contains all policies as can be seen in Intune web portal 'Device' > 'Device Configuration'
    if ($all -or $policyType -contains 'configurationPolicy') {
        Write-Verbose "Processing Configuration policies"
        Write-Progress -Activity $progressActivity -Status "Processing Configuration policies" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $configurationPolicy = @()

        # Templates profile type
        # api returns also Windows Update Ring policies, but they are filtered, so just policies as in GUI are returned
        Write-Verbose "`t- processing 'deviceConfigurations'"
        $dcTemplate = Invoke-MSGraphRequest -Url ("https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$filter=(not isof('microsoft.graph.windowsUpdateForBusinessConfiguration') and not isof('microsoft.graph.iosUpdateConfiguration'))$expandFilter$selectFilter" -replace "\s+", "%20") | Get-MSGraphAllPages | select * -ExcludeProperty 'assignments@odata.context'
        $dcTemplate | ? { $_ } | % { $configurationPolicy += $_ }

        # Administrative Templates
        Write-Verbose "`t- processing 'groupPolicyConfigurations'"
        $dcAdmTemplate = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations?$expandFilter$selectFilter" | Get-MSGraphAllPages | select * -ExcludeProperty 'assignments@odata.context'
        $dcAdmTemplate | ? { $_ } | % { $configurationPolicy += $_ }

        # mobileAppConfigurations
        Write-Verbose "`t- processing 'mobileAppConfigurations'"
        $dcMobileAppConf = Invoke-MSGraphRequest -Url ("https://graph.microsoft.com/beta/deviceAppManagement/mobileAppConfigurations?`$filter=(microsoft.graph.androidManagedStoreAppConfiguration/appSupportsOemConfig eq true)$expandFilter$selectFilter" -replace "\s+", "%20") | Get-MSGraphAllPages | select * -ExcludeProperty 'assignments@odata.context'
        $dcMobileAppConf | ? { $_ } | % { $configurationPolicy += $_ }

        # Settings Catalog profile type
        # api returns also Attack Surface Reduction Rules and Account protection policies (from Endpoint Security section), but they are filtered, so just policies as in GUI are returned
        # configurationPolicies objects have property Name instead of DisplayName
        Write-Verbose "`t- processing 'configurationPolicies'"
        $custSelectFilter = $selectFilter -replace "displayname", "name"
        if ($basicOverview) {
            $custExpandFilter = $expandFilter
        } else {
            $custExpandFilter = "$expandFilter,settings"
        }
        $dcSettingCatalog = Invoke-MSGraphRequest -Url ("https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=(platforms eq 'windows10' or platforms eq 'macOS' or platforms eq 'iOS') and (technologies eq 'mdm' or technologies eq 'windows10XManagement' or technologies eq 'appleRemoteManagement' or technologies eq 'mdm,appleRemoteManagement') and (templateReference/templateFamily eq 'none')$custExpandFilter$custSelectFilter" -replace "\s+", "%20") | Get-MSGraphAllPages | select @{n = 'Displayname'; e = { $_.Name } }, * -ExcludeProperty 'Name', 'assignments@odata.context'
        $dcSettingCatalog | ? { $_ } | % { $configurationPolicy += $_ }

        if ($configurationPolicy) {
            $resultProperty.ConfigurationPolicy = $configurationPolicy
        } else {
            $resultProperty.ConfigurationPolicy = $null
        }
    }

    # MacOS Custom Attribute Shell scripts
    if ($all -or $policyType -contains 'customAttributeShellScript') {
        Write-Verbose "Processing Custom Attribute Shell scripts"
        Write-Progress -Activity $progressActivity -Status "Processing Custom Attribute Shell scripts" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceCustomAttributeShellScripts?$expandFilter$selectFilter"
        $customAttributeShellScript = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.CustomAttributeShellScript = $customAttributeShellScript
    }

    # ESP, WHFB, Enrollment Limit, Enrollment Platform Restrictions configurations
    if ($all -or $policyType -contains 'deviceEnrollmentConfiguration') {
        Write-Verbose "Processing Device Enrollment configurations: ESP, WHFB, Enrollment Limit, Enrollment Platform Restrictions"
        Write-Progress -Activity $progressActivity -Status "Processing Device Enrollment configurations: ESP, WHFB, Enrollment Limit, Enrollment Platform Restrictions" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?$expandFilter$selectFilter"
        $deviceEnrollmentConfiguration = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.DeviceEnrollmentConfiguration = $deviceEnrollmentConfiguration
    }

    # Device Configuration Powershell Scripts
    if ($all -or $policyType -contains 'deviceManagementPSHScript') {
        Write-Verbose "Processing PowerShell scripts"
        Write-Progress -Activity $progressActivity -Status "Processing PowerShell scripts" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts?$expandFilter$selectFilter"
        $deviceConfigPSHScript = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.DeviceManagementPSHScript = $deviceConfigPSHScript
    }

    # Device Configuration Shell Scripts
    if ($all -or $policyType -contains 'deviceManagementShellScript') {
        Write-Verbose "Processing Shell scripts"
        Write-Progress -Activity $progressActivity -Status "Processing Shell scripts" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceShellScripts?$expandFilter$selectFilter"
        $deviceConfigShellScript = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.DeviceManagementShellScript = $deviceConfigShellScript
    }

    # Security Baselines, Antivirus policies, Defender policies, Disk Encryption policies, Account Protection policies, Local User Group Membership, Firewall, Endpoint detection and response, Attack surface reduction
    if ($all -or $policyType -contains 'endpointSecurity') {
        Write-Verbose "Processing Endpoint Security policies"
        Write-Progress -Activity $progressActivity -Status "Processing Endpoint Security policies" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $endpointSecurityPolicy = @()

        #region process: Security Baselines, Antivirus policies, Defender policies, Disk Encryption policies, Account Protection policies (not 'Local User Group Membership')
        if ($basicOverview) {
            $endpointSecPol = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/intents?$selectFilter" | Get-MSGraphAllPages
        } else {
            $templates = (Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/intents" -ErrorAction Stop).Value
            $endpointSecPol = @()
            foreach ($template in $templates) {
                Write-Verbose "`t- processing intent $($template.id), template $($template.templateId)"

                $settings = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/intents/$($template.id)/settings"
                $templateDetail = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/templates/$($template.templateId)"

                $template | Add-Member Noteproperty -Name 'platforms' -Value $templateDetail.platformType -Force # to match properties of second function region objects
                $template | Add-Member Noteproperty -Name 'type' -Value "$($templateDetail.templateType)-$($templateDetail.templateSubtype)" -Force

                $templSettings = @()
                foreach ($setting in $settings.value) {
                    $displayName = $setting.definitionId -replace "deviceConfiguration--", "" -replace "admx--", "" -replace "_", " "
                    if ($null -eq $setting.value) {
                        if ($setting.definitionId -eq "deviceConfiguration--windows10EndpointProtectionConfiguration_firewallRules") {
                            $v = $setting.valueJson | ConvertFrom-Json
                            foreach ($item in $v) {
                                $templSettings += [PSCustomObject]@{
                                    Name  = "FW Rule - $($item.displayName)"
                                    Value = ($item | ConvertTo-Json)
                                }
                            }
                        } else {
                            $v = ""
                            $templSettings += [PSCustomObject]@{ Name = $displayName; Value = $v }
                        }
                    } else {
                        $v = $setting.value
                        $templSettings += [PSCustomObject]@{ Name = $displayName; Value = $v }
                    }
                }

                $template | Add-Member Noteproperty -Name Settings -Value $templSettings -Force
                $template | Add-Member Noteproperty -Name 'settingCount' -Value $templSettings.count -Force # to match properties of second function region objects
                $assignments = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/intents/$($template.id)/assignments"
                $template | Add-Member Noteproperty -Name Assignments -Value $assignments.Value -Force
                $endpointSecPol += $template | select -Property * -ExcludeProperty templateId
            }
        }
        $endpointSecPol | ? { $_ } | % { $endpointSecurityPolicy += $_ }
        #endregion process: Security Baselines, Antivirus policies, Defender policies, Disk Encryption policies, Account Protection policies (not 'Local User Group Membership')

        #region process: Account Protection policies (just 'Local User Group Membership'), Firewall, Endpoint Detection and Response, Attack Surface Reduction
        if ($basicOverview) {
            $custSelectFilter = $selectFilter -replace "displayname", "name"
            $endpointSecPol2 = Invoke-MSGraphRequest -HttpMethod GET -Url ("https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=(templateReference/templateFamily ne 'none')$expandFilter$custSelectFilter,templateReference" -replace "\s+", "%20") | Get-MSGraphAllPages | ? { $_.templateReference.templateFamily -like "endpointSecurity*" } | select @{ n = 'id'; e = { $_.id } }, @{ n = 'displayName'; e = { $_.name } }, * -ExcludeProperty 'templateReference', 'id', 'name', 'assignments@odata.context' # id as calculated property to have it first and still be able to use *
        } else {
            $endpointSecPol2 = Invoke-MSGraphRequest -HttpMethod GET -Url ("https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$select=id,name,description,isAssigned,platforms,lastModifiedDateTime,settingCount,roleScopeTagIds,templateReference&`$expand=Assignments,Settings&`$filter=(templateReference/templateFamily ne 'none')" -replace "\s+", "%20") | Get-MSGraphAllPages | ? { $_.templateReference.templateFamily -like "endpointSecurity*" } | select -Property id, @{n = 'displayName'; e = { $_.name } }, description, isAssigned, lastModifiedDateTime, roleScopeTagIds, platforms, @{n = 'type'; e = { $_.templateReference.templateFamily } }, templateReference, @{n = 'settings'; e = { $_.settings | % { [PSCustomObject]@{
                            # trying to have same settings format a.k.a. name/value as in previous function region
                            Name  = $_.settinginstance.settingDefinitionId
                            Value = $(
                                # property with setting value isn't always same, try to get the used one
                                $valuePropertyName = $_.settinginstance | Get-Member -MemberType NoteProperty | ? name -Like "*value" | select -ExpandProperty name
                                if ($valuePropertyName) {
                                    # Write-Verbose "Value property $valuePropertyName was found"
                                    $_.settinginstance.$valuePropertyName
                                } else {
                                    # Write-Verbose "Value property wasn't found, therefore saving whole object as value"
                                    $_.settinginstance
                                }
                            )
                        } } }
            }, settingCount, assignments -ExcludeProperty 'assignments@odata.context', 'settings', 'settings@odata.context', 'technologies', 'name', 'templateReference'
            #endregion process: Account Protection policies (just 'Local User Group Membership'), Firewall, Endpoint Detection and Response, Attack Surface Reduction
        }
        $endpointSecPol2 | ? { $_ } | % { $endpointSecurityPolicy += $_ }

        if ($endpointSecurityPolicy) {
            $resultProperty.EndpointSecurity = $endpointSecurityPolicy
        } else {
            $resultProperty.EndpointSecurity = $null
        }
    }

    # iOS App Provisioning profiles
    if ($all -or $policyType -contains 'iosAppProvisioningProfile') {
        Write-Verbose "Processing iOS App Provisioning profiles"
        Write-Progress -Activity $progressActivity -Status "Processing iOS App Provisioning profiles" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/iosLobAppProvisioningConfigurations?$expandFilter$selectFilter"
        $iosAppProvisioningProfile = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.IOSAppProvisioningProfile = $iosAppProvisioningProfile
    }

    # iOS Update configurations
    if ($all -or $policyType -contains 'iosUpdateConfiguration') {
        Write-Verbose "Processing iOS Update configurations"
        Write-Progress -Activity $progressActivity -Status "Processing iOS Update configurations" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$filter=isof('microsoft.graph.iosUpdateConfiguration')$expandFilter$selectFilter"
        $iosUpdateConfiguration = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.IOSUpdateConfiguration = $iosUpdateConfiguration
    }

    # macOS Update configurations
    if ($all -or $policyType -contains 'macOSSoftwareUpdateConfiguration') {
        Write-Verbose "Processing macOS Update configurations"
        Write-Progress -Activity $progressActivity -Status "Processing macOS Update configurations" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$filter=isof('microsoft.graph.macOSSoftwareUpdateConfiguration')$expandFilter$selectFilter"
        $macosSoftwareUpdateConfiguration = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.MacOSSoftwareUpdateConfiguration = $macosSoftwareUpdateConfiguration
    }

    # Policy Sets
    if ($all -or $policyType -contains 'policySet') {
        Write-Verbose "Processing Policy Sets"
        Write-Progress -Activity $progressActivity -Status "Processing Policy Sets" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $policySet = @()

        $uri = 'https://graph.microsoft.com/beta/deviceAppManagement/policySets'
        $policySetList = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages

        if ($basicOverview) {
            $custExpandFilter = $expandFilter
        } else {
            $custExpandFilter = "$expandFilter,items"
        }
        foreach ($policy in $policySetList) {
            $uri = "https://graph.microsoft.com/beta/deviceAppManagement/policySets/$($policy.id)/?$custExpandFilter$selectFilter"
            $policyContent = Invoke-MSGraphRequest -Url $uri | select -Property * -ExcludeProperty '@odata.context', 'assignments@odata.context', 'items@odata.context'

            $policySet += $policyContent
        }

        if ($policySet) {
            $resultProperty.PolicySet = $policySet
        } else {
            $resultProperty.PolicySet = $null
        }
    }

    # Remediation Scripts
    if ($all -or $policyType -contains 'remediationScript') {
        Write-Verbose "Processing Remediation (Health) scripts"
        Write-Progress -Activity $progressActivity -Status "Processing Remediation (Health) scripts" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts?$expandFilter$selectFilter"
        $remediationScript = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.RemediationScript = $remediationScript
    }

    # S mode supplemental policies
    if ($all -or $policyType -contains 'sModeSupplementalPolicy') {
        Write-Verbose "Processing S Mode Supplemental policies"
        Write-Progress -Activity $progressActivity -Status "Processing S mode supplemental policies" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/wdacSupplementalPolicies?$expandFilter$selectFilter"
        $sModeSupplementalPolicy = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.SModeSupplementalPolicy = $sModeSupplementalPolicy
    }

    # Windows Autopilot Deployment profile
    if ($all -or $policyType -contains 'windowsAutopilotDeploymentProfile') {
        Write-Verbose "Processing Windows Autopilot Deployment profile"
        Write-Progress -Activity $progressActivity -Status "Processing Windows Autopilot Deployment profile" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles?$expandFilter$selectFilter"
        $windowsAutopilotDeploymentProfile = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.WindowsAutopilotDeploymentProfile = $windowsAutopilotDeploymentProfile
    }

    # Windows Feature Update profiles
    if ($all -or $policyType -contains 'windowsFeatureUpdateProfile') {
        Write-Verbose "Processing Windows Feature Update profiles"
        Write-Progress -Activity $progressActivity -Status "Processing Windows Feature Update profiles" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsFeatureUpdateProfiles?$expandFilter$selectFilter"
        $windowsFeatureUpdateProfile = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.WindowsFeatureUpdateProfile = $windowsFeatureUpdateProfile
    }

    # Windows Quality Update profiles
    if ($all -or $policyType -contains 'windowsQualityUpdateProfile') {
        Write-Verbose "Processing Windows Quality Update profiles"
        Write-Progress -Activity $progressActivity -Status "Processing Windows Quality Update profiles" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsQualityUpdateProfiles?$expandFilter$selectFilter"
        $windowsQualityUpdateProfile = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.WindowsQualityUpdateProfile = $windowsQualityUpdateProfile
    }

    # Update rings for Windows 10 and later is part of configurationPolicy (#microsoft.graph.windowsUpdateForBusinessConfiguration)
    if ($all -or $policyType -contains 'windowsUpdateRing') {
        Write-Verbose "Processing Windows Update rings"
        Write-Progress -Activity $progressActivity -Status "Processing Windows Update rings" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = ("https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$filter=isof('microsoft.graph.windowsUpdateForBusinessConfiguration')$expandFilter$selectFilter" -replace "\s+", "%20")
        $windowsUpdateRing = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.WindowsUpdateRing = $windowsUpdateRing
    }
    #endregion get Intune policies

    # output result
    $result = New-Object -TypeName PSObject -Property $resultProperty

    if ($flatOutput) {
        # extract main object properties (policy types) and output the data as array of policies instead of one big object
        $result | Get-Member -MemberType NoteProperty | select -exp name | % {
            $polType = $_

            $result.$polType | ? { $_ } | % {
                # add parent section as property
                $_ | Add-Member -MemberType NoteProperty -Name 'PolicyType' -Value $polType
                # output modified child object
                $_
            }
        }
    } else {
        $result
    }
}

function Get-IntuneRemediationScript {
    <#
    .SYNOPSIS
    Function for showing Remediation scripts deployed from Intune to local/remote computer.

    Scripts details are gathered from clients registry (HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts\Execution) and Intune log file ($env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log).

    .DESCRIPTION
    Function for showing Remediation scripts deployed from Intune to local/remote computer.

    Scripts details are gathered from clients registry (HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts\Execution) and Intune log file ($env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log).

    .PARAMETER computerName
    Name of remote computer where you want to get the data from.

    .PARAMETER getDataFromIntune
    Switch for getting Scripts and User names from Intune, so locally used IDs can be translated to them.

    .PARAMETER credential
    Credential object used for Intune authentication.

    .PARAMETER tenantId
    Azure Tenant ID.
    Requirement for Intune App authentication.

    .EXAMPLE
    Get-IntuneRemediationScript

    Get and show common Remediation script(s) deployed from Intune to this computer.
    #>

    [CmdletBinding()]
    param (
        [string] $computerName,

        [switch] $getDataFromIntune,

        [System.Management.Automation.PSCredential] $credential,

        [string] $tenantId
    )

    #region helper function
    function _getRemediationScript {
        param ([string] $scriptID)
        $intuneRemediationScript | ? id -EQ $scriptID
    }

    function _getScopeName {
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
            } elseif ($id -match "^S-\d+-\d+-\d+") {
                # it is local account
                return ((New-Object System.Security.Principal.SecurityIdentifier($id)).Translate([System.Security.Principal.NTAccount])).Value
            } else {
                # it is AzureAD account
                if ($getDataFromIntune) {
                    return ($intuneUser | ? id -EQ $id).userPrincipalName
                } else {
                    $userSID = Get-UserSIDForUserAzureID $id
                    if ($userSID) {
                        _getScopeName $userSID
                    } else {
                        return $id
                    }
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
        $allFunctionDefs = "function _getScopeName { ${function:_getScopeName} }; function _getIntuneScript { ${function:_getIntuneScript} }; function _getRemediationScript { ${function:_getRemediationScript} }; function Get-UserSIDForUserAzureID { ${function:Get-UserSIDForUserAzureID} }; function Get-IntuneLogRemediationScriptData { ${function:Get-IntuneLogRemediationScriptData} }"
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
        $intuneRemediationScript = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts?select=id,displayname" | Get-MSGraphAllPages
        $intuneUser = Invoke-MSGraphRequest -Url 'https://graph.microsoft.com/beta/users?select=id,userPrincipalName' | Get-MSGraphAllPages
    }

    if ($computerName) {
        $session = New-PSSession -ComputerName $computerName -ErrorAction Stop
    }
    #endregion prepare

    #region get data
    $scriptBlock = {
        param($verbosePref, $getDataFromIntune, $intuneRemediationScript, $intuneUser, $allFunctionDefs)

        # inherit verbose settings from host session
        $VerbosePreference = $verbosePref

        # recreate functions from their text definitions
        . ([ScriptBlock]::Create($allFunctionDefs))

        # get additional script data (script content etc)
        $scriptData = Get-IntuneLogRemediationScriptData

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

                $extraScriptData = $scriptData | ? PolicyId -EQ $remScriptID

                if ($getDataFromIntune) {
                    $property = [ordered]@{
                        "Scope"                             = _getScopeName $userAzureObjectID
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
                        "Scope"                             = _getScopeName $userAzureObjectID
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

                # add additional properties when possible
                if ($extraScriptData) {
                    Write-Verbose "Enrich script object data with information found in Intune log files"

                    $extraScriptData = $extraScriptData | select * -ExcludeProperty AccountId, PolicyId, DocumentSchemaVersion

                    $newProperty = Get-Member -InputObject $extraScriptData -MemberType NoteProperty
                    $newProperty | % {
                        $propertyName = $_.Name
                        $propertyValue = $extraScriptData.$propertyName

                        $property.$propertyName = $propertyValue
                    }
                } else {
                    Write-Verbose "For script $remScriptID there are no extra information in Intune log files"
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

    Invoke-Command @param | select -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName
    #endregion get data

    if ($computerName) {
        Remove-PSSession $session
    }
}

function Get-IntuneRemediationScriptLocally {
    <#
    .SYNOPSIS
    Function for showing Remediation scripts deployed from Intune to local/remote computer.

    Scripts details are gathered from clients registry (HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts\Execution) and Intune log file ($env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log).

    .DESCRIPTION
    Function for showing Remediation scripts deployed from Intune to local/remote computer.

    Scripts details are gathered from clients registry (HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts\Execution) and Intune log file ($env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log).

    .PARAMETER computerName
    Name of remote computer where you want to get the data from.

    .PARAMETER getDataFromIntune
    Switch for getting Scripts and User names from Intune, so locally used IDs can be translated to them.

    .PARAMETER credential
    Credential object used for Intune authentication.

    .PARAMETER tenantId
    Azure Tenant ID.
    Requirement for Intune App authentication.

    .EXAMPLE
    Get-IntuneRemediationScriptLocally

    Get and show common Remediation script(s) deployed from Intune to this computer.
    #>

    [CmdletBinding()]
    param (
        [string] $computerName,

        [switch] $getDataFromIntune,

        [System.Management.Automation.PSCredential] $credential,

        [string] $tenantId
    )

    #region helper function
    function _getRemediationScript {
        param ([string] $scriptID)
        $intuneRemediationScript | ? id -EQ $scriptID
    }

    function _getScopeName {
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
            } elseif ($id -match "^S-\d+-\d+-\d+") {
                # it is local account
                return ((New-Object System.Security.Principal.SecurityIdentifier($id)).Translate([System.Security.Principal.NTAccount])).Value
            } else {
                # it is AzureAD account
                if ($getDataFromIntune) {
                    return ($intuneUser | ? id -EQ $id).userPrincipalName
                } else {
                    $userSID = Get-UserSIDForUserAzureID $id
                    if ($userSID) {
                        _getScopeName $userSID
                    } else {
                        return $id
                    }
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
        $allFunctionDefs = "function _getScopeName { ${function:_getScopeName} }; function _getIntuneScript { ${function:_getIntuneScript} }; function _getRemediationScript { ${function:_getRemediationScript} }; function Get-UserSIDForUserAzureID { ${function:Get-UserSIDForUserAzureID} }; function Get-IntuneLogRemediationScriptData { ${function:Get-IntuneLogRemediationScriptData} }"
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
        $intuneRemediationScript = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts?select=id,displayname" | Get-MSGraphAllPages
        $intuneUser = Invoke-MSGraphRequest -Url 'https://graph.microsoft.com/beta/users?select=id,userPrincipalName' | Get-MSGraphAllPages
    }

    if ($computerName) {
        $session = New-PSSession -ComputerName $computerName -ErrorAction Stop
    }
    #endregion prepare

    #region get data
    $scriptBlock = {
        param($verbosePref, $getDataFromIntune, $intuneRemediationScript, $intuneUser, $allFunctionDefs)

        # inherit verbose settings from host session
        $VerbosePreference = $verbosePref

        # recreate functions from their text definitions
        . ([ScriptBlock]::Create($allFunctionDefs))

        # get additional script data (script content etc)
        $scriptData = Get-IntuneLogRemediationScriptData

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

                $extraScriptData = $scriptData | ? PolicyId -EQ $remScriptID

                if ($getDataFromIntune) {
                    $property = [ordered]@{
                        "Scope"                             = _getScopeName $userAzureObjectID
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
                        "Scope"                             = _getScopeName $userAzureObjectID
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

                # add additional properties when possible
                if ($extraScriptData) {
                    Write-Verbose "Enrich script object data with information found in Intune log files"

                    $extraScriptData = $extraScriptData | select * -ExcludeProperty AccountId, PolicyId, DocumentSchemaVersion

                    $newProperty = Get-Member -InputObject $extraScriptData -MemberType NoteProperty
                    $newProperty | % {
                        $propertyName = $_.Name
                        $propertyValue = $extraScriptData.$propertyName

                        $property.$propertyName = $propertyValue
                    }
                } else {
                    Write-Verbose "For script $remScriptID there are no extra information in Intune log files"
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

    Invoke-Command @param | select -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName
    #endregion get data

    if ($computerName) {
        Remove-PSSession $session
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

function Get-IntuneScriptContentLocally {
    <#
    .SYNOPSIS
    Function for getting content of the (non-remediation) scripts deployed from Intune MDM to this computer.

    Unfortunately scripts has to be reapplied on the client, so take that into account! Only during this time, it is possible to copy the scripts content.

    .DESCRIPTION
    Function for getting content of the (non-remediation) scripts deployed from Intune MDM to this computer.

    Unfortunately scripts has to be reapplied on the client, so take that into account! Only during this time, it is possible to copy the scripts content.

    Data are gathered by:
     - forcing redeploy of Intune scripts (so we can capture them)
     - watching folder where Intune temporarily stores scripts before they are being run ("C:\Program Files (x86)\Microsoft Intune Management Extension\Policies\Scripts") and by copying them to user TEMP location for further processing
     - output the results as PS object

    .PARAMETER force
    Switch for skipping warning about redeploying Intune scripts.

    .EXAMPLE
    Get-IntuneScriptContentLocally

    Redeploy all Intune scripts to this client, capture their content during this time and return it as an PowerShell objects.
    #>

    [CmdletBinding()]
    param (
        [switch] $force
    )

    # base variables
    $jobName = "Intune_Script_Copy_" + (Get-Date).ToString('HH:mm.ss')
    $tmpFolder = "$env:TEMP\intune_script_copy" # if modified, change also in Invoke-FileSystemWatcher Action parameter!

    if (!$force) {
        Write-Warning "All (non-remediation) scripts deployed from Intune will be reapplied! (this is the only way to get their content on the client side unfortunately)"

        $choice = ""
        while ($choice -notmatch "^[Y|N]$") {
            $choice = Read-Host "Do you really want to continue? (Y|N)"
        }
        if ($choice -eq "N") {
            return
        }
    }

    if (Test-Path $tmpFolder -ErrorAction SilentlyContinue) {
        # cleanup
        Remove-Item $tmpFolder -Recurse -Force -ErrorAction Stop
    }

    $null = New-Item -Path $tmpFolder -ItemType Directory

    # monitor & copy applied Intune scripts
    Write-Warning "Starting Intune script monitor&copy job ($jobName)"
    $null = Start-Job -Name $jobName {
        Invoke-FileSystemWatcher -PathToMonitor "C:\Program Files (x86)\Microsoft Intune Management Extension\Policies\Scripts" -ChangeType Created -Filter "*.ps1" -Action {
            $tmpFolder = "$env:TEMP\intune_script_copy" # has to be hardcoded :(

            $details = $event.SourceEventArgs
            $name = $details.Name -replace "\.ps1"
            $fullPath = $details.FullPath

            # Write-Host "Copying $name '$fullPath' to '$tmpFolder'"
            Copy-Item $fullPath $tmpFolder -Force
        }
    }

    # force Intune scripts redeployment
    if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Warning "You are not running this function as administrator. Redeploy of Intune scripts cannot be forced. Just new deployments processed in background will be captured!"
    } else {
        Write-Warning "Forcing redeploy of Intune scripts"
        Invoke-IntuneScriptRedeploy -scriptType script -all -WarningVariable redeployWarningMsg

        if ($redeployWarningMsg -match "No deployed scripts detected") {
            Write-Warning "Previous warning could be caused by running this function or 'Invoke-IntuneScriptRedeploy' in last few minutes. If this is the case, WAIT. If it is no, there are probably no Intune scripts deployed to your computer and you can cancel this function via CTRL + C shortcut."
            #TODO remove job $jobName in case user use CTRL + C
        }
    }

    # wait for Intune scripts processing to finish
    Write-Warning "Waiting for the completion of Intune scripts redeploy (this can take several minutes!)"
    $null = Invoke-FileContentWatcher -path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\AgentExecutor.log" -searchString "Agent executor completed." -stopOnFirstMatch

    # stop copying job because all scripts were already processed
    Write-Verbose "Removing Intune script copy job"
    $result = Get-Job -Name $jobName | Receive-Job
    Get-Job -Name $jobName | Remove-Job -Force

    #region process & output copied Intune scripts
    $intuneScript = Get-ChildItem $tmpFolder -File -Filter "*.ps1" | select -ExpandProperty FullName

    if (!$intuneScript) {
        throw "Script copy job haven't processed any scripts. Job output was: $result"
    }

    $intuneScript | % {
        $scriptPath = $_

        # script name is in format '<scope>_<scriptid>.ps1'
        $scriptFileName = (Split-Path $scriptPath -Leaf) -replace "\.ps1$"
        $scope = ($scriptFileName -split "_")[0]
        $scriptId = ($scriptFileName -split "_")[1]

        [PSCustomObject]@{
            Id      = $scriptId
            Scope   = $scope
            Content = Get-Content $scriptPath -Raw
        }
    }
    #endregion process & output copied Intune scripts

    # cleanup
    Write-Verbose "Removing folder '$tmpFolder'"
    Remove-Item $tmpFolder -Recurse -Force
}

function Get-IntuneScriptLocally {
    <#
    .SYNOPSIS
    Function for showing (non-remediation) scripts deployed from Intune to local/remote computer.

    Script details are gathered from clients registry (HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\Policies) and if 'includeScriptContent' parameter is used, script content is gathered during forced redeploy of the scripts.

    .DESCRIPTION
    Function for showing (non-remediation) scripts deployed from Intune to local/remote computer.

    Script details are gathered from clients registry (HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\Policies) and if 'includeScriptContent' parameter is used, script content is gathered during forced redeploy of the scripts.

    .PARAMETER computerName
    Name of remote computer where you want to force the redeploy.

    .PARAMETER includeScriptContent
    Switch for including Intune scripts content.

    This will need administrator rights and lead to redeploy of all such scripts to the client!

    .PARAMETER force
    Switch for skipping script redeploy confirmation.

    .PARAMETER credential
    Credential object used for Intune authentication.

    .PARAMETER tenantId
    Azure Tenant ID.
    Requirement for Intune App authentication.

    .EXAMPLE
    Get-IntuneScriptLocally

    Get and show (non-remediation) script(s) deployed from Intune to this computer. Script content will NOT be included.

    .EXAMPLE
    Get-IntuneScriptLocally -includeScriptContent

    Get and show (non-remediation) script(s) deployed from Intune to this computer. Script content will be included.
    #>

    [CmdletBinding()]
    param (
        [string] $computerName,

        [switch] $includeScriptContent,

        [switch] $force,

        [switch] $getDataFromIntune,

        [System.Management.Automation.PSCredential] $credential,

        [string] $tenantId
    )

    #region helper function
    function _getIntuneScript {
        param ([string] $scriptID)

        $intuneScript | ? id -EQ $scriptID
    }

    # function translates user Azure ID or SID to its display name
    function _getTargetName {
        param ([string] $id)

        Write-Verbose "Translating account $id to its name (SID)"

        if (!$id) {
            Write-Verbose "Id was null"
            return
        } elseif ($id -eq 'device') {
            # xml nodes contains 'device' instead of 'Device'
            return 'Device'
        }

        $errPref = $ErrorActionPreference
        $ErrorActionPreference = "Stop"
        try {
            if ($id -eq '00000000-0000-0000-0000-000000000000' -or $id -eq 'S-0-0-00-0000000000-0000000000-000000000-000') {
                Write-Verbose "`t- Id belongs to device"
                return 'Device'
            } elseif ($id -match "^S-\d+-\d+-\d+") {
                # it is local account
                Write-Verbose "`t- Id is SID, trying to translate to local account name"
                return ((New-Object System.Security.Principal.SecurityIdentifier($id)).Translate([System.Security.Principal.NTAccount])).Value
            } else {
                # it is AzureAD account
                Write-Verbose "`t- Id belongs to AAD account"
                if ($getDataFromIntune) {
                    Write-Verbose "`t- Translating ID using Intune data"
                    return ($intuneUser | ? id -EQ $id).userPrincipalName
                } else {
                    Write-Verbose "`t- Getting SID that belongs to AAD ID, by searching Intune logs"
                    $userSID = Get-UserSIDForUserAzureID $id
                    if ($userSID) {
                        _getTargetName $userSID
                    } else {
                        return $id
                    }
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
        $allFunctionDefs = "function _getTargetName { ${function:_getTargetName} }; function _getIntuneScript { ${function:_getIntuneScript} }; function Get-IntuneScriptContentLocally { ${function:Get-IntuneScriptContentLocally} }; function Invoke-IntuneScriptRedeploy { ${function:Invoke-IntuneScriptRedeploy} }"
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
        $intuneScript = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts?select=id,displayname" | Get-MSGraphAllPages
        $intuneUser = Invoke-MSGraphRequest -Url 'https://graph.microsoft.com/beta/users?select=id,userPrincipalName' | Get-MSGraphAllPages
    }

    if ($computerName) {
        $session = New-PSSession -ComputerName $computerName -ErrorAction Stop
    }
    #endregion prepare

    #region get data
    $scriptBlock = {
        param ($verbosePref, $getDataFromIntune, $intuneScript, $intuneUser, $allFunctionDefs, $includeScriptContent, $force)

        # inherit verbose settings from host session
        $VerbosePreference = $verbosePref

        # caching of script ID > Name translations
        $scriptNameList = @{}

        # recreate functions from their text definitions
        . ([ScriptBlock]::Create($allFunctionDefs))

        if ($includeScriptContent) {
            if ($force) {
                $scriptContent = Get-IntuneScriptContentLocally -force
            } else {
                $scriptContent = Get-IntuneScriptContentLocally
            }
        }

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

                if ($scriptContent) {
                    $property.Content = $scriptContent | ? Id -EQ $scriptID | select -ExpandProperty Content
                }

                New-Object -TypeName PSObject -Property $property
            }
        }
    }

    $param = @{
        scriptBlock  = $scriptBlock
        argumentList = ($VerbosePreference, $getDataFromIntune, $intuneScript, $intuneUser, $allFunctionDefs, $includeScriptContent, $force)
    }
    if ($computerName) {
        $param.session = $session
    }

    Invoke-Command @param | select -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName
    #endregion get data

    if ($computerName) {
        Remove-PSSession $session
    }
}

function Get-IntuneWin32AppLocally {
    <#
    .SYNOPSIS
    Function for showing Win32 apps deployed from Intune to local/remote computer.

    Apps details are gathered from clients registry (HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps) and Intune log file ($env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log)

    .DESCRIPTION
    Function for showing Win32 apps deployed from Intune to local/remote computer.

    App details are gathered from clients registry (HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps) and Intune log file ($env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log)

    .PARAMETER computerName
    Name of remote computer where you want to get Win32 apps from.

    .PARAMETER getDataFromIntune
    Switch for getting Apps and User names from Intune, so locally used IDs can be translated.
    If you omit this switch, local Intune logs will be searched for such information instead.

    .PARAMETER credential
    Credential object used for Intune authentication.

    .PARAMETER tenantId
    Azure Tenant ID.
    Requirement for Intune App authentication.

    .PARAMETER excludeSystemApp
    Switch for excluding Apps targeted to SYSTEM.

    .EXAMPLE
    Get-IntuneWin32AppLocally

    Get and show Win32App(s) deployed from Intune to local computer.
    IDs of targeted users and apps will be translated using information from local Intune log files.

    .EXAMPLE
    Get-IntuneWin32AppLocally -computerName PC-01 -getDataFromIntune credential (Get-Credential)

    Get and show Win32App(s) deployed from Intune to computer PC-01. IDs of apps and targeted users will be translated to corresponding names.

    .EXAMPLE
    $win32AppData = Get-IntuneWin32AppLocally

    $myApp = ($win32AppData | ? DisplayName -eq 'MyApp')

    "Output complete object"
    $myApp

    "Detection script content for application 'MyApp'"
    $myApp.additionalData.DetectionRule.DetectionText.ScriptBody

    "Requirement script content for application 'MyApp'"
    $myApp.additionalData.ExtendedRequirementRules.RequirementText.ScriptBody

    "Install command for application 'MyApp'"
    $myApp.additionalData.InstallCommandLine

    Show various interesting information for 'MyApp' application deployment.
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
    # function translates user Azure ID or SID to its display name
    function _getTargetName {
        param ([string] $id)

        Write-Verbose "Translating account $id to its name (SID)"

        if (!$id) {
            Write-Verbose "Id was null"
            return
        } elseif ($id -eq 'device') {
            # xml nodes contains 'device' instead of 'Device'
            return 'Device'
        }

        $errPref = $ErrorActionPreference
        $ErrorActionPreference = "Stop"
        try {
            if ($id -eq '00000000-0000-0000-0000-000000000000' -or $id -eq 'S-0-0-00-0000000000-0000000000-000000000-000') {
                Write-Verbose "`t- Id belongs to device"
                return 'Device'
            } elseif ($id -match "^S-\d+-\d+-\d+") {
                # it is local account
                Write-Verbose "`t- Id is SID, trying to translate to local account name"
                return ((New-Object System.Security.Principal.SecurityIdentifier($id)).Translate([System.Security.Principal.NTAccount])).Value
            } else {
                # it is AzureAD account
                Write-Verbose "`t- Id belongs to AAD account"
                if ($getDataFromIntune) {
                    Write-Verbose "`t- Translating ID using Intune data"
                    return ($intuneUser | ? id -EQ $id).userPrincipalName
                } else {
                    Write-Verbose "`t- Getting SID that belongs to AAD ID, by searching Intune logs"
                    $userSID = Get-UserSIDForUserAzureID $id
                    if ($userSID) {
                        _getTargetName $userSID
                    } else {
                        return $id
                    }
                }
            }
        } catch {
            Write-Warning "Unable to translate $id to account name ($_)"
            $ErrorActionPreference = $errPref
            return $id
        }
    }

    # function for translating error codes to error messages
    function Get-Win32AppErrMsg {
        param (
            [string] $errorCode
        )

        if (!$errorCode -or $errorCode -eq 0) { return }

        # https://docs.microsoft.com/en-us/troubleshoot/mem/intune/app-install-error-codes
        $errorCodeList = @{
            "-942583883"  = "The app failed to install."
            "-942583878"  = "The app installation was canceled because the installation (APK) file was deleted after download, but before installation."
            "-942583877"  = "The app installation was canceled because the process was restarted during installation."
            "-2016345060" = "The application was not detected after installation completed successfully."
            "-942583886"  = "The download failed because of an unknown error."
            "-942583688"  = "The download failed because of an unknown error. The policy will be retried the next time the device syncs."
            "-942583887"  = "The end user canceled the app installation."
            "-942583787"  = "The file download process was unexpectedly stopped."
            "-942583684"  = "The file download service was unexpectedly stopped. The policy will be retried the next time the device syncs."
            "-942583880"  = "The app failed to uninstall."
            "-942583881"  = "The app installation APK file used for the upgrade does not match the signature for the current app on the device."
            "-942583879"  = "The end user canceled the app installation."
            "-942583876"  = "Uninstall of the app was canceled because the process was restarted during installation."
            "-942583882"  = "The app installation APK file cannot be installed because it was not signed."
            "-2016335610" = "Apple MDM Agent error: App installation command failed with no error reason specified. Retry app installation."
            "-2016333508" = "Network connection on the client was lost or interrupted. Later attempts should succeed in a better network environment."
            "-2016333507" = "Could not retrieve license for the app with iTunes Store ID"
            "-2016341112" = "iOS/iPadOS device is currently busy."
            "-2016330908" = "The app installation has failed."
            "-2016330906" = "The app is managed, but has expired or been removed by the user."
            "-2016330912" = "The app is scheduled for installation, but needs a redemption code to complete the transaction."
            "-2016330883" = "Unknown error."
            "-2016330910" = "The user rejected the offer to install the app."
            "-2016330909" = "The user rejected the offer to update the app."
            "-2016345112" = "Unknown error"
            "-2016330861" = "Can only install VPP apps on Shared iPad."
            "-2016330860" = "Can't install apps when App Store is disabled."
            "-2016330859" = "Can't find VPP license for app."
            "-2016330858" = "Can't install system apps with your MDM provider."
            "-2016330857" = "Can't install apps when device is in Lost Mode."
            "-2016330856" = "Can't install apps when device is in kiosk mode."
            "-2016330852" = "Can't install 32-bit apps on this device."
            "-2016330855" = "User must sign in to the App Store."
            "-2016330854" = "Unknown problem. Please try again."
            "-2016330853" = "The app installation failed. Intune will try again the next time the device syncs."
            "-2016330882" = "License Assignment failed with Apple error 'No VPP licenses remaining'"
            "-2016330898" = "App Install Failure 12024: Unknown cause."
            "-2016330881" = "Needed app configuration policy not present, ensure policy is targeted to same groups."
            "-2016330903" = "Device VPP licensing is only applicable for iOS/iPadOS 9.0+ devices."
            "-2016330865" = "The application is installed on the device but is unmanaged."
            "-2016330904" = "User declined app management"
            "-2016335971" = "Unknown error."
            "-2016330851" = "The latest version of the app failed to update from an earlier version."
            "-2016330897" = "Your connection to Intune timed out."
            "-2016330896" = "You lost connection to the Internet."
            "-2016330894" = "You lost connection to the Internet."
            "-2016330893" = "You lost connection to the Internet."
            "-2016330889" = "The secure connection failed."
            "-2016330880" = "CannotConnectToITunesStoreError"
            "-2016330849" = "The VPP App has an update available"
            "2016330850"  = "Can't enforce app uninstall setting. Retry installing the app."
            "-2147009281" = "(client error)"
            "-2133909476" = "(client error)"
            "-2147009296" = "The package is unsigned. The publisher name does not match the signing certificate subject. Check the AppxPackagingOM event log for information. For more information, see Troubleshooting packaging, deployment, and query of Windows Store apps."
            "-2147009285" = "Increment the version number of the app, then rebuild and re-sign the package. Remove the old package for every user on the system before you install the new package. For more information, see Troubleshooting packaging, deployment, and query of Windows Store apps."
        }

        $errorMessage = $errorCodeList.$errorCode
        if (!$errorMessage) {
            $errorMessage = "*unable to translate $errorCode*"
        }

        return $errorMessage
    }

    # create helper functions text definition for usage in remote sessions
    $allFunctionDefs = "function _getTargetName { ${function:_getTargetName} }; function Get-UserSIDForUserAzureID { ${function:Get-UserSIDForUserAzureID} }; function Get-Win32AppErrMsg { ${function:Get-Win32AppErrMsg} }; function Get-IntuneLogWin32AppData { ${function:Get-IntuneLogWin32AppData} }; function Get-IntuneLogWin32AppReportingResultData { ${function:Get-IntuneLogWin32AppReportingResultData} }"
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
    }
    #endregion prepare

    #region get data
    $scriptBlock = {
        param($verbosePref, $excludeSystemApp, $getDataFromIntune, $intuneApp, $intuneUser, $allFunctionDefs)

        # inherit verbose settings from host session
        $VerbosePreference = $verbosePref

        # recreate functions from their text definitions
        . ([ScriptBlock]::Create($allFunctionDefs))

        # get additional data from Intune logs
        Write-Verbose "Getting additional Win32App data from client Intune logs"
        $logData = Get-IntuneLogWin32AppData
        $logReportingData = Get-IntuneLogWin32AppReportingResultData # to be able to translate IDs of apps which don't meet requirements

        $processedWin32AppId = @()

        foreach ($scope in (Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps" -ErrorAction SilentlyContinue | ? PSChildName -NotIn "OperationalState", "Reporting")) {
            $userAzureObjectID = Split-Path $scope.Name -Leaf

            if ($excludeSystemApp -and $userAzureObjectID -eq "00000000-0000-0000-0000-000000000000") {
                Write-Verbose "Skipping system deployments"
                continue
            }

            $userWin32AppRoot = $scope.PSPath
            $win32AppIDList = Get-ChildItem $userWin32AppRoot | select -ExpandProperty PSChildName | % { $_ -replace "_\d+$" } | select -Unique | ? { $_ -ne 'GRS' }

            $win32AppIDList | % {
                $win32AppID = $_

                Write-Verbose "Processing App ID $win32AppID"

                $processedWin32AppId += $win32AppID

                #region get Win32App data
                $newestWin32AppRecord = Get-ChildItem $userWin32AppRoot | ? PSChildName -Match ([regex]::escape($win32AppID)) | Sort-Object -Descending -Property PSChildName | select -First 1

                try {
                    $lastUpdatedTimeUtc = $null
                    $lastUpdatedTimeUtc = Get-ItemPropertyValue $newestWin32AppRecord.PSPath -Name LastUpdatedTimeUtc -ErrorAction Stop
                } catch {
                    Write-Verbose "`tUnable to get LastUpdatedTimeUtc data"
                }

                try {
                    $deploymentType = $null
                    $deploymentType = Get-ItemPropertyValue $newestWin32AppRecord.PSPath -Name Intent -ErrorAction Stop
                } catch {
                    Write-Verbose "`tUnable to get Intent data"
                }
                if ($deploymentType) {
                    switch ($deploymentType) {
                        1 { $deploymentType = "Available" }
                        3 { $deploymentType = "Required" }
                        4 { $deploymentType = "Uninstall" }
                        default { Write-Error "Undefined deployment type $deploymentType" }
                    }
                }

                try {
                    $complianceStateMessage = $null
                    $complianceStateMessage = Get-ItemPropertyValue "$($newestWin32AppRecord.PSPath)\ComplianceStateMessage" -Name ComplianceStateMessage -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Write-Verbose "`tUnable to get Compliance State Message data"
                }

                $complianceState = $complianceStateMessage.ComplianceState
                if ($complianceState) {
                    switch ($complianceState) {
                        0 { $complianceState = "Unknown" }
                        1 { $complianceState = "Compliant" }
                        2 { $complianceState = "Not compliant" }
                        3 { $complianceState = "Conflict (Not applicable for app deployment)" }
                        4 { $complianceState = "Error" }
                        default { Write-Error "Undefined compliance status $complianceState" }
                    }
                }

                $desiredState = $complianceStateMessage.DesiredState
                if ($desiredState) {
                    switch ($desiredState) {
                        0	{ $desiredState = "None" }
                        1	{ $desiredState = "NotPresent" }
                        2	{ $desiredState = "Present" }
                        3	{ $desiredState = "Unknown" }
                        4	{ $desiredState = "Available" }
                        default { Write-Error "Undefined desired status $desiredState" }
                    }
                }

                try {
                    $enforcementStateMessage = $null
                    $enforcementStateMessage = Get-ItemPropertyValue "$($newestWin32AppRecord.PSPath)\EnforcementStateMessage" -Name EnforcementStateMessage -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Write-Verbose "`tUnable to get Enforcement State Message data"
                }

                $enforcementState = $enforcementStateMessage.EnforcementState
                if ($enforcementState) {
                    switch ($enforcementState) {
                        1000	{ $enforcementState = "Succeeded" }
                        1003	{ $enforcementState = "Received command to install" }
                        2000	{ $enforcementState = "Enforcement action is in progress" }
                        2007	{ $enforcementState = "App enforcement will be attempted once all dependent apps have been installed" }
                        2008	{ $enforcementState = "App has been installed but is not usable until device has rebooted" }
                        2009	{ $enforcementState = "App has been downloaded but no installation has been attempted" }
                        3000	{ $enforcementState = "Enforcement action aborted due to requirements not being met" }
                        4000	{ $enforcementState = "Enforcement action could not be completed due to unknown reason" }
                        5000	{ $enforcementState = "Enforcement action failed due to error.  Error code needs to be checked to determine detailed status" }
                        5003	{ $enforcementState = "Client was unable to download app content." }
                        5999	{ $enforcementState = "Enforcement action failed due to error, will retry immediately." }
                        6000	{ $enforcementState = "Enforcement action has not been attempted.  No reason given." }
                        6001	{ $enforcementState = "App install is blocked because one or more of the app's dependencies failed to install." }
                        6002	{ $enforcementState = "App install is blocked on the machine due to a pending hard reboot." }
                        6003	{ $enforcementState = "App install is blocked because one or more of the app's dependencies have requirements which are not met." }
                        6004	{ $enforcementState = "App is a dependency of another application and is configured to not automatically install." }
                        6005	{ $enforcementState = "App install is blocked because one or more of the app's dependencies are configured to not automatically install." }
                        default { Write-Error "Undefined enforcement status $enforcementState" }
                    }
                }

                $lastError = $complianceStateMessage.ErrorCode
                if (!$lastError) { $lastError = 0 } # because of HTML conditional formatting ($null means that cell will have red background)
                #endregion get Win32App data

                #TODO I don't differentiate between user and device scope, but it seems log contains just user data?
                $appLogData = $logData | ? Id -EQ $win32AppID
                $appLogReportingData = $logReportingData | ? Id -EQ $win32AppID

                #region output the results
                # prepare final object properties
                $property = [ordered]@{
                    "Name"               = ''
                    "Id"                 = $win32AppID
                    "Scope"              = _getTargetName $userAzureObjectID
                    "LastUpdatedTimeUtc" = $lastUpdatedTimeUtc
                    "ComplianceState"    = $complianceState
                    "EnforcementState"   = $enforcementState
                    "EnforcementError"   = Get-Win32AppErrMsg $enforcementStateMessage.ErrorCode
                    "LastError"          = $lastError
                    "ProductVersion"     = $complianceStateMessage.ProductVersion
                    "DesiredState"       = $desiredState
                    # "EnforcementErrorCode" = $enforcementStateMessage.ErrorCode
                    "DeploymentType"     = $deploymentType
                    "ScopeId"            = $userAzureObjectID
                }
                if ($getDataFromIntune) {
                    $property.Name = ($intuneApp | ? id -EQ $win32AppID).DisplayName
                } else {
                    $property.Name = if ($appLogData.Name) { $appLogData.Name } else { $appLogReportingData.Name }
                }

                # add additional properties when possible
                if ($appLogData) {
                    Write-Verbose "Enrich app object data with information found in Intune log files"

                    $appLogData = $appLogData | select * -ExcludeProperty Id, Name

                    $newProperty = Get-Member -InputObject $appLogData -MemberType NoteProperty
                    $newProperty | % {
                        $propertyName = $_.Name
                        $propertyValue = $appLogData.$propertyName

                        $property.$propertyName = $propertyValue
                    }
                } else {
                    Write-Verbose "For app $win32AppID there are no extra information in Intune log files"
                }

                New-Object -TypeName PSObject -Property $property
                #endregion output the results
            }
        }

        #region warn about deployed but skip-installation apps
        if ($logReportingData) {
            $notProcessedApp = $logReportingData | ? { $_.Id -notin $processedWin32AppId }
            if ($notProcessedApp) {
                Write-Warning "Following apps didn't start installation: $($notProcessedApp.Name -join ', ')`n`nReason can be recent forced redeploy of such app or that deployment requirements are not met. For more information run 'Get-IntuneLogWin32AppReportingResultData'"
            }
        }
        #endregion warn about deployed but skip-installation apps
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
        $win32App
    } else {
        Write-Warning "No deployed Win32App detected"
    }
    #endregion let user redeploy chosen app

    if ($computerName) {
        Remove-PSSession $session
    }
}

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

function Get-UserSIDForUserAzureID {
    <#
    .SYNOPSIS
    Function finds SID for given user Azure ID.

    .DESCRIPTION
    Function finds SID for given user Azure ID.
    Uses client's Intune log to get this information.

    .PARAMETER userId
    Azure ID to translate.

    .EXAMPLE
    Get-UserSIDForUserAzureID -userId 91b91882-f81b-4ba4-9d7d-10cd49219b79

    Translates user Azure ID 91b91882-f81b-4ba4-9d7d-10cd49219b79 into local SID.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $userId
    )

    # create global variable for cache purposes
    if (!$azureUserIdList.keys) {
        $global:azureUserIdList = @{}
    }

    if ($azureUserIdList.keys -contains $userId) {
        # return cached information
        return $azureUserIdList.$userId
    }

    $intuneLogList = Get-ChildItem -Path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs" -Filter "IntuneManagementExtension*.log" -File | sort LastWriteTime -Descending | select -ExpandProperty FullName

    if (!$intuneLogList) {
        Write-Error "Unable to find any Intune log files. Redeploy will probably not work as expected."
        return
    }

    foreach ($intuneLog in $intuneLogList) {
        # how content of the log can looks like
        # [Win32App] ..................... Processing user session 1, userId: e5834928-0f19-492d-8a69-3fbc98fd84eb, userSID: S-1-5-21-2475586523-545188003-3344463812-8050 .....................
        # [Win32App] EspPreparation starts for userId: e5834928-0f19-442d-8a69-3fbc98fd84eb userSID: S-1-5-21-2475586523-545182003-3344463812-8050

        Write-Verbose "Searching $userId in '$intuneLog'"

        $userMatch = Select-String -Path $intuneLog -Pattern "(?:\[Win32App\] \.* Processing user session \d+, userId: $userId, userSID: (S-[0-9-]+) )|(?:\[Win32App\] EspPreparation starts for userId: $userId userSID: (S-[0-9-]+))" -List
        if ($userMatch) {
            # cache the results
            if ($azureUserIdList) {
                $azureUserIdList.$userId = $userMatch.matches.groups[1].value
            }
            # return user SID
            return $userMatch.matches.groups[1].value
        }
    }

    Write-Warning "Unable to find User '$userId' in any of the Intune log files. Unable to translate this AAD ID to local SID."
    # cache the results
    $azureUserIdList.$userId = $null
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

    .PARAMETER all
    Switch to redeploy all scripts of selected type (script, remediationScript).

    .PARAMETER dontWait
    Don't wait on script execution completion.

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
    [Alias("Invoke-IntuneScriptRedeployLocally")]
    param (
        [string] $computerName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('script', 'remediationScript')]
        [string] $scriptType,

        [switch] $getDataFromIntune,

        [System.Management.Automation.PSCredential] $credential,

        [string] $tenantId,

        [switch] $all,

        [switch] $dontWait
    )

    if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        throw "Run as admin"
    }

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
        if ($all) {
            $scriptToRedeploy = $script
        } else {
            $scriptToRedeploy = $script | Out-GridView -PassThru -Title "Pick script(s) for redeploy"
        }

        if ($scriptToRedeploy) {
            $scriptBlock = {
                param ($verbosePref, $scriptToRedeploy, $scriptType, $dontWait)

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
                    Write-Warning "Preparing redeploy for script $scriptId (scope $scopeId) by deleting it's registry key"

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

                if (!$dontWait) {
                    if ($scriptType -eq 'script') {
                        Write-Warning "Waiting for start of the Intune script(s) redeploy (this can take minute or two)"
                        $null = Invoke-FileContentWatcher -path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\AgentExecutor.log" -searchString "Prepare to run Powershell Script" -stopOnFirstMatch
                        Write-Warning "Waiting for the completion of the Intune script(s) redeploy (this can take several minutes!)"
                        $null = Invoke-FileContentWatcher -path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\AgentExecutor.log" -searchString "Agent executor completed." -stopOnFirstMatch
                    } elseif ($scriptType -eq 'remediationScript') {
                        Write-Warning "Waiting for start of the Intune remediation script(s) redeploy (this can take minute or two)"
                        # [HS] Calcuated earliest time is 04.10.2022 15:26:25
                        $calculatedStart = Invoke-FileContentWatcher -path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log" -searchString "earliest time is" -stopOnFirstMatch
                        $calculatedStart = ([regex]"\d+\.\d+\.\d+ \d+:\d+:\d+").Match($calculatedStart).value
                        Write-Warning "Calculated start of the Intune remediation script(s) redeploy is set to $calculatedStart"
                        Write-Warning "Waiting for the completion of the Intune remediation script(s) redeploy"
                        $null = Invoke-FileContentWatcher -path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\AgentExecutor.log" -searchString "Powershell exit code is" -stopOnFirstMatch # beware that this detects FIRST script finish..if user redeploy multiple scripts this will be confusing
                    }
                }
            }

            $param = @{
                scriptBlock  = $scriptBlock
                argumentList = ($VerbosePreference, $scriptToRedeploy, $scriptType, $dontWait)
            }
            if ($computerName) {
                $param.session = $session
            }

            Invoke-Command @param
        }
    } else {
        Write-Warning "No deployed script detected. Try to restart service 'IntuneManagementExtension'?"
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

    OutGridView is used to output discovered Apps.

    Redeploy means that corresponding registry keys will be deleted from registry and service IntuneManagementExtension will be restarted.

    .PARAMETER computerName
    Name of remote computer where you want to force the redeploy.

    .PARAMETER getDataFromIntune
    Switch for getting Apps and User names from Intune, so locally used IDs can be translated.
    If you omit this switch, local Intune logs will be searched for such information instead.

    .PARAMETER credential
    Credential object used for Intune authentication.

    .PARAMETER tenantId
    Azure Tenant ID.
    Requirement for Intune App authentication.

    .PARAMETER dontWait
    Don't wait on Win32App redeploy completion.

    .EXAMPLE
    Invoke-IntuneWin32AppRedeploy

    Get and show Win32App(s) deployed from Intune to this computer. Selected ones will be then redeployed.
    IDs of targeted users and apps will be translated using information from local Intune log files.

    .EXAMPLE
    Invoke-IntuneWin32AppRedeploy -computerName PC-01 -getDataFromIntune credential $creds

    Get and show Win32App(s) deployed from Intune to computer PC-01. IDs of apps and targeted users will be translated to corresponding names. Selected ones will be then redeployed.
    #>

    [CmdletBinding()]
    [Alias("Invoke-IntuneWin32AppRedeployLocally")]
    param (
        [string] $computerName,

        [switch] $getDataFromIntune,

        [System.Management.Automation.PSCredential] $credential,

        [string] $tenantId,

        [switch] $dontWait
    )

    if (!(Get-Command Get-IntuneWin32AppLocally)) {
        throw "Command Get-IntuneWin32AppLocally is missing"
    }

    if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        throw "Run as admin"
    }

    #region helper function
    # function gets app GRS hash from Intune log files
    function Get-Win32AppGRSHash {
        param (
            [Parameter(Mandatory = $true)]
            [string] $appId
        )

        $intuneLogList = Get-ChildItem -Path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs" -Filter "IntuneManagementExtension*.log" -File | sort LastWriteTime -Descending | select -ExpandProperty FullName

        if (!$intuneLogList) {
            Write-Error "Unable to find any Intune log files. Redeploy will probably not work as expected."
            return
        }

        foreach ($intuneLog in $intuneLogList) {
            $appMatch = Select-String -Path $intuneLog -Pattern "\[Win32App\]\[V3Processor\] Processing subgraph with app ids: $appId" -Context 0, 1
            if ($appMatch) {
                foreach ($match in $appMatch) {
                    $hash = ([regex]"\\GRS\\(.*)\\").Matches($match).captures.groups[1].value
                    if ($hash) {
                        return $hash
                    }
                }
            }
        }

        Write-Verbose "Unable to find App '$appId' GRS hash in any of the Intune log files. Redeploy will probably not work as expected"
    }
    # create helper functions text definition for usage in remote sessions
    $allFunctionDefs = "function Get-Win32AppGRSHash { ${function:Get-Win32AppGRSHash} };"
    #endregion helper function

    #region get deployed Win32Apps
    $param = @{}
    if ($computerName) { $param.computerName = $computerName }
    if ($getDataFromIntune) { $param.getDataFromIntune = $true }
    if ($credential) { $param.credential = $credential }
    if ($tenantId) { $param.tenantId = $tenantId }

    Write-Verbose "Getting deployed Win32Apps"
    $win32App = Get-IntuneWin32AppLocally @param
    #endregion get deployed Win32Apps

    if ($win32App) {
        $appToRedeploy = $win32App | Out-GridView -PassThru -Title "Pick app(s) for redeploy"

        #region redeploy selected Win32Apps
        if ($appToRedeploy) {
            $scriptBlock = {
                param ($verbosePref, $allFunctionDefs, $appToRedeploy, $dontWait)

                # inherit verbose settings from host session
                $VerbosePreference = $verbosePref

                # recreate functions from their text definitions
                . ([ScriptBlock]::Create($allFunctionDefs))

                $win32AppKeys = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps" -Recurse -Depth 2 | select PSChildName, PSPath, PSParentPath

                $appToRedeploy | % {
                    $appId = $_.id
                    $appName = $_.name
                    $scopeId = $_.scopeId
                    $scope = $_.scope
                    if ($scopeId -eq 'device') { $scopeId = "00000000-0000-0000-0000-000000000000" }
                    if (!$appId) { throw "ID property is missing. Problem is probably in function Get-IntuneWin32AppLocally." }
                    if (!$scopeId) { throw "ScopeId property is missing. Problem is probably in function Get-IntuneWin32AppLocally." }
                    $txt = $appName
                    if (!$txt) { $txt = $appId }
                    Write-Warning "Preparing redeploy for Win32App '$txt' (scope $scopeId) by deleting it's registry key"

                    $win32AppKeyToDelete = $win32AppKeys | ? { $_.PSChildName -Match "^$appId`_\d+" -and $_.PSParentPath -Match "\\$scopeId$" }

                    if ($win32AppKeyToDelete) {
                        $win32AppKeyToDelete | % {
                            Write-Verbose "Deleting $($_.PSPath)"
                            Remove-Item $_.PSPath -Force -Recurse
                        }

                        # GRS key needs to be deleted too https://call4cloud.nl/2022/07/retry-lola-retry/#part1-4
                        $win32AppKeyGRSHash = Get-Win32AppGRSHash $appId
                        if ($win32AppKeyGRSHash) {
                            $win32AppGRSKeys = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\$scopeId\GRS"
                            $win32AppGRSKeyToDelete = $win32AppGRSKeys | ? { $_.PSChildName -eq $win32AppKeyGRSHash }
                            if ($win32AppGRSKeyToDelete) {
                                Write-Verbose "Deleting $($win32AppGRSKeyToDelete.PSPath)"
                                Remove-Item $win32AppGRSKeyToDelete.PSPath -Force -Recurse
                            }
                        }
                    } else {
                        throw "BUG??? App $appId with scope $scopeId wasn't found in the registry"
                    }
                }

                Write-Warning "Invoking redeploy (by restarting service IntuneManagementExtension). Redeploy can take several minutes!"
                Restart-Service IntuneManagementExtension -Force

                if (!$dontWait) {
                    Write-Warning "Waiting for start of the Intune Win32App(s) redeploy (this can take minute or two)"
                    $null = Invoke-FileContentWatcher -path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log" -searchString "Load global Win32App settings" -stopOnFirstMatch
                    Write-Warning "Waiting for the completion of the Intune Win32App(s) redeploy (this can take several minutes!)"
                    $null = Invoke-FileContentWatcher -path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log" -searchString "application poller stopped." -stopOnFirstMatch
                }
            }

            $param = @{
                scriptBlock  = $scriptBlock
                argumentList = ($VerbosePreference, $allFunctionDefs, $appToRedeploy, $dontWait)
            }
            if ($computerName) {
                $param.computerName = $computerName
            }

            Invoke-Command @param
        }
        #endregion redeploy selected Win32Apps
    } else {
        Write-Warning "No deployed Win32App detected"
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

    if (!(Get-Command Invoke-AsSystem)) {
        throw "Important function Invoke-AsSystem is missing. It is part of CommonStuff module."
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
        Write-Verbose "ActiveDirectory module is missing, unable to obtain computer GUID"
        if ((Get-WmiObject win32_operatingsystem -Property caption).caption -match "server") {
            Write-Verbose "To install it, use: Install-WindowsFeature RSAT-AD-PowerShell -IncludeManagementTools"
        } else {
            Write-Verbose "To install it, use: Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online"
        }
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

function Search-IntuneAccountPolicyAssignment {
    <#
    .SYNOPSIS
    Function for getting Intune policies, assigned (directly/indirectly) to selected account.
    Exclude assignments and assignments for 'All Users', 'All Devices' are taken in account by default when calculating the results.

    .DESCRIPTION
    Function for getting Intune policies, assigned (directly/indirectly) to selected account.
    Exclude assignments and assignments for 'All Users', 'All Devices' are taken in account by default when calculating the results.

    Intune Filters are ignored for now!

    .PARAMETER accountId
    ObjectID of the account you are getting assignments for.

    .PARAMETER skipAllUsersAllDevicesAssignments
    Switch. Hides all assignments for 'All Users' and 'All Devices'.
    A.k.a. just policies assigned to selected account (groups where he is member (directly or transitively)), will be outputted.

    .PARAMETER ignoreExcludes
    Switch. Ignore policies EXCLUDE assignments when calculating the results.

    By default if specified account is member of any excluded group, policy will be omitted.

    .PARAMETER justDirectGroupAssignments
    Switch. Usable only if accountId belongs to a group.
    Just assignments for this particular group will be shown. Not assignments for groups this group is member of or assignments for 'All Users' or 'All Devices'.

    But as a side effect assignments which would be otherwise ignored, because of exclude rule for parent group where this one is as a member will be shown!"

    .PARAMETER policyType
    Array of Intune policy types you want to search through.

    Possible values are:
    'ALL' to search through all policies.

    'app','appConfigurationPolicy','appProtectionPolicy','compliancePolicy','configurationPolicy','customAttributeShellScript','deviceEnrollmentConfiguration','deviceManagementPSHScript','deviceManagementShellScript','endpointSecurity','iosAppProvisioningProfile','iosUpdateConfiguration',
    'macOSSoftwareUpdateConfiguration','policySet','remediationScript','sModeSupplementalPolicy','windowsAutopilotDeploymentProfile','windowsFeatureUpdateProfile','windowsQualityUpdateProfile','windowsUpdateRing' to search through just some policies subset.

    By default 'ALL' policies are searched.

    .PARAMETER intunePolicy
    Object as returned by Get-IntunePolicy function.
    Can be used if you make more searches to avoid getting Intune policies over and over again.

    .PARAMETER basicOverview
    Switch. Just some common subset of available policy properties will be gathered (id, displayName, lastModifiedDateTime, assignments).
    Makes the result more human readable.

    .PARAMETER flatOutput
    Switch. All Intune policies will be outputted as array instead of one psobject with policies divided into separate sections/object properties.
    Policy parent "type" is added as new property 'PolicyType' to each policy for filtration purposes.

    .EXAMPLE
    $null = Connect-MSGraph
    $null = Connect-MgGraph
    Search-IntuneAccountPolicyAssignment -accountId a815da8b-6324-4feb-94ef-96723ba4fbf7 -justDirectGroupAssignments

    Get all Intune policies assigned DIRECTLY to specified GROUP account (a.k.a. NOT to groups where specified group is member of!). Policies assigned to 'All Users', 'All Devices' will be omitted. Policies where specified GROUP is excluded will be omitted!

    .EXAMPLE
    $null = Connect-MSGraph
    $null = Connect-MgGraph
    Search-IntuneAccountPolicyAssignment -accountId a815da8b-6324-4feb-94ef-96723ba4fbf7 -policyType 'compliancePolicy','configurationPolicy'

    Get just 'compliancePolicy','configurationPolicy' Intune policies assigned to specified account (a.k.a. groups where he is member of (directly/transitively)). Policies assigned to 'All Users', 'All Devices' will be included. Policies where specified account (a.k.a. groups where he is member of (directly/transitively)) is excluded will be omitted!

    .EXAMPLE
    $null = Connect-MSGraph
    $null = Connect-MgGraph
    Search-IntuneAccountPolicyAssignment -accountId a815da8b-6324-4feb-94ef-96723ba4fbf7

    Get all Intune policies assigned to specified account (a.k.a. groups where he is member of (directly/transitively)). Policies assigned to 'All Users', 'All Devices' will be included. Policies where specified account (a.k.a. groups where he is member of (directly/transitively)) is excluded will be omitted!

    .EXAMPLE
    $null = Connect-MSGraph
    $null = Connect-MgGraph
    Search-IntuneAccountPolicyAssignment -accountId a815da8b-6324-4feb-94ef-96723ba4fbf7 -basicOverview

    Get all Intune policies assigned to specified account (a.k.a. groups where he is member of (directly/transitively)). Policies assigned to 'All Users', 'All Devices' will be included. Policies where specified account (a.k.a. groups where he is member of (directly/transitively)) is excluded will be omitted!

    Result will be one PSObject with policies saved in it's properties. And just subset of available properties for each policy will be gathered.

    .EXAMPLE
    $null = Connect-MSGraph
    $null = Connect-MgGraph
    Search-IntuneAccountPolicyAssignment -accountId a815da8b-6324-4feb-94ef-96723ba4fbf7 -flatOutput

    Get all Intune policies assigned to specified account (a.k.a. groups where he is member of (directly/transitively)). Policies assigned to 'All Users', 'All Devices' will be included. Policies where specified account (a.k.a. groups where he is member of (directly/transitively)) is excluded will be omitted!

    Result will be array of policies.

    .EXAMPLE
    $null = Connect-MSGraph
    $null = Connect-MgGraph
    # cache the Intune policies
    $intunePolicy = Get-IntunePolicy
    Search-IntuneAccountPolicyAssignment -accountId a815da8b-6324-4feb-94ef-96723ba4fbf7 -intunePolicy $intunePolicy -basicOverview
    Search-IntuneAccountPolicyAssignment -accountId 3465da8b-6325-daeb-94ef-56723ba4f5gt -intunePolicy $intunePolicy -basicOverview

    Do multiple searches using cached Intune policies.

    .EXAMPLE
    $null = Connect-MSGraph
    $null = Connect-MgGraph
    $intunePolicy = Get-IntunePolicy -flatOutput
    Search-IntuneAccountPolicyAssignment -accountId a815da8b-6324-4feb-94ef-96723ba4fbf7 -intunePolicy $intunePolicy -basicOverview -flatOutput
    Search-IntuneAccountPolicyAssignment -accountId 3465da8b-6325-daeb-94ef-56723ba4f5gt -intunePolicy $intunePolicy -flatOutput

    Do multiple searches using cached Intune policies.

    .NOTES
    Requires function Get-IntunePolicy.
    #>

    [CmdletBinding()]
    [Alias("Search-IntuneAccountAppliedPolicy", "Get-IntuneAccountPolicyAssignment")]
    param (
        [Parameter(Mandatory = $true)]
        [string] $accountId,

        [switch] $skipAllUsersAllDevicesAssignments,

        [switch] $ignoreExcludes,

        [switch] $justDirectGroupAssignments,

        [ValidateSet('ALL', 'app', 'appConfigurationPolicy', 'appProtectionPolicy', 'compliancePolicy', 'configurationPolicy', 'customAttributeShellScript', 'deviceEnrollmentConfiguration', 'deviceManagementPSHScript', 'deviceManagementShellScript', 'endpointSecurity', 'iosAppProvisioningProfile', 'iosUpdateConfiguration', 'macOSSoftwareUpdateConfiguration', 'policySet', 'remediationScript', 'sModeSupplementalPolicy', 'windowsAutopilotDeploymentProfile', 'windowsFeatureUpdateProfile', 'windowsQualityUpdateProfile', 'windowsUpdateRing')]
        [ValidateNotNullOrEmpty()]
        [string[]] $policyType = 'ALL',

        $intunePolicy,

        [switch] $basicOverview,

        [switch] $flatOutput
    )

    Write-Warning "For now, assignment filters are ignored when deciding if assignment should be shown as applied!"

    if (!(Get-Module Microsoft.Graph.DirectoryObjects) -and !(Get-Module Microsoft.Graph.DirectoryObjects -ListAvailable)) {
        throw "Module Microsoft.Graph.DirectoryObjects is missing"
    }
    if (!(Get-Module Microsoft.Graph.Intune) -and !(Get-Module Microsoft.Graph.Intune -ListAvailable)) {
        throw "Module Microsoft.Graph.Intune is missing"
    }

    #region helper functions
    # check whether there is at least one assignment that includes one of the groups searched account is member of and at the same time, there is none exclude rule
    function _isAssigned {
        $input | ? {
            $isAssigned = $false
            $isExcluded = $false

            $policy = $_

            Write-Verbose "Processing policy '$($policy.displayName)' ($($policy.id))"

            if (!$accountId) {
                # if no account specified, return all assignments
                return $true
            }

            foreach ($assignment in $policy.assignments) {
                # Write-Verbose "`tApplied to group(s): $($assignment.target.groupId -join ', ')"

                if (!$isAssigned -and ($assignment.target.groupId -in $accountMemberOfGroup.Id -and $assignment.target.'@odata.type' -eq '#microsoft.graph.groupAssignmentTarget')) {
                    Write-Verbose "`t++  INCLUDE assignment for group $($assignment.target.groupId) exists"
                    $isAssigned = $true
                } elseif (!$isAssigned -and !$skipAllUsersAllDevicesAssignments -and ($assignment.target.'@odata.type' -eq '#microsoft.graph.allDevicesAssignmentTarget')) {
                    Write-Verbose "`t++  INCLUDE assignment for 'All devices' exists"
                    $isAssigned = $true
                } elseif (!$isAssigned -and !$skipAllUsersAllDevicesAssignments -and ($assignment.target.'@odata.type' -eq '#microsoft.graph.allLicensedUsersAssignmentTarget')) {
                    Write-Verbose "`t++  INCLUDE assignment for 'All users' exists"
                    $isAssigned = $true
                } elseif (!$ignoreExcludes -and $assignment.target.groupId -in $accountMemberOfGroup.Id -and $assignment.target.'@odata.type' -eq '#microsoft.graph.exclusionGroupAssignmentTarget') {
                    Write-Verbose "`t--  EXCLUDE assignment for group $($assignment.target.groupId) exists"
                    $isExcluded = $true
                    break # faster processing, but INCLUDE assignments process after EXCLUDE ones won't be shown
                } else {
                    # this assignment isn't for searched account
                }
            }

            if ($isExcluded -or !$isAssigned) {
                Write-Verbose "`t--- NOT applied"
                return $false
            } else {
                Write-Verbose "`t+++ IS applied"
                return $true
            }
        }
    }
    #endregion helper functions

    #region get account group membership
    # assignment cannot be targeted to user/device but group, i.e. get account group membership
    $objectType = $null
    $accountObj = $null

    $accountObj = Get-MgDirectoryObjectById -Ids $accountId -Types group, user, device -ErrorAction Stop | Expand-MgAdditionalProperties
    $objectType = $accountObj.ObjectType
    if (!$objectType) {
        throw "Undefined object. It is not user, group or device."
    }
    Write-Verbose "$accountId '$($accountObj.DisplayName)' is a $objectType"

    switch ($objectType) {
        'device' {
            if ($justDirectGroupAssignments) {
                Write-Warning "Parameter 'justDirectGroupAssignments' can be used only if group is searched. Ignoring."
            }

            Write-Verbose "Getting account transitive memberOf property"
            $accountMemberOfGroup = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/v1.0/devices/$accountId/transitiveMemberOf?`$select=displayName,id" -ErrorAction Stop | Get-MSGraphAllPages | select Id, DisplayName

        }

        'user' {
            if ($justDirectGroupAssignments) {
                Write-Warning "Parameter 'justDirectGroupAssignments' can be used only if group is searched. Ignoring."
            }

            Write-Verbose "Getting account transitive memberOf property"
            $accountMemberOfGroup = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/users/$accountId/transitiveMemberOf?`$select=displayName,id" -ErrorAction Stop | Get-MSGraphAllPages | select Id, DisplayName
        }

        'group' {
            if ($justDirectGroupAssignments) {
                Write-Warning "Just assignments for this particular group will be shown. Not assignments for groups this group is member of or assignments for 'All Users' or 'All Devices'. But as a side effect assignments which would be otherwise ignored, because of exclude rule for parent group where this one is as a member will be shown!"

                $skipAllUsersAllDevicesAssignments = $true

                # search just the group itself
                $accountMemberOfGroup = $accountObj | select Id, DisplayName
            } else {
                Write-Verbose "Getting account transitive memberOf property"
                $accountMemberOfGroup = @()
                # add group itself
                $accountMemberOfGroup += $accountObj | select Id, DisplayName
                # add group transitive memberof
                $accountMemberOfGroup += Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/groups/$accountId/transitiveMemberOf?`$select=displayName,id" -ErrorAction Stop | Get-MSGraphAllPages | select Id, DisplayName
            }
        }

        default {
            throw "Undefined object type $objectType"
        }
    }

    if (!$justDirectGroupAssignments) {
        if ($accountMemberOfGroup) {
            Write-Verbose "Account is member of group(s):`n$(($accountMemberOfGroup | % {"`t" + $_.DisplayName + " (" + $_.Id + ")"}) -join "`n")"
        } elseif ($objectType -ne 'group' -and !$accountMemberOfGroup -and $skipAllUsersAllDevicesAssignments) {
            Write-Warning "Account $accountId isn't member of any group and 'All Users', 'All Devices' assignments should be skipped. Stopping."

            return
        }
    }
    #endregion get account group membership

    # get Intune policies
    if (!$intunePolicy) {
        $param = @{
            policyType = $policyType
        }
        if ($flatOutput) { $param.flatOutput = $true }
        $intunePolicy = Get-IntunePolicy @param
    } else {
        Write-Verbose "Given IntunePolicy object will be used instead of calling Get-IntunePolicy. Therefore PolicyType parameter is ignored too."
        if ($flatOutput -and $intunePolicy -and !(($intunePolicy | select -First 1).PolicyType)) {
            throw "Given IntunePolicy object isn't 'flat' (created using Get-IntunePolicy -flatOutput)."
        }
    }

    #region filter & output Intune policies
    if ($flatOutput) {
        # I am working directly with array of policies
        # filter & output
        if ($basicOverview) {
            $intunePolicy | _isAssigned | select id, displayName, lastModifiedDateTime, assignments, policyType
        } else {
            $intunePolicy | _isAssigned
        }
    } else {
        # I am working with object, where policies are stored as values of this object properties (policy names)
        $resultProperty = [ordered]@{}

        $intunePolicy | Get-Member -MemberType NoteProperty | select -ExpandProperty name | % {
            $policyName = $_

            Write-Verbose "$policyName policies:"

            if ($intunePolicy.$policyName) {
                # filter out policies that are not assigned to searched account
                $assignedPolicy = $intunePolicy.$policyName | _isAssigned

                if ($assignedPolicy) {
                    if ($basicOverview) {
                        $assignedPolicy = $assignedPolicy | select id, displayName, lastModifiedDateTime, assignments
                    }

                    $resultProperty.$policyName = $assignedPolicy
                } else {
                    Write-Verbose "There is none policy of type '$policyName' assigned. Skipping"
                }
            } else {
                Write-Verbose "There is none policy of type '$policyName'. Skipping"
            }
        }

        # output filtered object
        New-Object -TypeName PSObject -Property $resultProperty
    }
    #endregion filter & output Intune policies
}

function Upload-IntuneAutopilotHash {
    <#
    .SYNOPSIS
    Function for uploading Autopilot hash into Intune.

    .DESCRIPTION
    Function for uploading Autopilot hash into Intune.
    Autopilot hash can be gathered from local computer or passed in PS object.

    Beware that when the device already exists in the Autopilot, it won't be recreated (hash doesn't change)!

    .PARAMETER psObject
    PS object with properties that will be used for upload.
    - (mandatory) SerialNumber
        Device serial number.
    - (mandatory) HardwareHash
        Device hardware hash.
    - (optional) Hostname
        Device hostname
    - (optional) ownerUPN
        Device owner UPN

    .PARAMETER thisDevice
    Switch that instead of using PS object (psObject) for getting the data, hash of this computer will be uploaded.
    Requires admin rights!

    .PARAMETER ownerUPN
    UPN of the device owner.

    .PARAMETER groupTag
    Group tag for easier identification of the devices.

    By default current date.

    .EXAMPLE
    Upload-IntuneAutopilotHash -thisDevice -ownerUPN johnd@contoso.com -Verbose

    Uploads this device hash into Intune Autopilot. Owner will be johnd@contoso.com and hostname $env:COMPUTERNAME.

    .EXAMPLE
    $data = [PSCustomObject]@{
        SerialNumber = "123456"
        HardwareHash = "T0FmBAEAHAAAAAoAHgZhSgAACgCSBmFKYGIyKgg...." # can be obtained via: (Get-CimInstance -Namespace "root/cimv2/mdm/dmmap" -Class "MDM_DevDetail_Ext01" -Filter "InstanceID='Ext' AND ParentID='./DevDetail'" -Verbose:$false).DeviceHardwareData
    }

    Upload-IntuneAutopilotHash -psObject $data -Verbose

    Uploads device with specified serial number and hash into Intune Autopilot. Owner and hostname will be empty.

    .EXAMPLE
    $domain = "contoso.com"
    $data = Get-CMAutopilotHash -computername ni-20-ntb
    $data = $data | select *, @{n='OwnerUPN';e={$_.Owner + "@" + $domain}}

    Upload-IntuneAutopilotHash -psObject $data -Verbose

    Uploads device with specified serial number and hash (retrieved from SCCM database) into Intune Autopilot. Owner will be empty but hostname will be filled with value from SCCM database (ni-20-ntb).

    .NOTES
    Inspired by https://www.manishbangia.com/import-autopilot-devices-sccm-sqlquery/ and https://www.powershellgallery.com/packages/Upload-WindowsAutopilotDeviceInfo/1.0.0/Content/Upload-WindowsAutopilotDeviceInfo.ps1
    #>

    [CmdletBinding(DefaultParameterSetName = 'PSObject')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "PSObject")]
        [PSCustomObject] $psObject,

        [Parameter(Mandatory = $true, ParameterSetName = "thisDevice")]
        [switch] $thisDevice,

        [string] $ownerUPN,

        [parameter(Mandatory = $false, HelpMessage = "Specify the order identifier, e.g. 'Purchase<ID>'.")]
        [ValidateNotNullOrEmpty()]
        [string] $groupTag = (Get-Date -Format "dd.MM.yyyy")
    )

    # check mandatory properties
    if ($psObject) {
        $property = $psObject | Get-Member -MemberType NoteProperty, Property

        if ($property.Name -notcontains "SerialNumber") {
            throw "PSObject doesn't contain property SerialNumber"
        }
        if ($property.Name -notcontains "HardwareHash") {
            throw "PSObject object doesn't contain property HardwareHash"
        }
    }

    $AuthToken = New-GraphAPIAuthHeader -reuseExistingAzureADSession -useADAL -showDialogType auto

    function Get-ErrorResponseBody {
        param(
            [parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [System.Exception]$Exception
        )

        # Read the error stream
        $ErrorResponseStream = $Exception.Response.GetResponseStream()
        $StreamReader = New-Object System.IO.StreamReader($ErrorResponseStream)
        $StreamReader.BaseStream.Position = 0
        $StreamReader.DiscardBufferedData()
        $ResponseBody = $StreamReader.ReadToEnd();

        # Handle return object
        return $ResponseBody
    }

    if ($thisDevice) {
        # Gather device hash data

        if (! ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            throw "You don't have administrator rights"
        }

        Write-Verbose -Message "Gather device hash data from local machine"
        $HardwareHash = (Get-CimInstance -Namespace "root/cimv2/mdm/dmmap" -Class "MDM_DevDetail_Ext01" -Filter "InstanceID='Ext' AND ParentID='./DevDetail'" -Verbose:$false).DeviceHardwareData
        $SerialNumber = (Get-CimInstance -ClassName "Win32_BIOS" -Verbose:$false).SerialNumber
        [PSCustomObject]$psObject = @{
            SerialNumber = $SerialNumber
            HardwareHash = $HardwareHash
            Hostname     = $env:COMPUTERNAME
        }
    } else {
        # data was provided using PSObject properties
    }

    # Construct Graph variables
    $GraphVersion = "beta"
    $GraphResource = "deviceManagement/importedWindowsAutopilotDeviceIdentities"
    $GraphURI = "https://graph.microsoft.com/$($GraphVersion)/$($GraphResource)"

    foreach ($hashItem in $psObject) {
        "Processing $($hashItem.SerialNumber)"

        # Construct hash table for new Autopilot device identity and convert to JSON
        Write-Verbose -Message "Constructing required JSON body based upon parameter input data for device hash upload"
        $AutopilotDeviceIdentity = [ordered]@{
            '@odata.type'        = '#microsoft.graph.importedWindowsAutopilotDeviceIdentity'
            'groupTag'           = $groupTag
            'serialNumber'       = $hashItem.SerialNumber
            'productKey'         = ''
            'hardwareIdentifier' = $hashItem.HardwareHash
            'state'              = @{
                '@odata.type'          = 'microsoft.graph.importedWindowsAutopilotDeviceIdentityState'
                'deviceImportStatus'   = 'pending'
                'deviceRegistrationId' = ''
                'deviceErrorCode'      = 0
                'deviceErrorName'      = ''
            }
        }

        # set owner
        if ($hashItem.ownerUPN) {
            "`t - set owner $($hashItem.ownerUPN)"
            $AutopilotDeviceIdentity.assignedUserPrincipalName = $hashItem.ownerUPN
        } elseif ($ownerUPN) {
            "`t - set owner $ownerUPN"
            $AutopilotDeviceIdentity.assignedUserPrincipalName = $ownerUPN
        }

        $AutopilotDeviceIdentityJSON = $AutopilotDeviceIdentity | ConvertTo-Json

        try {
            # Call Graph API and post JSON data for new Autopilot device identity
            Write-Verbose -Message "Attempting to post data for hardware hash upload"
            # $result = Add-AutopilotImportedDevice -serialNumber $SerialNumber -hardwareIdentifier $HardwareHash -groupTag $groupTag #-assignedUser
            $result = Invoke-RestMethod -Uri $GraphURI -Headers $AuthToken -Method Post -Body $AutopilotDeviceIdentityJSON -ContentType "application/json" -ErrorAction Stop -Verbose:$false
            # $result
            Write-Verbose "Upload of $($hashItem.SerialNumber) finished"
        } catch [System.Exception] {
            # Construct stream reader for reading the response body from API call
            $ResponseBody = Get-ErrorResponseBody -Exception $_.Exception

            # Handle response output and error message
            Write-Output -InputObject "Response content:`n$ResponseBody"
            Write-Warning -Message "Failed to upload hardware hash. Request to $($GraphURI) failed with HTTP Status $($_.Exception.Response.StatusCode) and description: $($_.Exception.Response.StatusDescription)"
        }

        # set deviceName
        if ($hashItem.Hostname) {
            # invoking Intune Sync, to get imported device into Intune database, so I can set its hostname
            try {
                # Call Graph API and post Autopilot devices sync command
                Write-Verbose -Message "Attempting to perform a sync action in Autopilot"
                $GraphResource = "deviceManagement/windowsAutopilotSettings/sync"
                $GraphURI = "https://graph.microsoft.com/$($GraphVersion)/$($GraphResource)"
                $result = (Invoke-RestMethod -Uri $GraphURI -Headers $AuthToken -Method Post -ErrorAction Stop -Verbose:$false).Value
                Write-Verbose "Autopilot sync started"
            } catch [System.Exception] {
                # Construct stream reader for reading the response body from API call
                $ResponseBody = Get-ErrorResponseBody -Exception $_.Exception

                # Handle response output and error message
                Write-Output -InputObject "Response content:`n$ResponseBody"
                Write-Warning -Message "Request to $GraphURI failed with HTTP Status $($_.Exception.Response.StatusCode) and description: $($_.Exception.Response.StatusDescription)"
            }

            "`t - set hostname $($hashItem.Hostname)"
            $i = 0
            while (1) {
                ++$i
                $deviceId = Get-AutopilotDevice -serial $hashItem.SerialNumber -ea Stop | select -exp id
                if (!$deviceId) {
                    if ($i -gt 50) {
                        throw "$($hashItem.Hostname) ($($hashItem.SerialNumber)) didn't upload successfully. It probably exists in different tenant?"
                    }
                    Write-Host "`t`t$($hashItem.SerialNumber) not yet created..waiting"
                    Start-Sleep 10
                    continue
                }
                try {
                    Set-AutopilotDevice -id $deviceId -displayName $hashItem.Hostname -ea Stop
                    break
                } catch {
                    throw $_
                }
            }
        }
    }

    # invoking Intune Sync, to get imported devices into Intune database ASAP
    try {
        # Call Graph API and post Autopilot devices sync command
        Write-Verbose -Message "Attempting to perform a sync action in Autopilot"
        $GraphResource = "deviceManagement/windowsAutopilotSettings/sync"
        $GraphURI = "https://graph.microsoft.com/$($GraphVersion)/$($GraphResource)"
        $result = (Invoke-RestMethod -Uri $GraphURI -Headers $AuthToken -Method Post -ErrorAction Stop -Verbose:$false).Value
        Write-Verbose "Autopilot sync started"
    } catch [System.Exception] {
        # Construct stream reader for reading the response body from API call
        $ResponseBody = Get-ErrorResponseBody -Exception $_.Exception

        # Handle response output and error message
        Write-Output -InputObject "Response content:`n$ResponseBody"
        Write-Warning -Message "Request to $GraphURI failed with HTTP Status $($_.Exception.Response.StatusCode) and description: $($_.Exception.Response.StatusDescription)"
    }
}

Export-ModuleMember -function Connect-MSGraph2, ConvertFrom-MDMDiagReport, ConvertFrom-MDMDiagReportXML, Get-BitlockerEscrowStatusForAzureADDevices, Get-ClientIntunePolicyResult, Get-HybridADJoinStatus, Get-IntuneDeviceComplianceStatus, Get-IntuneEnrollmentStatus, Get-IntuneLog, Get-IntuneLogRemediationScriptData, Get-IntuneLogWin32AppData, Get-IntuneLogWin32AppReportingResultData, Get-IntuneOverallComplianceStatus, Get-IntunePolicy, Get-IntuneRemediationScript, Get-IntuneRemediationScriptLocally, Get-IntuneReport, Get-IntuneScriptContentLocally, Get-IntuneScriptLocally, Get-IntuneWin32AppLocally, Get-MDMClientData, Get-UserSIDForUserAzureID, Invoke-IntuneScriptRedeploy, Invoke-IntuneWin32AppRedeploy, Invoke-MDMReenrollment, Invoke-ReRegisterDeviceToIntune, New-GraphAPIAuthHeader, Reset-HybridADJoin, Reset-IntuneEnrollment, Search-IntuneAccountPolicyAssignment, Upload-IntuneAutopilotHash

Export-ModuleMember -alias Connect-MSGraphApp2, Get-IntuneAccountPolicyAssignment, Get-IntuneAuthHeader, Get-IntuneClientPolicyResult, Get-IntuneJoinStatus, Get-IntunePolicyResult, Invoke-IntuneEnrollmentRepair, Invoke-IntuneEnrollmentReset, Invoke-IntuneReenrollment, Invoke-IntuneScriptRedeployLocally, Invoke-IntuneWin32AppRedeployLocally, ipresult, New-IntuneAuthHeader, Repair-IntuneEnrollment, Reset-IntuneJoin, Search-IntuneAccountAppliedPolicy
