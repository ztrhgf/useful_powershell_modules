@{
    RootModule           = 'MSGraphStuff.psm1'
    ModuleVersion        = '1.1.11'
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
- Invoke-GraphBatchRequest - Function for invoking Graph Api batch request(s) that handles pagination, throttling and server-side errors
- New-GraphAPIAuthHeader - Function for generating header that can be used for authentication of Graph API requests
- New-GraphBatchRequest - Function for creating PSObject that can be used in Graph Api batching requests
- ...
'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = 'Core', 'Desktop'
    RequiredModules      = @('Az.Accounts', 'MSAL.PS', 'DependencySearch', @{ ModuleName = 'CommonStuff'; ModuleVersion = '1.0.23' })
    FunctionsToExport    = '*'
    CmdletsToExport      = '*'
    VariablesToExport    = '*'
    AliasesToExport      = '*'
    PrivateData          = @{
        PSData = @{
            Tags         = @('PowerShell', 'Graph', 'Microsoft', 'API', 'MSGraph', 'MSGraphStuff', 'Batch')
            ProjectUri   = 'https://github.com/ztrhgf/useful_powershell_modules'
            ReleaseNotes = '
            1.1.11
                CHANGED
                    Expand-MgAdditionalProperties - uses Expand-ObjectProperty now
            1.1.10
                FIXED
                    New-GraphBatchRequest - various fixes
                    Invoke-GraphBatchRequest - various fixes
            1.1.9
                FIXED
                    Invoke-GraphBatchRequest - stop returning of empty objects on failed requests
                CHANGED
                    Invoke-GraphBatchRequest - better error message
            1.1.8
                FIXED
                    New-GraphBatchRequest - "Parameter set cannot be resolved using the specified named parameters"
            1.1.7
                FIXED
                    Invoke-GraphBatchRequest - fixed "You cannot call a method on a null-valued expression" when no result is returned
                CHANGED
                    New-GraphBatchRequest - added support for using placeholder value as an request Id
            1.1.6
                FIXED
                    Invoke-GraphBatchRequest - primitive types were not returned when "dontBeautifyResult" parameter was NOT used
            1.1.5
                CHANGED
                    Invoke-GraphBatchRequest - exclude @odata.context, @odata.nextLink properties when result is in value property
                    New-GraphBatchRequest - merged url and urlWithPlaceholder parameters
                                          - added support for specifying ID for urls with placeholder
            1.1.4
                FIXED
                    Invoke-GraphBatchRequest - example typo
                                             - incorrect detection of empty body when processing results
            1.1.3
                CHANGED
                    Invoke-GraphBatchRequest - added parameter "dontAddRequestId"
                FIXED
                    Invoke-GraphBatchRequest - pipeline fixes
                    New-GraphBatchRequest - header no longer [string], other minor edits
            1.1.2
                ADDED
                    New-GraphBatchRequest
                    Invoke-GraphBatchRequest
            1.1.1
                CHANGED
                    New-GraphAPIAuthHeader - support for Az 5.x (SecureString returned by Get-AzAccessToken)

            1.1.0
                CHANGED
                    Get-CodeGraphPermissionRequirement - requires module Microsoft.Graph.Authentication (at least version 2.18.0) where output of the Find-MgGraphCommand command used for getting the permissions was significantly changed
                                                       - change in permission filtering logic, change in the returned output (error messages), ...
            1.0.11
                FIXED
                    Get-CodeGraphPermissionRequirement - ignore #requires module statements
            1.0.10
                CHANGED
                    Get-CodeGraphModuleDependency - omit type property as it is useless
            1.0.9
                ADDED
                    Get-MgGraphAllPages
                CHANGED
                    Get-CodeGraphPermissionRequirement - added Get-MgContext as command that doesnt require any privileges
                    Invoke-GraphAPIRequest - better detection of value property
            1.0.8
                FIXED
                    Get-CodeGraphModuleDependency - ignore Import-Module results, fixed DependencyPath extraction
                CHANGED
                    Get-CodeGraphPermissionRequirement - added switch allOccurrences, removed unknownDependencyAsObject parameter when searching for dependencies, because there is no real reason to return such results
            1.0.7
                CHANGED
                    Get-CodeGraphPermissionRequirement - permissions output optimized by default, to change that use dontFilterPermissions
            1.0.6
                CHANGED
                    Get-CodeGraphPermissionRequirement - new examples and checks
                ADDED
                    Get-CodeGraphModuleDependency
            1.0.5
                CHANGED
                    Get-CodeGraphPermissionRequirement - new aliases, support for both permType, added method, apiVersion to the output, added searching for graph api calls using Invoke-MsGraphRequest, Invoke-RestMethod, Invoke-WebRequest and their aliases
                FIXED
                    Get-CodeDependency - fixed skipping of modules when processJustMSGraphSDK switch is used
                '
        } # End of PSData hashtable
    } # End of PrivateData hashtable
}