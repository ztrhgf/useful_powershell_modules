@{
    RootModule        = 'TestModule.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '1f9e4f50-2cac-411b-80f8-16003b8a5542'
    Author            = '@AndrewZtrhgf'
    CompanyName       = 'Unknown'
    Copyright         = '(c) 2022 @AndrewZtrhgf. All rights reserved.'
    Description       = 'Various Azure related functions. Some of them are explained at https://doitpsway.com.

Some of the interesting functions:
Remove-O365OrphanedMailbox - fixes problem of the orphaned mailboxes
- ...
'
    PowerShellVersion = '5.1'
    RequiredModules   = @("AzureADStuff")
    FunctionsToExport = '*'
    CmdletsToExport   = '*'
    VariablesToExport = '*'
    AliasesToExport   = '*'
    PrivateData       = @{
        PSData = @{
            Tags       = @('O365', 'Office365', 'ExchangeOnline', 'PowerShell')
            ProjectUri = 'https://doitpsway.com/series/sccm-mdt-intune'
        } # End of PSData hashtable
    } # End of PrivateData hashtable
}