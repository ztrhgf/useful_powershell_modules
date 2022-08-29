function Get-IntuneWin32App {
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
    Get-IntuneWin32App

    Get and show Win32App(s) deployed from Intune to local computer.
    IDs of targeted users and apps will be translated using information from local Intune log files.

    .EXAMPLE
    Get-IntuneWin32App -computerName PC-01 -getDataFromIntune credential (Get-Credentials)

    Get and show Win32App(s) deployed from Intune to computer PC-01. IDs of apps and targeted users will be translated to corresponding names.

    .EXAMPLE
    $win32AppData = Get-IntuneWin32App

    $myApp = ($win32AppData | ? DisplayName -eq 'MyApp')

    "Output complete object"
    $myApp

    "Detection script content for application 'MyApp'"
    $myApp.additionalData.DetectionRule.DetectionText.ScriptBody

    "Requirement script content for application 'MyApp'"
    $myApp.additionalData.ExtendedRequirementRules.RequirementText.ScriptBody

    "Installation script content for application 'MyApp'"
    $myApp.additionalData.InstallCommandLine

    Show various interesting information for MyApp application deployment.
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
                    $userSID = Get-IntuneUserSID $id
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

    # function translates user Azure ID to local SID, by getting such info from Intune log files
    function Get-IntuneUserSID {
        param (
            [Parameter(Mandatory = $true)]
            [string] $userId
        )

        $intuneLogList = Get-ChildItem -Path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs" -Filter "IntuneManagementExtension*.log" -File | sort LastWriteTime -Descending | select -ExpandProperty FullName

        if (!$intuneLogList) {
            Write-Error "Unable to find any Intune log files. Redeploy will probably not work as expected."
            return
        }

        foreach ($intuneLog in $intuneLogList) {
            # how content of the log can looks like
            # [Win32App] ..................... Processing user session 1, userId: e5834928-0f19-492d-8a69-3fbc98fd84eb, userSID: S-1-5-21-2475586523-545188003-3344463812-8050 .....................
            # [Win32App] EspPreparation starts for userId: e5834928-0f19-442d-8a69-3fbc98fd84eb userSID: S-1-5-21-2475586523-545182003-3344463812-8050

            $userMatch = Select-String -Path $intuneLog -Pattern "(?:\[Win32App\] \.* Processing user session \d+, userId: $userId, userSID: (S-[0-9-]+) )|(?:\[Win32App\] EspPreparation starts for userId: $userId userSID: (S-[0-9-]+))" -List
            if ($userMatch) {
                # return user SID
                return $userMatch.matches.groups[1].value
            }
        }

        Write-Warning "Unable to find User '$userId' in any of the Intune log files. Unable to translate this AAD ID to local SID."
    }

    # function translates app Azure ID to name, by getting such info from Intune log files
    function Get-IntuneWin32AppName {
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
            # how content of the log can looks like
            # [Win32App] app result (id = e524e208-0758-4b38-a15a-60688778421c, name = BuiltinAdminPSProfile.ps1, version = 2) is different from cached one, save to cache.
            # [Win32App] Processing app (id=e524e208-0758-4b38-a15a-60688778421c, name = BuiltinAdminPSProfile.ps1) with mode = DetectInstall	IntuneManagementExtension	26.07.2022 15:44:56	80 (0x0050)

            $appMatch = Select-String -Path $intuneLog -Pattern "(?:\[Win32App\] ExecManager: processing targeted app \(name='([^,]+)', id='$appId'\))|(?:\[Win32App\] app result \(id = $appId, name = ([^,]+),)" -List
            if ($appMatch) {
                # return app name
                return $appMatch.matches.groups[1].value
            }
        }

        Write-Warning "Unable to find App '$appId' in any of the Intune log files. Unable to translate its ID to Name."
        return "*unable to obtain from local logs*"
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
    $allFunctionDefs = "function _getTargetName { ${function:_getTargetName} }; function Get-IntuneWin32AppName { ${function:Get-IntuneWin32AppName} }; function Get-IntuneUserSID { ${function:Get-IntuneUserSID} }; function Get-Win32AppErrMsg { ${function:Get-Win32AppErrMsg} }; function Get-IntuneLogWin32AppData { ${function:Get-IntuneLogWin32AppData} }"
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

        foreach ($app in (Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps" -ErrorAction SilentlyContinue)) {
            $userAzureObjectID = Split-Path $app.Name -Leaf

            if ($excludeSystemApp -and $userAzureObjectID -eq "00000000-0000-0000-0000-000000000000") {
                Write-Verbose "Skipping system deployments"
                continue
            }

            $userWin32AppRoot = $app.PSPath
            $win32AppIDList = Get-ChildItem $userWin32AppRoot | select -ExpandProperty PSChildName | % { $_ -replace "_\d+$" } | select -Unique | ? { $_ -ne 'GRS' }

            $win32AppIDList | % {
                $win32AppID = $_

                Write-Verbose "Processing App ID $win32AppID"

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

                #region output the results
                if ($getDataFromIntune) {
                    $property = [ordered]@{
                        "Scope"              = _getTargetName $userAzureObjectID
                        "DisplayName"        = ($intuneApp | ? id -EQ $win32AppID).DisplayName
                        "Id"                 = $win32AppID
                        "ComplianceState"    = $complianceState
                        "LastUpdatedTimeUtc" = $lastUpdatedTimeUtc
                        "ProductVersion"     = $complianceStateMessage.ProductVersion
                        "LastError"          = $lastError
                        "DesiredState"       = $desiredState
                        "EnforcementState"   = $enforcementState
                        # "EnforcementErrorCode" = $enforcementStateMessage.ErrorCode
                        "EnforcementError"   = Get-Win32AppErrMsg $enforcementStateMessage.ErrorCode
                        "DeploymentType"     = $deploymentType
                        "ScopeId"            = $userAzureObjectID
                    }
                } else {
                    $property = [ordered]@{
                        "Scope"              = _getTargetName $userAzureObjectID
                        "DisplayName"        = Get-IntuneWin32AppName $win32AppID
                        "Id"                 = $win32AppID
                        "ComplianceState"    = $complianceState
                        "LastUpdatedTimeUtc" = $lastUpdatedTimeUtc
                        "ProductVersion"     = $complianceStateMessage.ProductVersion
                        "LastError"          = $lastError
                        "DesiredState"       = $desiredState
                        "EnforcementState"   = $enforcementState
                        # "EnforcementErrorCode" = $enforcementStateMessage.ErrorCode
                        "EnforcementError"   = Get-Win32AppErrMsg $enforcementStateMessage.ErrorCode
                        "DeploymentType"     = $deploymentType
                        "ScopeId"            = $userAzureObjectID
                    }
                }

                $appLogData = $logData | ? Id -EQ $win32AppID
                if ($appLogData) {
                    Write-Verbose "Enrich app object data with information found in Intune log files"
                    $property.additionalData = $appLogData
                } else {
                    Write-Verbose "For app $win32AppID there are no extra information in Intune log files"
                }

                New-Object -TypeName PSObject -Property $property
                #endregion output the results
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
        $win32App
    } else {
        Write-Warning "No deployed Win32App detected"
    }
    #endregion let user redeploy chosen app

    if ($computerName) {
        Remove-PSSession $session
    }
}