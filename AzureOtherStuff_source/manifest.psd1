@{
    RootModule        = 'TestModule.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a0ef14ff-c5d6-47e9-a431-ffb512637245'
    Author            = '@AndrewZtrhgf'
    CompanyName       = 'Unknown'
    Copyright         = '(c) 2022 @AndrewZtrhgf. All rights reserved.'
    Description       = 'Various Azure related functions. More details at https://doitpsway.com/series/azure.
Some of the interesting functions:
- Get-AzureAssessNotificationEmail
- Get-AzureDevOpsOrganizationOverview
- Open-AzureAdminConsentPage
- ...
'
    PowerShellVersion = '5.1'
    RequiredModules   = @('MSGraphStuff', 'AzureCommonStuff')
    FunctionsToExport = @()
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('Azure', 'PowerShell', 'Monitoring', 'Audit', 'Security', 'Graph', 'Runbook')
            ProjectUri   = 'https://github.com/ztrhgf/useful_powershell_modules'
            ReleaseNotes = '
            * 1.0.0
                * Initial release. Some functions are migrated from now deprecated AzureADStuff module, some are completely new.
            '
        } # End of PSData hashtable
    } # End of PrivateData hashtable
}