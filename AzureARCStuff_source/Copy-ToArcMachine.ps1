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