function Get-AzureLocalExtensionCompatibilityTable {
    <#
    .SYNOPSIS
    Fetches the Azure CLI stack-hci-vm extension compatibility table.
    To know which versions of the Azure CLI stack-hci-vm extension are compatible with specific Azure Local versions.

    .DESCRIPTION
    This function retrieves the compatibility table for Azure CLI stack-hci-vm extensions from a markdown file hosted on GitHub at https://raw.githubusercontent.com/Azure-Samples/AzureLocal/refs/heads/main/Arc%20VMs%20Extension%20Compatibility.md.

    .OUTPUTS
    Returns a list of custom objects representing the compatibility data.

    .EXAMPLE
    Get-AzureHCIExtensionCompatibilityTable
    #>

    [CmdletBinding()]
    param ()

    $url = "https://raw.githubusercontent.com/Azure-Samples/AzureLocal/refs/heads/main/Arc%20VMs%20Extension%20Compatibility.md"

    try {
        # Fetch the raw content of the markdown file
        $markdownContent = Invoke-RestMethod -Uri $url -ErrorAction Stop
    } catch {
        throw "Failed to download the compatibility file from '$url'. Error: $_"
    }

    $lines = $markdownContent -split "`r?`n"
    $tableLines = @()
    $inTable = $false

    # Identify the table (header line) and collect all rows
    foreach ($line in $lines) {
        if ($line -match '^\|\s*Release Build\s*\|\s*Release Series\s*\|\s*vmss-hci\s*\|\s*stack-hci-vm\s*\|\s*API Version\s*\|') {
            $inTable = $true
            $tableLines += $line
            continue
        }
        if ($inTable) {
            if ($line -match '^\|') {
                $tableLines += $line
            } else {
                break
            }
        }
    }

    if ($tableLines.Count -lt 2) {
        throw "Can't find the Markdown table with the expected header."
    }

    # Skip header and separator lines to extract data rows
    $dataRows = $tableLines | Select-Object -Skip 2

    # Parse each row
    $results = foreach ($row in $dataRows) {
        $cols = $row -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        [PSCustomObject]@{
            ReleaseBuild  = $cols[0]
            ReleaseSeries = $cols[1]
            VmssHci       = $cols[2]
            StackHciVm    = $cols[3]
            ApiVersion    = $cols[4]
        }
    }

    # Output the full mapping table
    $results
}

function Get-AzureLocalHealth {
    <#
    .SYNOPSIS
        Retrieves health alerts for an Azure Local (HCI) cluster using Azure Resource Graph.

    .DESCRIPTION
        The Get-AzureLocalHealth function queries Azure Resource Graph for active health alerts related to a specified Azure Local (HCI) cluster.
        It filters alerts by subscription, resource group, and cluster name, returning only alerts with a 'Fired' monitor condition.

    .PARAMETER SubscriptionId
        The Azure subscription ID containing the Azure Local (HCI) cluster.

    .PARAMETER ResourceGroupName
        The resource group name where the Azure Local (HCI) cluster resides.

    .PARAMETER ClusterName
        The name of the Azure Local (HCI) cluster.

    .EXAMPLE
        Get-AzureLocalHealth -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -ResourceGroupName "AHCI-MAIN" -ClusterName "AHCI-MAIN"

        Retrieves all active health alerts for the cluster 'AHCI-MAIN' in resource group 'AHCI-MAIN' within the specified subscription.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$subscriptionId,

        [Parameter(Mandatory = $true)]
        [string]$resourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]$clusterName
    )

    $query = @"
alertsmanagementresources | where type == 'microsoft.alertsmanagement/alerts' | extend severity = tostring(properties["essentials"]["severity"]) | where properties["essentials"]["targetResource"] =~ '/subscriptions/$subscriptionId/resourcegroups/$resourceGroupName/providers/microsoft.azurestackhci/clusters/$clusterName' or properties["essentials"]["targetResource"] startswith '/subscriptions/$subscriptionId/resourcegroups/$resourceGroupName/providers/microsoft.azurestackhci/clusters/$clusterName/'
| where properties["essentials"]["monitorCondition"] in~ ('Fired')
"@
    Search-AzGraph -Query $query
}

function Get-AzureLocalImage {
    <#
    .SYNOPSIS
    Retrieves existing Azure Local (HCI) VM images.

    .DESCRIPTION
    This function retrieves a list of VM images available in the specified Azure Local (HCI) environment.

    .PARAMETER SubscriptionId
    The subscription ID to filter the VM images.

    .PARAMETER ResourceGroupName
    The resource group name to filter the VM images.

    .EXAMPLE
    Get-AzureLocalImage -SubscriptionId "66cdebf5-fbaf-4040-b777-4507fe1ccb5e" -ResourceGroupName "ahci-main"

    .NOTES
    Requires Azure CLI with stack-hci-vm extension installed.
    #>

    [CmdletBinding()]
    param(
        [string]$SubscriptionId,

        [string]$ResourceGroupName
    )

    Write-Verbose "Retrieving existing Azure Local VM images..."

    # Get all VM images from Azure Local
    if ($SubscriptionId) {
        $SubscriptionIdText = " --subscription '$SubscriptionId'"
    } else {
        $SubscriptionIdText = $null
        Write-Verbose "No SubscriptionId provided, using default subscription"
    }

    if ($ResourceGroupName) {
        $ResourceGroupNameText = " --resource-group '$ResourceGroupName'"
    } else {
        $ResourceGroupNameText = $null
        Write-Verbose "No ResourceGroupName provided, using default resource group"
    }

    $azCommand = "az stack-hci-vm image list $SubscriptionIdText $ResourceGroupNameText --output json"
    $result = Invoke-Expression $azCommand

    $result | ConvertFrom-Json
}

function Get-AzureLocalMarketplaceImageVersion {
    <#
    .SYNOPSIS
        Retrieves the latest version of Azure local marketplace images.

    .DESCRIPTION
        The Get-AzureLocalMarketplaceImageVersion function queries the Azure local marketplace
        to determine the latest available version of specific images. This is useful for
        automation scripts that need to reference the most recent image versions.

    .PARAMETER PublisherName
        The publisher name of the Azure image to query.

    .PARAMETER Offer
        The offer name of the Azure image to query.

    .PARAMETER Sku
        The SKU of the Azure image to query.

    .PARAMETER Location
        The Azure region location to check for image availability.

    .PARAMETER Architecture
        The architecture of the image.

        Default is 'x64'. Other option is 'Arm64'.

    .EXAMPLE
        Get-AzureLocalMarketplaceImageVersion -Publisher 'microsoftwindowsserver' -Offer 'windowsserver' -SKU '2022-datacenter-azure-edition' -Location westeurope

    .LINK
        https://docs.microsoft.com/en-us/powershell/module/az.compute/get-azvmimagepublisher
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Publisher,

        [Parameter(Mandatory = $true)]
        [string]$Offer,

        [Parameter(Mandatory = $true)]
        [string]$SKU,

        [ValidateNotNullOrEmpty()]
        [string]$Location = $_azureLocation,

        [ValidateSet('Arm64', 'x64')]
        [string] $Architecture = "x64"
    )

    if (!$Location) { throw "Location is not set." }

    Write-Verbose "Retrieving marketplace image versions for $Publisher/$Offer/$SKU in $Location"

    # Get all versions for the specific SKU
    $result = Invoke-Expression "az vm image list --publisher '$Publisher' --offer '$Offer' --sku '$SKU' --location '$Location' --architecture '$Architecture' --all --output json"

    # from some reason even if --sku is used to filter just specific SKUs, even different ones are returned. Same goes for Offer.
    $result = $result | ConvertFrom-Json | ? { $_.Sku -eq $SKU -and $_.Offer -eq $Offer }

    $result | Sort-Object -Property { [version]$_.version } -Descending
}

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

function New-AzureLocalVMImage {
    <#
    .SYNOPSIS
    Creates a new Azure Local (HCI) VM image with a specific version.

    .DESCRIPTION
    This function creates VM images on Azure Local (HCI) infrastructure using either
    marketplace images with specific versions or custom VHD/VHDX files.

    .PARAMETER ResourceGroupName
    The resource group where the image will be created.

    .PARAMETER CustomLocationId
    The custom location ID for the Azure Local environment.

    .PARAMETER ImageName
    The name for the new VM image.

    Dots are not allowed, because anything behind the dot is considered as file extension.

    .PARAMETER Publisher
    The publisher of the marketplace image (e.g., 'MicrosoftWindowsServer').

    .PARAMETER Offer
    The offer name (e.g., 'WindowsServer').

    .PARAMETER SKU
    The SKU name (e.g., '2022-datacenter-azure-edition').

    .PARAMETER Version
    The specific version to use. Use 'latest' for the most recent version.

    .PARAMETER VhdPath
    Path to a custom VHD/VHDX file (alternative to marketplace image).

    .PARAMETER OSType
    Operating system type. Defaults to 'Windows'.

    .PARAMETER StoragePathId
    Storage path ID for the image storage location.

    .EXAMPLE
    $cluster = $_azureLocalClusterList[0]
    $publisher = "MicrosoftWindowsServer"
    $offer = "WindowsServer"
    $sku = "2022-datacenter-azure-edition"

    az account set --subscription $cluster.SubscriptionName
    $customLocationID = az customlocation show --resource-group $cluster.ResourceGroupName --name $cluster.CustomLocation --query id -o tsv

    $imageVersionList = Get-AzureLocalMarketplaceImageVersion -Publisher $publisher -Offer $offer -SKU $sku -Location westeurope

    New-AzureLocalVMImage -ResourceGroupName $cluster.ResourceGroupName -CustomLocationId $customLocationID -ImageName "WinServer2022-v1" -Publisher $publisher -Offer $offer -SKU $sku -Version $imageVersionList[0].Version

    Create newest available version of Windows Server 2022 image.

    .EXAMPLE
    New-AzureLocalVMImage -ResourceGroupName "rg-azlocal" -CustomLocationId "/subscriptions/.../customLocations/cl-hci" -ImageName "CustomWin11" -VhdPath "\\storage\images\Win11Custom.vhdx"

    .NOTES
    Requires Azure CLI with stack-hci-vm extension installed.
    #>

    [CmdletBinding(DefaultParameterSetName = 'Marketplace')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]$CustomLocationId,

        [Parameter(Mandatory = $true)]
        [ValidateScript( {
                if ($_ -like '*.*') {
                    throw "$_ contains dots, which are not allowed in image names."
                } else {
                    $true
                }
            })]
        [string]$ImageName,

        [Parameter(Mandatory = $true, ParameterSetName = 'Marketplace')]
        [string]$Publisher,

        [Parameter(Mandatory = $true, ParameterSetName = 'Marketplace')]
        [string]$Offer,

        [Parameter(Mandatory = $true, ParameterSetName = 'Marketplace')]
        [string]$SKU,

        [Parameter(Mandatory = $false, ParameterSetName = 'Marketplace')]
        [string]$Version = 'latest',

        [Parameter(Mandatory = $true, ParameterSetName = 'CustomVHD')]
        [string]$VhdPath,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Windows', 'Linux')]
        [string]$OSType = 'Windows',

        [Parameter(Mandatory = $false)]
        [string]$StoragePathId
    )

    Write-Verbose "Creating Azure Local VM image: $ImageName"

    # Check if Azure CLI is available
    $azVersion = az version --output json 2>$null
    if (-not $azVersion) {
        throw "Azure CLI is not available or not properly configured"
    }

    # Build the base command
    $azCommand = @(
        'az', 'stack-hci-vm', 'image', 'create',
        '--resource-group', $ResourceGroupName,
        '--custom-location', $CustomLocationId,
        '--name', $ImageName,
        '--os-type', $OSType
    )

    # Add marketplace-specific parameters
    if ($PSCmdlet.ParameterSetName -eq 'Marketplace') {
        $azCommand += @(
            '--publisher', $Publisher,
            '--offer', $Offer,
            '--sku', $SKU,
            '--version', $Version
        )

        Write-Verbose "Using marketplace image: $Publisher/$Offer/$SKU/$Version"
    }

    # Add custom VHD parameters
    if ($PSCmdlet.ParameterSetName -eq 'CustomVHD') {
        if (-not (Test-Path $VhdPath)) {
            throw "VHD file not found: $VhdPath"
        }
        $azCommand += @('--image-path', $VhdPath)

        Write-Verbose "Using custom VHD: $VhdPath"
    }

    # Add storage path if specified
    if ($StoragePathId) {
        $azCommand += @('--storage-path-id', $StoragePathId)
    }

    # Output the results in JSON format
    $azCommand += @('--output', 'json')

    # Execute the command
    $command = $azCommand -join ' '
    Write-Verbose "Executing: $command"
    $errOutput = $($imageInfo = Invoke-Expression $command | ConvertFrom-Json ) 2>&1 # redirect error stream to success stream, so we can capture it

    if ($LASTEXITCODE -eq 0) {
        Write-Verbose "Successfully created VM image '$($imageInfo.name)'"

        return $imageInfo
    } else {
        throw "Failed to create VM image '$ImageName'. Error was: $errOutput"
    }
}

Export-ModuleMember -function Get-AzureLocalExtensionCompatibilityTable, Get-AzureLocalHealth, Get-AzureLocalImage, Get-AzureLocalMarketplaceImageVersion, Get-AzureLocalVMOverview, New-AzureLocalVMImage

