@{
    RootModule           = 'IntuneStuff.psm1'
    ModuleVersion        = '1.7.0'
    GUID                 = 'a69f8a7d-33d7-43ee-b45b-195896313942'
    Author               = '@AndrewZtrhgf'
    CompanyName          = 'Unknown'
    Copyright            = '(c) 2022 @AndrewZtrhgf. All rights reserved.'
    Description          = 'Various Intune related functions. Some of them are explained at https://doitpshway.com/series/sccm-mdt-intune.

Some of the interesting functions:
- Compare-IntuneSecurityBaseline - compare two security baselines
- Get-IntuneRemediationScriptLocally - gets Intune Remediation scripts information from client`s log files and registry (including scripts content)
- Get-IntuneScriptLocally - gets Intune (non-remediation) scripts information from client`s registry and captured script files (including scripts content)
- Get-IntuneWin32AppLocally - gets Win32Apps information from client`s log files and registry (including install/uninstall commands and detection/requirements scripts)
- Get-ClientIntunePolicyResult - RSOP/gpresult for Intune (also available as HTML report)
- Get-IntuneAuditEvent - get Intune Audit events
- Get-IntuneLog - opens Intune logs (files & system logs)
- Get-IntunePolicy - gets ALL Intune (assignable) policies (from Apps to Windows Update Rings)
- Get-UserSIDForUserAzureID - translates user AzureID to local SID
- Invoke-IntuneCommand - "Invoke-Command" alternative for Intune managed Windows clients :)
- Invoke-MDMReenrollment - resets device Intune management connection
- Invoke-IntuneScriptRedeploy - redeploy script deployed from Intune
- Invoke-IntuneWin32AppRedeploy - redeploy application deployed from Intune
- Invoke-IntuneWin32AppAssignment - assign selected Win32 apps
- Remove-IntuneWin32AppAssignment - deassign selected Win32 apps
- Reset-HybridADJoin - reset Hybrid AzureAD join connection
- Reset-IntuneEnrollment - reset device Intune management enrollment
- Search-IntuneAccountPolicyAssignment - search user/device/group assigned Intune policies
- Set-AADDeviceExtensionAttribute - set/reset device extension attribute
- Upload-IntuneAutopilotHash - upload given autopilot hash (owner and hostname) into Intune
- ...
'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = 'Core', 'Desktop'
    RequiredModules      = @('Az.Accounts', 'Microsoft.Graph.Authentication', 'Microsoft.Graph.DeviceManagement.Administration', 'Microsoft.Graph.DirectoryObjects', 'Microsoft.Graph.Devices.CorporateManagement', 'Microsoft.Graph.DeviceManagement', 'Microsoft.Graph.DeviceManagement.Enrollment', 'Microsoft.Graph.Beta.DeviceManagement', 'Microsoft.Graph.Beta.DeviceManagement.Actions', 'Microsoft.Graph.Groups', 'WindowsAutoPilotIntune', 'CommonStuff', 'MSGraphStuff', 'MSAL.PS')
    FunctionsToExport    = '*'
    CmdletsToExport      = '*'
    VariablesToExport    = '*'
    AliasesToExport      = '*'
    PrivateData          = @{
        PSData = @{
            Tags         = @('MEMCM', 'PowerShell', 'Intune', 'MDM', 'IntuneStuff')
            ProjectUri   = 'https://github.com/ztrhgf/useful_powershell_modules'
            ReleaseNotes = '
            1.7.0
                ADDED
                    Get-IntuneRemediationResult - Get results for an Intune remediation script run
                CHANGED
                    Invoke-IntuneCommand - rewritten to use Graph Api Batching (almost 10x faster now)
                                         - slight changes in settings format output
                    Get-IntuneDeviceHardware, Get-IntuneDiscoveredApp - rewritten to match new New-GraphBatchRequest version parameters
            1.6.4
                ADDED
                    Get-IntuneDeviceHardware
                    Get-IntuneDeviceOnDemandProactiveRemediationStatus
                    Get-IntuneDiscoveredApp
                CHANGED
                    Invoke-IntuneCommand - deviceId parameter
                                         - detection of multiple devices with same name
            1.6.3
                CHANGED
                    Invoke-IntuneCommand - added support for SCCM co-managed clients
                                         - better function help
            1.6.2
                ADDED
                    Compare-IntuneSecurityBaseline
            1.6.1
                FIXED
                    Get-IntuneReport - fixed error "UnsupportedMediaType"
                CHANGED
                    Get-IntuneReport - added support for new reports
            1.5.1
                CHANGED
                    Added Core PSH support to the module manifest
                REMOVED
                    Connect-MSGraph2 - no longer needed
                    Microsoft.Graph.Intune module was replaced by other supported Graph modules.
            1.5.0
                CHANGED
                    Invoke-IntuneCommand - Windows managed devices filtering, skipped device support, UTC in date property names
                FIXED
                    Invoke-IntuneCommand - missing deviceName, remediation removal after CTRL + C
            1.4.9
                CHANGED
                    Invoke-IntuneCommand - added parameter prependCommandDefinition
            1.4.8
                CHANGED
                    Invoke-IntuneCommand - added parameters scriptBlock, remediationSuffix
                                         - added support for converting compressed strings back
            1.4.7
                ADDED
                    Invoke-IntuneCommand
                    Invoke-IntuneRemediationOnDemand
                    New-IntuneRemediation
                    Remove-IntuneRemediation
                REMOVED
                    Get-IntuneRemediationScript (duplicity with Get-IntuneRemediationScriptLocally)
            1.4.6
                ADDED
                    Invoke-IntuneScriptRedeploy - noDetails switch
                    Invoke-IntuneWin32AppRedeploy - noDetails switch
            1.4.5
                FIXED
                    Invoke-IntuneScriptRedeploy redeploy when getDataFromIntune is used
                    Get-IntuneReport filter check for app report
                ADDED
                    Invoke-IntuneWin32AppAssignment
                    Remove-IntuneWin32AppAssignment
            1.4.3
                FIXED
                    Get-IntunePolicy returns assignments when basicOverview is used
            '
        } # End of PSData hashtable
    } # End of PrivateData hashtable
}