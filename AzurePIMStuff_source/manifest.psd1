@{
    RootModule           = 'AzurePIMStuff.psm1'
    ModuleVersion        = '0.0.2'
    GUID                 = '38677584-d79f-4f27-81db-c6bdd8fa3b32'
    Author               = '@AndrewZtrhgf'
    CompanyName          = 'Unknown'
    Copyright            = '(c) 2025 @AndrewZtrhgf. All rights reserved.'
    Description          = 'PowerShell module for Azure Privileged Identity Management (PIM) automation. Some of them are explained at https://doitpshway.com.

Some of the interesting functions:
- Get-PIMGroup: Returns Azure groups with some PIM eligible assignments.
- Get-PIMGroupEligibleAssignment: Returns eligible assignments for Azure AD groups.
- Get-PIMAccountEligibleMemberOf: Returns groups where selected account(s) is eligible (via PIM) as a member.
- Get-PIMDirectoryRoleAssignmentSetting: Gets PIM assignment settings for a given Azure AD directory role.
- Get-PIMDirectoryRoleEligibleAssignment: Returns Azure Directory role eligible assignments.
- Get-PIMManagementGroupEligibleAssignment: Returns all PIM eligible IAM assignments on selected (all) Azure Management group(s).
- Get-PIMResourceRoleAssignmentSetting: Gets PIM assignment settings for a given Azure resource role at a specific scope.
- Get-PIMSubscriptionEligibleAssignment: Returns eligible role assignments on selected subscription(s) and below (resources included).
'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = 'Core', 'Desktop'
    RequiredModules      = @(
        'Az.Accounts',
        'Microsoft.Graph.Authentication',
        'MSGraphStuff',
        @{ModuleName = 'AzureCommonStuff'; ModuleVersion = '1.0.7' }
    )
    FunctionsToExport    = '*'
    CmdletsToExport      = '*'
    VariablesToExport    = '*'
    AliasesToExport      = '*'
    PrivateData          = @{
        PSData = @{
            Tags         = @('Azure', 'PIM', 'AzurePIMStuff')
            ProjectUri   = 'https://github.com/ztrhgf/useful_powershell_modules'
            ReleaseNotes = '
            0.0.2
                Added additional PIM functions for enhanced management.
            0.0.1
                Initial release with core PIM automation functions.
            '
        }
    }
}