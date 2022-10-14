#
# Module manifest for module 'azureadstuff'
#
# Generated by: @AndrewZtrhgf
#
# Generated on: 14.10.2022
#

@{

# Script module or binary module file associated with this manifest.
RootModule = 'azureadstuff.psm1'

# Version number of this module.
ModuleVersion = '1.0.15'

# Supported PSEditions
# CompatiblePSEditions = @()

# ID used to uniquely identify this module
GUID = '1f9e4f50-2cac-411b-80f8-16003b8a5542'

# Author of this module
Author = '@AndrewZtrhgf'

# Company or vendor of this module
CompanyName = 'Unknown'

# Copyright statement for this module
Copyright = '(c) 2022 @AndrewZtrhgf. All rights reserved.'

# Description of the functionality provided by this module
Description = 'Various Azure related functions. Some of them are explained at https://doitpsway.com.

Some of the interesting functions:
- Add-AzureADAppUserConsent - granting permission consent on behalf of another user
- Add-AzureADAppCertificate - add the auth. certificate (existing or create self-signed) to selected Azure application as an secret
- Get-AzureADAccountOccurrence - for getting all occurrences of specified account in your Azure environment
- Get-AzureADAppVerificationStatus - get Azure app publisher verification status
- Get-AzureADAppConsentRequest - for getting all application admin consent requests
- Get-AzureADDeviceMembership - similar to Get-AzureADUserMembership, but for devices
- Get-AzureDevOpsOrganizationOverview - list of all DevOps organizations
- Remove-AzureADAccountOccurrence - remove specified account from various Azure environment sections and optionally replace it with other user and inform him. Should be used with Get-AzureADAccountOccurrence.
- Remove-AzureADAppUserConsent - removes user consent
- ...

Some of the authentication-related functions:
- Connect-AzureAD2 - smarter version of Connect-AzureAD that can reuse existing session and more
- New-AzureDevOpsAuthHeader
- New-GraphAPIAuthHeader
'

# Minimum version of the Windows PowerShell engine required by this module
PowerShellVersion = '5.1'

# Name of the Windows PowerShell host required by this module
# PowerShellHostName = ''

# Minimum version of the Windows PowerShell host required by this module
# PowerShellHostVersion = ''

# Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
# DotNetFrameworkVersion = ''

# Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
# CLRVersion = ''

# Processor architecture (None, X86, Amd64) required by this module
# ProcessorArchitecture = ''

# Modules that must be imported into the global environment prior to importing this module
RequiredModules = @('AzureAD', 
               'Az.Accounts', 
               'Az.Resources', 
               'MSAL.PS', 
               'PnP.PowerShell', 
               'Microsoft.Graph.Authentication', 
               'Microsoft.Graph.Applications', 
               'Microsoft.Graph.Users', 
               'Microsoft.Graph.Identity.SignIns')

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
FunctionsToExport = 'Add-AzureADAppCertificate', 'Add-AzureADAppUserConsent', 
               'Add-AzureADGuest', 'Connect-AzAccount2', 'Connect-AzureAD2', 
               'Connect-PnPOnline2', 'Disable-AzureADGuest', 
               'Get-AzureADAccountOccurrence', 'Get-AzureADAppConsentRequest', 
               'Get-AzureADAppRegistration', 'Get-AzureADAppUsersAndGroups', 
               'Get-AzureADAppVerificationStatus', 
               'Get-AzureADAssessNotificationEmail', 'Get-AzureADDeviceMembership', 
               'Get-AzureADEnterpriseApplication', 
               'Get-AzureAdGroupMemberRecursive', 'Get-AzureADManagedIdentity', 
               'Get-AzureADResource', 'Get-AzureADRoleAssignments', 
               'Get-AzureADServicePrincipalOverview', 'Get-AzureADSPPermissions', 
               'Get-AzureDevOpsOrganizationOverview', 'Get-SharepointSiteOwner', 
               'Invoke-GraphAPIRequest', 'New-AzureADMSIPConditionalAccessPolicy', 
               'New-AzureDevOpsAuthHeader', 'New-GraphAPIAuthHeader', 
               'Open-AzureADAdminConsentPage', 'Remove-AzureADAccountOccurrence', 
               'Remove-AzureADAppUserConsent', 'Set-AADDeviceExtensionAttribute', 
               'Start-AzureADSync'

# Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
CmdletsToExport = '*'

# Variables to export from this module
VariablesToExport = '*'

# Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
AliasesToExport = 'Get-AzureADIAMRoleAssignments', 'Get-AzureADPSPermissionGrants', 
               'Get-AzureADPSPermissions', 'Get-AzureADRBACRoleAssignments', 
               'Get-AzureADServiceAppRoleAssignment2', 
               'Get-AzureADServicePrincipal2', 
               'Get-AzureADServicePrincipalPermissions', 'Get-IntuneAuthHeader', 
               'New-AzureADGuest', 'New-IntuneAuthHeader', 'Remove-AzureADGuest', 
               'Sync-ADtoAzure'

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
        Tags = 'Azure','PowerShell','Monitoring','Audit','Security'

        # A URL to the license for this module.
        # LicenseUri = ''

        # A URL to the main website for this project.
        ProjectUri = 'https://doitpsway.com/series/azure'

        # A URL to an icon representing this module.
        # IconUri = ''

        # ReleaseNotes of this module
        # ReleaseNotes = ''

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

