@{
    RootModule        = 'TestModule.psm1'
    ModuleVersion     = '1.0.3'
    GUID              = '1f9e4f50-2cac-411b-80f8-16003b8a5542'
    Author            = '@AndrewZtrhgf'
    CompanyName       = 'Unknown'
    Copyright         = '(c) 2022 @AndrewZtrhgf. All rights reserved.'
    Description       = 'Various Azure related functions. Some of them are explained at https://doitpsway.com.

Some of the interesting functions:
- Add-CMDeviceToCollection - adding selected device to selected collection
- Clear-CMClientCache - clearing SCCM client cache
- Connect-SCCM - making remote session to SCCM server
- Get-CMLog - openning the correct SCCM client/server log(s) based on specified topic
- Invoke-CMAdminServiceQuery - invoking query against SCCM Admin Service
- Invoke-CMAppInstall - invoking installation of deployed application(s) on the client
- Invoke-CMComplianceEvaluation - invoking of compliance validations
- Refresh-CMCollection - refreshing SCCM collection members
- Update-CMAppSourceContent - updating source data of the application
- Update-CMClientPolicy - updating of SCCM client policies (like gpupdate for GPO)
- Get-CMAutopilotHash - read client Autopilot hash from SCCM database
- ...
'
    PowerShellVersion = '5.1'
    RequiredModules   = @("CommonStuff")
    FunctionsToExport = '*'
    CmdletsToExport   = '*'
    VariablesToExport = '*'
    AliasesToExport   = '*'
    PrivateData       = @{
        PSData = @{
            Tags       = @('MEMCM', 'PowerShell', 'SCCM')
            ProjectUri = 'https://doitpsway.com/series/sccm-mdt-intune'
        } # End of PSData hashtable
    } # End of PrivateData hashtable
}