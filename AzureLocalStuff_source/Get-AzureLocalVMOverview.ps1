function Get-AzureLocalVMOverview {
    <#
    .SYNOPSIS
    Retrieves a comprehensive overview of Azure Local (Azure Stack HCI) virtual machines.

    .DESCRIPTION
    Get-AzureLocalVMOverview queries Azure Resource Graph to retrieve detailed information about virtual machines running on Azure Local (formerly Azure Stack HCI) infrastructure.

    The function gathers:
    - Custom locations and their enabled services
    - Resource bridge appliances
    - Virtual machine instances and their properties
    - Network interface configurations including IP addresses and subnets
    - Data disk information including size and provisioning state

    All VMs are enriched with their associated custom location, resource bridge, network interfaces, and disks information.

    .EXAMPLE
    Get-AzureLocalVMOverview

    Retrieves all Azure Local VMs across all custom locations in the current Azure context.

    .OUTPUTS
    System.Object
    Returns custom objects containing VM information with the following properties:
    - id: Resource ID of the VM
    - name: VM name
    - type: Resource type
    - location: Azure region
    - resourceGroup: Resource group name
    - subscriptionId: Subscription ID
    - properties: VM properties (OS profile, hardware profile, storage profile, network profile)
    - extendedLocation: Custom location reference
    - systemData: System metadata
    - basicInfo: Basic Azure resource information
    - nics: Array of network interface configurations
    - disks: Array of data disk configurations
    - customLocation: Associated custom location object
    - resourceBridge: Associated resource bridge appliance object

    .NOTES
    This function requires:
    - Azure PowerShell session with appropriate permissions
    - Access to Azure Resource Graph API
    - Read permissions on Azure Local resources

    The function uses Azure Resource Graph queries for efficient data retrieval across multiple subscriptions.

    #>

    [CmdletBinding()]
    param ()

    $queryUrl = "https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01"

    #region get custom locations, clusters, resource bridge appliances
    [System.Collections.Generic.List[object]] $batchRequest = @()

    #region get custom locations
    $customLocationQuery = @"
resources
| where type =~ "microsoft.extendedLocation/customLocations"
| extend clusterId = tolower(properties.hostResourceId), datacenter = coalesce(tags.Datacenter, ''), customLocationId = tolower(id)
| parse kind = regex clusterId with ".*providers/" provider "/.*"
| join kind=leftouter (
	ExtendedLocationResources
	| where type =~ 'microsoft.extendedlocation/customLocations/enabledResourcetypes'
	| parse kind=regex id with customLocationId "(?i)/enabledresourcetypes/.*"
	| extend extensionId = tolower(properties.clusterExtensionId), extensionType = tolower(properties.extensionType), customLocationId = tolower(customLocationId)
	| parse kind=regex extensionId with "(?i).*/extensions/" extensionName
	| extend extensionDisplayName = case(extensionType =~ 'microsoft.avs','Azure VMware Solution',
										extensionType =~ 'microsoft.vmware','VMware',
										extensionType =~ 'microsoft.scvmm','System Center Virtual Machine Manager',
										extensionType =~ 'microsoft.azstackhci.operator','Azure Local',
										extensionType)
	| extend extensionName = strcat(extensionDisplayName, ' (', extensionName, ')')
	| summarize enabledServices = strcat_array(make_set(extensionName), ",") by customLocationId ) on customLocationId
| extend enabledServices = coalesce(enabledServices, 'Unknown')
| project id, name, datacenter, clusterId, enabledServices, resourceGroup, location, subscriptionId, type, kind, tags|where (type !~ ('dell.storage/filesystems'))|where (type !~ ('pinecone.vectordb/organizations'))|where (type !~ ('liftrbasic.samplerp/organizations'))|where (type !~ ('commvault.contentstore/cloudaccounts'))|where (type !~ ('paloaltonetworks.cloudngfw/globalrulestacks'))|where (type !~ ('microsoft.liftrpilot/organizations'))|where (type !~ ('microsoft.agfoodplatform/farmbeats'))|where (type !~ ('microsoft.agricultureplatform/agriservices'))|where (type !~ ('microsoft.arc/allfairfax'))|where (type !~ ('microsoft.arc/all'))|where (type !~ ('microsoft.cdn/profiles/securitypolicies'))|where (type !~ ('microsoft.cdn/profiles/secrets'))|where (type !~ ('microsoft.cdn/profiles/rulesets'))|where (type !~ ('microsoft.cdn/profiles/rulesets/rules'))|where (type !~ ('microsoft.cdn/profiles/afdendpoints/routes'))|where (type !~ ('microsoft.cdn/profiles/origingroups'))|where (type !~ ('microsoft.cdn/profiles/origingroups/origins'))|where (type !~ ('microsoft.cdn/profiles/afdendpoints'))|where (type !~ ('microsoft.cdn/profiles/customdomains'))|where (type !~ ('microsoft.chaos/workspaces'))|where (type !~ ('microsoft.chaos/privateaccesses'))|where (type !~ ('microsoft.sovereign/transparencylogs'))|where (type !~ ('microsoft.classiccompute/domainnames/slots/roles'))|where (type !~ ('microsoft.classiccompute/domainnames'))|where (type !~ ('microsoft.cloudtest/pools'))|where (type !~ ('microsoft.cloudtest/images'))|where (type !~ ('microsoft.cloudtest/hostedpools'))|where (type !~ ('microsoft.cloudtest/buildcaches'))|where (type !~ ('microsoft.cloudtest/accounts'))|where (type !~ ('microsoft.compute/virtualmachineflexinstances'))|where (type !~ ('microsoft.compute/standbypoolinstance'))|where (type !~ ('microsoft.compute/computefleetscalesets'))|where (type !~ ('microsoft.compute/computefleetinstances'))|where (type !~ ('microsoft.containerservice/managedclusters/microsoft.kubernetesconfiguration/fluxconfigurations'))|where (type !~ ('microsoft.kubernetes/connectedclusters/microsoft.kubernetesconfiguration/fluxconfigurations'))|where (type !~ ('microsoft.containerservice/managedclusters/microsoft.kubernetesconfiguration/namespaces'))|where (type !~ ('microsoft.kubernetes/connectedclusters/microsoft.kubernetesconfiguration/namespaces'))|where (type !~ ('microsoft.containerservice/managedclusters/microsoft.kubernetesconfiguration/extensions'))|where (type !~ ('microsoft.portalservices/extensions/deployments'))|where (type !~ ('microsoft.portalservices/extensions'))|where (type !~ ('microsoft.portalservices/extensions/slots'))|where (type !~ ('microsoft.portalservices/extensions/versions'))|where (type !~ ('microsoft.deviceregistry/convergedassets'))|where (type !~ ('microsoft.deviceregistry/devices'))|where (type !~ ('microsoft.deviceupdate/updateaccounts'))|where (type !~ ('microsoft.deviceupdate/updateaccounts/updates'))|where (type !~ ('microsoft.deviceupdate/updateaccounts/deviceclasses'))|where (type !~ ('microsoft.deviceupdate/updateaccounts/deployments'))|where (type !~ ('microsoft.deviceupdate/updateaccounts/agents'))|where (type !~ ('microsoft.deviceupdate/updateaccounts/activedeployments'))|where (type !~ ('microsoft.discovery/supercomputers/nodepools'))|where (type !~ ('microsoft.discovery/datacontainers/dataassets'))|where (type !~ ('microsoft.documentdb/garnetclusters'))|where (type !~ ('microsoft.documentdb/fleetspacepotentialdatabaseaccountswithlocations'))|where (type !~ ('microsoft.documentdb/fleetspacepotentialdatabaseaccounts'))|where (type !~ ('private.easm/workspaces'))|where (type !~ ('microsoft.fairfieldgardens/provisioningresources'))|where (type !~ ('microsoft.fairfieldgardens/provisioningresources/provisioningpolicies'))|where (type !~ ('microsoft.healthmodel/healthmodels'))|where (type !~ ('microsoft.hybridcompute/machinessoftwareassurance'))|where (type !~ ('microsoft.hybridcompute/machinespaygo'))|where (type !~ ('microsoft.hybridcompute/machinesesu'))|where (type !~ ('microsoft.hybridcompute/arcgatewayassociatedresources'))|where (type !~ ('microsoft.hybridconnectivity/publiccloudconnectors/multicloudsyncedresources'))|where (type !~ ('microsoft.hybridcompute/machinessovereign'))|where (type !~ ('microsoft.hybridcompute/arcserverwithwac'))|where (type !~ ('microsoft.network/networkvirtualappliances'))|where (type !~ ('microsoft.network/virtualhubs')) or ((kind =~ ('routeserver')))|where (type !~ ('microsoft.devhub/iacprofiles'))|where (type !~ ('microsoft.gallery/myareas/galleryitems'))|where (type !~ ('private.monitorgrafana/dashboards'))|where (type !~ ('microsoft.insights/diagnosticsettings'))|where (type !~ ('microsoft.network/privatednszones/virtualnetworklinks'))|where not((type =~ ('microsoft.network/serviceendpointpolicies')) and ((kind =~ ('internal'))))|where (type !~ ('microsoft.managednetworkfabric/fabricroutepolicies'))|where (type !~ ('microsoft.managednetworkfabric/fabricnetworktaps'))|where (type !~ ('microsoft.managednetworkfabric/fabricnetworkpacketbrokers'))|where (type !~ ('microsoft.managednetworkfabric/fabricnetworkdevices'))|where (type !~ ('microsoft.managednetworkfabric/fabricresources'))|where (type !~ ('microsoft.networkcloud/clustervolumes'))|where (type !~ ('microsoft.networkcloud/clustertrunkednetworks'))|where (type !~ ('microsoft.networkcloud/clusterstorageappliances'))|where (type !~ ('microsoft.networkcloud/clusterl3networks'))|where (type !~ ('microsoft.networkcloud/clusterl2networks'))|where (type !~ ('microsoft.networkcloud/clusterresources'))|where (type !~ ('microsoft.networkcloud/clusternetworks'))|where (type !~ ('microsoft.networkcloud/clustercloudservicesnetworks'))|where (type !~ ('microsoft.resources/resourcegraphvisualizer'))|where (type !~ ('microsoft.orbital/l2connections'))|where (type !~ ('microsoft.orbital/groundstations'))|where (type !~ ('microsoft.orbital/edgesites'))|where (type !~ ('microsoft.oriondb/clusters'))|where (type !~ ('microsoft.recommendationsservice/accounts/modeling'))|where (type !~ ('microsoft.recommendationsservice/accounts/serviceendpoints'))|where (type !~ ('microsoft.relationships/servicegrouprelationships'))|where (type !~ ('microsoft.resources/virtualsubscriptionsforresourcepicker'))|where (type !~ ('microsoft.resources/deletedresources'))|where (type !~ ('microsoft.deploymentmanager/rollouts'))|where (type !~ ('microsoft.features/featureprovidernamespaces/featureconfigurations'))|where (type !~ ('microsoft.saashub/cloudservices/hidden'))|where (type !~ ('microsoft.providerhub/providerregistrations'))|where (type !~ ('microsoft.providerhub/providerregistrations/customrollouts'))|where (type !~ ('microsoft.providerhub/providerregistrations/defaultrollouts'))|where (type !~ ('microsoft.edge/configurations'))|where not((type =~ ('microsoft.synapse/workspaces/sqlpools')) and ((kind =~ ('v3'))))|where (type !~ ('microsoft.mission/virtualenclaves/workloads'))|where (type !~ ('microsoft.mission/virtualenclaves'))|where (type !~ ('microsoft.mission/communities/transithubs'))|where (type !~ ('microsoft.mission/virtualenclaves/enclaveendpoints'))|where (type !~ ('microsoft.mission/enclaveconnections'))|where (type !~ ('microsoft.mission/communities/communityendpoints'))|where (type !~ ('microsoft.mission/communities'))|where (type !~ ('microsoft.mission/catalogs'))|where (type !~ ('microsoft.mission/approvals'))|where (type !~ ('microsoft.network/virtualnetworkappliances'))|where (type !~ ('microsoft.workloads/insights'))|where (type !~ ('microsoft.zerotrustsegmentation/segmentationmanagers'))|where (type !~ ('private.zerotrustsegmentation/segmentationmanagers'))|where (type !~ ('microsoft.connectedcache/enterprisemcccustomers/enterprisemcccachenodes'))|where (type !~ ('microsoft.premonition/libraries/samples'))|where (type !~ ('microsoft.premonition/libraries/analyses'))|where not((type =~ ('microsoft.sql/servers')) and ((kind =~ ('v12.0,analytics'))))|where not((type =~ ('microsoft.sql/servers/databases')) and ((kind in~ ('system','v2.0,system','v12.0,system','v12.0,system,serverless','v12.0,user,datawarehouse,gen2,analytics'))))|project name,enabledServices,datacenter,resourceGroup,clusterId,id,type,kind,location,subscriptionId,tags|sort by (tolower(tostring(name))) asc
"@
    $batchRequest.add((New-AzureBatchRequest -method POST -url $queryUrl -content @{ query = $customLocationQuery } -name "customLocation"))
    #endregion get custom locations

    #region get clusters
    #TODO nevim jak propojit cluster <> custom location <> resource bridge
    # $clusterQuery = 'resources | where type =~ "microsoft.azurestackhci/clusters"'
    # @"
    # resources
    # | where type =~ "microsoft.azurestackhci/clusters"
    # | project id=tolower(id), name, type, kind, parentResourceId = tolower(id), nodesCount = array_length(properties.reportedProperties.nodes), resourceGroup
    # | sort by tolower(name) asc
    # "@
    # $batchRequest.add((New-AzureBatchRequest -method POST -url $queryUrl -content @{ query = $clusterQuery } -name "cluster"))
    #endregion get clusters

    #region get resource bridge appliances
    $resourceBridgeQuery = @"
resources|where type =~ "microsoft.resourceconnector/appliances"
| extend status = properties.status, version = properties.version, clusterType = properties.distro, hostResource = properties.infrastructureConfig.provider, provisioningState=properties.provisioningState
| project id, name, status, version, clusterType, hostResource, type, tags, location, subscriptionId, resourceGroup, kind, provisioningState|extend tagsString=tostring(tags)|where (type !~ ('dell.storage/filesystems'))|where (type !~ ('pinecone.vectordb/organizations'))|where (type !~ ('liftrbasic.samplerp/organizations'))|where (type !~ ('commvault.contentstore/cloudaccounts'))|where (type !~ ('paloaltonetworks.cloudngfw/globalrulestacks'))|where (type !~ ('microsoft.liftrpilot/organizations'))|where (type !~ ('microsoft.agfoodplatform/farmbeats'))|where (type !~ ('microsoft.agricultureplatform/agriservices'))|where (type !~ ('microsoft.arc/allfairfax'))|where (type !~ ('microsoft.arc/all'))|where (type !~ ('microsoft.cdn/profiles/securitypolicies'))|where (type !~ ('microsoft.cdn/profiles/secrets'))|where (type !~ ('microsoft.cdn/profiles/rulesets'))|where (type !~ ('microsoft.cdn/profiles/rulesets/rules'))|where (type !~ ('microsoft.cdn/profiles/afdendpoints/routes'))|where (type !~ ('microsoft.cdn/profiles/origingroups'))|where (type !~ ('microsoft.cdn/profiles/origingroups/origins'))|where (type !~ ('microsoft.cdn/profiles/afdendpoints'))|where (type !~ ('microsoft.cdn/profiles/customdomains'))|where (type !~ ('microsoft.chaos/workspaces'))|where (type !~ ('microsoft.chaos/privateaccesses'))|where (type !~ ('microsoft.sovereign/transparencylogs'))|where (type !~ ('microsoft.classiccompute/domainnames/slots/roles'))|where (type !~ ('microsoft.classiccompute/domainnames'))|where (type !~ ('microsoft.cloudtest/pools'))|where (type !~ ('microsoft.cloudtest/images'))|where (type !~ ('microsoft.cloudtest/hostedpools'))|where (type !~ ('microsoft.cloudtest/buildcaches'))|where (type !~ ('microsoft.cloudtest/accounts'))|where (type !~ ('microsoft.compute/virtualmachineflexinstances'))|where (type !~ ('microsoft.compute/standbypoolinstance'))|where (type !~ ('microsoft.compute/computefleetscalesets'))|where (type !~ ('microsoft.compute/computefleetinstances'))|where (type !~ ('microsoft.containerservice/managedclusters/microsoft.kubernetesconfiguration/fluxconfigurations'))|where (type !~ ('microsoft.kubernetes/connectedclusters/microsoft.kubernetesconfiguration/fluxconfigurations'))|where (type !~ ('microsoft.containerservice/managedclusters/microsoft.kubernetesconfiguration/namespaces'))|where (type !~ ('microsoft.kubernetes/connectedclusters/microsoft.kubernetesconfiguration/namespaces'))|where (type !~ ('microsoft.containerservice/managedclusters/microsoft.kubernetesconfiguration/extensions'))|where (type !~ ('microsoft.portalservices/extensions/deployments'))|where (type !~ ('microsoft.portalservices/extensions'))|where (type !~ ('microsoft.portalservices/extensions/slots'))|where (type !~ ('microsoft.portalservices/extensions/versions'))|where (type !~ ('microsoft.deviceregistry/convergedassets'))|where (type !~ ('microsoft.deviceregistry/devices'))|where (type !~ ('microsoft.deviceupdate/updateaccounts'))|where (type !~ ('microsoft.deviceupdate/updateaccounts/updates'))|where (type !~ ('microsoft.deviceupdate/updateaccounts/deviceclasses'))|where (type !~ ('microsoft.deviceupdate/updateaccounts/deployments'))|where (type !~ ('microsoft.deviceupdate/updateaccounts/agents'))|where (type !~ ('microsoft.deviceupdate/updateaccounts/activedeployments'))|where (type !~ ('microsoft.discovery/supercomputers/nodepools'))|where (type !~ ('microsoft.discovery/datacontainers/dataassets'))|where (type !~ ('microsoft.documentdb/garnetclusters'))|where (type !~ ('microsoft.documentdb/fleetspacepotentialdatabaseaccountswithlocations'))|where (type !~ ('microsoft.documentdb/fleetspacepotentialdatabaseaccounts'))|where (type !~ ('private.easm/workspaces'))|where (type !~ ('microsoft.fairfieldgardens/provisioningresources'))|where (type !~ ('microsoft.fairfieldgardens/provisioningresources/provisioningpolicies'))|where (type !~ ('microsoft.healthmodel/healthmodels'))|where (type !~ ('microsoft.hybridcompute/machinessoftwareassurance'))|where (type !~ ('microsoft.hybridcompute/machinespaygo'))|where (type !~ ('microsoft.hybridcompute/machinesesu'))|where (type !~ ('microsoft.hybridcompute/arcgatewayassociatedresources'))|where (type !~ ('microsoft.hybridconnectivity/publiccloudconnectors/multicloudsyncedresources'))|where (type !~ ('microsoft.hybridcompute/machinessovereign'))|where (type !~ ('microsoft.hybridcompute/arcserverwithwac'))|where (type !~ ('microsoft.network/networkvirtualappliances'))|where (type !~ ('microsoft.network/virtualhubs')) or ((kind =~ ('routeserver')))|where (type !~ ('microsoft.devhub/iacprofiles'))|where (type !~ ('microsoft.gallery/myareas/galleryitems'))|where (type !~ ('private.monitorgrafana/dashboards'))|where (type !~ ('microsoft.insights/diagnosticsettings'))|where (type !~ ('microsoft.network/privatednszones/virtualnetworklinks'))|where not((type =~ ('microsoft.network/serviceendpointpolicies')) and ((kind =~ ('internal'))))|where (type !~ ('microsoft.managednetworkfabric/fabricroutepolicies'))|where (type !~ ('microsoft.managednetworkfabric/fabricnetworktaps'))|where (type !~ ('microsoft.managednetworkfabric/fabricnetworkpacketbrokers'))|where (type !~ ('microsoft.managednetworkfabric/fabricnetworkdevices'))|where (type !~ ('microsoft.managednetworkfabric/fabricresources'))|where (type !~ ('microsoft.networkcloud/clustervolumes'))|where (type !~ ('microsoft.networkcloud/clustertrunkednetworks'))|where (type !~ ('microsoft.networkcloud/clusterstorageappliances'))|where (type !~ ('microsoft.networkcloud/clusterl3networks'))|where (type !~ ('microsoft.networkcloud/clusterl2networks'))|where (type !~ ('microsoft.networkcloud/clusterresources'))|where (type !~ ('microsoft.networkcloud/clusternetworks'))|where (type !~ ('microsoft.networkcloud/clustercloudservicesnetworks'))|where (type !~ ('microsoft.resources/resourcegraphvisualizer'))|where (type !~ ('microsoft.orbital/l2connections'))|where (type !~ ('microsoft.orbital/groundstations'))|where (type !~ ('microsoft.orbital/edgesites'))|where (type !~ ('microsoft.oriondb/clusters'))|where (type !~ ('microsoft.recommendationsservice/accounts/modeling'))|where (type !~ ('microsoft.recommendationsservice/accounts/serviceendpoints'))|where (type !~ ('microsoft.relationships/servicegrouprelationships'))|where (type !~ ('microsoft.resources/virtualsubscriptionsforresourcepicker'))|where (type !~ ('microsoft.resources/deletedresources'))|where (type !~ ('microsoft.deploymentmanager/rollouts'))|where (type !~ ('microsoft.features/featureprovidernamespaces/featureconfigurations'))|where (type !~ ('microsoft.saashub/cloudservices/hidden'))|where (type !~ ('microsoft.providerhub/providerregistrations'))|where (type !~ ('microsoft.providerhub/providerregistrations/customrollouts'))|where (type !~ ('microsoft.providerhub/providerregistrations/defaultrollouts'))|where (type !~ ('microsoft.edge/configurations'))|where not((type =~ ('microsoft.synapse/workspaces/sqlpools')) and ((kind =~ ('v3'))))|where (type !~ ('microsoft.mission/virtualenclaves/workloads'))|where (type !~ ('microsoft.mission/virtualenclaves'))|where (type !~ ('microsoft.mission/communities/transithubs'))|where (type !~ ('microsoft.mission/virtualenclaves/enclaveendpoints'))|where (type !~ ('microsoft.mission/enclaveconnections'))|where (type !~ ('microsoft.mission/communities/communityendpoints'))|where (type !~ ('microsoft.mission/communities'))|where (type !~ ('microsoft.mission/catalogs'))|where (type !~ ('microsoft.mission/approvals'))|where (type !~ ('microsoft.network/virtualnetworkappliances'))|where (type !~ ('microsoft.workloads/insights'))|where (type !~ ('microsoft.zerotrustsegmentation/segmentationmanagers'))|where (type !~ ('private.zerotrustsegmentation/segmentationmanagers'))|where (type !~ ('microsoft.connectedcache/enterprisemcccustomers/enterprisemcccachenodes'))|where (type !~ ('microsoft.premonition/libraries/samples'))|where (type !~ ('microsoft.premonition/libraries/analyses'))|where not((type =~ ('microsoft.sql/servers')) and ((kind =~ ('v12.0,analytics'))))|where not((type =~ ('microsoft.sql/servers/databases')) and ((kind in~ ('system','v2.0,system','v12.0,system','v12.0,system,serverless','v12.0,user,datawarehouse,gen2,analytics'))))|project name,status,version,tagsString,id,type,kind,location,subscriptionId,resourceGroup,tags|sort by (tolower(tostring(name))) asc
"@
    $batchRequest.add((New-AzureBatchRequest -method POST -url $queryUrl -content @{ query = $resourceBridgeQuery } -name "resourceBridge"))
    #endregion get resource bridge appliances

    $batchResult = Invoke-AzureBatchRequest -batchRequest $batchRequest

    # $clusterList = $batchResult | ? RequestName -EQ "cluster"
    $customLocationList = $batchResult | ? RequestName -EQ "customLocation"
    $resourceBridgeList = $batchResult | ? RequestName -EQ "resourceBridge"
    #endregion get custom locations, clusters, resource bridge appliances

    foreach ($customLocation in $customLocationList) {
        $customLocationId = $customLocation.id

        Write-Verbose "Processing custom location $($customLocation.name) ($($customLocationId))"

        #region get VMs
        Write-Verbose "Getting VMs"
        $vmQuery = @"
resources
| where type =~ "Microsoft.HybridCompute/machines" and kind in~ ("HCI")
| project hostId = tolower(id),name
| join kind=inner (
    ExtensibilityResources
    | where type =~ "microsoft.azurestackhci/virtualmachineinstances"
    | parse kind=regex flags=i id with hostId "/providers/microsoft.azurestackhci/virtualmachineinstances/default"
    | project hostId = tolower(hostId), guestId = tolower(id), properties, extendedLocation, systemData, type, location, resourceGroup, subscriptionId
    | extend customLocation = tostring(extendedLocation["name"])
    | where customLocation =~ "$customLocationId"
) on hostId
| project id = hostId, name, type, location, resourceGroup, subscriptionId, properties, extendedLocation, systemData
"@
        $vmList = New-AzureBatchRequest -method POST -url $queryUrl -content @{ query = $vmQuery } | Invoke-AzureBatchRequest
        #endregion get VMs

        # get basic info for each VM
        Write-Verbose "Getting VMs details"
        $vmListBasicInfo = New-AzureBatchRequest -url "<placeholder>?api-version=2024-05-20-preview" -placeholder $vmList.Id -placeholderAsId | Invoke-AzureBatchRequest

        # get basic HCI specific info for each VM
        [System.Collections.Generic.List[object]] $batchRequest = @()
        New-AzureBatchRequest -url "<placeholder>/providers/Microsoft.AzureStackHCI/virtualMachineInstances/default?api-version=2023-09-01-preview" -placeholder $vmList.Id -placeholderAsId | % { $batchRequest.add($_) }

        $diskQuery = @"
ExtensibilityResources
    | where type =~ "microsoft.azurestackhci/virtualmachineinstances"
    | mv-expand dataDisks=properties.storageProfile.dataDisks
    | extend vmDiskParts = iff(array_length(split(dataDisks.name, "/")) == 1, split(dataDisks.id, "/"), split(dataDisks.name, "/"))
    | extend vmDiskName = tostring(vmDiskParts[array_length(vmDiskParts)-1])
    | extend diskId = tostring(dataDisks.id)
    | join (
        resources
        | where type == "microsoft.azurestackhci/virtualharddisks" and properties.provisioningState =~ "succeeded" and extendedLocation.name =~ "$customLocationId"
        | extend diskParts = split(id, "/")
        | extend diskName = tostring(diskParts[array_length(diskParts)-1])
    ) on `$left.diskId == `$right.id
    | extend updatedProperties = pack("diskSizeBytes",properties1['diskSizeGB'],"provisioningState",properties1['provisioningState'],"diskSizeGB",properties1['diskSizeGB'],"status",properties1['status'],"dynamic",properties1['dynamic'],"containerId",properties1['containerId'])
    | project
            id = id1,
            name = name1,
            type = type1,
            tenantId = tenantId1,
            location = location1,
            resourceGroup = resourceGroup1,
            subscriptionId = subscriptionId1,
            managedBy = managedBy1,
            sku = sku1,
            plan = plan1,
            properties = updatedProperties,
            tags = tags,
            identity = identity1,
            zones = zones1,
            extendedLocation = extendedLocation1
"@
        $batchRequest.add((New-AzureBatchRequest -method POST -url $queryUrl -content @{ query = $diskQuery } -name "diskInfo" ))

        $nicQuery = @"
resources
| where type =~ "Microsoft.AzureStackHCI/networkinterfaces" and
    properties.provisioningState =~ "succeeded" and
    extendedLocation.name =~ "$customLocationId"
| extend ipConfigurationsProperties = properties.ipConfigurations[0].properties
| extend gateway = ipConfigurationsProperties.gateway
| extend ipAddress = ipConfigurationsProperties.privateIPAddress
| extend networkId = tolower(tostring(ipConfigurationsProperties.subnet.id))
| join kind=leftouter (
    resources
    | where type == "microsoft.azurestackhci/logicalnetworks" and properties.provisioningState =~ "succeeded"
    | extend networkId = tolower(tostring(id))
    | extend subnetProperties = properties.subnets[0].properties
    | extend addressPrefix = subnetProperties.addressPrefix
    | extend ipv4Type = coalesce(subnetProperties.ipAllocationMethod, "Dynamic")
    | project networkId, subnetProperties, addressPrefix, ipv4Type
) on networkId
| extend network = pack("id", networkId, "addressPrefix", addressPrefix, "ipv4Type", ipv4Type, "gatewayAddress", gateway)
| project-away ipConfigurationsProperties, networkId, networkId1, addressPrefix, ipv4Type, gateway, subnetProperties
"@
        $batchRequest.add((New-AzureBatchRequest -method POST -url $queryUrl -content @{ query = $nicQuery } -name "nicInfo"))

        Write-Verbose "Getting VMs details - HCI data, disks and nics"
        $batchResult = Invoke-AzureBatchRequest -batchRequest $batchRequest

        $vmListBasicHCIInfo = $batchResult | ? RequestName -In $vmList.Id
        $vmListDiskInfo = $batchResult | ? RequestName -EQ "diskInfo"
        $vmListNicInfo = $batchResult | ? RequestName -EQ "nicInfo"

        foreach ($vm in $vmListBasicHCIInfo) {
            $vmId = $vm.id
            # $vmCustomLocation = $vm.extendedLocation | ? type -EQ 'CustomLocation' | select -ExpandProperty Name
            $vmCustomLocation = $customLocationId

            Write-Verbose "Processing VM $($vm.properties.osProfile.computerName) ($($vm.id))"

            $vmBasicData = $vmListBasicInfo | ? id -EQ $vm.RequestName | select * -ExcludeProperty RequestName

            $nicId = $vm.properties.networkProfile.networkInterfaces.id

            $diskId = $vm.properties.storageProfile.datadisks.id

            $nicData = $vmListNicInfo | ? id -In $nicId | select * -ExcludeProperty RequestName
            $diskData = $vmListDiskInfo | ? id -In $diskId | select * -ExcludeProperty RequestName

            $vm | Add-Member -MemberType NoteProperty -Name "basicInfo" -Value $vmBasicData
            $vm | Add-Member -MemberType NoteProperty -Name "nics" -Value $nicData
            $vm | Add-Member -MemberType NoteProperty -Name "disks" -Value $diskData
            $vm | Add-Member -MemberType NoteProperty -Name "customLocation" -Value $customLocation
            $vm | Add-Member -MemberType NoteProperty -Name "resourceBridge" -Value ($resourceBridgeList | ? id -EQ $customLocation.clusterId)
            $vm | select * -ExcludeProperty RequestName
        }
    }
}