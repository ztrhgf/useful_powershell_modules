@{
    RootModule        = 'TestModule.psm1'
    ModuleVersion     = '1.0.5'
    GUID              = 'a69f8a7d-33d7-43ee-b45b-195896313942'
    Author            = '@AndrewZtrhgf'
    CompanyName       = 'Unknown'
    Copyright         = '(c) 2022 @AndrewZtrhgf. All rights reserved.'
    Description       = 'Various Intune related functions. Some of them are explained at https://doitpsway.com.

Some of the interesting functions:
- Get-ClientIntunePolicyResult - RSOP/gpresult for Intune
- Invoke-IntuneScriptRedeploy - redeploy script deployed from Intune
- Invoke-IntuneWin32AppRedeploy - redeploy application deployed from Intune
- Get-IntuneLog - opens Intune logs (files & system logs)
- ...
'
    PowerShellVersion = '5.1'
    RequiredModules   = @('PSWriteHtml', 'Microsoft.Graph.Intune', 'WindowsAutoPilotIntune', 'CommonStuff')
    FunctionsToExport = '*'
    CmdletsToExport   = '*'
    VariablesToExport = '*'
    AliasesToExport   = '*'
    PrivateData       = @{
        PSData = @{
            Tags       = @('MEMCM', 'PowerShell', 'Intune', 'MDM')
            ProjectUri = 'https://doitpsway.com/series/sccm-mdt-intune'
        } # End of PSData hashtable
    } # End of PrivateData hashtable
}