function Copy-ToArcMachine {
    <#
    .SYNOPSIS
    Copy-Item (via arc-ssh-proxy) proxy function for ARC machines.
    Enables you to copy item(s) to your ARC machine(s) via arc-ssh-proxy.

    .DESCRIPTION
    Copy-Item (via arc-ssh-proxy) proxy function for ARC machines.
    Enables you to copy item(s) to your ARC machine(s) via arc-ssh-proxy.

    .PARAMETER path
    Source path for the Copy-Item operation.

    .PARAMETER destination
    Destination path for the Copy-Item operation.

    The folder structure has to already exist on the ARC machine! It won't be created automatically.

    .PARAMETER connectionConfig
    PSCustomObject(s) where two properties have to be defined:
     - MachineName (ARC machine name)
     - ResourceGroupName (RG where the machine is located)

    Can be used to copy files against multiple ARC machines (unlike parameters 'machineName' and 'resourceGroupName' which can target only one).

    .PARAMETER resourceGroupName
    Nam of the resource group where the ARC machine is placed.

    If both 'resourceGroupName' and 'machineName' parameters aren't provided, you will be asked through GUI to pick some of the existing ARC machines interactively.

    .PARAMETER machineName
    Name of the ARC machine.

    If both 'resourceGroupName' and 'machineName' parameters aren't provided, you will be asked through GUI to pick some of the existing ARC machines interactively.

    .PARAMETER userName
    Name of the existing ARC-machine local user that will be used during SSH authentication.

    By default $_localAdminName or 'administrator' if empty.

    .PARAMETER machineType
    Type of the ARC machine.

    Possible values are: 'Microsoft.HybridCompute/machines', 'Microsoft.Compute/virtualMachines', 'Microsoft.ConnectedVMwarevSphere/virtualMachines', 'Microsoft.ScVmm/virtualMachines', 'Microsoft.AzureStackHCI/virtualMachines'

    Default value is 'Microsoft.HybridCompute/machines'.

    .PARAMETER privateKeyFile
    Path to the SSH private key file.

    Default will be used if not provided.

    .PARAMETER keyVault
    Name of the KeyVault where secret with private key is stored.

    If provided, stored private key will be used instead of a local one.
    It will be temporarily downloaded, used for the connection and then safely discarded.

    By default $_arcSSHKeyVaultName.

    .PARAMETER secretName
    Name of the secret where private key is stored.

    By default $_ITSSHSecretName.

    .EXAMPLE
    Copy-ToArcMachine -path "C:\tools\*" -destination "C:\tools\"

    Copy a folder content to specified ARC machine destination folder (such folder has to exists already!).

    .EXAMPLE
    Copy-ToArcMachine -path "C:\tools\procmon.exe" -destination "C:\tools\"

    Copy a file to specified ARC machine destination folder (such folder has to exists already!).

    .NOTES
    Prerequisites:
        1. SSH has to be configured & running on the ARC machine
            https://learn.microsoft.com/en-us/azure/azure-arc/servers/ssh-arc-overview?tabs=azure-powershell
            https://learn.microsoft.com/en-us/azure/azure-arc/servers/ssh-arc-powershell-remoting?tabs=azure-powershell
        2. Default connectivity endpoint must be created
            Invoke-AzRestMethod -Method put -Path /subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.HybridCompute/machines/<machineName>/providers/Microsoft.HybridConnectivity/endpoints/default?api-version=2023-03-15 -Payload '{"properties": {"type": "default"}}'
        3. Service Configuration in the Connectivity Endpoint on the Arc-enabled server must be set to allow SSH connection to a specific port
            Invoke-AzRestMethod -Method put -Path /subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.HybridCompute/machines/<machineName>/providers/Microsoft.HybridConnectivity/endpoints/default/serviceconfigurations/SSH?api-version=2023-03-15 -Payload '{"properties": {"serviceName": "SSH", "port": 22}}'
        4. Public SSH key has to be set on the server and private key has to be on your device

    Debugging:
        If you receive "Permission denied (publickey,keyboard-interactive)." it is bad/missing private key on your computer ('keyFile' parameter) or specified local username ('userName' parameter) doesn't match existing one.
    #>

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript( {
                if (Test-Path -Path $_) {
                    $true
                } else {
                    throw "'$_' doesn't exist"
                }
            })]
        [string] $path,

        [Parameter(Mandatory = $true)]
        [string] $destination,

        [Parameter(Mandatory = $true, ParameterSetName = "MultipleMachines")]
        [ValidateNotNullOrEmpty()]
        [PSCustomObject[]] $connectionConfig,

        [Parameter(Mandatory = $true, ParameterSetName = "OneMachine")]
        [ValidateNotNullOrEmpty()]
        [string] $resourceGroupName,

        [Parameter(Mandatory = $true, ParameterSetName = "OneMachine")]
        [ValidateNotNullOrEmpty()]
        [string] $machineName,

        [ValidateNotNullOrEmpty()]
        [string] $userName = $_localAdminName,

        [ValidateSet('Microsoft.HybridCompute/machines', 'Microsoft.Compute/virtualMachines', 'Microsoft.ConnectedVMwarevSphere/virtualMachines', 'Microsoft.ScVmm/virtualMachines', 'Microsoft.AzureStackHCI/virtualMachines')]
        [string] $machineType = 'Microsoft.HybridCompute/machines',

        [Parameter(Mandatory = $true, ParameterSetName = "PrivateKeyFile")]
        [ValidateScript( {
                if (Test-Path -Path $_ -PathType Leaf) {
                    $true
                } else {
                    throw "'$_' file doesn't exist"
                }
            })]
        [string] $privateKeyFile,

        [Parameter(Mandatory = $true, ParameterSetName = "KeyVault")]
        [string] $keyVault = $_arcSSHKeyVaultName,

        [Parameter(Mandatory = $true, ParameterSetName = "KeyVault")]
        [string] $secretName = $_ITSSHSecretName
    )

    #region checks
    if (!$userName) {
        $userName = "Administrator"
    }

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    if (($resourceGroupName -and !$machineName) -or (!$resourceGroupName -and $machineName)) {
        throw "Set both 'resourceGroupName' and 'machineName' parameters or none of them"
    }
    #endregion checks

    #region get missing parameter values
    if ($resourceGroupName -and $machineName) {
        $connectionConfig = [PSCustomObject]@{
            MachineName       = $machineName
            ResourceGroupName = $resourceGroupName
        }
    } else {
        while (!$connectionConfig) {
            if (!$arcMachineList) {
                $arcMachineList = Get-ArcMachineOverview

                if (!$arcMachineList) {
                    throw "Unable to find any ARC machines"
                }
            }

            $arcMachineList | select name, resourceGroup, status | Out-GridView -Title "Select ARC machine to connect" -OutputMode Multiple | % {
                $connectionConfig += [PSCustomObject]@{
                    MachineName       = $_.Name
                    ResourceGroupName = $_.ResourceGroup
                }
            }
        }
    }
    #endregion get missing parameter values

    #region get/create ARC session(s)
    $PSBoundParameters2 = @{
        ConnectionConfig = $connectionConfig
    }
    # add explicitly specified parameters if any
    $PSBoundParameters.GetEnumerator() | ? Key -In "UserName", "MachineType", "PrivateKeyFile", "KeyVault", "SecretName" | % {
        $PSBoundParameters2.($_.Key) = $_.Value
    }
    $arcSession = New-ArcPSSession @PSBoundParameters2
    #endregion get/create ARC session(s)

    # copy file(s) the command on the ARC machine(s)
    $arcSession | % {
        Write-Verbose "Copy items to the '$($_.ComputerName)'"
        Copy-Item -Path $path -Destination $destination -ToSession $_ -Force
    }
}

function Enter-ArcPSSession {
    <#
    .SYNOPSIS
    Enter interactive remote session to ARC machine via arc-ssh-proxy.

    .DESCRIPTION
    Enter interactive remote session to ARC machine via arc-ssh-proxy.

    1. SSH session via ARC agent will be created
    2. PS remote session via created SSH session will be made & entered

    Check NOTES for more details.

    .PARAMETER resourceGroupName
    Nam of the resource group where the ARC machine is placed.

    If both 'resourceGroupName' and 'machineName' parameters aren't provided, you will be asked through GUI to pick some of the existing ARC machines interactively.

    .PARAMETER machineName
    Name of the ARC machine.

    If both 'resourceGroupName' and 'machineName' parameters aren't provided, you will be asked through GUI to pick some of the existing ARC machines interactively.

    .PARAMETER userName
    Name of the existing ARC-machine local user that will be used during SSH authentication.

    By default $_localAdminName or 'administrator' if empty.

    .PARAMETER machineType
    Type of the ARC machine.

    Possible values are: 'Microsoft.HybridCompute/machines', 'Microsoft.Compute/virtualMachines', 'Microsoft.ConnectedVMwarevSphere/virtualMachines', 'Microsoft.ScVmm/virtualMachines', 'Microsoft.AzureStackHCI/virtualMachines'

    Default value is 'Microsoft.HybridCompute/machines'.

    .PARAMETER privateKeyFile
    Path to the SSH private key file.

    Default will be used if not provided.

    .PARAMETER keyVault
    Name of the KeyVault where secret with private key is stored.

    If provided, stored private key will be used instead of a local one.
    It will be temporarily downloaded, used for the connection and then safely discarded.

    By default $_arcSSHKeyVaultName.

    .PARAMETER secretName
    Name of the secret where private key is stored.

    By default $_ITSSHSecretName.

    .EXAMPLE
    Enter-ArcPSSession

    1. GUI with available ARC machines will be shown to pick one.
    2. Connection to the selected machine will be made via
        - SSH using local user 'administrator'
        - followed by creation of the remote PowerShell interactive session (through created SSH session).

    If $_arcSSHKeyVaultName and $_ITSSHSecretName are set then private SSH key will be temporarily retrieved from the selected KeyVault.
    Otherwise locally stored private key (c:\Users\<user>\.ssh\id_ecdsa) will be used.

    .EXAMPLE
    Enter-ArcPSSession -resourceGroupName arcMachines -machineName arcServer01

    1. Connection to the selected machine will be made via
        - SSH using local user 'administrator'
        - followed by creation of the remote PowerShell interactive session (through created SSH session).

    If $_arcSSHKeyVaultName and $_ITSSHSecretName are set then private SSH key will be temporarily retrieved from the selected KeyVault.
    Otherwise locally stored private key (c:\Users\<user>\.ssh\id_ecdsa) will be used.

    .EXAMPLE
    Enter-ArcPSSession -resourceGroupName arcMachines -machineName arcServer01 -privateKeyFile "C:\Users\admin\.ssh\id_ecdsa_servers" -userName root

    1. Connection to the selected machine will be made via
        - SSH using local user 'root'
        - followed by creation of the remote PowerShell interactive session (through created SSH session).

    Specified private SSH key will be used to authenticate.

    .EXAMPLE
    Enter-ArcPSSession -keyVault KeyVaultArc -secretName AAAAE2VjZHNhLXNoYTItbmlzdHAyNTY

    1. GUI with available ARC machines will be shown to pick one.
    2. Connection to the selected machine will be made via
        - SSH using local user 'administrator' and temporary private key (retrieved from the KeyVault)
        - followed by creation of the remote PowerShell interactive session (through created SSH session).

    The specified KeyVault and secret will be used to temporarily retrieve the SSH private key

    .NOTES
    Prerequisites:
        1. SSH has to be configured & running on the ARC machine
            https://learn.microsoft.com/en-us/azure/azure-arc/servers/ssh-arc-overview?tabs=azure-powershell
            https://learn.microsoft.com/en-us/azure/azure-arc/servers/ssh-arc-powershell-remoting?tabs=azure-powershell
        2. Default connectivity endpoint must be created
            Invoke-AzRestMethod -Method put -Path /subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.HybridCompute/machines/<machineName>/providers/Microsoft.HybridConnectivity/endpoints/default?api-version=2023-03-15 -Payload '{"properties": {"type": "default"}}'
        3. Service Configuration in the Connectivity Endpoint on the Arc-enabled server must be set to allow SSH connection to a specific port
            Invoke-AzRestMethod -Method put -Path /subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.HybridCompute/machines/<machineName>/providers/Microsoft.HybridConnectivity/endpoints/default/serviceconfigurations/SSH?api-version=2023-03-15 -Payload '{"properties": {"serviceName": "SSH", "port": 22}}'
        4. Public SSH key has to be set on the server and private key has to be on your device

    Debugging:
        If you receive "Permission denied (publickey,keyboard-interactive)." it is bad/missing private key on your computer ('privateKeyFile' parameter) or specified local username ('userName' parameter) doesn't match existing one.
    #>

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [ValidateNotNullOrEmpty()]
        [string] $resourceGroupName,

        [ValidateNotNullOrEmpty()]
        [string] $machineName,

        [ValidateNotNullOrEmpty()]
        [string] $userName = $_localAdminName,

        [ValidateSet('Microsoft.HybridCompute/machines', 'Microsoft.Compute/virtualMachines', 'Microsoft.ConnectedVMwarevSphere/virtualMachines', 'Microsoft.ScVmm/virtualMachines', 'Microsoft.AzureStackHCI/virtualMachines')]
        [string] $machineType = 'Microsoft.HybridCompute/machines',

        [Parameter(Mandatory = $true, ParameterSetName = "PrivateKeyFile")]
        [ValidateScript( {
                if (Test-Path -Path $_ -PathType Leaf) {
                    $true
                } else {
                    throw "'$_' file doesn't exist"
                }
            })]
        [string] $privateKeyFile,

        [Parameter(Mandatory = $true, ParameterSetName = "KeyVault")]
        [string] $keyVault = $_arcSSHKeyVaultName,

        [Parameter(Mandatory = $true, ParameterSetName = "KeyVault")]
        [string] $secretName = $_ITSSHSecretName
    )

    #region checks
    if (!$userName) {
        $userName = "Administrator"
    }

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    if (($resourceGroupName -and !$machineName) -or (!$resourceGroupName -and $machineName)) {
        throw "Set both 'resourceGroupName' and 'machineName' parameters or none of them"
    }
    #endregion checks

    #region get missing parameter values
    while (!$resourceGroupName -and !$machineName) {
        if (!$arcMachineList) {
            $arcMachineList = Get-ArcMachineOverview
        }

        $selected = $arcMachineList | select name, resourceGroup, status | Out-GridView -Title "Select ARC machine to connect" -OutputMode Single

        $resourceGroupName = $selected.resourceGroup
        $machineName = $selected.name
    }
    #endregion get missing parameter values

    #region get/create ARC session(s)
    $PSBoundParameters2 = @{
        resourceGroupName = $resourceGroupName
        machineName       = $machineName
    }
    # add explicitly specified parameters if any
    $PSBoundParameters.GetEnumerator() | ? Key -In "UserName", "MachineType", "PrivateKeyFile", "KeyVault", "SecretName" | % {
        $PSBoundParameters2.($_.Key) = $_.Value
    }
    $arcSession = New-ArcPSSession @PSBoundParameters2
    #endregion get/create ARC session(s)

    #TODO any benefit of using Enter-AzVM?
    Enter-PSSession -Session $arcSession
}

function Get-ARCExtensionAvailableVersion {
    <#
    .SYNOPSIS
    Returns all available versions of selected ARC extension.

    .DESCRIPTION
    Returns all available versions of selected ARC extension.

    .PARAMETER location
    Extension ARC machine location.
    Because extensions are rolled out gradually, different locations can show different results.

    .PARAMETER publisherName
    Extension publisher name.

    .PARAMETER type
    Extension type/name.

    .EXAMPLE
    # to get all extensions
    # Get-ARCExtensionOverview

    Get-ARCExtensionAvailableVersion -Location westeurope -PublisherName Microsoft.Compute -Type CustomScriptExtension
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $location,

        [Parameter(Mandatory = $true)]
        [string] $publisherName,

        [Parameter(Mandatory = $true)]
        [Alias("Name")]
        [string] $type
    )

    Get-AzVMExtensionImage -Location $location -PublisherName $publisherName -Type $type | Sort-Object -Property { [version]$_.version }
}

function Get-ARCExtensionOverview {
    <#
    .SYNOPSIS
    Returns overview of all installed ARC extensions.

    .DESCRIPTION
    Returns overview of all installed ARC extensions.

    .EXAMPLE
    Get-ARCExtensionOverview

    Returns overview of all installed ARC extensions.
    #>

    [CmdletBinding()]
    param()

    if (!(Get-Module Az.ResourceGraph) -and !(Get-Module Az.ResourceGraph -ListAvailable)) {
        throw "Module Az.ResourceGraph is missing. Function $($MyInvocation.MyCommand) cannot continue"
    }

    $query = @'
resources
| where type =~ "microsoft.hybridcompute/machines/extensions"
'@
    # | project id, publisher = properties.publisher, type = properties.type, automaticUpgradesEnabled = properties.enableAutomaticUpgrade

    # execute the query
    Search-AzGraph -Query $Query
}

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

function Invoke-ArcCommand {
    <#
    .SYNOPSIS
    Invoke-Command (via arc-ssh-proxy) proxy functions for ARC machines.
    Enables you to run command against your ARC machines via arc-ssh-proxy.

    .DESCRIPTION
    Invoke-Command (via arc-ssh-proxy) proxy functions for ARC machines.
    Enables you to run command against your ARC machines via arc-ssh-proxy.

    .PARAMETER connectionConfig
    PSCustomObject(s) where two properties have to be defined:
     - MachineName (ARC machine name)
     - ResourceGroupName (RG where the machine is located)

    Can be used to invoke command against multiple ARC machines (unlike parameters 'machineName' and 'resourceGroupName' which can target only one)

    .PARAMETER scriptBlock
    Scriptblock to run on ARC machine(s).

    .PARAMETER argumentList
    Argument list that should be passed to scriptBlock.

    .PARAMETER resourceGroupName
    Nam of the resource group where the ARC machine is placed.

    If both 'resourceGroupName' and 'machineName' parameters aren't provided, you will be asked through GUI to pick some of the existing ARC machines interactively.

    .PARAMETER machineName
    Name of the ARC machine.

    If both 'resourceGroupName' and 'machineName' parameters aren't provided, you will be asked through GUI to pick some of the existing ARC machines interactively.

    .PARAMETER userName
    Name of the existing ARC-machine local user that will be used during SSH authentication.

    By default $_localAdminName or 'administrator' if empty.

    .PARAMETER machineType
    Type of the ARC machine.

    Possible values are: 'Microsoft.HybridCompute/machines', 'Microsoft.Compute/virtualMachines', 'Microsoft.ConnectedVMwarevSphere/virtualMachines', 'Microsoft.ScVmm/virtualMachines', 'Microsoft.AzureStackHCI/virtualMachines'

    Default value is 'Microsoft.HybridCompute/machines'.

    .PARAMETER privateKeyFile
    Path to the SSH private key file.

    Default will be used if not provided.

    .PARAMETER keyVault
    Name of the KeyVault where secret with private key is stored.

    If provided, stored private key will be used instead of a local one.
    It will be temporarily downloaded, used for the connection and then safely discarded.

    By default $_arcSSHKeyVaultName.

    .PARAMETER secretName
    Name of the secret where private key is stored.

    By default $_ITSSHSecretName.

    .EXAMPLE
    Invoke-ArcCommand -scriptBlock {hostname} -Verbose

    Run specified command against interactively selected arc machine(s) via arc-ssh-proxy session(s).

    .EXAMPLE
    Invoke-ArcCommand -scriptBlock {hostname} -machineName 'ARC-01' -resourceGroupName 'RG' -Verbose

    Run specified command against specified ARC machine via arc-ssh-proxy session(s).

    .EXAMPLE
    $connectionConfig = @(
        [PSCustomObject]@{
            MachineName       = 'ARC-01'
            ResourceGroupName = 'RG'
        },

        [PSCustomObject]@{
            MachineName       = 'ARC-02'
            ResourceGroupName = 'RG'
        },

        [PSCustomObject]@{
            MachineName       = 'ARC-B13'
            ResourceGroupName = 'RGXXX'
        }
    )

    Invoke-ArcCommand -scriptBlock {hostname} -connectionConfig $connectionConfig -Verbose

    Run specified command against ARC machines specified in the $connectionConfig via arc-ssh-proxy session(s).

    .NOTES
    Prerequisites:
        1. SSH has to be configured & running on the ARC machine
            https://learn.microsoft.com/en-us/azure/azure-arc/servers/ssh-arc-overview?tabs=azure-powershell
            https://learn.microsoft.com/en-us/azure/azure-arc/servers/ssh-arc-powershell-remoting?tabs=azure-powershell
        2. Default connectivity endpoint must be created
            Invoke-AzRestMethod -Method put -Path /subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.HybridCompute/machines/<machineName>/providers/Microsoft.HybridConnectivity/endpoints/default?api-version=2023-03-15 -Payload '{"properties": {"type": "default"}}'
        3. Service Configuration in the Connectivity Endpoint on the Arc-enabled server must be set to allow SSH connection to a specific port
            Invoke-AzRestMethod -Method put -Path /subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.HybridCompute/machines/<machineName>/providers/Microsoft.HybridConnectivity/endpoints/default/serviceconfigurations/SSH?api-version=2023-03-15 -Payload '{"properties": {"serviceName": "SSH", "port": 22}}'
        4. Public SSH key has to be set on the server and private key has to be on your device

    Debugging:
        If you receive "Permission denied (publickey,keyboard-interactive)." it is bad/missing private key on your computer ('keyFile' parameter) or specified local username ('userName' parameter) doesn't match existing one.
    #>

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "MultipleMachines")]
        [ValidateNotNullOrEmpty()]
        [PSCustomObject[]] $connectionConfig,

        [Parameter(Mandatory = $true)]
        [ScriptBlock] $scriptBlock,

        $argumentList,

        [Parameter(Mandatory = $true, ParameterSetName = "OneMachine")]
        [ValidateNotNullOrEmpty()]
        [string] $resourceGroupName,

        [Parameter(Mandatory = $true, ParameterSetName = "OneMachine")]
        [ValidateNotNullOrEmpty()]
        [string] $machineName,

        [ValidateNotNullOrEmpty()]
        [string] $userName = $_localAdminName,

        [ValidateSet('Microsoft.HybridCompute/machines', 'Microsoft.Compute/virtualMachines', 'Microsoft.ConnectedVMwarevSphere/virtualMachines', 'Microsoft.ScVmm/virtualMachines', 'Microsoft.AzureStackHCI/virtualMachines')]
        [string] $machineType = 'Microsoft.HybridCompute/machines',

        [Parameter(Mandatory = $true, ParameterSetName = "PrivateKeyFile")]
        [ValidateScript( {
                if (Test-Path -Path $_ -PathType Leaf) {
                    $true
                } else {
                    throw "'$_' file doesn't exist"
                }
            })]
        [string] $privateKeyFile,

        [Parameter(Mandatory = $true, ParameterSetName = "KeyVault")]
        [string] $keyVault = $_arcSSHKeyVaultName,

        [Parameter(Mandatory = $true, ParameterSetName = "KeyVault")]
        [string] $secretName = $_ITSSHSecretName
    )

    #region checks
    if (!$userName) {
        $userName = "Administrator"
    }

    if ($connectionConfig) {
        foreach ($config in $connectionConfig) {
            $property = $config | Get-Member -MemberType NoteProperty | select -ExpandProperty Name

            if ($config.count -ne 2 -or ('MachineName' -notin $property -or 'ResourceGroupName' -notin $property)) {
                throw "Connection object isn't in the correct format. It has to be PSCustomObject with two properties: 'MachineName' and 'ResourceGroupName'"
            }
        }
    }

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    if (($resourceGroupName -and !$machineName) -or (!$resourceGroupName -and $machineName)) {
        throw "Set both 'resourceGroupName' and 'machineName' parameters or none of them"
    }
    #endregion checks

    #region get missing parameter values
    if ($resourceGroupName -and $machineName) {
        $connectionConfig = [PSCustomObject]@{
            MachineName       = $machineName
            ResourceGroupName = $resourceGroupName
        }
    } else {
        while (!$connectionConfig) {
            if (!$arcMachineList) {
                $arcMachineList = Get-ArcMachineOverview

                if (!$arcMachineList) {
                    throw "Unable to find any ARC machines"
                }
            }

            $arcMachineList | select name, resourceGroup, status | Out-GridView -Title "Select ARC machine to connect" -OutputMode Multiple | % {
                $connectionConfig += [PSCustomObject]@{
                    MachineName       = $_.Name
                    ResourceGroupName = $_.ResourceGroup
                }
            }
        }
    }
    #endregion get missing parameter values

    #region get/create ARC session(s)
    $PSBoundParameters2 = @{
        ConnectionConfig = $connectionConfig
    }
    # add explicitly specified parameters if any
    $PSBoundParameters.GetEnumerator() | ? Key -In "UserName", "MachineType", "PrivateKeyFile", "KeyVault", "SecretName" | % {
        $PSBoundParameters2.($_.Key) = $_.Value
    }
    $arcSession = New-ArcPSSession @PSBoundParameters2
    #endregion get/create ARC session(s)

    # invoke the command on the ARC machine(s)
    $param = @{
        Session     = $arcSession
        ScriptBlock = $scriptBlock
    }
    if ($argumentList) {
        $param.ArgumentList = $argumentList
    }

    Invoke-Command @param
}

function Invoke-ArcRDP {
    <#
    .SYNOPSIS
    RDP to ARC machine via arc-ssh-proxy.

    .DESCRIPTION
    RDP to ARC machine via arc-ssh-proxy.

    1. SSH session via ARC agent will be created
    2. PS remote session via created SSH session will be made & entered

    Check NOTES for more details.

    .PARAMETER resourceGroupName
    Name of the resource group where the ARC machine is placed.

    If both 'resourceGroupName' and 'machineName' parameters aren't provided, you will be asked through GUI to pick some of the existing ARC machines interactively.

    .PARAMETER machineName
    Name of the ARC machine.

    If both 'resourceGroupName' and 'machineName' parameters aren't provided, you will be asked through GUI to pick some of the existing ARC machines interactively.

    .PARAMETER userName
    Name of the existing ARC-machine local user that will be used during SSH authentication.

    By default $_localAdminName or 'administrator' if empty.

    .PARAMETER privateKeyFile
    Path to the SSH private key file.

    Default will be used if not provided (typically in '<userprofile>\.ssh').

    .PARAMETER keyVault
    Name of the KeyVault where secret with private key is stored.

    If provided, stored private key will be used instead of a local one.
    It will be temporarily downloaded, used for the connection and then safely discarded.

    By default $_arcSSHKeyVaultName.

    .PARAMETER secretName
    Name of the secret where private key is stored.

    By default $_ITSSHSecretName.

    .PARAMETER rdpCredential
    Credentials that should be used for RDP.

    .PARAMETER rdpUserName
    UserName that should be used for RDP.

    By default 'administrator' (default in Enter-AzVM).

    .EXAMPLE
    Invoke-ArcRDP -resourceGroupName arcMachines -machineName arcServer01

    Connect to arcServer01 as local user 'administrator' via ssh-tunneled RDP.

    .EXAMPLE
    Invoke-ArcRDP -resourceGroupName arcMachines -machineName arcServer01 -privateKeyFile "C:\Users\admin\.ssh\id_ecdsa_servers"

    Connect to arcServer01 as local user 'administrator' using specified private key via ssh-tunneled RDP.

    .EXAMPLE
    Invoke-ArcRDP

    1. GUI with available ARC machines will be shown to pick one.
    2. Connection to the selected machine will be made via
        - SSH using local user 'administrator'
        - followed by RDP connection as 'administrator' (tunneled through created SSH session).

    If $_arcSSHKeyVaultName and $_ITSSHSecretName are set then private ssh key will be temporarily retrieved from the selected KeyVault.
    Otherwise locally stored private key (c:\Users\<user>\.ssh\id_ecdsa) will be used.

    .NOTES
    Prerequisites:
        1. SSH has to be configured & running on the ARC machine
            https://learn.microsoft.com/en-us/azure/azure-arc/servers/ssh-arc-overview?tabs=azure-powershell
            https://learn.microsoft.com/en-us/azure/azure-arc/servers/ssh-arc-powershell-remoting?tabs=azure-powershell
        2. Default connectivity endpoint must be created
            Invoke-AzRestMethod -Method put -Path /subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.HybridCompute/machines/<machineName>/providers/Microsoft.HybridConnectivity/endpoints/default?api-version=2023-03-15 -Payload '{"properties": {"type": "default"}}'
        3. Service Configuration in the Connectivity Endpoint on the Arc-enabled server must be set to allow SSH connection to a specific port
            Invoke-AzRestMethod -Method put -Path /subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.HybridCompute/machines/<machineName>/providers/Microsoft.HybridConnectivity/endpoints/default/serviceconfigurations/SSH?api-version=2023-03-15 -Payload '{"properties": {"serviceName": "SSH", "port": 22}}'
        4. Public SSH key has to be set on the server and private key has to be on your device

    Debugging:
        If you receive:
            - "Permission denied (publickey,keyboard-interactive)." it is bad/missing private key on your computer ('privateKeyFile' parameter) or specified local username ('userName' parameter) doesn't match existing one.
            - "no such identity: <pathToSSHPrivateKey>: No such file or directory" and you are asked to enter credentials. SSH authentication was made after the private key was automatically deleted. Try to run the function again or increase the value in $cleanupWaitTime variable.
    #>

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [ValidateNotNullOrEmpty()]
        [string] $resourceGroupName,

        [ValidateNotNullOrEmpty()]
        [string] $machineName,

        [ValidateNotNullOrEmpty()]
        [string] $userName = $_localAdminName,

        [Parameter(Mandatory = $true, ParameterSetName = "PrivateKeyFile")]
        [ValidateScript( {
                if (Test-Path -Path $_ -PathType Leaf) {
                    $true
                } else {
                    throw "'$_' file doesn't exist"
                }
            })]
        [string] $privateKeyFile,

        [Parameter(Mandatory = $true, ParameterSetName = "KeyVault")]
        [string] $keyVault = $_arcSSHKeyVaultName,

        [Parameter(Mandatory = $true, ParameterSetName = "KeyVault")]
        [string] $secretName = $_ITSSHSecretName,

        [System.Management.Automation.PSCredential] $rdpCredential,

        [string] $rdpUserName
    )

    #region checks
    if ($rdpCredential -and $rdpUserName) {
        throw "Specify 'rdpUserName' or 'rdpCredential' parameter. Not both."
    }

    if (!$userName) {
        $userName = "Administrator"
    }

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    if (($resourceGroupName -and !$machineName) -or (!$resourceGroupName -and $machineName)) {
        throw "Set both 'resourceGroupName' and 'machineName' parameters or none of them"
    }
    #endregion checks

    #region get missing parameter values
    while (!$resourceGroupName -and !$machineName) {
        if (!$arcMachineList) {
            $arcMachineList = Get-ArcMachineOverview
        }

        $selected = $arcMachineList | select name, resourceGroup, status | Out-GridView -Title "Select ARC machine to connect" -OutputMode Single

        $resourceGroupName = $selected.resourceGroup
        $machineName = $selected.name
    }
    #endregion get missing parameter values

    #region RDP autologon
    if ($rdpCredential -or $rdpUserName) {
        if ($rdpCredential) {
            $user = $rdpCredential.UserName
            $password = $rdpCredential.GetNetworkCredential().Password
        } elseif ($rdpUserName) {
            $user = $rdpUserName
            $password = "dummy" # user will be asked to enter the correct password
        }

        # save user login and password for autologon using cmdkey (to store it in Cred. Manager)
        $computer = "localhost"
        Write-Verbose "Saving credentials for host: $computer user: $user to CredMan"
        $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
        $Process = New-Object System.Diagnostics.Process
        $ProcessInfo.FileName = "$($env:SystemRoot)\system32\cmdkey.exe"
        $ProcessInfo.Arguments = "/generic:TERMSRV/$computer /user:$user /pass:`"$password`""
        $ProcessInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $ProcessInfo.RedirectStandardOutput = ".\NUL"
        $ProcessInfo.UseShellExecute = $false
        $Process.StartInfo = $ProcessInfo
        [void]$Process.Start()
        $null = $Process.WaitForExit()

        if ($Process.ExitCode -ne 0) {
            throw 'Unable to add credentials to Cred. Manageru, but just for sure, check it.'
        }
    }
    #endregion RDP autologon

    # download SSH private key from the KeyVault
    if ($keyVault -and $secretName) {
        # private key saved in the KeyVault should be used for authentication instead of existing local private key

        # remove the parameter path validation
        (Get-Variable privateKeyFile).Attributes.Clear()

        # where the key will be saved
        $privateKeyFile = Join-Path $env:TEMP ("spk_" + $secretName)

        # saving private key to temp file
        Write-Verbose "Saving SSH private key to the '$privateKeyFile'"
        Get-AzureKeyVaultMVSecret -name $secretName -vaultName $keyVault -ErrorAction Stop | Out-File $privateKeyFile -Force
    }

    #region cleanup
    $cleanupWaitTime = 10

    if ($keyVault -and $secretName) {
        # remove the private key ASAP
        Write-Verbose "SSH key will be removed in $cleanupWaitTime seconds"
        $null = Start-Job -Name "cleanup_pvk" -ScriptBlock {
            param ($privateKeyFile, $cleanupWaitTime)

            # we need to wait with deleting the file until function Enter-AzVM has been executed
            Start-Sleep $cleanupWaitTime

            #region helper functions
            function Remove-FileSecure {
                <#
            .SYNOPSIS
            Function for secure overwrite and deletion of file(s).
            It will overwrite file(s) in a secure way by using a cryptographically strong sequence of random values using .NET functions.

            .DESCRIPTION
            Function for secure overwrite and deletion of file(s).
            It will overwrite file(s) in a secure way by using a cryptographically strong sequence of random values using .NET functions.

            .PARAMETER File
            Path to file that should be overwritten.

            .OUTPUTS
            Boolean. True if successful else False.

            .NOTES
            https://gallery.technet.microsoft.com/scriptcenter/Secure-File-Remove-by-110adb68
            #>

                [CmdletBinding()]
                [OutputType([boolean])]
                param(
                    [Parameter(Mandatory = $true, ValueFromPipeline = $true )]
                    [System.IO.FileInfo] $File
                )

                BEGIN {
                    $r = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
                }

                PROCESS {
                    $retObj = $null

                    if ((Test-Path $file -PathType Leaf) -and $pscmdlet.ShouldProcess($file)) {
                        $f = $file
                        if ( !($f -is [System.IO.FileInfo]) ) {
                            $f = New-Object System.IO.FileInfo($file)
                        }

                        $l = $f.length

                        $s = $f.OpenWrite()

                        try {
                            $w = New-Object system.diagnostics.stopwatch
                            $w.Start()

                            [long]$i = 0
                            $b = New-Object byte[](1024 * 1024)
                            while ( $i -lt $l ) {
                                $r.GetBytes($b)

                                $rest = $l - $i

                                if ( $rest -gt (1024 * 1024) ) {
                                    $s.Write($b, 0, $b.length)
                                    $i += $b.LongLength
                                } else {
                                    $s.Write($b, 0, $rest)
                                    $i += $rest
                                }
                            }
                            $w.Stop()
                        } finally {
                            $s.Close()

                            $null = Remove-Item $f.FullName -Force -Confirm:$false -ErrorAction Stop
                        }
                    } else {
                        Write-Warning "$($f.FullName) wasn't found"
                        return $false
                    }

                    return $true
                }
            }
            #endregion helper functions

            Remove-FileSecure $privateKeyFile
        } -ArgumentList $privateKeyFile, $cleanupWaitTime
    }

    if ($rdpCredential -or $rdpUserName) {
        # remove saved credentials from Cred. Manager ASAP
        Write-Verbose "RDP credentials will be removed from CredMan in $cleanupWaitTime seconds"
        $null = Start-Job -Name "cleanup_rdp" -ScriptBlock {
            param ($computer, $cleanupWaitTime)

            # we need to wait with deleting the credentials until function Enter-AzVM has been executed
            Start-Sleep $cleanupWaitTime

            $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
            $Process = New-Object System.Diagnostics.Process
            $ProcessInfo.FileName = "$($env:SystemRoot)\system32\cmdkey.exe"
            $ProcessInfo.Arguments = "/delete:TERMSRV/$computer"
            $ProcessInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
            $ProcessInfo.RedirectStandardOutput = ".\NUL"
            $ProcessInfo.UseShellExecute = $false
            $Process.StartInfo = $ProcessInfo
            [void]$Process.Start()
            $null = $Process.WaitForExit()

            if ($Process.ExitCode -ne 0) {
                throw "Removal of RDP credentials for host '$computer' failed. Remove them manually from Credential Manager!"
            }
        } -ArgumentList $computer, $cleanupWaitTime
    }
    #endregion cleanup

    $param = @{
        ResourceGroupName = $resourceGroupName
        Name              = $machineName
        LocalUser         = $userName
        Rdp               = $true
    }
    if ($privateKeyFile) {
        $param.PrivateKeyFile = $privateKeyFile
    }
    Enter-AzVM @param -Verbose
}

function New-ArcPSSession {
    <#
    .SYNOPSIS
    Enter interactive remote session to ARC machine via arc-ssh-proxy.

    .DESCRIPTION
    Enter interactive remote session to ARC machine via arc-ssh-proxy.

    1. SSH session via ARC agent will be created
    2. PS remote session via created SSH session will be made

    Check NOTES for more details.

    .PARAMETER connectionConfig
    PSCustomObject(s) where two properties have to be defined:
     - MachineName (ARC machine name)
     - ResourceGroupName (RG where the machine is located)

    Can be used to invoke command against multiple ARC machines (unlike parameters 'machineName' and 'resourceGroupName' which can target only one)

    .PARAMETER resourceGroupName
    Nam of the resource group where the ARC machine is placed.

    If both 'resourceGroupName' and 'machineName' parameters aren't provided, you will be asked through GUI to pick some of the existing ARC machines interactively.

    .PARAMETER machineName
    Name of the ARC machine.

    If both 'resourceGroupName' and 'machineName' parameters aren't provided, you will be asked through GUI to pick some of the existing ARC machines interactively.

    .PARAMETER userName
    Name of the existing ARC-machine local user that will be used during SSH authentication.

    By default $_localAdminName or 'administrator' if empty.

    .PARAMETER machineType
    Type of the ARC machine.

    Possible values are: 'Microsoft.HybridCompute/machines', 'Microsoft.Compute/virtualMachines', 'Microsoft.ConnectedVMwarevSphere/virtualMachines', 'Microsoft.ScVmm/virtualMachines', 'Microsoft.AzureStackHCI/virtualMachines'

    Default value is 'Microsoft.HybridCompute/machines'.

    .PARAMETER privateKeyFile
    Path to the SSH private key file.

    Default will be used if not provided.

    .PARAMETER keyVault
    Name of the KeyVault where secret with private key is stored.

    If provided, stored private key will be used instead of a local one.
    It will be temporarily downloaded, used for the connection and then safely discarded.

    By default $_arcSSHKeyVaultName.

    .PARAMETER secretName
    Name of the secret where private key is stored.

    By default $_ITSSHSecretName.

    .EXAMPLE
    $session = New-ArcPSSession

    1. GUI with available ARC machines will be shown to pick one.
    2. Connection to the selected machine will be made via
        - SSH using local user 'Administrator'
        - followed by creation of the remote PowerShell session (through created SSH session).

    If $_arcSSHKeyVaultName and $_ITSSHSecretName are set then private SSH key will be temporarily retrieved from the selected KeyVault.
    Otherwise locally stored private key (c:\Users\<user>\.ssh\id_ecdsa) will be used.

    .EXAMPLE
    $session = New-ArcPSSession -resourceGroupName arcMachines -machineName arcServer01

    1. Connection to the specified machine will be made via
        - SSH using local user 'Administrator'
        - followed by creation of the remote PowerShell session (through created SSH session).

    If $_arcSSHKeyVaultName and $_ITSSHSecretName are set then private SSH key will be temporarily retrieved from the selected KeyVault.
    Otherwise locally stored private key (c:\Users\<user>\.ssh\id_ecdsa) will be used.


    .EXAMPLE
    $session = New-ArcPSSession -resourceGroupName arcMachines -machineName arcServer01 -privateKeyFile "C:\Users\admin\.ssh\id_ecdsa_servers"

    1. Connection to the selected machine will be made via
        - SSH using local user 'Administrator'
        - followed by creation of the remote PowerShell session (through created SSH session).

    Specified private SSH key will be used to authenticate.

    .EXAMPLE
    $connectionConfig = @(
        [PSCustomObject]@{
            MachineName       = 'testo-noad-srv'
            ResourceGroupName = 'ARC_Machines'
        },

        [PSCustomObject]@{
            MachineName       = 'WIN-OQ0E0OHUK4H'
            ResourceGroupName = 'ARC_Machines'
        }
    )

    $arcSessions = New-ArcPSSession -connectionConfig $connectionConfig

    1. Connection to the specified machines will be made via
        - SSH using local user 'Administrator'
        - followed by creation of the remote PowerShell sessions (through created SSH session).

    If $_arcSSHKeyVaultName and $_ITSSHSecretName are set then private SSH key will be temporarily retrieved from the selected KeyVault.
    Otherwise locally stored private key (c:\Users\<user>\.ssh\id_ecdsa) will be used.

    .NOTES
    Prerequisites:
        1. SSH has to be configured & running on the ARC machine
            https://learn.microsoft.com/en-us/azure/azure-arc/servers/ssh-arc-overview?tabs=azure-powershell
            https://learn.microsoft.com/en-us/azure/azure-arc/servers/ssh-arc-powershell-remoting?tabs=azure-powershell
        2. Default connectivity endpoint must be created
            Invoke-AzRestMethod -Method put -Path /subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.HybridCompute/machines/<machineName>/providers/Microsoft.HybridConnectivity/endpoints/default?api-version=2023-03-15 -Payload '{"properties": {"type": "default"}}'
        3. Service Configuration in the Connectivity Endpoint on the Arc-enabled server must be set to allow SSH connection to a specific port
            Invoke-AzRestMethod -Method put -Path /subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.HybridCompute/machines/<machineName>/providers/Microsoft.HybridConnectivity/endpoints/default/serviceconfigurations/SSH?api-version=2023-03-15 -Payload '{"properties": {"serviceName": "SSH", "port": 22}}'
        4. Public SSH key has to be set on the server and private key has to be on your device

    Debugging:
        If you receive "Permission denied (publickey,keyboard-interactive)." it is bad/missing private key on your computer ('privateKeyFile' parameter) or specified local username ('userName' parameter) doesn't match existing one.
    #>

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "MultipleMachines")]
        [ValidateNotNullOrEmpty()]
        [PSCustomObject[]] $connectionConfig,

        [Parameter(Mandatory = $true, ParameterSetName = "OneMachine")]
        [ValidateNotNullOrEmpty()]
        [string] $resourceGroupName,

        [Parameter(Mandatory = $true, ParameterSetName = "OneMachine")]
        [ValidateNotNullOrEmpty()]
        [string[]] $machineName,

        [ValidateNotNullOrEmpty()]
        [string] $userName = $_localAdminName,

        [ValidateSet('Microsoft.HybridCompute/machines', 'Microsoft.Compute/virtualMachines', 'Microsoft.ConnectedVMwarevSphere/virtualMachines', 'Microsoft.ScVmm/virtualMachines', 'Microsoft.AzureStackHCI/virtualMachines')]
        [string] $machineType = 'Microsoft.HybridCompute/machines',

        [Parameter(Mandatory = $true, ParameterSetName = "PrivateKeyFile")]
        [ValidateScript( {
                if (Test-Path -Path $_ -PathType Leaf) {
                    $true
                } else {
                    throw "'$_' file doesn't exist"
                }
            })]
        [string] $privateKeyFile,

        [Parameter(Mandatory = $true, ParameterSetName = "KeyVault")]
        [string] $keyVault = $_arcSSHKeyVaultName,

        [Parameter(Mandatory = $true, ParameterSetName = "KeyVault")]
        [string] $secretName = $_ITSSHSecretName
    )

    #region checks
    if (!$userName) {
        $userName = "Administrator"
    }

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }
    #endregion checks

    #region get missing parameter values
    if ($resourceGroupName -and $machineName) {
        $connectionConfig = [PSCustomObject]@{
            MachineName       = $machineName
            ResourceGroupName = $resourceGroupName
        }
    } else {
        while (!$connectionConfig) {
            if (!$arcMachineList) {
                $arcMachineList = Get-ArcMachineOverview

                if (!$arcMachineList) {
                    throw "Unable to find any ARC machines"
                }
            }

            $arcMachineList | select name, resourceGroup, status | Out-GridView -Title "Select ARC machine to connect" -OutputMode Multiple | % {
                $connectionConfig += [PSCustomObject]@{
                    MachineName       = $_.Name
                    ResourceGroupName = $_.ResourceGroup
                }
            }
        }
    }
    #endregion get missing parameter values

    #region helper functions
    function Get-ArcPSSession {
        <#
        .SYNOPSIS
        Function returns opened SSH PSSession for selected ARC machine.

        .DESCRIPTION
        Function returns opened SSH PSSession for selected ARC machine.
        It uses specific session name format when searching for the sessions (I create ARC sessions with name "$resourceGroupName_$machineName").

        .PARAMETER resourceGroupName
        Resource group name where ARC machine is located.

        .PARAMETER machineName
        Name of the ARC machine.

        .PARAMETER PSSessionList
        If provided, just specified sessions will be searched for instead of retrieval of all existing sessions.

        .EXAMPLE
        $session = Get-ArcPSSession -resourceGroupName $resourceGroupName -machineName $machineName

        Returns existing usable SSH PSSession for selected ARC machine.
        .EXAMPLE
        $existingSession = Get-PSSession | ? { $_.Transport -eq "SSH" -and $_.State -eq "Opened" } | Group-Object -Property Name | % { $_.Group | select -First 1 }
        $session = Get-ArcPSSession -resourceGroupName $resourceGroupName -machineName $machineName -PSSessionList $existingSession

        Returns PSSession matching selected ARC machine from the given session list.
        #>

        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string] $resourceGroupName,

            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string] $machineName,

            [System.Management.Automation.Runspaces.PSSession[]] $PSSessionList
        )

        if ($PSSessionList) {
            $existingSession = $PSSessionList
        } else {
            $existingSession = Get-PSSession | ? { $_.Transport -eq "SSH" -and $_.State -eq "Opened" } | Group-Object -Property Name | % { $_.Group | select -First 1 }
        }

        $existingSession | ? { $_.ComputerName -eq $machineName -and $_.Name -eq "$resourceGroupName`_$machineName" }
    }
    #endregion helper functions

    try {
        # get existing usable SSH sessions
        $existingSession = Get-PSSession | ? { $_.Transport -eq "SSH" -and $_.State -eq "Opened" } | Group-Object -Property Name | % { $_.Group | select -First 1 }

        #region determine if some session needs to be created
        $missingSession = $false

        foreach ($config in $connectionConfig) {
            [string]$machineName = $config.MachineName
            $resourceGroupName = $config.ResourceGroupName

            if (!(Get-ArcPSSession -resourceGroupName $resourceGroupName -machineName $machineName -PSSessionList $existingSession)) {
                $missingSession = $true
                break
            }
        }
        #endregion determine if some session needs to be created

        if ($missingSession) {
            # use KeyVault SSH private key instead of the local one
            if ($keyVault -and $secretName) {
                # private key saved in the KeyVault should be used for authentication instead of existing local private key

                # remove the parameter path validation
                (Get-Variable privateKeyFile).Attributes.Clear()

                # where the key will be saved
                $privateKeyFile = Join-Path $env:TEMP ("spk_" + $secretName)

                # saving private key to temp file
                Write-Verbose "Saving SSH private key to the '$privateKeyFile'"
                Get-AzureKeyVaultMVSecret -name $secretName -vaultName $keyVault -ErrorAction Stop | Out-File $privateKeyFile -Force
            } else {
                Write-Verbose "Default private SSH key will be used"
            }
        } else {
            Write-Verbose "All required sessions already exist"
        }

        #region return usable and/or newly created sessions
        # create ssh proxy config for missing sessions
        $connectionConfig | % -Parallel {
            $config = $_
            [string]$machineName = $config.MachineName
            $resourceGroupName = $config.ResourceGroupName
            $configPath = "$env:temp\sshconfig_$resourceGroupName`_$machineName.config"

            $VerbosePreference = $using:VerbosePreference

            $exstSession = $using:existingSession | ? { $_.ComputerName -eq $machineName -and $_.Name -eq "$resourceGroupName`_$machineName" }

            # use existing session if possible or create a new one
            if (!$exstSession) {
                Write-Verbose "Creating new ssh proxy configuration for '$machineName'"
                $proxyConfig = Export-AzSshConfig -ResourceGroupName $resourceGroupName -Name $machineName -LocalUser $using:userName -ResourceType $using:machineType -ConfigFilePath $configPath -Force -Overwrite
            }
        }

        # pssessions cannot be created in the separate runspace (-Parallel), therefore this second foreach cycle
        foreach ($config in $connectionConfig) {
            [string]$machineName = $config.MachineName
            $resourceGroupName = $config.ResourceGroupName
            $configPath = "$env:temp\sshconfig_$resourceGroupName`_$machineName.config"

            $exstSession = Get-ArcPSSession -resourceGroupName $resourceGroupName -machineName $machineName -PSSessionList $existingSession

            # use existing session if possible or create a new one
            if ($exstSession) {
                Write-Verbose "Reusing existing session '$($exstSession.Name)' for '$machineName' machine"
                $exstSession
            } else {
                Write-Verbose "Creating new session for connecting to '$machineName'"
                if (!(Test-Path $configPath -ea SilentlyContinue)) {
                    Write-Error "There is no proxy configuration created for '$machineName' ($resourceGroupName). Skipping!"
                    continue
                }
                $proxyCommand = Get-Content $configPath | Select-String -Pattern "ProxyCommand"
                $proxyCommand = $proxyCommand -replace "\s*ProxyCommand\s*"
                $options = @{ProxyCommand = ('"' + ($proxyCommand -replace '"') + '"') }

                $param = @{
                    Name     = "$resourceGroupName`_$machineName"
                    HostName = $machineName
                    UserName = $userName
                    Options  = $options
                }
                if ($privateKeyFile) {
                    $param.keyfilepath = $privateKeyFile
                }

                New-PSSession @param
            }
        }
        #endregion return usable and/or newly created sessions
    } finally {
        # sensitive files cleanup
        if ($missingSession -and ($keyVault -and $secretName)) {
            #region helper functions
            function Remove-FileSecure {
                <#
                .SYNOPSIS
                Function for secure overwrite and deletion of file(s).
                It will overwrite file(s) in a secure way by using a cryptographically strong sequence of random values using .NET functions.

                .DESCRIPTION
                Function for secure overwrite and deletion of file(s).
                It will overwrite file(s) in a secure way by using a cryptographically strong sequence of random values using .NET functions.

                .PARAMETER File
                Path to file that should be overwritten.

                .OUTPUTS
                Boolean. True if successful else False.

                .NOTES
                https://gallery.technet.microsoft.com/scriptcenter/Secure-File-Remove-by-110adb68
                #>

                [CmdletBinding()]
                [OutputType([boolean])]
                param(
                    [Parameter(Mandatory = $true, ValueFromPipeline = $true )]
                    [System.IO.FileInfo] $File
                )

                BEGIN {
                    $r = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
                }

                PROCESS {
                    $retObj = $null

                    if ((Test-Path $file -PathType Leaf) -and $pscmdlet.ShouldProcess($file)) {
                        $f = $file
                        if ( !($f -is [System.IO.FileInfo]) ) {
                            $f = New-Object System.IO.FileInfo($file)
                        }

                        $l = $f.length

                        $s = $f.OpenWrite()

                        try {
                            $w = New-Object system.diagnostics.stopwatch
                            $w.Start()

                            [long]$i = 0
                            $b = New-Object byte[](1024 * 1024)
                            while ( $i -lt $l ) {
                                $r.GetBytes($b)

                                $rest = $l - $i

                                if ( $rest -gt (1024 * 1024) ) {
                                    $s.Write($b, 0, $b.length)
                                    $i += $b.LongLength
                                } else {
                                    $s.Write($b, 0, $rest)
                                    $i += $rest
                                }
                            }
                            $w.Stop()
                        } finally {
                            $s.Close()

                            $null = Remove-Item $f.FullName -Force -Confirm:$false -ErrorAction Stop
                        }
                    } else {
                        Write-Warning "$($f.FullName) wasn't found"
                        return $false
                    }

                    return $true
                }
            }
            #endregion helper functions

            Write-Verbose "Removing SSH key '$privateKeyFile'"
            Remove-FileSecure $privateKeyFile

            Get-ChildItem "$env:temp\az_ssh_config" -Recurse -File | % {
                Write-Verbose "Removing SSH relay information '$($_.FullName)'"
                Remove-FileSecure $_.FullName
            }
        }
    }
}

Export-ModuleMember -function Copy-ToArcMachine, Enter-ArcPSSession, Get-ARCExtensionAvailableVersion, Get-ARCExtensionOverview, Get-ArcMachineOverview, Invoke-ArcCommand, Invoke-ArcRDP, New-ArcPSSession

