#Requires -Module Microsoft.Graph.Intune
#Requires -Module WindowsAutoPilotIntune
function Connect-MSGraph2 {
    <#
    .SYNOPSIS
    Function for connecting to Microsoft Graph.

    .DESCRIPTION
    Function for connecting to Microsoft Graph.
    Support (interactive) user or application authentication
    Without specifying any parameters, interactive user auth. will be used.

    To use app. auth. tenantId, appId and appSecret parameters have to be specified!
    TIP: you can use credential parameter to pass appId and appSecret securely

    .PARAMETER TenantId
    ID of your tenant.

    Default is $_tenantId.

    .PARAMETER AppId
    Azure AD app ID (GUID) for the application that will be used to authenticate

    .PARAMETER AppSecret
    Specifies the Azure AD app secret corresponding to the app ID that will be used to authenticate.
    Can be generated in Azure > 'App Registrations' > SomeApp > 'Certificates & secrets > 'Client secrets'.

    .PARAMETER Credential
    Credential object that can be used both for user and app authentication.

    .PARAMETER Beta
    Set schema to beta.

    .PARAMETER returnConnection
    Switch for returning connection info (like original Connect-AzureAD command do).

    .EXAMPLE
    Connect-MSGraph2

    Connect to MS Graph interactively using user authentication.

    .EXAMPLE
    Connect-MSGraph2 -TenantId 1111 -AppId 1234 -AppSecret 'pass'

    Connect to MS Graph using app. authentication.

    .EXAMPLE
    Connect-MSGraph2 -TenantId 1111 -credential (Get-Credential)

    Connect to MS Graph using app. authentication. AppId and AppSecret will be extracted from credential object.

    .EXAMPLE
    Connect-MSGraph2 -credential (Get-Credential)

    Connect to MS Graph using user authentication.

    .NOTES
    Requires module Microsoft.Graph.Intune
    #>

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [Alias("Connect-MSGraphApp2")]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "AppAuth")]
        [Parameter(Mandatory = $true, ParameterSetName = "App2Auth")]
        [string] $tenantId = $_tenantId
        ,
        [Parameter(Mandatory = $true, ParameterSetName = "AppAuth")]
        [string] $appId
        ,
        [Parameter(Mandatory = $true, ParameterSetName = "AppAuth")]
        [string] $appSecret
        ,
        [Parameter(Mandatory = $true, ParameterSetName = "App2Auth")]
        [Parameter(Mandatory = $true, ParameterSetName = "UserAuth")]
        [System.Management.Automation.PSCredential] $credential,

        [switch] $beta,

        [switch] $returnConnection
    )

    if (!(Get-Command Connect-MSGraph -ea silent)) {
        throw "Module Microsoft.Graph.Intune is missing"
    }
    if (!(Get-Command Connect-MSGraphApp -ea silent)) {
        throw "Module WindowsAutoPilotIntune is missing"
    }

    if ($beta) {
        if ((Get-MSGraphEnvironment).SchemaVersion -ne "beta") {
            $null = Update-MSGraphEnvironment -SchemaVersion beta
        }
    }

    if ($tenantId -and (($appId -and $appSecret) -or $credential)) {
        Write-Verbose "Authenticating using app auth."

        if (!$appId -and $credential) {
            $appId = $credential.UserName
        }
        if (!$appSecret -and $credential) {
            $appSecret = $credential.GetNetworkCredential().password
        }

        $param = @{
            Tenant      = $tenantId
            AppId       = $appId
            AppSecret   = $appSecret
            ErrorAction = 'Stop'
        }

        if ($returnConnection) {
            Connect-MSGraphApp @param
        } else {
            $null = Connect-MSGraphApp @param
        }
        Write-Verbose "Connected to Intune tenant $tenantId"
    } else {
        Write-Verbose "Authenticating using user auth."

        $param = @{
            ErrorAction = 'Stop'
        }
        if ($credential) {
            $param.Credential = $credential
        }

        if ($returnConnection) {
            Connect-MSGraph @param
        } else {
            $null = Connect-MSGraph @param
        }
        Write-Verbose "Connected to Intune tenant using user authentication"
    }
}