@{
    RootModule        = 'CommonStuff.psm1'
    ModuleVersion     = '1.0.23'
    GUID              = 'a69f8a7d-33d7-43ee-b45b-195896313942'
    Author            = '@AndrewZtrhgf'
    CompanyName       = 'Unknown'
    Copyright         = '(c) 2022 @AndrewZtrhgf. All rights reserved.'
    Description       = 'Various helper functions for modules IntuneStuff, AzureADStuff etc. Some of them are explained at https://doitpshway.com.

    Some of the interesting functions:
    - ConvertFrom-HTMLTable - extracts & converts html table from given file/string/com object into the PSObject
    - ConvertFrom-XML - converts XML into PSObject
    - ConvertFrom-CompressedString
    - ConvertTo-CompressedString
    - Compare-Object2 - can be used for comparison of strings, objects, arrays of primitives/objects
    - Export-ScriptsToModule - export functions defined in ps1 files into PS module (including aliases and manifest file)
    - Get-InstalledSoftware - returns installed software on local/remote computer
    - Get-SFCLogEvent - gets SFC related lines from CBS.log
    - Get-PSHScriptBlockLoggingEvent - gets PowerShell Script Block logging events with context like who/when/how run the command, ...
    - Invoke-AsSystem - invoke given command under SYSTEM account. Support returning of the command transcript.
    - Invoke-AsLoggedUser - invoke given command under all currently logged users (impersonate given user). Support returning of the command transcript.
    - Invoke-FileContentWatcher - monitors changes in selected file content
    - Invoke-FileSystemWatcher - monitors changes in selected folder
    - Invoke-RestMethod2 - Invoke-RestMethod proxy functions that supports pagination, throttling
    - Invoke-SQL - invoke SQL command (uses Security=SSPI authentication)
    - Invoke-MSTSC - invoke RDP connection using LAPS credentials (and more)
    - Publish-Module2 - solves error "The specified RequiredModules entry xxx In the module manifest xxx.psd1 is invalid" in case of missing required modules
    - Uninstall-ApplicationViaUninstallString - uninstalls application using information retrieved from system registry
    - Send-EmailViaSendGrid - send email using SendGrid (supports api token retrieval from Azure Keyvault or credentials object)
    - ...
    '
    PowerShellVersion = '5.1'
    RequiredModules   = @()
    FunctionsToExport = @()
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('PowerShell', 'CommonStuff', 'HTML', 'SQL', 'File', 'Clipboard')
            ProjectUri   = 'https://github.com/ztrhgf/useful_powershell_modules'
            ReleaseNotes = '
            1.0.23
                ADDED
                    Expand-ObjectProperty - expands nested object property to the main object
                CHANGED
                    Publish-Module2 - added support for required modules defined via hashtable
                    Export-ScriptsToModule - added support for required modules defined via hashtable
                                           - new parameter sensitiveInfoRegex for checking sensitive information in scripts
                    REMOVED
                        PowerHTML module from the module manifest. Install manually if necessary.
            1.0.22
                CHANGED
                    Invoke-MSTSC - fix for Windows PSH
            1.0.21
                CHANGED
                    Invoke-AsSystem - new parameters scriptFile, usePSHCore
                    Invoke-RestMethod2 - better handling of next link
                    Invoke-MSTSC - rewrite for modern Windows LAPS; added core PSH support
            1.0.19
                ADDED
                    Send-EmailViaSendGrid
            1.0.19
                ADDED
                    Quote-String
                    Read-FromClipboard
                REMOVED
                    Removed obsolete requirement for AdmPwd.PS module. Invoke-MSTSC uses built-in LAPS module instead.
            1.0.18
                CHANGED
                    ConvertTo-CompressedString - fixed pipeline support
                    ConvertFrom-CompressedString - fixed pipeline support
            1.0.17
                CHANGED
                    ConvertTo-CompressedString - added support for pipeline input
                    ConvertFrom-CompressedString - added support for pipeline input
            1.0.16
                ADDED
                    ConvertFrom-CompressedString
                    ConvertTo-CompressedString
            1.0.15
                CHANGED
                    renamed Create-BasicAuthHeader to New-BasicAuthHeader to avoid unapproved verb warning (Create-BasicAuthHeader is now alias)
            1.0.14
                ADDED
                    Get-PSHScriptBlockLoggingEvent
            '
        } # End of PSData hashtable
    } # End of PrivateData hashtable
}