@{
    RootModule        = 'TestModule.psm1'
    ModuleVersion     = '1.0.6'
    GUID              = '1f9e4f50-2cac-411b-80f8-16003b8a5542'
    Author            = '@AndrewZtrhgf'
    CompanyName       = 'Unknown'
    Copyright         = '(c) 2022 @AndrewZtrhgf. All rights reserved.'
    Description       = 'Various Azure related functions. Some of them are explained at https://doitpsway.com.

Some of the interesting functions:
- Get-AzureADAccountOccurrence - for getting all occurrences of specified account in your Azure environment
- Get-AzureADAppConsentRequest - for getting all application admin consent requests
- Get-AzureDevOpsOrganizationOverview - list of all DevOps organizations
- Add-AzureADAppCertificate - add the certificate (existing or create self-signed) to selected Azure application as an secret
- Add-AzureADAppUserConsent - granting permission consent on behalf of another user

Some of the authentication-related functions:
- New-AzureDevOpsAuthHeader
- New-GraphAPIAuthHeader'
    PowerShellVersion = '5.1'
    RequiredModules   = @('AzureAD', 'Az.Accounts', 'Az.Resources', 'AzureAD', 'MSAL.PS', 'PnP.PowerShell', 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Applications', 'Microsoft.Graph.Users', 'Microsoft.Graph.Identity.SignIns')
    FunctionsToExport = '*'
    CmdletsToExport   = '*'
    VariablesToExport = '*'
    AliasesToExport   = '*'
    PrivateData       = @{
        PSData = @{
            Tags       = @('Azure', 'PowerShell', 'Monitoring', 'Audit', 'Security')
            ProjectUri = 'https://doitpsway.com/series/azure'
        } # End of PSData hashtable
    } # End of PrivateData hashtable
}