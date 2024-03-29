@{
    RootModule        = 'TestModule.psm1'
    ModuleVersion     = '1.0.3'
    GUID              = '3eed1f11-9d8b-4417-b55c-f71cbb9f17ec'
    Author            = '@AndrewZtrhgf'
    CompanyName       = 'Unknown'
    Copyright         = '(c) 2022 @AndrewZtrhgf. All rights reserved.'
    Description       = 'Various functions for working with Atlassian Confluence. Some of them are explained at https://doitpsway.com.

    Some of the interesting functions:
    - Connect-Confluence - authenticates to your Confluence instance
    - Compare-ConfluencePageTable - compares two list of objects where first one is gathered from given Confluence wiki page table (identified using page ID and table index)
    - ConvertTo-ConfluenceTableHtml - converts given object into HTML table code but
        - pipe | sign in object value no more breaks table formatting
        - values in cells are not surrounded with spaces a.k.a. table columns can be sorted
    - Get-ConfluencePage2 - returns Confluence page content using native Invoke-WebRequest. Returned object contains parsed HTML (as Com object), raw HTML page content etc
    - Get-ConfluencePageTable - extracts table(s) from given Confluence page and converts it into the psobject
    - Set-ConfluencePage2 - Proxy function for Set-ConfluencePage. Adds possibility to set just selected table`s content on given page (and leave rest of the page intact)
    - ...
    '
    PowerShellVersion = '5.1'
    RequiredModules   = @('ConfluencePS', 'CommonStuff')
    FunctionsToExport = '*'
    CmdletsToExport   = '*'
    VariablesToExport = '*'
    AliasesToExport   = '*'
    PrivateData       = @{
        PSData = @{
            Tags       = @('PowerShell', 'Confluence')
            ProjectUri = 'https://github.com/ztrhgf/useful_powershell_modules'
        } # End of PSData hashtable
    } # End of PrivateData hashtable
}