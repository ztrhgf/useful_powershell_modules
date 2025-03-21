@{
    RootModule           = 'MSGraphStuff.psm1'
    ModuleVersion        = '1.1.1'
    GUID                 = '712b70b5-7e0d-4d83-a2e5-68389e890337'
    Author               = '@AndrewZtrhgf'
    CompanyName          = 'Unknown'
    Copyright            = '(c) 2022 @AndrewZtrhgf. All rights reserved.'
    Description          = 'Microsoft Graph API related functions. Some of them are explained at https://doitpshway.com.

Some of the functions:
- Expand-MgAdditionalProperties - Function for expanding "AdditionalProperties" hash property to the main object aka flattens the returned object
- Get-CodeGraphModuleDependency - Function for getting Graph SDK modules required to run given code
- Get-CodeGraphPermissionRequirement - Function for getting Graph API permissions (scopes) that are needed tu run selected code
- Invoke-GraphAPIRequest - Function for creating request against Microsoft Graph API. Unlike official one supports paging and throttling
- New-GraphAPIAuthHeader - Function for generating header that can be used for authentication of Graph API requests
- ...
'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = 'Core', 'Desktop'
    RequiredModules      = @('Az.Accounts', 'MSAL.PS', 'DependencySearch')
    FunctionsToExport    = '*'
    CmdletsToExport      = '*'
    VariablesToExport    = '*'
    AliasesToExport      = '*'
    PrivateData          = @{
        PSData = @{
            Tags         = @('PowerShell', 'Graph', 'Microsoft', 'API', 'MSGraph', 'MSGraphStuff')
            ProjectUri   = 'https://github.com/ztrhgf/useful_powershell_modules'
            ReleaseNotes = '
            1.0.5
                EDIT
                    Get-CodeGraphPermissionRequirement - new aliases, support for both permType, added method, apiVersion to the output, added searching for graph api calls using Invoke-MsGraphRequest, Invoke-RestMethod, Invoke-WebRequest and their aliases
                BUGFIX
                    Get-CodeDependency - fixed skipping of modules when processJustMSGraphSDK switch is used
            1.0.6
                EDIT
                    Get-CodeGraphPermissionRequirement - new examples and checks
                ADDED
                    Get-CodeGraphModuleDependency
            1.0.7
                EDIT
                    Get-CodeGraphPermissionRequirement - permissions output optimized by default, to change that use dontFilterPermissions
            1.0.8
                BUGFIX
                    Get-CodeGraphModuleDependency - ignore Import-Module results, fixed DependencyPath extraction
                EDIT
                    Get-CodeGraphPermissionRequirement - added switch allOccurrences, removed unknownDependencyAsObject parameter when searching for dependencies, because there is no real reason to return such results
            1.0.8
                EDIT
                    Get-CodeGraphModuleDependency - omit type property as it is useless
            1.0.9
                ADDED
                    Get-MgGraphAllPages
                EDIT
                    Get-CodeGraphPermissionRequirement - added Get-MgContext as command that doesnt require any privileges
                    Invoke-GraphAPIRequest - better detection of value property
            1.0.11
                BUGFIX
                    Get-CodeGraphPermissionRequirement - ignore #requires module statements
            1.1.0
                EDIT
                    Get-CodeGraphPermissionRequirement - requires module Microsoft.Graph.Authentication (at least version 2.18.0) where output of the Find-MgGraphCommand command used for getting the permissions was significantly changed
                                                       - change in permission filtering logic, change in the returned output (error messages), ...
            1.1.1
                EDIT
                    New-GraphAPIAuthHeader - support for Az 5.x (SecureString returned by Get-AzAccessToken)
                '
        } # End of PSData hashtable
    } # End of PrivateData hashtable
}