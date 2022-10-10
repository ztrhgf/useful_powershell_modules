
#requires -modules Microsoft.Graph.Intune
function Get-IntunePolicy {
    <#
    .SYNOPSIS
    Function for getting all/subset of Intune (assignable) policies using Graph API.

    .DESCRIPTION
    Function for getting all/subset of Intune (assignable) policies using Graph API.

    These policies can be retrieved:
     - Apps
     - App Configuration policies
     - App Protection policies
     - Compliance policies
     - Configuration policies
      - Administrative Templates
      - Settings Catalog
      - Templates
     - MacOS Custom Attribute Shell Scripts
     - Device Enrollment Configurations
     - Device Management PowerShell scripts
     - Device Management Shell scripts
     - Endpoint Security
        - Account Protection policies
        - Antivirus policies
        - Attack Surface Reduction policies
        - Defender policies
        - Disk Encryption policies
        - Endpoint Detection and Response policies
        - Firewall policies
        - Security baselines
     - iOS App Provisioning profiles
     - iOS Update Configurations
     - Policy Sets
     - Remediation Scripts
     - S Mode Supplemental policies
     - Windows Autopilot Deployment profiles
     - Windows Feature Update profiles
     - Windows Quality Update profiles
     - Windows Update Rings

    .PARAMETER policyType
    What type of policies should be gathered.

    Possible values are:
    'ALL' to get all policies.

    'app','appConfigurationPolicy','appProtectionPolicy','compliancePolicy','configurationPolicy','customAttributeShellScript','deviceEnrollmentConfiguration','deviceManagementPSHScript','deviceManagementShellScript','endpointSecurity','iosAppProvisioningProfile','iosUpdateConfiguration','policySet','remediationScript','sModeSupplementalPolicy','windowsAutopilotDeploymentProfile','windowsFeatureUpdateProfile','windowsQualityUpdateProfile','windowsUpdateRing' to get just some policies subset.

    By default 'ALL' policies are selected.

    .PARAMETER simple
    Switch. Just subset of available policy properties will be gathered (id, displayName, lastModifiedDateTime, assignments).
    Makes the result more human readable.

    .PARAMETER flat
    Switch. All Intune policies will be outputted as array instead of one psobject with policies divided into separate sections/object properties.
    Policies "parent" section is added as new property 'Section' to each policy.

    .EXAMPLE
    Connect-MSGraph
    Get-IntunePolicy

    Get all Intune policies.

    .EXAMPLE
    Connect-MSGraph
    Get-IntunePolicy -policyType 'app', 'compliancePolicy'

    Get just Apps and Compliance Intune policies.

    .EXAMPLE
    Connect-MSGraph
    Get-IntunePolicy -policyType 'app', 'compliancePolicy' -simple

    Get just Apps and Compliance Intune policies with subset of available properties (id, displayName, lastModifiedDateTime, assignments) for each policy.

    .EXAMPLE
    Connect-MSGraph
    Get-IntunePolicy -flat

    Get all Intune policies, but not as one psobject, but as array of all policies.
    #>

    [CmdletBinding()]
    param (
        # if policyType values changes, don't forget to modify 'Search-IntuneAccountPolicyAssignment' accordingly!
        [ValidateSet('ALL', 'app', 'appConfigurationPolicy', 'appProtectionPolicy', 'compliancePolicy', 'configurationPolicy', 'customAttributeShellScript', 'deviceEnrollmentConfiguration', 'deviceManagementPSHScript', 'deviceManagementShellScript', 'endpointSecurity', 'iosAppProvisioningProfile', 'iosUpdateConfiguration', 'policySet', 'remediationScript', 'sModeSupplementalPolicy', 'windowsAutopilotDeploymentProfile', 'windowsFeatureUpdateProfile', 'windowsQualityUpdateProfile', 'windowsUpdateRing')]
        [string[]] $policyType = 'ALL',

        [switch] $simple,

        [switch] $flat
    )

    if (!(Get-Module Microsoft.Graph.Intune) -and !(Get-Module Microsoft.Graph.Intune -ListAvailable)) {
        throw "Module Microsoft.Graph.Intune is missing"
    }

    if ($policyType -contains 'ALL') {
        Write-Verbose "ALL policies will be gathered"
        $all = $true
    } else {
        $all = $false
    }

    # create parameters hash for sub-functions and uri parameters for api calls
    if ($simple) {
        Write-Verbose "Just subset of available policy properties will be gathered"
        $selectFilter = '&$select=id,displayName,lastModifiedDateTime,assignments'
        $selectParam = @{select = ('id', 'displayName', 'lastModifiedDateTime', 'assignments') }
    } else {
        $selectFilter = $null
        $selectParam = @{}
    }

    # progress variables
    $i = 0
    $policyTypeCount = $policyType.Count
    if ($policyType -eq 'ALL') {
        $policyTypeCount = (Get-Variable "policyType").Attributes.ValidValues.count - 1
    }
    $progressActivity = "Getting Intune policies"

    #region get Intune policies
    # define main PS object property hash
    $resultProperty = [ordered]@{}

    # Apps
    if ($all -or $policyType -contains 'app') {
        # https://graph.microsoft.com/beta/deviceAppManagement/mobileApps
        Write-Verbose "Processing Apps"
        Write-Progress -Activity $progressActivity -Status "Processing Apps" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $app = Get-IntuneMobileApp @selectParam -Expand assignments | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.App = $app
    }

    # iOS App Provisioning profiles
    if ($all -or $policyType -contains 'iosAppProvisioningProfile') {
        Write-Verbose "Processing iOS App Provisioning profiles"
        Write-Progress -Activity $progressActivity -Status "Processing iOS App Provisioning profiles" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = 'https://graph.microsoft.com/beta/deviceAppManagement/iosLobAppProvisioningConfigurations?$expand=assignments' + $selectFilter
        $iosAppProvisioningProfile = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.IOSAppProvisioningProfile = $iosAppProvisioningProfile
    }

    # S mode supplemental policies
    if ($all -or $policyType -contains 'sModeSupplementalPolicy') {
        Write-Verbose "Processing S mode supplemental policies"
        Write-Progress -Activity $progressActivity -Status "Processing S mode supplemental policies" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = 'https://graph.microsoft.com/beta/deviceAppManagement/wdacSupplementalPolicies?$expand=assignments' + $selectFilter
        $sModeSupplementalPolicy = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.SModeSupplementalPolicy = $sModeSupplementalPolicy
    }

    # Device Compliance
    if ($all -or $policyType -contains 'compliancePolicy') {
        Write-Verbose "Processing Compliance policies"
        Write-Progress -Activity $progressActivity -Status "Processing Compliance policies" -PercentComplete (($i++ / $policyTypeCount) * 100)

        # https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies
        $compliancePolicy = Get-IntuneDeviceCompliancePolicy @selectParam -Expand assignments | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.CompliancePolicy = $compliancePolicy
    }

    # Device Configuration
    # contains all policies as can be seen in Intune web portal 'Device' > 'Device Configuration'
    if ($all -or $policyType -contains 'configurationPolicy') {
        Write-Verbose "Processing Configuration policies"
        Write-Progress -Activity $progressActivity -Status "Processing Configuration policies" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $configurationPolicy = @()

        # Templates profile type
        # api returns also Windows Update Ring policies, but they are filtered, so just policies as in GUI are returned
        $dcTemplate = Invoke-MSGraphRequest -Url ("https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$expand=Assignments&`$filter=(not isof('microsoft.graph.windowsUpdateForBusinessConfiguration') and not isof('microsoft.graph.iosUpdateConfiguration'))$selectFilter" -replace "\s+", "%20") | Get-MSGraphAllPages | select * -ExcludeProperty 'assignments@odata.context'
        $dcTemplate | ? { $_ } | % { $configurationPolicy += $_ }

        # Administrative Templates
        $dcAdmTemplate = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations?`$expand=Assignments$selectFilter" | Get-MSGraphAllPages | select * -ExcludeProperty 'assignments@odata.context'
        $dcAdmTemplate | ? { $_ } | % { $configurationPolicy += $_ }

        # mobileAppConfigurations
        $dcMobileAppConf = Invoke-MSGraphRequest -Url ("https://graph.microsoft.com/beta/deviceAppManagement/mobileAppConfigurations?`$filter=(microsoft.graph.androidManagedStoreAppConfiguration/appSupportsOemConfig eq true)&`$expand=Assignments$selectFilter" -replace "\s+", "%20") | Get-MSGraphAllPages | select * -ExcludeProperty 'assignments@odata.context'
        $dcMobileAppConf | ? { $_ } | % { $configurationPolicy += $_ }

        # Settings Catalog profile type
        # api returns also Attack Surface Reduction Rules and Account protection policies (from Endpoint Security section), but they are filtered, so just policies as in GUI are returned
        # configurationPolicies objects have property Name instead of DisplayName
        $custSelectFilter = $selectFilter -replace "displayname", "name"
        $dcSettingCatalog = Invoke-MSGraphRequest -Url ("https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$expand=Assignments&`$filter=(platforms eq 'windows10' or platforms eq 'macOS' or platforms eq 'iOS') and (technologies eq 'mdm' or technologies eq 'windows10XManagement' or technologies eq 'appleRemoteManagement' or technologies eq 'mdm,appleRemoteManagement') and (templateReference/templateFamily eq 'none')$custSelectFilter" -replace "\s+", "%20") | Get-MSGraphAllPages | select @{n = 'Displayname'; e = { $_.Name } }, * -ExcludeProperty 'Name', 'assignments@odata.context'
        $dcSettingCatalog | ? { $_ } | % { $configurationPolicy += $_ }

        $resultProperty.ConfigurationPolicy = $configurationPolicy
    }

    # Device Configuration Powershell Scripts
    if ($all -or $policyType -contains 'deviceManagementPSHScript') {
        Write-Verbose "Processing PowerShell scripts"
        Write-Progress -Activity $progressActivity -Status "Processing PowerShell scripts" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = 'https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts?$expand=Assignments' + $selectFilter
        $deviceConfigPSHScript = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.DeviceManagementPSHScript = $deviceConfigPSHScript
    }

    # Device Configuration Shell Scripts
    if ($all -or $policyType -contains 'deviceManagementShellScript') {
        Write-Verbose "Processing Shell scripts"
        Write-Progress -Activity $progressActivity -Status "Processing Shell scripts" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = 'https://graph.microsoft.com/beta/deviceManagement/deviceShellScripts?$expand=Assignments' + $selectFilter
        $deviceConfigShellScript = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.DeviceManagementShellScript = $deviceConfigShellScript
    }

    # MacOS Custom Attribute Shell scripts
    if ($all -or $policyType -contains 'customAttributeShellScript') {
        Write-Verbose "Processing Remediation (Health) scripts"
        Write-Progress -Activity $progressActivity -Status "Processing Custom Attribute Shell scripts" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = 'https://graph.microsoft.com/beta/deviceManagement/deviceCustomAttributeShellScripts?$expand=assignments' + $selectFilter
        $customAttributeShellScript = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.CustomAttributeShellScript = $customAttributeShellScript
    }

    # Remediation Scripts
    if ($all -or $policyType -contains 'remediationScript') {
        Write-Verbose "Processing Remediation (Health) scripts"
        Write-Progress -Activity $progressActivity -Status "Processing Remediation (Health) scripts" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = 'https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts?$expand=Assignments' + $selectFilter
        $remediationScript = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.RemediationScript = $remediationScript
    }

    # Security Baselines, Antivirus policies, Defender policies, Disk Encryption policies, Account Protection policies, Local User Group Membership, Firewall, Endpoint detection and response, Attack surface reduction
    if ($all -or $policyType -contains 'endpointSecurity') {
        Write-Verbose "Processing Endpoint Security policies"
        Write-Progress -Activity $progressActivity -Status "Processing Endpoint Security policies" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $endpointSecurityPolicy = @()

        #region process: Security Baselines, Antivirus policies, Defender policies, Disk Encryption policies, Account Protection policies (not 'Local User Group Membership')
        $templates = (Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/intents" -ErrorAction Stop).Value
        $endpointSecPol = @()
        foreach ($template in $templates) {
            Write-Verbose "`t- processing intent $($template.id), template $($template.templateId)"

            $settings = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/intents/$($template.id)/settings"
            $templateDetail = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/templates/$($template.templateId)"

            $template | Add-Member Noteproperty -Name 'platforms' -Value $templateDetail.platformType -Force # to match properties of second function region objects
            $template | Add-Member Noteproperty -Name 'type' -Value "$($templateDetail.templateType)-$($templateDetail.templateSubtype)" -Force

            $templSettings = @()
            foreach ($setting in $settings.value) {
                $displayName = $setting.definitionId -replace "deviceConfiguration--", "" -replace "admx--", "" -replace "_", " "
                if ($null -eq $setting.value) {
                    if ($setting.definitionId -eq "deviceConfiguration--windows10EndpointProtectionConfiguration_firewallRules") {
                        $v = $setting.valueJson | ConvertFrom-Json
                        foreach ($item in $v) {
                            $templSettings += [PSCustomObject]@{
                                Name  = "FW Rule - $($item.displayName)"
                                Value = ($item | ConvertTo-Json)
                            }
                        }
                    } else {
                        $v = ""
                        $templSettings += [PSCustomObject]@{ Name = $displayName; Value = $v }
                    }
                } else {
                    $v = $setting.value
                    $templSettings += [PSCustomObject]@{ Name = $displayName; Value = $v }
                }
            }

            $template | Add-Member Noteproperty -Name Settings -Value $templSettings -Force
            $template | Add-Member Noteproperty -Name 'settingCount' -Value $templSettings.count -Force # to match properties of second function region objects
            $assignments = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/intents/$($template.id)/assignments"
            $template | Add-Member Noteproperty -Name Assignments -Value $assignments.Value -Force
            $endpointSecPol += $template | select -Property * -ExcludeProperty templateId
        }
        $endpointSecPol | ? { $_ } | % { $endpointSecurityPolicy += $_ }
        #endregion process: Security Baselines, Antivirus policies, Defender policies, Disk Encryption policies, Account Protection policies (not 'Local User Group Membership')

        #region process: Account Protection policies (just 'Local User Group Membership'), Firewall, Endpoint Detection and Response, Attack Surface Reduction
        $endpointSecPol2 = Invoke-MSGraphRequest -HttpMethod GET -Url ("https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$select=id,name,description,isAssigned,platforms,lastModifiedDateTime,settingCount,roleScopeTagIds,templateReference&`$expand=Assignments,Settings&`$filter=(templateReference/templateFamily ne 'none')" -replace "\s+", "%20") | Get-MSGraphAllPages | ? { $_.templateReference.templateFamily -like "endpointSecurity*" } | select -Property id, @{n = 'displayName'; e = { $_.name } }, description, isAssigned, lastModifiedDateTime, roleScopeTagIds, platforms, @{n = 'type'; e = { $_.templateReference.templateFamily } }, templateReference, @{n = 'settings'; e = { $_.settings | % { [PSCustomObject]@{
                        # trying to have same settings format a.k.a. name/value as in previous function region
                        Name  = $_.settinginstance.settingDefinitionId
                        Value = $(
                            # property with setting value isn't always same, try to get the used one
                            $valuePropertyName = $_.settinginstance | Get-Member -MemberType NoteProperty | ? name -Like "*value" | select -ExpandProperty name
                            if ($valuePropertyName) {
                                # Write-Verbose "Value property $valuePropertyName was found"
                                $_.settinginstance.$valuePropertyName
                            } else {
                                # Write-Verbose "Value property wasn't found, therefore saving whole object as value"
                                $_.settinginstance
                            }
                        )
                    } } }
        }, settingCount, assignments -ExcludeProperty 'assignments@odata.context', 'settings', 'settings@odata.context', 'technologies', 'name', 'templateReference'
        #endregion process: Account Protection policies (just 'Local User Group Membership'), Firewall, Endpoint Detection and Response, Attack Surface Reduction
        $endpointSecPol2 | ? { $_ } | % { $endpointSecurityPolicy += $_ }

        $resultProperty.EndpointSecurity = $endpointSecurityPolicy
    }

    # Windows Autopilot Deployment profile
    if ($all -or $policyType -contains 'windowsAutopilotDeploymentProfile') {
        Write-Verbose "Processing Windows Autopilot Deployment profile"
        Write-Progress -Activity $progressActivity -Status "Processing Windows Autopilot Deployment profile" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles?$expand=Assignments' + $selectFilter
        $windowsAutopilotDeploymentProfile = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.WindowsAutopilotDeploymentProfile = $windowsAutopilotDeploymentProfile
    }

    # ESP, WHFB, Enrollment Limit, Enrollment Platform Restrictions configurations
    if ($all -or $policyType -contains 'deviceEnrollmentConfiguration') {
        Write-Verbose "Processing Device Enrollment configurations: ESP, WHFB, Enrollment Limit, Enrollment Platform Restrictions"
        Write-Progress -Activity $progressActivity -Status "Processing Device Enrollment configurations: ESP, WHFB, Enrollment Limit, Enrollment Platform Restrictions" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = 'https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?$expand=Assignments' + $selectFilter
        $deviceEnrollmentConfiguration = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.DeviceEnrollmentConfiguration = $deviceEnrollmentConfiguration
    }

    # Windows Feature Update profiles
    if ($all -or $policyType -contains 'windowsFeatureUpdateProfile') {
        Write-Verbose "Processing Windows Feature Update profiles"
        Write-Progress -Activity $progressActivity -Status "Processing Windows Feature Update profiles" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = 'https://graph.microsoft.com/beta/deviceManagement/windowsFeatureUpdateProfiles?$expand=Assignments' + $selectFilter
        $windowsFeatureUpdateProfile = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.WindowsFeatureUpdateProfile = $windowsFeatureUpdateProfile
    }

    # Windows Quality Update profiles
    if ($all -or $policyType -contains 'windowsQualityUpdateProfile') {
        Write-Verbose "Processing Windows Quality Update profiles"
        Write-Progress -Activity $progressActivity -Status "Processing Windows Quality Update profiles" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = 'https://graph.microsoft.com/beta/deviceManagement/windowsQualityUpdateProfiles?$expand=Assignments' + $selectFilter
        $windowsQualityUpdateProfile = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.WindowsQualityUpdateProfile = $windowsQualityUpdateProfile
    }

    # Update rings for Windows 10 and later is part of configurationPolicy (#microsoft.graph.windowsUpdateForBusinessConfiguration)
    if ($all -or $policyType -contains 'windowsUpdateRing') {
        Write-Verbose "Processing Windows Update rings"
        Write-Progress -Activity $progressActivity -Status "Processing Windows Update rings" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = ("https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$filter=isof('microsoft.graph.windowsUpdateForBusinessConfiguration')&`$expand=Assignments$selectFilter" -replace "\s+", "%20")
        $windowsUpdateRing = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.WindowsUpdateRing = $windowsUpdateRing
    }

    # iOS Update configurations
    if ($all -or $policyType -contains 'iosUpdateConfiguration') {
        Write-Verbose "Processing iOS Update configurations"
        Write-Progress -Activity $progressActivity -Status "Processing iOS Update configurations" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$filter=isof('microsoft.graph.iosUpdateConfiguration')&`$expand=assignments" + $selectFilter
        $iosUpdateConfiguration = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'

        $resultProperty.IOSUpdateConfiguration = $iosUpdateConfiguration
    }

    # App Configuration policies
    if ($all -or $policyType -contains 'appConfigurationPolicy') {
        Write-Verbose "Processing App Configuration policies"
        Write-Progress -Activity $progressActivity -Status "Processing App Configuration policies" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $appConfigurationPolicy = @()

        # targetedManagedAppConfigurations
        $uri = 'https://graph.microsoft.com/beta/deviceAppManagement/targetedManagedAppConfigurations?$expand=Assignments' + $selectFilter
        $targetedManagedAppConfigurations = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'
        $targetedManagedAppConfigurations | ? { $_ } | % { $appConfigurationPolicy += $_ }

        # mobileAppConfigurations
        $uri = "https://graph.microsoft.com//beta/deviceAppManagement/mobileAppConfigurations?`$filter=(microsoft.graph.androidManagedStoreAppConfiguration/appSupportsOemConfig eq false or isof('microsoft.graph.androidManagedStoreAppConfiguration') eq false)&`$expand=Assignments$selectFilter" -replace "\s+", "%20"
        $mobileAppConfigurations = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'
        $mobileAppConfigurations | ? { $_ } | % { $appConfigurationPolicy += $_ }

        $resultProperty.AppConfigurationPolicy = $appConfigurationPolicy
    }

    # App Protection policies
    if ($all -or $policyType -contains 'appProtectionPolicy') {
        Write-Verbose "Processing App Protection policies"
        Write-Progress -Activity $progressActivity -Status "Processing App Protection policies" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $appProtectionPolicy = @()

        # iosManagedAppProtections
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/iosManagedAppProtections?`$expand=assignments" + $selectFilter
        $iosManagedAppProtections = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'
        $iosManagedAppProtections | ? { $_ } | % { $appProtectionPolicy += $_ }

        # androidManagedAppProtections
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/androidManagedAppProtections?`$expand=assignments" + $selectFilter
        $androidManagedAppProtections = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'
        $androidManagedAppProtections | ? { $_ } | % { $appProtectionPolicy += $_ }

        # targetedManagedAppConfigurations
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/targetedManagedAppConfigurations?`$expand=assignments" + $selectFilter
        $targetedManagedAppConfigurations = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'
        $targetedManagedAppConfigurations | ? { $_ } | % { $appProtectionPolicy += $_ }

        # windowsInformationProtectionPolicies
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/windowsInformationProtectionPolicies?`$expand=assignments" + $selectFilter
        $windowsInformationProtectionPolicies = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'
        $windowsInformationProtectionPolicies | ? { $_ } | % { $appProtectionPolicy += $_ }

        # mdmWindowsInformationProtectionPolicies
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mdmWindowsInformationProtectionPolicies?`$expand=assignments" + $selectFilter
        $mdmWindowsInformationProtectionPolicies = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages | select -Property * -ExcludeProperty 'assignments@odata.context'
        $mdmWindowsInformationProtectionPolicies | ? { $_ } | % { $appProtectionPolicy += $_ }

        $resultProperty.AppProtectionPolicy = $appProtectionPolicy
    }

    # Policy Sets
    if ($all -or $policyType -contains 'policySet') {
        Write-Verbose "Processing Policy Sets"
        Write-Progress -Activity $progressActivity -Status "Processing Policy Sets" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $uri = 'https://graph.microsoft.com/beta/deviceAppManagement/policySets'
        $policySet = Invoke-MSGraphRequest -Url $uri | Get-MSGraphAllPages
        $resultProperty.policySet = @()
        foreach ($policy in $policySet) {
            $uri = "https://graph.microsoft.com/beta/deviceAppManagement/policySets/$($policy.id)/?`$expand=assignments,items" + $selectFilter
            $policyContent = Invoke-MSGraphRequest -Url $uri | select -Property * -ExcludeProperty '@odata.context', 'assignments@odata.context', 'items@odata.context'

            $resultProperty.PolicySet += $policyContent
        }
    }
    #endregion get Intune policies

    # output result
    $result = New-Object -TypeName PSObject -Property $resultProperty

    if ($flat) {
        # extract main object properties (policy types) and output the data as array of policies instead of one big object
        $result | Get-Member -MemberType NoteProperty | select -exp name | % {
            $polType = $_

            $result.$polType | ? { $_ } | % {
                # add parent section as property
                $_ | Add-Member -MemberType NoteProperty -Name PolicyType -Value $polType
                # output modified child object
                $_
            }
        }
    } else {
        $result
    }
}