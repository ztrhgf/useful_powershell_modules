#Requires -Module Microsoft.Graph.Applications
function Set-AzureAppCertificate {
    <#
    .SYNOPSIS
    Function for creating (or replacing existing) authentication certificate for selected AzureAD Application.

    .DESCRIPTION
    Function for creating (or replacing existing) authentication certificate for selected AzureAD Application.

    Use this function with cerPath parameter (if you already have existing certificate you want to add) or rest of the parameters (if you want to create it first). If new certificate will be create, it will be named '<appId>.cer'.

    .PARAMETER appId
    Application ID of the Azure application registration, to which you want to assign certificate.

    .PARAMETER cerPath
    Path to existing '.cer' certificate which should be added to the application.

    .PARAMETER StartDate
    Datetime object defining since when certificate will be valid.

    Default value is now.

    .PARAMETER EndDate
    Datetime object defining to when certificate will be valid.

    Default value is 2 years from now.

    .PARAMETER Password
    Secure string with password that will protect certificate private key.

    Choose a strong one!

    .PARAMETER directory
    Path to folder where pfx (cert. with private key) certificate will be exported.

    By default current working directory.

    .PARAMETER dontRemoveFromCertStore
    Switch to NOT remove certificate from the local cert. store after it is created&exported to pfx.

    .EXAMPLE
    Set-AzureAppCertificate -appId cc210920-4c75-48ad-868b-6aa2dbcd1d51 -cerPath C:\cert\appCert.cer

    Adds certificate 'appCert' to the Azure application cc210920-4c75-48ad-868b-6aa2dbcd1d51.

    .EXAMPLE
    Set-AzureAppCertificate -appId cc210920-4c75-48ad-868b-6aa2dbcd1d51 -password (Read-Host -AsSecureString)

    Creates new self signed certificate, export it as pfx (cert with private key) into working directory and adds its public counterpart (.cer) to the Azure application cc210920-4c75-48ad-868b-6aa2dbcd1d51.
    Certificate private key will be protected by entered password and it will be valid 2 years from now.
    #>

    [CmdletBinding(DefaultParameterSetName = 'createCert')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "cerExists")]
        [Parameter(Mandatory = $true, ParameterSetName = "createCert")]
        [string] $appId,

        [Parameter(Mandatory = $true, ParameterSetName = "cerExists")]
        [ValidateScript( {
                if ($_ -match ".cer$" -and (Test-Path -Path $_)) {
                    $true
                } else {
                    throw "$_ is not a .cer file or doesn't exist"
                }
            })]
        [string] $cerPath,

        [Parameter(Mandatory = $false, ParameterSetName = "createCert")]
        [DateTime] $startDate = (Get-Date),

        [Parameter(Mandatory = $false, ParameterSetName = "createCert")]
        [ValidateScript( {
                if ($_ -gt (Get-Date)) {
                    $true
                } else {
                    throw "$_ has to be in the future"
                }
            })]
        [DateTime] $endDate = (Get-Date).AddYears(2),

        [Parameter(Mandatory = $true, ParameterSetName = "createCert")]
        [SecureString]$password,

        [Parameter(Mandatory = $false, ParameterSetName = "createCert")]
        [ValidateScript( {
                if (Test-Path -Path $_ -PathType Container) {
                    $true
                } else {
                    throw "$_ is not a folder or doesn't exist"
                }
            })]
        [string] $directory = (Get-Location),

        [switch] $dontRemoveFromCertStore
    )

    $null = Connect-MgGraph -ea Stop

    # test that app exists
    try {
        $application = Get-MgApplication -Filter "AppId eq '$appId'" -ErrorAction Stop
    } catch {
        throw "Application registration with AppId $appId doesn't exist"
    }

    $appCert = $application | select -exp KeyCredentials
    if ($appCert | ? EndDateTime -GT ([datetime]::Today)) {
        $choice = ""
        while ($choice -notmatch "^[Y|N]$") {
            $choice = Read-Host "There is a valid certificate(s) already. Do you really want to REPLACE it?! (Y|N)"
        }
        if ($choice -eq "N") {
            break
        }
    }

    if ($cerPath) {
        $cert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2($cerPath)
    } else {
        Write-Warning "Creating self signed certificate named '$appId'"
        $cert = New-SelfSignedCertificate -CertStoreLocation 'cert:\currentuser\my' -Subject "CN=$appId" -NotBefore $startDate -NotAfter $endDate -KeySpec Signature -KeyLength 2048 -KeyAlgorithm RSA -HashAlgorithm SHA256

        Write-Warning "Exporting '$appId.pfx' to '$directory'"
        $pfxFile = Join-Path $directory "$appId.pfx"
        $path = 'cert:\currentuser\my\' + $cert.Thumbprint
        $null = Export-PfxCertificate -Cert $path -FilePath $pfxFile -Password $password

        if (!$dontRemoveFromCertStore) {
            Write-Verbose "Removing created certificate from cert. store"
            Get-ChildItem 'cert:\currentuser\my' | ? { $_.thumbprint -eq $cert.Thumbprint } | Remove-Item
        }
    }

    # $keyValue = [System.Convert]::ToBase64String($cert.GetRawCertData())
    # $base64Thumbprint = [System.Convert]::ToBase64String($cert.GetCertHash())
    # $endDateTime = ($cert.NotAfter).ToUniversalTime().ToString( "yyyy-MM-ddTHH:mm:ssZ" )
    # $startDateTime = ($cert.NotBefore).ToUniversalTime().ToString( "yyyy-MM-ddTHH:mm:ssZ" )

    Write-Warning "Adding certificate secret to the application $($application.DisplayName)"

    # toto funguje s update-mgaaplication
    $keyCredentialParams = @{
        DisplayName = "certificate" # in reality this sets description field :D
        Type        = "AsymmetricX509Cert"
        Usage       = "Verify"
        Key         = $cert.GetRawCertData()
        # StartDateTime       = ($cert.NotBefore).ToUniversalTime().ToString( "yyyy-MM-ddTHH:mm:ssZ" )
        # EndDateTime         = ($cert.NotAfter).ToUniversalTime().ToString( "yyyy-MM-ddTHH:mm:ssZ" )
    }

    Update-MgApplication -ApplicationId $application.Id -KeyCredential $keyCredentialParams

    Write-Warning "Don't fortget that account hat will use this certificate needs to have permission to read it's private key!"
}