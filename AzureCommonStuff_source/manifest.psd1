@{
    RootModule           = 'AzureCommonStuff.psm1'
    ModuleVersion        = '1.0.7'
    GUID                 = '6c464298-9b3e-478a-996b-e095aaf15c91'
    Author               = '@AndrewZtrhgf'
    CompanyName          = 'Unknown'
    Copyright            = '(c) 2022 @AndrewZtrhgf. All rights reserved.'
    Description          = 'Various Azure related functions focused on authentication etc. More details at https://doitpshway.com/series/azure.
Some of the interesting functions:
- Connect-AzAccount2 - proxy function for Connect-AzAccount, but supports reusing the existing session
- Connect-PnPOnline2 - proxy function for Connect-PnPOnline with some enhancements like: automatic MFA auth if MFA detected, skipping authentication if already authenticated etc
- Get-AzureDirectoryObject - gets Azure directory object (user, group, device etc.) by its ID
- Get-AzureDirectoryObjectMemberOf - gets Azure directory object (user, group, device etc.) memberships by its ID
- Invoke-AzureBatchRequest - function to make batch requests against Azure Resource Manager provider (unofficial) api
- New-AzureBatchRequest - function to create batch request object usable against Azure Resource Manager provider (unofficial) api
- New-AzureDevOpsAuthHeader - creates auth header for DevOps authentication
- ...
'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = 'Core', 'Desktop'
    RequiredModules      = @('Az.Accounts', 'PnP.PowerShell', 'MSAL.PS')
    FunctionsToExport    = @()
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags         = @('Azure', 'AzureCommonStuff', 'PowerShell', 'Monitoring', 'Audit', 'Security', 'Graph', 'Runbook', 'Batch', 'ARM')
            ProjectUri   = 'https://github.com/ztrhgf/useful_powershell_modules'
            ReleaseNotes = '
            1.0.7
                ADDED
                    Get-AzureDirectoryObject
                    Get-AzureDirectoryObjectMemberOf
            1.0.6
                FIXED
                    Invoke-AzureBatchRequest - stop returning of empty objects on failed requests
                CHANGED
                    New-AzureBatchRequest - merged url and urlWithPlaceholder parameters
                                          - added support for specifying ID for urls with placeholder
            1.0.5
                CHANGED
                    Invoke-AzureBatchRequest - added parameter "dontAddRequestName"
                FIXED
                    Invoke-AzureBatchRequest - pipeline fixes
                    New-AzureBatchRequest - slashes replace fix
            1.0.4
                ADDED
                    Invoke-AzureBatchRequest
                    New-AzureBatchRequest
            1.0.3
                CHANGED
                    New-AzureDevOpsAuthHeader - MSAL is now not default auth
            1.0.2
                ADDED
                    Connect-PnPOnline2 - new parameter useWebLogin
            1.0.1
                CHANGED
                    fixes & new parameters for Connect-AzAccount2
            1.0.0
                Initial release. Some functions are migrated from now deprecated AzureADStuff module, some are completely new.
            '
        } # End of PSData hashtable
    } # End of PrivateData hashtable
}