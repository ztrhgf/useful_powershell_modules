#
# Module manifest for module 'DependencySearch'
#

@{
    ModuleVersion        = '1.1.8'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = 'Core', 'Desktop'
    GUID                 = 'fe71797d-d6a2-4395-861f-94e217501206'
    Author               = '@AndrewZtrhgf'
    CompanyName          = 'Unknown'
    Copyright            = '(c) 2023 @AndrewZtrhgf. All rights reserved.'
    Description          = 'Module contains functions that allows you to check for PowerShell code/script/module dependencies through static code analysis (AST).
    Some of the interesting functions:
    - Get-CodeDependency - searches for PowerShell code/script/module dependencies through static code analysis (AST). Supports also checks against PowerShell Gallery
    - Get-CodeDependencyStatus - gets (module) dependencies of given script/module and warns you about possible problems
    - Get-CorrespondingGraphCommand - translates given AzureAD or MSOnline command to Graph command
    - Get-ModuleCommandUsedInCode - searches for commands (defined in specific module) in given script file
    '
    RequiredModules      = @('CommonStuff')
    FunctionsToExport    = '*'
    CmdletsToExport      = '*'
    VariablesToExport    = '*'
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags         = @('PowerShell', 'Dependency', 'AST', 'DependencySearch')
            ProjectUri   = 'https://github.com/ztrhgf/useful_powershell_modules'
            ReleaseNotes = '
            1.1.8
                BUGFIX
                    Get-CodeDependency - fixed processing of & etc operators
            1.1.7
                BUGFIX
                    Get-CodeDependency - fixed incorrect null comparison operator
            1.1.6
                EDIT
                    Get-CodeDependency - supports new dependencies (psedition, psversion)
                    Get-CodeDependencyStatus - new param dependencyParam
                BUGFIX
                    Get-CorrespondingGraphCommand - changed table headers in MS documentation
            1.1.5
                EDIT
                    Get-CodeDependency - optimalization so that availableModules needed only if goDeep is used
            1.1.4
                EDIT
                    Get-CodeDependency - added support for processing of graph api commands
                BUGFIX
                    Get-CodeDependency - fixed skipping of modules when processJustMSGraphSDK switch is used
            1.1.3
                EDIT
                    Get-CodeDependency - added parameter processEveryTime for internal use in Get-CodeGraphPermissionRequirement
            1.1.2
                EDIT
                    Get-CodeDependency - fixes, change in dependency search logic (controlled by new getDependencyOfRequiredModule parameter), added optimization parameter processJustMSGraphSDK for Get-CodeGraphPermissionRequirement
            1.1.1
                BUGFIX
                    Get-CorrespondingGraphCommand - MS has changed their site a little bit, edited to match the new one
            1.1.0
                EDIT
                    Get-CodeDependency - huge rewrite & lots of improvements
                    Get-ImportModuleFromAST - align the code with changes in Get-CodeDependency
                    Get-CodeDependencyStatus - align the code with changes in Get-CodeDependency
                '
        } # End of PSData hashtable
    } # End of PrivateData hashtable
}