@{
    RootModule           = 'M365DefenderStuff.psm1'
    ModuleVersion        = '1.0.1'
    GUID                 = 'e41efadc-6c92-41b6-92e7-1cb748be1007'
    Author               = '@AndrewZtrhgf'
    CompanyName          = 'Unknown'
    Copyright            = '(c) 2022 @AndrewZtrhgf. All rights reserved.'
    Description          = 'Various functions related to Microsoft Defender services (APIs). Some of them are explained at https://doitpshway.com.

    Some of the interesting functions:
    - Get-M365DefenderMachine - get specific/all machine(s)
    - Get-M365DefenderMachineUser - get machine owner
    - Get-M365DefenderMachineVulnerability - get vulnerabilities detected on the machine
    - Get-M365DefenderRecommendation - get specific/all recommendation(s)
    - Get-M365DefenderSoftware - get specific/all software
    - Get-M365DefenderVulnerability - get specific/all vulnerability/ies
    - Get-M365DefenderVulnerabilityReport - returns customized output of Get-M365DefenderMachineVulnerability
    - Invoke-M365DefenderAdvancedQuery - returns result of the specified KQL
    - Invoke-M365DefenderSoftwareEvidenceQuery - returns Software Evidence query results from DeviceTvmSoftwareEvidenceBeta table
    - New-M365DefenderAuthHeader - creates authentication header for accessing Microsoft 365 Defender API. Supports authentication using Managed identity, current user, app secret
    - ...
    '
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = 'Core', 'Desktop'
    RequiredModules      = @('CommonStuff')
    FunctionsToExport    = '*'
    CmdletsToExport      = '*'
    VariablesToExport    = '*'
    AliasesToExport      = '*'
    PrivateData          = @{
        PSData = @{
            Tags         = @('PowerShell', 'M365DefenderStuff', 'Defender')
            ProjectUri   = 'https://github.com/ztrhgf/useful_powershell_modules'
            ReleaseNotes = '
            1.0.1
                CHANGED
                    New-M365DefenderAuthHeader - support for Az 5.x (SecureString returned by Get-AzAccessToken)
            1.0.0
                ADDED
                    Get-M365DefenderMachine
                    Get-M365DefenderMachineUser
                    Get-M365DefenderMachineVulnerability
                    Get-M365DefenderRecommendation
                    Get-M365DefenderSoftware
                    Get-M365DefenderVulnerability
                    Get-M365DefenderVulnerabilityReport
                    Invoke-M365DefenderAdvancedQuery
                    Invoke-M365DefenderSoftwareEvidenceQuery
                    New-M365DefenderAuthHeader
            '
        } # End of PSData hashtable
    } # End of PrivateData hashtable
}