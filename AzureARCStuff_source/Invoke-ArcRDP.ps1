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

    # get missing parameter values
    while (!$resourceGroupName -and !$machineName) {
        if (!$arcMachineList) {
            $arcMachineList = Get-ArcMachineOverview
        }

        $selected = $arcMachineList | select name, resourceGroup, status | Out-GridView -Title "Select ARC machine to connect" -OutputMode Single

        $resourceGroupName = $selected.resourceGroup
        $machineName = $selected.name
    }

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
        Write-Verbose "Saving credentials for $computer and $user to CredMan"
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

    # download private key from the KeyVault
    if ($keyVault -and $secretName) {
        # private key saved in the KeyVault should be used for authentication instead of existing local private key

        # remove the parameter path validation
        (Get-Variable privateKeyFile).Attributes.Clear()

        # where the key will be saved
        $privateKeyFile = Join-Path $env:TEMP ("spk" + (Get-Random))

        # saving private key to temp file
        Write-Verbose "Saving private key to the '$privateKeyFile'"
        Get-AzureKeyVaultMVSecret -name $secretName -vaultName $keyVault -ErrorAction Stop | Out-File $privateKeyFile -Force
    }

    #region cleanup
    if ($keyVault -and $secretName) {
        # remove the private key ASAP
        Write-Verbose "SSH key will be removed in 5 seconds"
        $null = Start-Job -Name "cleanup" -ScriptBlock {
            param ($privateKeyFile)

            # I have to wait a little bit so the Enter-AzVM is being run
            Start-Sleep 5

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
        } -ArgumentList $privateKeyFile
    }

    if ($rdpCredential -or $rdpUserName) {
        # remove saved credentials from Cred. Manager ASAP
        Write-Verbose "RDP password will be removed from CredMan in 5 seconds"
        $null = Start-Job -Name "cleanup" -ScriptBlock {
            param ($computer)

            # I have to wait a little bit so the Enter-AzVM is being run
            Start-Sleep 5

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
                throw 'Removal of credentials failed. Remove them manually from  Cred. Manager!'
            }
        } -ArgumentList $computer
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