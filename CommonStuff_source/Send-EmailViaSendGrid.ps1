#requires -modules PSSendGrid
function Send-EmailViaSendGrid {
    <#
    .SYNOPSIS
    Function for sending email using SendGrid service.

    .DESCRIPTION
    Function for sending email using SendGrid service.

    Supports retrieval of the api token from Azure Keyvault or from given credentials object.

    .PARAMETER to
    Email address(es) of recipient(s).

    .PARAMETER subject
    Email subject.

    .PARAMETER body
    Email body.

    .PARAMETER asHTML
    Switch for sending email body as HTML instead of plaintext.

    .PARAMETER from
    Sender email address.

    .PARAMETER credentials
    PSCredential object that contains SendGrid authentication token in the password field.

    If not provided, token will be retrieved from Azure vault if possible.

    .EXAMPLE
    $cr = Get-Credential -UserName "whatever" -Message "Enter SendGrid token to the password field"

    $param = @{
        to = 'johnd@contoso.com'
        from = 'marie@contoso.com'
        subject = 'greetings'
        body = "Hi,`nhow are you?"
        credentials = $cr
    }
    Send-EmailViaSendGrid @param

    Will send plaintext email using given token to johnd@contoso.com.

    .EXAMPLE
    Connect-AzAccount

    $param = @{
        to = 'johnd@contoso.com'
        from = 'marie@contoso.com'
        subject = 'greetings'
        body = 'Hi,<br>how are you?'
        asHTML = $true
        vaultSubscription = 'production'
        vaultName = 'secrets'
        secretName = 'sendgrid'
    }
    Send-EmailViaSendGrid @param

    Will send HTML email (using token retrieved from Azure Keyvault) to johnd@contoso.com.
    To be able to automatically retrieve token from Azure Vault, you have to be authenticated (Connect-AzAccount).
#>

[CmdletBinding(DefaultParameterSetName = 'credentials')]
    param (
        [ValidateScript( {
            if ($_ -like "*@*") {
                $true
            } else {
                throw "$_ is not a valid email address (johnd@contoso.com)"
            }
        })]
        [string[]] $to = $_sendTo,

        [Parameter(Mandatory = $true)]
        [string] $subject,

        [Parameter(Mandatory = $true)]
        [string] $body,

        [switch] $asHTML,

        [ValidateScript( {
            if ($_ -like "*@*") {
                $true
            } else {
                throw "$_ is not a valid email address (johnd@contoso.com)"
            }
        })]
        [string] $from = $_sendFrom,

        [Parameter(Mandatory = $true, ParameterSetName = "credentials")] 
        [System.Management.Automation.PSCredential] $credentials,

        [Parameter(Mandatory = $false, ParameterSetName = "keyvault")] 
        [string] $vaultSubscription = $_vaultSubscription,

        [Parameter(Mandatory = $false, ParameterSetName = "keyvault")] 
        [string] $vaultName = $_vaultName,

        [Parameter(Mandatory = $false, ParameterSetName = "keyvault")] 
        [string] $secretName = $_secretName
    )

    #region checks
    if (!(Get-Command Send-PSSendGridMail -ea SilentlyContinue)) {
        throw "Command Send-PSSendGridMail is missing (part of module PSSendGrid)"
    }

    if (!$to) {
        throw "$($MyInvocation.MyCommand) has to have 'to' parameter defined"
    }
    if (!$from) {
        throw "$($MyInvocation.MyCommand) has to have 'from' parameter defined"
    }

    if ($credentials -and !($credentials.GetNetworkCredential().password)) {
            throw "Credentials doesn't contain password"
    } elseif (!$credentials) {
        if (!$vaultSubscription) {
            throw "$($MyInvocation.MyCommand) has to have 'vaultSubscription' parameter defined"
        }
        if (!$vaultName) {
            throw "$($MyInvocation.MyCommand) has to have 'vaultName' parameter defined"
        }
        if (!$secretName) {
            throw "$($MyInvocation.MyCommand) has to have 'secretName' parameter defined"
        } 
    }
    #endregion checks

    #region retrieve token
    if (!$credentials) {
        try {
            $currentSubscription = (Get-AzContext).Subscription.Name
            if ($currentSubscription -ne $vaultSubscription) {
                Write-Verbose "Switching subscription to $vaultSubscription"
                $null = Select-AzSubscription $vaultSubscription
            }

            Write-Verbose "Retrieving sendgrid token (vault: $vaultName, secret: $secretName)"
            $token = Get-AzKeyVaultSecret -VaultName $vaultName -Name $secretName -AsPlainText -ErrorAction Stop

            Write-Verbose "Switching subscription back to $currentSubscription"
            $null = Select-AzSubscription $currentSubscription
        } catch {
            if ($_ -match "Run Connect-AzAccount to login") {
                throw "Unable to obtain sendgrid token from Azure Vault, because you are not authenticated. Use Connect-AzAccount to fix this"
            } else {
                throw "Unable to obtain sendgrid token from Azure Vault.`n`n$_"
            }
        }
    } else {
        $token = $credentials.GetNetworkCredential().password
        if (!$token) {
            throw "Token parameter doesn't contain token"
        }
    }
    #endregion retrieve token

    $param = @{
        FromAddress = $from
        ToAddress   = $to
        Subject     = $subject
        Token       = $token
    }
    if ($asHTML) {
        $param.BodyAsHTML = $body
    } else {
        $param.Body = $body
    }

    Write-Verbose "Sending email"
    Send-PSSendGridMail @param
}