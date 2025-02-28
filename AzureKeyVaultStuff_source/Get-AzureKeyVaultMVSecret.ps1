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