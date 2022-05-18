function Connect-AzureAD2 {
    <#
    .SYNOPSIS
    Function for connecting to Azure AD. Reuse already existing session if possible.
    Supports user and app authentication.

    .DESCRIPTION
    Function for connecting to Azure AD. Reuse already existing session if possible.
    Supports user and app authentication.

    .PARAMETER tenantId
    Azure AD tenant domain name/id.
    It is optional for user auth. but mandatory for app. auth!

    Default is $_tenantId.

    .PARAMETER credential
    User credentials for connecting to AzureAD.

    .PARAMETER asYourself
    Switch for user authentication using current user credentials.

    .PARAMETER applicationId
    Application ID of the enterprise application.
    Mandatory for app. auth.

    .PARAMETER certificateThumbprint
    Thumbprint of the certificate that should be used for app. auth.
    Corresponding certificate has to exists in machine certificate store and user must have permissions to read its private key!

    .PARAMETER returnConnection
    Switch for returning connection info (like original Connect-AzureAD command do).

    How to create such certificate:
    $pwd = "nejakeheslo"
    $notAfter = (Get-Date).AddMonths(60)
    $thumb = (New-SelfSignedCertificate -DnsName "someDNSname" -CertStoreLocation "cert:\LocalMachine\My" -KeyExportPolicy Exportable -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider" -NotAfter $notAfter).Thumbprint
    $pwd = ConvertTo-SecureString -String $pwd -Force -AsPlainText
    Export-PfxCertificate -Cert "cert:\localmachine\my\$thumb" -FilePath c:\temp\examplecert.pfx -Password $pwd
    udelat export public casti certifikatu (.cer) a naimportovat k vybrane aplikaci v Azure portalu

    .EXAMPLE
    Connect-AzureAD2 -asYourself

    Connect using current user credentials.

    .EXAMPLE
    Connect-AzureAD2 -credential (Get-Credential)

    Connect using user credentials.

    .EXAMPLE
    $thumbprint = Get-ChildItem Cert:\LocalMachine\My | ? subject -EQ "CN=contoso.onmicrosoft.com" | select -ExpandProperty Thumbprint
    Connect-AzureAD2 -ApplicationId 'cd2ae428-35f9-21b4-a527-7d3gf8f1e5cf' -CertificateThumbprint $thumbprint

    Connect using app. authentication (certificate).
    #>

    [CmdletBinding(DefaultParameterSetName = 'userAuth')]
    param (
        [Parameter(ParameterSetName = "userAuth")]
        [System.Management.Automation.PSCredential] $credential,

        [Parameter(ParameterSetName = "userAuth")]
        [switch] $asYourself,

        [Parameter(ParameterSetName = "appAuth")]
        [Parameter(ParameterSetName = "userAuth")]
        [Alias("tenantDomain")]
        [string] $tenantId = $_tenantId,

        [Parameter(Mandatory = $true, ParameterSetName = "appAuth")]
        [string] $applicationId,

        [Parameter(Mandatory = $true, ParameterSetName = "appAuth")]
        [string] $certificateThumbprint,

        [switch] $returnConnection
    )

    if (!(Get-Command Connect-AzureAD -ea SilentlyContinue)) { throw "Module AzureAD is missing" }

    if ([Microsoft.Open.Azure.AD.CommonLibrary.AzureSession]::AccessTokens) {
        $token = [Microsoft.Open.Azure.AD.CommonLibrary.AzureSession]::AccessTokens
        Write-Verbose "Connected to tenant: $($token.AccessToken.TenantId) with user: $($token.AccessToken.UserId)"
    } else {
        if ($applicationId) {
            # app auth
            if (!$tenantId) { throw "tenantId parameter is undefined" }

            # check certificate
            foreach ($store in ('CurrentUser', 'LocalMachine')) {
                $cert = Get-Item "Cert:\$store\My\$certificateThumbprint" -ErrorAction SilentlyContinue
                if ($cert) {
                    if (!$cert.HasPrivateKey) {
                        throw "Certificate $certificateThumbprint doesn't contain private key!"
                    }
                    try {
                        $rsaCert = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
                    } catch {
                        throw "Account $env:USERNAME doesn't have right to read private key of certificate $certificateThumbprint (use Add-CertificatePermission to fix it)!"
                    }

                    break
                }
            }
            if (!$cert) { throw "Certificate $certificateThumbprint isn't located in $env:USERNAME nor $env:COMPUTERNAME Personal store" }

            $param = @{
                ErrorAction           = "Stop"
                TenantId              = $tenantId
                ApplicationId         = $applicationId
                CertificateThumbprint = $certificateThumbprint
            }

            if ($returnConnection) {
                Connect-AzureAD @param
            } else {
                $null = Connect-AzureAD @param
            }
        } else {
            # user auth
            $param = @{ errorAction = "Stop" }
            if ($credential) { $param.credential = $credential }
            if ($tenantId) { $param.TenantId = $tenantId }
            if ($asYourself) {
                $upn = whoami -upn
                if ($upn) {
                    $param.AccountId = $upn
                } else {
                    Write-Error "Unable to obtain your UPN. Run again without 'asYourself' switch"
                    return
                }
            }

            if ($returnConnection) {
                Connect-AzureAD @param
            } else {
                $null = Connect-AzureAD @param
            }
        }
    }
}