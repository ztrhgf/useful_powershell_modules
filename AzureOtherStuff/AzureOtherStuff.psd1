#
# Module manifest for module 'AzureOtherStuff'
#
# Generated by: @AndrewZtrhgf
#
# Generated on: 19.03.2025
#

@{

# Script module or binary module file associated with this manifest.
RootModule = 'AzureOtherStuff.psm1'

# Version number of this module.
ModuleVersion = '1.0.3'

# Supported PSEditions
CompatiblePSEditions = 'Core', 'Desktop'

# ID used to uniquely identify this module
GUID = 'a0ef14ff-c5d6-47e9-a431-ffb512637245'

# Author of this module
Author = '@AndrewZtrhgf'

# Company or vendor of this module
CompanyName = 'Unknown'

# Copyright statement for this module
Copyright = '(c) 2022 @AndrewZtrhgf. All rights reserved.'

# Description of the functionality provided by this module
Description = 'Various Azure related functions. More details at https://doitpshway.com/series/azure.
Some of the interesting functions:
- Get-AzureAuditAggregatedSignInEvent - gets aggregated types of Azure sign-in logs: User sign-ins (non-interactive), Service principal sign-ins, Managed identity sign-ins
- Get-AzureAuditSignInEvent - proxy function for Get-MgBetaAuditLogSignIn that simplifies result filtering
- Get-AzureAssessNotificationEmail
- Get-AzureDevOpsOrganizationOverview
- Open-AzureAdminConsentPage
- ...
'

# Minimum version of the PowerShell engine required by this module
PowerShellVersion = '5.1'

# Name of the PowerShell host required by this module
# PowerShellHostName = ''

# Minimum version of the PowerShell host required by this module
# PowerShellHostVersion = ''

# Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
# DotNetFrameworkVersion = ''

# Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
# ClrVersion = ''

# Processor architecture (None, X86, Amd64) required by this module
# ProcessorArchitecture = ''

# Modules that must be imported into the global environment prior to importing this module
RequiredModules = @('Az.Accounts', 
               'MSGraphStuff', 
               'AzureCommonStuff')

# Assemblies that must be loaded prior to importing this module
# RequiredAssemblies = @()

# Script files (.ps1) that are run in the caller's environment prior to importing this module.
# ScriptsToProcess = @()

# Type files (.ps1xml) to be loaded when importing this module
# TypesToProcess = @()

# Format files (.ps1xml) to be loaded when importing this module
# FormatsToProcess = @()

# Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
# NestedModules = @()

# Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
FunctionsToExport = 'Get-AzureAssessNotificationEmail', 
               'Get-AzureAuditAggregatedSignInEvent', 'Get-AzureAuditSignInEvent', 
               'Get-AzureDevOpsOrganizationOverview', 'Open-AzureAdminConsentPage'

# Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
CmdletsToExport = @()

# Variables to export from this module
VariablesToExport = '*'

# Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
AliasesToExport = @()

# DSC resources to export from this module
# DscResourcesToExport = @()

# List of all modules packaged with this module
# ModuleList = @()

# List of all files packaged with this module
# FileList = @()

# Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
PrivateData = @{

    PSData = @{

        # Tags applied to this module. These help with module discovery in online galleries.
        Tags = 'Azure','PowerShell','Monitoring','Audit','Security','Graph','Runbook'

        # A URL to the license for this module.
        # LicenseUri = ''

        # A URL to the main website for this project.
        ProjectUri = 'https://github.com/ztrhgf/useful_powershell_modules'

        # A URL to an icon representing this module.
        # IconUri = ''

        # ReleaseNotes of this module
        ReleaseNotes = '
            1.0.0
                Initial release. Some functions are migrated from now deprecated AzureADStuff module, some are completely new.
            1.0.1
                ADDED
                    Get-AzureAuditSignInEvent
                    Get-AzureAuditAggregatedSignInEvent
            1.0.2
                CHANGED
                    Get-AzureAuditAggregatedSignInEvent - get rid of Microsoft.Graph.Intune module
                    Get-AzureAuditSignInEvent - by default gets any event type
            1.0.3
                CHANGED
                    Get-AzureDevOpsOrganizationOverview - fixes
                    Get-AzureAuditSignInEvent - added support for multiple ids
                    Get-AzureAuditAggregatedSignInEvent - support for Az 5.x (SecureString returned by Get-AzAccessToken)
            '

        # Prerelease string of this module
        # Prerelease = ''

        # Flag to indicate whether the module requires explicit user acceptance for install/update/save
        # RequireLicenseAcceptance = $false

        # External dependent modules of this module
        # ExternalModuleDependencies = @()

    } # End of PSData hashtable

 } # End of PrivateData hashtable

# HelpInfo URI of this module
# HelpInfoURI = ''

# Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
# DefaultCommandPrefix = ''

}

