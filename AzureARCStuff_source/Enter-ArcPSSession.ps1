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