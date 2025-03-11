#Requires -PSEdition Core

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
            $machineName = $config.MachineName
            $resourceGroupName = $config.ResourceGroupName

            if (!(Get-ArcPSSession -resourceGroupName $resourceGroupName -machineName $machineName -PSSessionList $existingSession)) {
                $missingSession = $true
                break
            }
        }
        #endregion determine if some session needs to be created

        # use KeyVault private key instead of local one
        if ($missingSession -and ($keyVault -and $secretName)) {
            # private key saved in the KeyVault should be used for authentication instead of existing local private key

            # remove the parameter path validation
            (Get-Variable privateKeyFile).Attributes.Clear()

            # where the key will be saved
            $privateKeyFile = Join-Path $env:TEMP ("spk" + (Get-Random))

            # saving private key to temp file
            Write-Verbose "Saving private key to the '$privateKeyFile'"
            Get-AzureKeyVaultMVSecret -name $secretName -vaultName $keyVault -ErrorAction Stop | Out-File $privateKeyFile -Force
        } else {
            Write-Verbose "Default private SSH key will be used"
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
            $machineName = $config.MachineName
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
        # safely delete stored private key
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
        }
    }
}