#requires -modules Microsoft.Graph.Authentication

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
     - MacOS Software Update Configurations
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

    'app','appConfigurationPolicy','appProtectionPolicy','compliancePolicy','configurationPolicy','customAttributeShellScript','deviceEnrollmentConfiguration','deviceManagementPSHScript','deviceManagementShellScript','endpointSecurity','iosAppProvisioningProfile','iosUpdateConfiguration','macOSSoftwareUpdateConfiguration','policySet','remediationScript','sModeSupplementalPolicy','windowsAutopilotDeploymentProfile','windowsFeatureUpdateProfile','windowsQualityUpdateProfile','windowsUpdateRing' to get just some policies subset.

    By default 'ALL' policies are selected.

    .PARAMETER basicOverview
    Switch. Just some common subset of available policy properties will be gathered (id, displayName, lastModifiedDateTime, assignments).
    Makes the result more human readable.

    .PARAMETER flatOutput
    Switch. All Intune policies will be outputted as array instead of one psobject with policies divided into separate sections/object properties.
    Policy parent "type" is added as new property 'PolicyType' to each policy for filtration purposes.

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
    Get-IntunePolicy -policyType 'app', 'compliancePolicy' -basicOverview

    Get just Apps and Compliance Intune policies with subset of available properties (id, displayName, lastModifiedDateTime, assignments) for each policy.

    .EXAMPLE
    Connect-MSGraph
    Get-IntunePolicy -flatOutput

    Get all Intune policies, but not as one psobject, but as array of all policies.
    #>

    [CmdletBinding()]
    param (
        # if policyType values changes, don't forget to modify 'Search-IntuneAccountPolicyAssignment' accordingly!
        [ValidateSet('ALL', 'app', 'appConfigurationPolicy', 'appProtectionPolicy', 'compliancePolicy', 'configurationPolicy', 'customAttributeShellScript', 'deviceEnrollmentConfiguration', 'deviceManagementPSHScript', 'deviceManagementShellScript', 'endpointSecurity', 'iosAppProvisioningProfile', 'iosUpdateConfiguration', 'macOSSoftwareUpdateConfiguration', 'policySet', 'remediationScript', 'sModeSupplementalPolicy', 'windowsAutopilotDeploymentProfile', 'windowsFeatureUpdateProfile', 'windowsQualityUpdateProfile', 'windowsUpdateRing')]
        [string[]] $policyType = 'ALL',

        [switch] $basicOverview,

        [switch] $flatOutput
    )

    if (!(Get-Command Get-MgContext -ErrorAction SilentlyContinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    if ($policyType -contains 'ALL') {
        Write-Verbose "ALL policies will be gathered"
        $all = $true
    } else {
        $all = $false
    }

    # Define select and expand parameters for API calls
    if ($basicOverview) {
        Write-Verbose "Just subset of available policy properties will be gathered"
        [string] $script:selectParams = 'id,displayName,lastModifiedDateTime,assignments' # these properties are common across all intune policies
        [string] $script:expandParams = 'assignments'
    } else {
        [string] $script:selectParams = '*'
        [string] $script:expandParams = 'assignments'
    }

    # progress variables
    $i = 0
    $policyTypeCount = $policyType.Count
    if ($policyType -eq 'ALL') {
        $policyTypeCount = (Get-Variable "policyType").Attributes.ValidValues.count - 1
    }
    $progressActivity = "Getting Intune policies"

    #region Build Batch Requests
    $allBatchRequests = [System.Collections.Generic.List[Object]]::new()
    Write-Verbose "Building all batch requests"

    # Apps
    if ($all -or $policyType -contains 'app') {
        Write-Verbose "Adding Apps requests to batch"
        Write-Progress -Activity $progressActivity -Status "Building Apps requests" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $filter = "microsoft.graph.managedApp/appAvailability eq null or microsoft.graph.managedApp/appAvailability eq 'lineOfBusiness' or isAssigned eq true"
        $url = "/deviceAppManagement/mobileApps?`$filter=$filter&`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "app" -url $url))
    }

    # App Configuration policies
    if ($all -or $policyType -contains 'appConfigurationPolicy') {
        Write-Verbose "Adding App Configuration policies requests to batch"
        Write-Progress -Activity $progressActivity -Status "Building App Configuration policies requests" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $url = "/deviceAppManagement/targetedManagedAppConfigurations?`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "targetedManagedAppConfigurations" -url $url))

        $filter = "microsoft.graph.androidManagedStoreAppConfiguration/appSupportsOemConfig eq false or isof('microsoft.graph.androidManagedStoreAppConfiguration') eq false"
        $url = "/deviceAppManagement/mobileAppConfigurations?`$filter=$filter&`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "mobileAppConfigurations" -url $url))
    }

    # App Protection policies
    if ($all -or $policyType -contains 'appProtectionPolicy') {
        Write-Verbose "Adding App Protection policies requests to batch"
        Write-Progress -Activity $progressActivity -Status "Building App Protection policies requests" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $url = "/deviceAppManagement/iosManagedAppProtections?`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "iosManagedAppProtections" -url $url))

        $url = "/deviceAppManagement/androidManagedAppProtections?`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "androidManagedAppProtections" -url $url))

        if (!($all -or $policyType -contains 'appConfigurationPolicy')) {
            $url = "/deviceAppManagement/targetedManagedAppConfigurations?`$select=$script:selectParams&`$expand=$script:expandParams"
            $allBatchRequests.Add((New-GraphBatchRequest -id "targetedManagedAppConfigurations_appProt" -url $url))
        }

        $url = "/deviceAppManagement/windowsInformationProtectionPolicies?`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "windowsInformationProtectionPolicies" -url $url))

        $url = "/deviceAppManagement/mdmWindowsInformationProtectionPolicies?`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "mdmWindowsInformationProtectionPolicies" -url $url))
    }

    # Device Compliance
    if ($all -or $policyType -contains 'compliancePolicy') {
        Write-Verbose "Adding Compliance policies requests to batch"
        Write-Progress -Activity $progressActivity -Status "Building Compliance policies requests" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $url = "/deviceManagement/deviceCompliancePolicies?`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "compliancePolicy" -url $url))
    }

    # Device Configuration
    if ($all -or $policyType -contains 'configurationPolicy') {
        Write-Verbose "Adding Configuration policies requests to batch"
        Write-Progress -Activity $progressActivity -Status "Building Configuration policies requests" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $filter = "not isof('microsoft.graph.windowsUpdateForBusinessConfiguration') and not isof('microsoft.graph.iosUpdateConfiguration')"
        $url = "/deviceManagement/deviceConfigurations?`$filter=$filter&`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "deviceConfigurations" -url $url))

        $url = "/deviceManagement/groupPolicyConfigurations?`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "groupPolicyConfigurations" -url $url))

        $filter = "microsoft.graph.androidManagedStoreAppConfiguration/appSupportsOemConfig eq true"
        $url = "/deviceAppManagement/mobileAppConfigurations?`$filter=$filter&`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "mobileAppConfigurationsOEM" -url $url))

        # configurationPolicies policies when expand operator is used gets throttled
        # therefore at first get just basic properties and secondly get settings and assignments via batching and enhance the former object
        Write-Verbose "Processing configuration policies"
        $filter = "(platforms eq 'windows10' or platforms eq 'macOS' or platforms eq 'iOS') and (technologies eq 'mdm' or technologies eq 'windows10XManagement' or technologies eq 'appleRemoteManagement' or technologies eq 'mdm,appleRemoteManagement') and (templateReference/templateFamily eq 'none')"
        $select = $script:selectParams -replace "displayName", "name"
        $url = "/deviceManagement/configurationPolicies?`$filter=$filter&`$select=$select"
        $configurationPolicyBatchResults = New-GraphBatchRequest -id "configurationPolicies" -url $url | Invoke-GraphBatchRequest -graphVersion beta
        $configurationPolicy = $null

        if ($configurationPolicyBatchResults) {
            # Build batch requests for assignments and settings
            $configurationPolicyExpandPropertyBatchRequests = [System.Collections.Generic.List[Object]]::new()
            # if $script:expandParams will contain anything else than 'assignments', final $configurationPolicyBatchResults Select-Object output has to be modified to reflect that!
            $expandParamsList = $script:expandParams, 'settings' | ? { $_ }

            $configurationPolicyBatchResults | % {
                $id = $_.id
                $expandParamsList | % {
                    $url = "/deviceManagement/configurationPolicies/<placeholder>/$_"
                    $configurationPolicyExpandPropertyBatchRequests.Add((New-GraphBatchRequest -id "$id`_$_" -placeholder $id -url $url))
                }
            }

            $configurationPolicyExpandPropertyBatchResults = Invoke-GraphBatchRequest -batchRequest $configurationPolicyExpandPropertyBatchRequests -graphVersion beta

            # enhance the basic object with assignments and settings properties
            $configurationPolicy = $configurationPolicyBatchResults | select *, @{Name = 'Settings'; Expression = {
                    $id = $_.id
                    $settings = $configurationPolicyExpandPropertyBatchResults | Where-Object { $_.RequestId -eq "$id`_settings" }
                    if ($settings) {
                        $settings.settingInstance
                    }
                }
            }, @{Name = 'Assignments'; Expression = {
                    $id = $_.id
                    $assignments = $configurationPolicyExpandPropertyBatchResults | Where-Object { $_.RequestId -eq "$id`_assignments" }
                    if ($assignments) {
                        $assignments | select * -ExcludeProperty RequestId
                    }
                }
            } -ExcludeProperty RequestId
        }
    }

    # MacOS Custom Attribute Shell scripts
    if ($all -or $policyType -contains 'customAttributeShellScript') {
        Write-Verbose "Adding Custom Attribute Shell scripts requests to batch"
        Write-Progress -Activity $progressActivity -Status "Building Custom Attribute Shell scripts requests" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $url = "/deviceManagement/deviceCustomAttributeShellScripts?`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "customAttributeShellScript" -url $url))
    }

    # ESP, WHFB, Enrollment Limit, Enrollment Platform Restrictions configurations
    if ($all -or $policyType -contains 'deviceEnrollmentConfiguration') {
        Write-Verbose "Adding Device Enrollment configurations requests to batch"
        Write-Progress -Activity $progressActivity -Status "Building Device Enrollment configurations requests" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $url = "/deviceManagement/deviceEnrollmentConfigurations?`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "deviceEnrollmentConfiguration" -url $url))
    }

    # Device Configuration Powershell Scripts
    if ($all -or $policyType -contains 'deviceManagementPSHScript') {
        Write-Verbose "Adding PowerShell scripts requests to batch"
        Write-Progress -Activity $progressActivity -Status "Building PowerShell scripts requests" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $url = "/deviceManagement/deviceManagementScripts?`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "deviceManagementPSHScript" -url $url))
    }

    # Device Configuration Shell Scripts
    if ($all -or $policyType -contains 'deviceManagementShellScript') {
        Write-Verbose "Adding Shell scripts requests to batch"
        Write-Progress -Activity $progressActivity -Status "Building Shell scripts requests" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $url = "/deviceManagement/deviceShellScripts?`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "deviceManagementShellScript" -url $url))
    }

    # Endpoint Security
    # TIP because of the specific output format and requirement that extra data needs to be processed, Endpoint Security policies are processed separately
    if ($all -or $policyType -contains 'endpointSecurity') {
        Write-Verbose "Processing Endpoint Security policies"
        Write-Progress -Activity $progressActivity -Status "Processing Endpoint Security policies" -PercentComplete (($i++ / $policyTypeCount) * 100)

        $endpointSecurityPolicy = @()

        #region process: Security Baselines, Antivirus policies, Defender policies, Disk Encryption policies, Account Protection policies (not 'Local User Group Membership')
        if ($basicOverview) {
            Write-Verbose "Processing endpoint security policies (basic)"
            $url = "/deviceManagement/intents?`$select=$script:selectParams&`$expand=$script:expandParams"
            $endpointSecPol = New-GraphBatchRequest -url $url -id "deviceManagementIntents" | Invoke-GraphBatchRequest -graphVersion beta -dontAddRequestId | select * -ExcludeProperty 'assignments@odata.context'

            if ($endpointSecPol) {
                # set assignments property, because it is unfortunately not returned via expand method
                $url = "/deviceManagement/intents/<placeholder>/assignments"
                $endpointSecPolAssignment = New-GraphBatchRequest -url $url -placeholder $endpointSecPol.Id -placeholderAsId | Invoke-GraphBatchRequest -graphVersion beta

                $endpointSecPolAssignment | % {
                    $id = $_.RequestId
                    $assignments = $_ | select * -ExcludeProperty RequestId
                    ($endpointSecPol | ? { $_.id -eq $id }).Assignments = $assignments
                }
            }
        } else {
            Write-Verbose "Processing endpoint security policies (detailed)"
            $url = "/deviceManagement/intents?`$select=$script:selectParams&`$expand=$script:expandParams"
            $intentList = New-GraphBatchRequest -url $url -id "deviceManagementIntents" | Invoke-GraphBatchRequest -graphVersion beta

            $endpointSecPol = @()

            if ($intentList) {
                # Build batch requests for all intents
                $batchRequests = [System.Collections.Generic.List[Object]]::new()

                foreach ($intent in $intentList) {
                    # Create batch requests for settings, template details, and assignments
                    $batchRequests.Add((New-GraphBatchRequest -url "/deviceManagement/intents/$($intent.id)/settings" -id "settings_$($intent.id)"))
                    $batchRequests.Add((New-GraphBatchRequest -url "/deviceManagement/templates/$($intent.templateId)" -id "template_$($intent.id)"))
                    $batchRequests.Add((New-GraphBatchRequest -url "/deviceManagement/intents/$($intent.id)/assignments" -id "assignments_$($intent.id)"))
                }

                Write-Verbose "Processing $($intentList.Count) security intents"
                $batchResults = Invoke-GraphBatchRequest -batchRequest $batchRequests -graphVersion beta

                # Process each template with the batch results
                foreach ($intent in $intentList) {
                    Write-Verbose "`t- processing intent $($intent.id), template $($intent.templateId)"

                    # Get settings, template details and assignments from batch results
                    $settings = $batchResults | ? RequestId -EQ "settings_$($intent.id)"
                    $templateDetail = $batchResults | ? RequestId -EQ "template_$($intent.id)"
                    $assignments = $batchResults | ? RequestId -EQ "assignments_$($intent.id)"

                    # Add properties to match the expected output format
                    $intent | Add-Member Noteproperty -Name 'platforms' -Value $templateDetail.platformType -Force # to match properties of the second region 'endpointSecurity' object
                    $intent | Add-Member Noteproperty -Name 'type' -Value "$($templateDetail.templateType)-$($templateDetail.templateSubtype)" -Force

                    $intentSettings = @()

                    foreach ($setting in $settings) {
                        $displayName = $setting.definitionId -replace "deviceConfiguration--", "" -replace "admx--", "" -replace "_", " "
                        if ($null -eq $setting.value) {
                            if ($setting.definitionId -eq "deviceConfiguration--windows10EndpointProtectionConfiguration_firewallRules") {
                                $v = $setting.valueJson | ConvertFrom-Json
                                foreach ($item in $v) {
                                    $intentSettings += [PSCustomObject]@{
                                        Name  = "FW Rule - $($item.displayName)"
                                        Value = ($item | ConvertTo-Json)
                                    }
                                }
                            } else {
                                $v = ""
                                $intentSettings += [PSCustomObject]@{ Name = $displayName; Value = $v }
                            }
                        } else {
                            $v = $setting.value
                            $intentSettings += [PSCustomObject]@{ Name = $displayName; Value = $v }
                        }
                    }

                    $intent | Add-Member Noteproperty -Name Settings -Value $intentSettings -Force
                    $intent | Add-Member Noteproperty -Name 'settingCount' -Value $intentSettings.count -Force # to match properties of the second region 'endpointSecurity' object
                    $intent | Add-Member Noteproperty -Name Assignments -Value $assignments -Force
                    $endpointSecPol += $intent | select -Property * -ExcludeProperty 'templateId', 'assignments@odata.context', 'isMigratingToConfigurationPolicy', 'RequestId'
                }
            }
        }

        $endpointSecPol | ? { $_ } | % { $endpointSecurityPolicy += $_ }
        #endregion process: Security Baselines, Antivirus policies, Defender policies, Disk Encryption policies, Account Protection policies (not 'Local User Group Membership')

        #region process: Account Protection policies (just 'Local User Group Membership'), Firewall, Endpoint Detection and Response, Attack Surface Reduction
        # because I am unable to make filtering on templateReference/templateFamily to work
        # get just templateReference property first and then filter out the ones that are not endpoint security policies
        Write-Verbose "Getting configuration policies"
        $confPolicyList = Invoke-MgGraphRequest -Uri "/beta/deviceManagement/configurationPolicies?`$select=id,templateReference&`$filter=templateReference/templateFamily ne 'none'" | Get-MgGraphAllPages

        $secPolicyList = $confPolicyList | ? { $_.templateReference.templateFamily -like "endpointSecurity*" -or $_.templateReference.templateFamily -like "baseline*" }

        if ($secPolicyList) {
            # configurationPolicies policies when expand operator is used gets throttled
            # therefore at first get just basic properties and secondly get settings and assignments via batching and enhance the former object

            if ($basicOverview) {
                # Prepare parameters for batch request
                $select = $script:selectParams -replace "displayName", "name"
                $select += ",templateReference"

                Write-Verbose "Processing endpoint security policies - Account Protection policies(basic)"
                $url = "/deviceManagement/configurationPolicies/<placeholder>?`$select=$select"
                $batchResults = New-GraphBatchRequest -url $url -placeholder $secPolicyList.id | Invoke-GraphBatchRequest -graphVersion beta

                # Filter and transform results
                $endpointSecPol2 = $batchResults |
                    select @{ n = 'id'; e = { $_.id } },
                    @{ n = 'displayName'; e = { $_.name } },
                    * -ExcludeProperty 'templateReference', 'id', 'name', 'assignments@odata.context', 'settings@odata.context', 'RequestId' # id as calculated property to have it first and still be able to use *
            } else {
                # Prepare parameters for batch request
                $select = 'id, name, description, isAssigned, platforms, lastModifiedDateTime, settingCount, roleScopeTagIds, templateReference'

                Write-Verbose "Processing endpoint security policies - Account Protection policies (detailed)"
                $url = "/deviceManagement/configurationPolicies/<placeholder>?`$select=$select"
                $batchResults = New-GraphBatchRequest -url $url -placeholder $secPolicyList.id | Invoke-GraphBatchRequest -graphVersion beta

                # Filter and transform results
                $configurationPolicyBatchResults = $batchResults |
                    select -Property id,
                    @{n = 'displayName'; e = { $_.name } },
                    description,
                    isAssigned,
                    lastModifiedDateTime,
                    roleScopeTagIds,
                    platforms,
                    @{n = 'type'; e = { $_.templateReference.templateFamily } },
                    templateReference,
                    settingCount
            }
        }

        if ($configurationPolicyBatchResults) {
            # Build batch requests for assignments and settings
            Write-Verbose "Building batch requests for assignments and settings"
            $configurationPolicyExpandPropertyBatchRequests = [System.Collections.Generic.List[Object]]::new()
            # if $script:expandParams will contain anything else than 'assignments', final $configurationPolicyBatchResults Select-Object output has to be modified to reflect that!
            $expandParamsList = $script:expandParams, 'settings' | ? { $_ }

            $configurationPolicyBatchResults | % {
                $id = $_.id
                $expandParamsList | % {
                    $url = "/deviceManagement/configurationPolicies/<placeholder>/$_"
                    $configurationPolicyExpandPropertyBatchRequests.Add((New-GraphBatchRequest -id "$id`_$_" -placeholder $id -url $url))
                }
            }

            $configurationPolicyExpandPropertyBatchResults = Invoke-GraphBatchRequest -batchRequest $configurationPolicyExpandPropertyBatchRequests -graphVersion beta

            # enhance the basic object with assignments and settings properties
            $endpointSecPol2 = $configurationPolicyBatchResults | select *, @{Name = 'Settings'; Expression = {
                    $id = $_.id
                    $settings = $configurationPolicyExpandPropertyBatchResults | Where-Object { $_.RequestId -eq "$id`_settings" }
                    if ($settings) {
                        $settings | % { [PSCustomObject]@{
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
                            }
                        }
                    }
                }
            }, @{Name = 'Assignments'; Expression = {
                    $id = $_.id
                    $assignments = $configurationPolicyExpandPropertyBatchResults | Where-Object { $_.RequestId -eq "$id`_assignments" }
                    if ($assignments) {
                        $assignments | select * -ExcludeProperty RequestId
                    }
                }
            } -ExcludeProperty RequestId
        }

        $endpointSecPol2 | ? { $_ } | % { $endpointSecurityPolicy += $_ }
        #endregion process: Account Protection policies (just 'Local User Group Membership'), Firewall, Endpoint Detection and Response, Attack Surface Reduction
    }

    # iOS App Provisioning profiles
    if ($all -or $policyType -contains 'iosAppProvisioningProfile') {
        Write-Verbose "Adding iOS App Provisioning profiles requests to batch"
        Write-Progress -Activity $progressActivity -Status "Building iOS App Provisioning profiles requests" -PercentComplete (($i++ / $policyTypeCount) * 100)
        $url = "/deviceAppManagement/iosLobAppProvisioningConfigurations?`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "iosAppProvisioningProfile" -url $url))
    }

    # iOS Update configurations
    if ($all -or $policyType -contains 'iosUpdateConfiguration') {
        Write-Verbose "Adding iOS Update configurations requests to batch"
        Write-Progress -Activity $progressActivity -Status "Building iOS Update configurations requests" -PercentComplete (($i++ / $policyTypeCount) * 100)
        $filter = "isof('microsoft.graph.iosUpdateConfiguration')"
        $url = "/deviceManagement/deviceConfigurations?`$filter=$filter&`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "iosUpdateConfiguration" -url $url))
    }

    # macOS Update configurations
    if ($all -or $policyType -contains 'macOSSoftwareUpdateConfiguration') {
        Write-Verbose "Adding macOS Update configurations requests to batch"
        Write-Progress -Activity $progressActivity -Status "Building macOS Update configurations requests" -PercentComplete (($i++ / $policyTypeCount) * 100)
        $filter = "isof('microsoft.graph.macOSSoftwareUpdateConfiguration')"
        $url = "/deviceManagement/deviceConfigurations?`$filter=$filter&`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "macOSSoftwareUpdateConfiguration" -url $url))
    }

    # Policy Sets
    if ($all -or $policyType -contains 'policySet') {
        Write-Verbose "Adding Policy Sets requests to batch"
        Write-Progress -Activity $progressActivity -Status "Building Policy Sets requests" -PercentComplete (($i++ / $policyTypeCount) * 100)
        $url = "/deviceAppManagement/policySets?`$select=$script:selectParams" # Expand is handled later
        $allBatchRequests.Add((New-GraphBatchRequest -id "policySet" -url $url))
    }

    # Remediation Scripts
    if ($all -or $policyType -contains 'remediationScript') {
        Write-Verbose "Adding Remediation (Health) scripts requests to batch"
        Write-Progress -Activity $progressActivity -Status "Building Remediation (Health) scripts requests" -PercentComplete (($i++ / $policyTypeCount) * 100)
        $url = "/deviceManagement/deviceHealthScripts?`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "remediationScript" -url $url))
    }

    # S mode supplemental policies
    if ($all -or $policyType -contains 'sModeSupplementalPolicy') {
        Write-Verbose "Adding S Mode Supplemental policies requests to batch"
        Write-Progress -Activity $progressActivity -Status "Building S mode supplemental policies requests" -PercentComplete (($i++ / $policyTypeCount) * 100)
        $url = "/deviceAppManagement/wdacSupplementalPolicies?`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "sModeSupplementalPolicy" -url $url))
    }

    # Windows Autopilot Deployment profile
    if ($all -or $policyType -contains 'windowsAutopilotDeploymentProfile') {
        Write-Verbose "Adding Windows Autopilot Deployment profile requests to batch"
        Write-Progress -Activity $progressActivity -Status "Building Windows Autopilot Deployment profile requests" -PercentComplete (($i++ / $policyTypeCount) * 100)
        $url = "/deviceManagement/windowsAutopilotDeploymentProfiles?`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "windowsAutopilotDeploymentProfile" -url $url))
    }

    # Windows Feature Update profiles
    if ($all -or $policyType -contains 'windowsFeatureUpdateProfile') {
        Write-Verbose "Adding Windows Feature Update profiles requests to batch"
        Write-Progress -Activity $progressActivity -Status "Building Windows Feature Update profiles requests" -PercentComplete (($i++ / $policyTypeCount) * 100)
        $url = "/deviceManagement/windowsFeatureUpdateProfiles?`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "windowsFeatureUpdateProfile" -url $url))
    }

    # Windows Quality Update profiles
    if ($all -or $policyType -contains 'windowsQualityUpdateProfile') {
        Write-Verbose "Adding Windows Quality Update profiles requests to batch"
        Write-Progress -Activity $progressActivity -Status "Building Windows Quality Update profiles requests" -PercentComplete (($i++ / $policyTypeCount) * 100)
        $url = "/deviceManagement/windowsQualityUpdateProfiles?`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "windowsQualityUpdateProfile" -url $url))
    }

    # Update rings for Windows 10 and later
    if ($all -or $policyType -contains 'windowsUpdateRing') {
        Write-Verbose "Adding Windows Update rings requests to batch"
        Write-Progress -Activity $progressActivity -Status "Building Windows Update rings requests" -PercentComplete (($i++ / $policyTypeCount) * 100)
        $filter = "isof('microsoft.graph.windowsUpdateForBusinessConfiguration')"
        $url = "/deviceManagement/deviceConfigurations?`$filter=$filter&`$select=$script:selectParams&`$expand=$script:expandParams"
        $allBatchRequests.Add((New-GraphBatchRequest -id "windowsUpdateRing" -url $url))
    }
    #endregion

    # Execute all batched requests
    Write-Verbose "Executing batch requests to retrieve all data..."
    Write-Progress -Activity $progressActivity -Status "Executing batch requests..." -PercentComplete 90
    if ($allBatchRequests) {
        # endpointSecurity is processed separately so there is a possibility to have empty $allBatchRequests
        $allBatchResults = Invoke-GraphBatchRequest -batchRequest $allBatchRequests -graphVersion beta
    }

    # Process the batch results and populate the result object
    Write-Verbose "Processing batch results..."
    Write-Progress -Activity $progressActivity -Status "Processing batch results..." -PercentComplete 95

    function _getBatchResultOutput {
        param (
            [Parameter(Mandatory = $true)]
            [string[]] $requestId
        )

        $allBatchResults | Where-Object { $_.RequestId -in $requestId } | select * -ExcludeProperty 'RequestId', 'assignments@odata.context', 'settings@odata.context', '@odata.type'
    }

    $resultProperty = [ordered]@{}

    if ($all -or $policyType -contains 'app') {
        $resultProperty.App = (_getBatchResultOutput -requestId "app")
    }
    if ($all -or $policyType -contains 'appConfigurationPolicy') {
        $resultProperty.AppConfigurationPolicy = (_getBatchResultOutput -requestId ("targetedManagedAppConfigurations", "mobileAppConfigurations"))
    }
    if ($all -or $policyType -contains 'appProtectionPolicy') {
        $resultProperty.AppProtectionPolicy = (_getBatchResultOutput -requestId ("iosManagedAppProtections", "androidManagedAppProtections", "targetedManagedAppConfigurations_appProt", "windowsInformationProtectionPolicies", "mdmWindowsInformationProtectionPolicies"))
    }
    if ($all -or $policyType -contains 'compliancePolicy') {
        $resultProperty.CompliancePolicy = (_getBatchResultOutput -requestId "compliancePolicy")
    }
    if ($all -or $policyType -contains 'configurationPolicy') {
        $resultProperty.ConfigurationPolicy = (_getBatchResultOutput -requestId ("deviceConfigurations", "groupPolicyConfigurations", "mobileAppConfigurationsOEM"))

        if ($configurationPolicy) {
            # add separately processed (to avoid throttling) configurations
            $resultProperty.ConfigurationPolicy += $configurationPolicy
        }
    }
    if ($all -or $policyType -contains 'customAttributeShellScript') {
        $resultProperty.CustomAttributeShellScript = (_getBatchResultOutput -requestId "customAttributeShellScript")
    }
    if ($all -or $policyType -contains 'deviceEnrollmentConfiguration') {
        $resultProperty.DeviceEnrollmentConfiguration = (_getBatchResultOutput -requestId "deviceEnrollmentConfiguration")
    }
    if ($all -or $policyType -contains 'deviceManagementPSHScript') {
        $resultProperty.DeviceManagementPSHScript = (_getBatchResultOutput -requestId "deviceManagementPSHScript")
    }
    if ($all -or $policyType -contains 'deviceManagementShellScript') {
        $resultProperty.DeviceManagementShellScript = (_getBatchResultOutput -requestId "deviceManagementShellScript")
    }
    if ($all -or $policyType -contains 'endpointSecurity') {
        if ($endpointSecurityPolicy) {
            $resultProperty.EndpointSecurity = $endpointSecurityPolicy
        } else {
            $resultProperty.EndpointSecurity = $null
        }
    }
    if ($all -or $policyType -contains 'iosAppProvisioningProfile') {
        $resultProperty.IOSAppProvisioningProfile = (_getBatchResultOutput -requestId "iosAppProvisioningProfile")
    }
    if ($all -or $policyType -contains 'iosUpdateConfiguration') {
        $resultProperty.IOSUpdateConfiguration = (_getBatchResultOutput -requestId "iosUpdateConfiguration")
    }
    if ($all -or $policyType -contains 'macOSSoftwareUpdateConfiguration') {
        $resultProperty.MacOSSoftwareUpdateConfiguration = (_getBatchResultOutput -requestId "macOSSoftwareUpdateConfiguration")
    }
    if ($all -or $policyType -contains 'policySet') {
        $policySets = _getBatchResultOutput -requestId "policySet" | select * -ExcludeProperty $excludedProperty
        if ($policySets -and !$basicOverview) {
            $policySetItemsRequests = [System.Collections.Generic.List[Object]]::new()
            foreach ($set in $policySets) {
                $policySetItemsRequests.Add((New-GraphBatchRequest -id "policysetitem_$($set.id)" -url "/deviceAppManagement/policySets/$($set.id)?`$expand=items"))
            }
            $resultProperty.PolicySet = (Invoke-GraphBatchRequest -batchRequest $policySetItemsRequests -graphVersion beta | select * -ExcludeProperty $excludedProperty)
        } else {
            $resultProperty.PolicySet = $policySets
        }
    }
    if ($all -or $policyType -contains 'remediationScript') {
        $resultProperty.RemediationScript = (_getBatchResultOutput -requestId "remediationScript" | select * -ExcludeProperty $excludedProperty)
    }
    if ($all -or $policyType -contains 'sModeSupplementalPolicy') {
        $resultProperty.SModeSupplementalPolicy = (_getBatchResultOutput -requestId "sModeSupplementalPolicy" | select * -ExcludeProperty $excludedProperty)
    }
    if ($all -or $policyType -contains 'windowsAutopilotDeploymentProfile') {
        $resultProperty.WindowsAutopilotDeploymentProfile = (_getBatchResultOutput -requestId "windowsAutopilotDeploymentProfile" | select * -ExcludeProperty $excludedProperty)
    }
    if ($all -or $policyType -contains 'windowsFeatureUpdateProfile') {
        $resultProperty.WindowsFeatureUpdateProfile = (_getBatchResultOutput -requestId "windowsFeatureUpdateProfile" | select * -ExcludeProperty $excludedProperty)
    }
    if ($all -or $policyType -contains 'windowsQualityUpdateProfile') {
        $resultProperty.WindowsQualityUpdateProfile = (_getBatchResultOutput -requestId "windowsQualityUpdateProfile" | select * -ExcludeProperty $excludedProperty)
    }
    if ($all -or $policyType -contains 'windowsUpdateRing') {
        $resultProperty.WindowsUpdateRing = (_getBatchResultOutput -requestId "windowsUpdateRing" | select * -ExcludeProperty $excludedProperty)
    }

    # output result
    $result = New-Object -TypeName PSObject -Property $resultProperty

    if ($flatOutput) {
        # extract main object properties (policy types) and output the data as array of policies instead of one big object
        $result | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object {
            $polType = $_
            $result.$polType | Where-Object { $_ } | ForEach-Object {
                # add parent section as property
                $_ | Add-Member -MemberType NoteProperty -Name 'PolicyType' -Value $polType -Force
                # output modified child object
                $_
            }
        }
    } else {
        $result
    }
}