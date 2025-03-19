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