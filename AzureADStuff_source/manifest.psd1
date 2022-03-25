@{
    RootModule        = 'TestModule.psm1'
    ModuleVersion     = '1.0.3'
    GUID              = '1f9e4f50-2cac-411b-80f8-16003b8a5542'
    Author            = '@AndrewZtrhgf'
    CompanyName       = 'Unknown'
    Copyright         = '(c) 2022 @AndrewZtrhgf. All rights reserved.'
    Description       = 'Various Azure related functions. Some of them are explained at https://doitpsway.com.

Some of the functions:
- Get-AzureADAccountOccurrence - for getting all account occurrences in your Azure environment
- Get-AzureADAppConsentRequest - for getting all application admin consent requests
- Get-AzureDevOpsOrganizationOverview - list of all DevOps organizations
- Add-AzureADAppCertificate - add the certificate (existing or create self-signed) to selected Azure application as an secret

Some of the authentication-related functions:
- New-AzureDevOpsAuthHeader
- New-GraphAPIAuthHeader'
    PowerShellVersion = '5.1'
    RequiredModules   = @('Az.Accounts', 'Az.Resources', 'AzureAD', 'MSAL.PS', 'PnP.PowerShell')
    FunctionsToExport = '*'
    CmdletsToExport   = '*'
    VariablesToExport = '*'
    AliasesToExport   = '*'
    PrivateData       = @{
        PSData = @{
            Tags       = @('Azure', 'PowerShell', 'Monitoring', 'Audit', 'Security')
            ProjectUri = 'https://doitpsway.com/how-to-find-all-places-in-azure-where-specific-account-is-used'
        } # End of PSData hashtable
    } # End of PrivateData hashtable
}