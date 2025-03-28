@{
    RootModule           = 'TestModule.psm1'
    ModuleVersion        = '1.0.4'
    GUID                 = '37b7cbe4-a986-4fc4-9d6b-6d04dc877ef2'
    Author               = '@AndrewZtrhgf'
    CompanyName          = 'Unknown'
    Copyright            = '(c) 2022 @AndrewZtrhgf. All rights reserved.'
    Description          = 'Various Azure ARC related functions. More details at https://doitpshway.com/series/azure.
Some of the interesting functions:
- Copy-ToArcMachine - copy file(s) to ARC machine via arc-ssh-proxy
- Enter-ArcPSSession - Enter interactive remote session to ARC machine via arc-ssh-proxy
- Get-ARCExtensionOverview - Returns overview of all installed ARC extensions
- Get-ArcMachineOverview - Get list of all ARC machines in your Azure tenant
- Invoke-ArcCommand - Invoke-Command like alternative via arc-ssh-proxy
- Invoke-ArcRDP - RDP to ARC machine via arc-ssh-proxy
- New-ArcPSSession - Create remote session to ARC machine via arc-ssh-proxy
- ...
'
    PowerShellVersion    = '7.0'
    CompatiblePSEditions = 'Core'
    RequiredModules      = @('Az.Accounts', 'Az.ResourceGraph', 'AzureKeyVaultStuff', 'Az.KeyVault', 'Az.Ssh', 'Az.Compute', 'Microsoft.Graph.Applications')
    FunctionsToExport    = @()
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags         = @('Azure', 'AzureARCStuff', 'PowerShell', 'ARC')
            ProjectUri   = 'https://github.com/ztrhgf/useful_powershell_modules'
            ReleaseNotes = '
            1.0.4
                CHANGED
                    Copy-ToArcMachine - can be run against multiple devices now
                    Invoke-ArcRDP - cleanup wait time increased to 10s
                    Invoke-ArcCommand - added parameter machineType to match New-ArcPSSession
                    Enter-ArcPSSession - added parameter machineType to match New-ArcPSSession
            1.0.3
                CHANGED
                    New-ArcPSSession - fixes; better private key file handling; added relay data cleanup
            1.0.2
                ADDED
                    Invoke-ArcCommand
                CHANGED
                    Copy-ToArcMachine - session creation logic moved to New-ArcPSSession
                    Enter-ArcPSSession - session creation logic moved to New-ArcPSSession
                    New-ArcPSSession - option to create multiple sessions at one
                    Invoke-ArcRDP - cleanup wait time increased to 7 seconds
                    Get-ArcMachineOverview - added SMI to the overview
            1.0.1
                ADDED
                    Copy-ToArcMachine
                CHANGED
                    New-ArcPSSession - renamed parameter keyFile to privateKeyFile; session reuse; unnecessary checks removal
                    Enter-ArcPSSession - session reuse; unnecessary checks removal
                    Invoke-ArcRDP - unnecessary checks removal
            1.0.0
                Initial release.
            '
        } # End of PSData hashtable
    } # End of PrivateData hashtable
}