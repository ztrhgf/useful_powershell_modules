function Get-ArcMachineOverview {
    <#
    .SYNOPSIS
    Get list of all ARC machines in your Azure tenant.

    .DESCRIPTION
    Get list of all ARC machines in your Azure tenant and their basic information.

    To get details about specific machine, use Get-AzConnectedMachine.

    .EXAMPLE
    Get-ArcMachineOverview

    Get list of all ARC machines in your Azure tenant and their basic information.
    #>

    [CmdletBinding()]
    param()

    if (!(Get-Module Az.ResourceGraph) -and !(Get-Module Az.ResourceGraph -ListAvailable)) {
        throw "Module Az.ResourceGraph is missing. Function $($MyInvocation.MyCommand) cannot continue"
    }

    # query stolen from developer tools pane at https://portal.azure.com/#view/Microsoft_Azure_ArcCenterUX/ArcCenterMenuBlade/~/servers
    $query = @'
resources
| where type =~ 'microsoft.hybridcompute/machines'
| extend machineId = tolower(tostring(id))
| extend datacenter = iif(isnull(tags.Datacenter), '', tags.Datacenter)
| extend state = properties.status
| extend SMI = identity.principalId
| extend status = case(
    state =~ 'Connected', 'Connected',
    state =~ 'Disconnected', 'Offline',
    state =~ 'Error', 'Error',
    state =~ 'Expired', 'Expired',
    '')
| extend osSku = properties.osSku
| extend os = properties.osName
| extend osName = case(
    os =~ 'windows', 'Windows',
    os =~ 'linux', 'Linux',
    '')
| extend operatingSystem = iif(isnotnull(osSku), osSku, osName)
| extend assessmentMode = iff(os =~ "windows",
    properties.osProfile.windowsConfiguration.patchSettings.assessmentMode,
    properties.osProfile.linuxConfiguration.patchSettings.assessmentMode)
| extend periodicAssessment = iff(isnotnull(assessmentMode) and assessmentMode =~ "AutomaticByPlatform", true, false)
| join kind=leftouter (
    resources
    | where type =~ "microsoft.hybridcompute/machines/extensions"
    | extend machineId = tolower(tostring(trim_end(@"\/\w+\/(\w|\.)+", id)))
    | extend provisioned = tolower(tostring(properties.provisioningState)) == "succeeded"
    | summarize
        MDEcnt = countif(properties.type in ("MDE.Linux", "MDE.Windows") and provisioned),
        AMAcnt = countif(properties.type in ("AzureMonitorWindowsAgent", "AzureMonitorLinuxAgent", "MicrosoftMonitoringAgent", "OmsAgentForLinux") and provisioned),
        WACcnt = countif(properties.type in ("AdminCenter") and provisioned) by machineId
) on machineId
| join kind=leftouter (
    patchassessmentresources
    | where type =~ "microsoft.hybridcompute/machines/patchassessmentresults"
    | where properties.status =~ "Succeeded" or properties.status =~ "Inprogress"
    | parse id with resourceId "/patchAssessmentResults" *
    | extend resourceId=tolower(resourceId)
    | project resourceId, assessProperties=properties
) on $left.machineId == $right.resourceId
| extend defenderStatus = iff ((MDEcnt>0), 'Enabled', 'Not enabled')
| extend monitoringAgent = iff ((AMAcnt>0), 'Installed','Not installed')
| extend wacStatus = iff ((WACcnt>0), 'Enabled', 'Not enabled')
| extend hostName = tostring(properties.displayName)
| extend name = iif(properties.cloudMetadata.provider == 'AWS' and name != hostName, strcat(name, "(", hostName, ")"), name)
| extend updateStatusBladeLinkText = case(
    (isnotnull(assessProperties) and assessProperties.status =~ "inprogress"), 'Checking for updates',
    ((isnotnull(assessProperties) and assessProperties.osType =~ "Windows" and (assessProperties.availablePatchCountByClassification.critical>0 or
    assessProperties.availablePatchCountByClassification.definition>0 or assessProperties.availablePatchCountByClassification.featurePack>0 or
    assessProperties.availablePatchCountByClassification.security>0 or
    assessProperties.availablePatchCountByClassification.servicePack>0 or assessProperties.availablePatchCountByClassification.tools>0 or
    assessProperties.availablePatchCountByClassification.updateRollup>0 or assessProperties.availablePatchCountByClassification.updates>0)) or
    (isnotnull(assessProperties) and assessProperties.osType =~ "Linux" and (assessProperties.availablePatchCountByClassification.other>0 or assessProperties.availablePatchCountByClassification.security>0))),
    strcat(iff(assessProperties.osType =~ 'Windows', toint(assessProperties.availablePatchCountByClassification.critical) + toint(assessProperties.availablePatchCountByClassification.definition)
    + toint(assessProperties.availablePatchCountByClassification.featurePack) + toint(assessProperties.availablePatchCountByClassification.security)
    + toint(assessProperties.availablePatchCountByClassification.servicePack) + toint(assessProperties.availablePatchCountByClassification.tools) + toint(assessProperties.availablePatchCountByClassification.updateRollup)
    + toint(assessProperties.availablePatchCountByClassification.updates),
    toint(assessProperties.availablePatchCountByClassification.other) + toint(assessProperties.availablePatchCountByClassification.security)), ' pending updates'),
    (isnotnull(assessProperties) and assessProperties.rebootPending =~ "true"), 'Pending reboot',
    ((isnotnull(assessProperties) and assessProperties.osType =~ "Windows" and (assessProperties.availablePatchCountByClassification.critical==0 and
    assessProperties.availablePatchCountByClassification.definition==0 and assessProperties.availablePatchCountByClassification.featurePack==0 and
    assessProperties.availablePatchCountByClassification.security==0 and assessProperties.availablePatchCountByClassification.servicePack==0 and
    assessProperties.availablePatchCountByClassification.tools==0 and assessProperties.availablePatchCountByClassification.updateRollup==0 and assessProperties.availablePatchCountByClassification.updates==0)) or
    (isnotnull(assessProperties) and assessProperties.osType =~ "Linux" and (assessProperties.availablePatchCountByClassification.other==0 and assessProperties.availablePatchCountByClassification.security==0))), 'No pending updates',
    ((isnull(periodicAssessment) or periodicAssessment == false)and (isnull(assessProperties) == true)), 'Enable periodic assessment', 'No updates data')
| extend updateStatusBladeLinkBlade = case(
    ((isnull(periodicAssessment) or periodicAssessment == false) and
    (isnull(assessProperties) == true)),
    pack("blade", "UpdateCenterUpdateSettingsBlade", "extension", "Microsoft_Azure_Automation"),
    pack("blade", "UpdateMgmtV2MenuBlade", "extension", "Microsoft_Azure_Automation")
    )
| extend updateStatusBladeLinkParameters = case(
    ((isnull(periodicAssessment) or periodicAssessment == false) and
    (isnull(assessProperties) == true)),
    pack("ids", pack_array(machineId), "source", "Arc_Server_BrowseResourceBlade"),
    pack("machineResourceId", id, "source", "Arc_Server_BrowseResourceBlade")
    )
| extend updateStatus = pack(
    "text", updateStatusBladeLinkText,
    "blade", updateStatusBladeLinkBlade.blade,
    "extension", updateStatusBladeLinkBlade.extension,
    "parameters", updateStatusBladeLinkParameters)
| project name, status, resourceGroup, subscriptionId, SMI, datacenter, operatingSystem, id, type, location, kind, tags, machineId, defenderStatus, monitoringAgent, wacStatus, updateStatus, hostName, updateStatusBladeLinkText|where (type !~ ('dell.storage/filesystems'))|where (type !~ ('arizeai.observabilityeval/organizations'))|where (type !~ ('lambdatest.hyperexecute/organizations'))|where (type !~ ('pinecone.vectordb/organizations'))|where (type !~ ('microsoft.weightsandbiases/instances'))|where (type !~ ('paloaltonetworks.cloudngfw/globalrulestacks'))|where (type !~ ('purestorage.block/storagepools/avsstoragecontainers'))|where (type !~ ('purestorage.block/reservations'))|where (type !~ ('purestorage.block/storagepools'))|where (type !~ ('solarwinds.observability/organizations'))|where (type !~ ('splitio.experimentation/experimentationworkspaces'))|where (type !~ ('microsoft.agfoodplatform/farmbeats'))|where (type !~ ('microsoft.agricultureplatform/agriservices'))|where (type !~ ('microsoft.appsecurity/policies'))|where (type !~ ('microsoft.arc/allfairfax'))|where (type !~ ('microsoft.arc/all'))|where (type !~ ('microsoft.cdn/profiles/securitypolicies'))|where (type !~ ('microsoft.cdn/profiles/secrets'))|where (type !~ ('microsoft.cdn/profiles/rulesets'))|where (type !~ ('microsoft.cdn/profiles/rulesets/rules'))|where (type !~ ('microsoft.cdn/profiles/afdendpoints/routes'))|where (type !~ ('microsoft.cdn/profiles/origingroups'))|where (type !~ ('microsoft.cdn/profiles/origingroups/origins'))|where (type !~ ('microsoft.cdn/profiles/afdendpoints'))|where (type !~ ('microsoft.cdn/profiles/customdomains'))|where (type !~ ('microsoft.chaos/privateaccesses'))|where (type !~ ('microsoft.sovereign/transparencylogs'))|where (type !~ ('microsoft.sovereign/landingzoneconfigurations'))|where (type !~ ('microsoft.hardwaresecuritymodules/cloudhsmclusters'))|where (type !~ ('microsoft.cloudtest/accounts'))|where (type !~ ('microsoft.cloudtest/hostedpools'))|where (type !~ ('microsoft.cloudtest/images'))|where (type !~ ('microsoft.cloudtest/pools'))|where (type !~ ('microsoft.compute/computefleetinstances'))|where (type !~ ('microsoft.compute/computefleetscalesets'))|where (type !~ ('microsoft.compute/standbypoolinstance'))|where (type !~ ('microsoft.compute/virtualmachineflexinstances'))|where (type !~ ('microsoft.kubernetesconfiguration/extensions'))|where (type !~ ('microsoft.containerservice/managedclusters/microsoft.kubernetesconfiguration/extensions'))|where (type !~ ('microsoft.kubernetes/connectedclusters/microsoft.kubernetesconfiguration/namespaces'))|where (type !~ ('microsoft.containerservice/managedclusters/microsoft.kubernetesconfiguration/namespaces'))|where (type !~ ('microsoft.kubernetes/connectedclusters/microsoft.kubernetesconfiguration/fluxconfigurations'))|where (type !~ ('microsoft.containerservice/managedclusters/microsoft.kubernetesconfiguration/fluxconfigurations'))|where (type !~ ('microsoft.portalservices/extensions/deployments'))|where (type !~ ('microsoft.portalservices/extensions'))|where (type !~ ('microsoft.portalservices/extensions/slots'))|where (type !~ ('microsoft.portalservices/extensions/versions'))|where (type !~ ('microsoft.datacollaboration/workspaces'))|where (type !~ ('microsoft.deviceregistry/devices'))|where (type !~ ('microsoft.deviceupdate/updateaccounts'))|where (type !~ ('microsoft.deviceupdate/updateaccounts/updates'))|where (type !~ ('microsoft.deviceupdate/updateaccounts/deviceclasses'))|where (type !~ ('microsoft.deviceupdate/updateaccounts/deployments'))|where (type !~ ('microsoft.deviceupdate/updateaccounts/agents'))|where (type !~ ('microsoft.deviceupdate/updateaccounts/activedeployments'))|where (type !~ ('private.easm/workspaces'))|where (type !~ ('microsoft.impact/connectors'))|where (type !~ ('microsoft.edgeorder/virtual_orderitems'))|where (type !~ ('microsoft.workloads/epicvirtualinstances'))|where (type !~ ('microsoft.fairfieldgardens/provisioningresources'))|where (type !~ ('microsoft.fairfieldgardens/provisioningresources/provisioningpolicies'))|where (type !~ ('microsoft.healthmodel/healthmodels'))|where (type !~ ('microsoft.hybridcompute/arcserverwithwac'))|where (type !~ ('microsoft.hybridcompute/machinessovereign'))|where (type !~ ('microsoft.hybridcompute/machinesesu'))|where (type !~ ('microsoft.hybridcompute/machinespaygo'))|where (type !~ ('microsoft.hybridcompute/machinessoftwareassurance'))|where (type !~ ('microsoft.network/virtualhubs')) or ((kind =~ ('routeserver')))|where (type !~ ('microsoft.network/networkvirtualappliances'))|where (type !~ ('microsoft.devhub/iacprofiles'))|where (type !~ ('microsoft.modsimworkbench/workbenches/chambers'))|where (type !~ ('microsoft.modsimworkbench/workbenches/chambers/files'))|where (type !~ ('microsoft.modsimworkbench/workbenches/chambers/filerequests'))|where (type !~ ('microsoft.modsimworkbench/workbenches/chambers/licenses'))|where (type !~ ('microsoft.modsimworkbench/workbenches/chambers/connectors'))|where (type !~ ('microsoft.modsimworkbench/workbenches/sharedstorages'))|where (type !~ ('microsoft.modsimworkbench/workbenches/chambers/storages'))|where (type !~ ('microsoft.modsimworkbench/workbenches/chambers/workloads'))|where (type !~ ('microsoft.insights/diagnosticsettings'))|where not((type =~ ('microsoft.network/serviceendpointpolicies')) and ((kind =~ ('internal'))))|where (type !~ ('microsoft.resources/resourcegraphvisualizer'))|where (type !~ ('microsoft.orbital/cloudaccessrouters'))|where (type !~ ('microsoft.orbital/terminals'))|where (type !~ ('microsoft.orbital/sdwancontrollers'))|where (type !~ ('microsoft.orbital/spacecrafts/contacts'))|where (type !~ ('microsoft.orbital/contactprofiles'))|where (type !~ ('microsoft.orbital/edgesites'))|where (type !~ ('microsoft.orbital/geocatalogs'))|where (type !~ ('microsoft.orbital/groundstations'))|where (type !~ ('microsoft.orbital/l2connections'))|where (type !~ ('microsoft.orbital/spacecrafts'))|where (type !~ ('microsoft.recommendationsservice/accounts/modeling'))|where (type !~ ('microsoft.recommendationsservice/accounts/serviceendpoints'))|where (type !~ ('microsoft.recoveryservicesbvtd/vaults'))|where (type !~ ('microsoft.recoveryservicesbvtd2/vaults'))|where (type !~ ('microsoft.recoveryservicesintd/vaults'))|where (type !~ ('microsoft.recoveryservicesintd2/vaults'))|where (type !~ ('microsoft.relationships/servicegroupmember'))|where (type !~ ('microsoft.relationships/dependencyof'))|where (type !~ ('microsoft.resources/deletedresources'))|where (type !~ ('microsoft.deploymentmanager/rollouts'))|where (type !~ ('microsoft.features/featureprovidernamespaces/featureconfigurations'))|where (type !~ ('microsoft.saashub/cloudservices/hidden'))|where (type !~ ('microsoft.providerhub/providerregistrations'))|where (type !~ ('microsoft.providerhub/providerregistrations/customrollouts'))|where (type !~ ('microsoft.providerhub/providerregistrations/defaultrollouts'))|where (type !~ ('microsoft.edge/configurations'))|where not((type =~ ('microsoft.synapse/workspaces/sqlpools')) and ((kind =~ ('v3'))))|where (type !~ ('microsoft.mission/virtualenclaves/workloads'))|where (type !~ ('microsoft.mission/virtualenclaves'))|where (type !~ ('microsoft.mission/communities/transithubs'))|where (type !~ ('microsoft.mission/virtualenclaves/enclaveendpoints'))|where (type !~ ('microsoft.mission/enclaveconnections'))|where (type !~ ('microsoft.mission/communities/communityendpoints'))|where (type !~ ('microsoft.mission/communities'))|where (type !~ ('microsoft.mission/catalogs'))|where (type !~ ('microsoft.mission/approvals'))|where (type !~ ('microsoft.workloads/insights'))|where (type !~ ('microsoft.hanaonazure/sapmonitors'))|where (type !~ ('microsoft.cloudhealth/healthmodels'))|where (type !~ ('microsoft.connectedcache/enterprisemcccustomers/enterprisemcccachenodes'))|where not((type =~ ('microsoft.sql/servers')) and ((kind =~ ('v12.0,analytics'))))|where not((type =~ ('microsoft.sql/servers/databases')) and ((kind in~ ('system','v2.0,system','v12.0,system','v12.0,system,serverless','v12.0,user,datawarehouse,gen2,analytics'))))|project name,kind,status,resourceGroup,operatingSystem,defenderStatus,monitoringAgent,updateStatus,id,type,location,subscriptionId,SMI,tags|sort by (tolower(tostring(name))) asc
'@

    # execute the query
    Search-AzGraph -Query $Query
}