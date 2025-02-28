function Get-AzureKeyVaultMVSecret {
    <#
    .SYNOPSIS
    Improved version of the official Get-AzKeyVaultSecret function that
     - supports retrieval of multiline secrets (a.k.a. login + password)
     - supports returning of the plaintext or plaintext converted to the PSCredential object

    .DESCRIPTION
    Improved version of the official Get-AzKeyVaultSecret function that
     - supports retrieval of multiline secrets (a.k.a. login + password)
     - supports returning of the plaintext or plaintext converted to the PSCredential object

    .PARAMETER name
    Name of the secret.

    .PARAMETER subscription
    Optional parameter to specify subscription where the KeyVault is placed.
    If not provided uses current subscription.

    .PARAMETER vaultName
    Name of the KeyVault.

    .PARAMETER asPSCredential
    By default the result is plaintext (splitted by newline).
    With this switch, plaintext is converted and returned as the PSCredential object.

    .EXAMPLE
    $credentials = Get-AzureKeyVaultMVSecret -vaultName MySecrets -name jira -asPSCredential

    Returns saved (multiline) jira secret (created via Set-AzureKeyVaultMVSecret) as the PSCredential object (name + password).

    .EXAMPLE
    $credentialsString = Get-AzureKeyVaultMVSecret -vaultName MySecrets -name jira

    $login = $credentialsString[0]
    $plaintextPassword = $credentialsString[1]

    Returns saved (multiline) jira secret (created via Set-AzureKeyVaultMVSecret) as multiline plaintext object (name + password splitted by newline).

    .NOTES
    https://www.modernendpoint.com/managed/Working-with-Azure-Key-Vault-in-PowerShell/
    #>

    [CmdletBinding()]
    [Alias("Get-AzureKeyVaultMultiValueSecret")]
    param (
        [Parameter(Mandatory = $true)]
        [string] $name,

        [string] $subscription,

        [Parameter(Mandatory = $true)]
        [string] $vaultName,

        [switch] $asPSCredential
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    if ($subscription) {
        $currentSubscription = (Get-AzContext).Subscription.Name
        if ($currentSubscription -ne $subscription) {
            $null = Select-AzSubscription $subscription
        }
    }

    $token = Get-AzKeyVaultSecret -VaultName $vaultName -Name $name -AsPlainText
    $token = $token -split "`n"

    if ($asPSCredential) {
        $userName = $token[0]
        $userPassword = $token[1]
        if ($userPassword) {
            [SecureString] $secureString = $userPassword | ConvertTo-SecureString -AsPlainText -Force
        } else {
            [SecureString] $secureString = (New-Object System.Security.SecureString)
        }
        New-Object System.Management.Automation.PSCredential -ArgumentList $userName, $secureString
    } else {
        $token
    }

    if ($subscription -and $currentSubscription -ne $subscription) {
        # switch back
        $null = Select-AzSubscription $currentSubscription
    }
}

function Set-AzureKeyVaultMVSecret {
    <#
    .SYNOPSIS
    Improved version of the official Set-AzKeyVaultSecret function that
     - supports saving multiline secrets (a.k.a. login + password) provided via PSCredential object or as file content.

    .DESCRIPTION
    Improved version of the official Set-AzKeyVaultSecret function that
     - supports saving multiline secrets (a.k.a. login + password) provided via PSCredential object or as file content.

    .PARAMETER name
    Name of the secret.

    .PARAMETER subscription
    Optional parameter to specify subscription where the KeyVault is placed.
    If not provided uses current subscription.

    .PARAMETER vaultName
    Name of the KeyVault.

    .PARAMETER credentials
    Credentials object that will be saved as KeyVault secret.
    Both username and the password.

    .PARAMETER file
    Path to file which content will be set as the secret value.

    .PARAMETER type
    Description of the secret.

    .EXAMPLE
    $credentials = Get-Credential

    Set-AzureKeyVaultMVSecret -vaultName MySecrets -name jira -credentials $credentials

    To the default KeyVault saves new multiline secret where on the first line will be login and on the second one password.
    The result can be later read using Get-AzureKeyVaultMVSecret.

    .EXAMPLE
    Set-AzureKeyVaultMVSecret -vaultName MySecrets -name AAAAE2VjZHNhLXNoYTItbmlzdHAyNKYAAAA -file C:\Users\admin\.ssh\id_ecdsa -type sshprivkey

    To the specified KeyVault saves new multiline secret where value of such secret is content of the specified file.

    .NOTES
    https://www.modernendpoint.com/managed/Working-with-Azure-Key-Vault-in-PowerShell/
    #>

    [CmdletBinding(DefaultParameterSetName = 'Credentials')]
    [Alias("Set-AzureKeyVaultMultiValueSecret")]
    param (
        [Parameter(Mandatory = $true)]
        [string] $name,

        [string] $subscription,

        [Parameter(Mandatory = $true)]
        [string] $vaultName,

        [Parameter(Mandatory = $true, ParameterSetName = "Credentials")]
        [PSCredential] $credentials,

        [Parameter(Mandatory = $true, ParameterSetName = "File")]
        [ValidateScript( {
                if (Test-Path -Path $_ -PathType Leaf) {
                    $true
                } else {
                    throw "'$_' file doesn't exist"
                }
            })]
        [string] $file,

        [string] $type
    )

    if (!(Get-Command 'Get-AzAccessToken' -ErrorAction silentlycontinue) -or !($azAccessToken = Get-AzAccessToken -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) -or $azAccessToken.ExpiresOn -lt [datetime]::now) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-AzAccount."
    }

    if ($subscription) {
        $currentSubscription = (Get-AzContext).Subscription.Name
        if ($currentSubscription -ne $subscription) {
            Write-Verbose "Switching to the $subscription subscription"
            $null = Select-AzSubscription $subscription
        }
    }

    if ($credentials) {
        $string = $credentials.UserName

        if ($credentials.GetNetworkCredential().password) {
            # in theory password doesn't have to be provided (unlike username)
            $string += "`n" + $credentials.GetNetworkCredential().password
        }
    } else {
        $string = Get-Content $file -Raw
    }

    $secretValue = ConvertTo-SecureString -String $string -AsPlainText -Force

    $param = @{
        VaultName   = $vaultName
        Name        = $name
        SecretValue = $secretValue
    }
    if ($type) {
        $param.ContentType = $type
    }
    $setSecret = Set-AzKeyVaultSecret @param

    if ($subscription -and $currentSubscription -ne $subscription) {
        # switch back
        Write-Verbose "Switching back to the $currentSubscription subscription"
        $null = Select-AzSubscription $currentSubscription
    }
}

Export-ModuleMember -function Get-AzureKeyVaultMVSecret, Set-AzureKeyVaultMVSecret

Export-ModuleMember -alias Get-AzureKeyVaultMultiValueSecret, Set-AzureKeyVaultMultiValueSecret
