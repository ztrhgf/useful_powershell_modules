#Requires -Module AzureAD
function Add-AzureADAppCertificate {
    <#
    .SYNOPSIS
    Function for (creating and) adding authentication certificate to selected AzureAD Application.

    .DESCRIPTION
    Function for (creating and) adding authentication certificate to selected AzureAD Application.

    Use this function with cerPath parameter (if you already have existing certificate you want to add) or rest of the parameters (if you want to create it first). If new certificate will be create, it will be named as application ID of the corresponding enterprise app.

    .PARAMETER appObjectId
    ObjectId of the Azure application registration, to which you want to assign certificate.

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

    Choose strong one!

    .PARAMETER directory
    Path to folder where pfx (cert. with private key) certificate will be exported.

    .PARAMETER dontRemoveFromCertStore
    Switch to NOT remove certificate from the local cert. store after it is created&exported to pfx.

    .EXAMPLE
    Add-AzureADAppCertificate -appObjectId cc210920-4c75-48ad-868b-6aa2dbcd1d51 -cerPath C:\cert\appCert.cer

    Adds certificate 'appCert' to the Azure application cc210920-4c75-48ad-868b-6aa2dbcd1d51.

    .EXAMPLE
    Add-AzureADAppCertificate -appObjectId cc210920-4c75-48ad-868b-6aa2dbcd1d51 -password (Read-Host -AsSecureString)

    Creates new self signed certificate, export it as pfx (cert with private key) into working directory and adds its public counterpart (.cer) it to the Azure application cc210920-4c75-48ad-868b-6aa2dbcd1d51.
    Certificate private key will be protected by entered password and it will be valid 2 years from now.

    .NOTES
    http://vcloud-lab.com/entries/microsoft-azure/create-an-azure-app-registrations-in-azure-active-directory-using-powershell-azurecli
    https://docs.microsoft.com/en-us/sharepoint/dev/solution-guidance/security-apponly-azuread
    #>

    [CmdletBinding(DefaultParameterSetName = 'createCert')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "cerExists")]
        [Parameter(Mandatory = $true, ParameterSetName = "createCert")]
        [string] $appObjectId,

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

    try {
        # test if connection already exists
        $null = Get-AzureADCurrentSessionInfo -ea Stop
    } catch {
        throw "You must call the Connect-AzureAD cmdlet before calling any other cmdlets."
    }

    # test that app exists
    try {
        $application = Get-AzureADApplication -ObjectId $appObjectId -ErrorAction Stop
        # corresponding enterprise app ID
        $entAppId = $application.AppId
    } catch {
        throw "Application registration with ObjectId $appObjectId doesn't exist"
    }

    if ($cerPath) {
        $cert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2($cerPath)
    } else {
        Write-Warning "Creating self signed certificate named '$entAppId'"
        $cert = New-SelfSignedCertificate -CertStoreLocation 'cert:\currentuser\my' -Subject "CN=$entAppId" -NotBefore $startDate -NotAfter $endDate -KeySpec Signature -KeyLength 2048 -KeyAlgorithm RSA -HashAlgorithm SHA256

        Write-Warning "Exporting '$entAppId.pfx' to '$directory'"
        $pfxFile = Join-Path $directory "$entAppId.pfx"
        $path = 'cert:\currentuser\my\' + $cert.Thumbprint
        $null = Export-PfxCertificate -Cert $path -FilePath $pfxFile -Password $password

        if (!$dontRemoveFromCertStore) {
            Write-Verbose "Removing created certificate from cert. store"
            Get-ChildItem 'cert:\currentuser\my' | ? { $_.thumbprint -eq $cert.Thumbprint } | Remove-Item
        }
    }

    $keyValue = [System.Convert]::ToBase64String($cert.GetRawCertData())
    $base64Thumbprint = [System.Convert]::ToBase64String($cert.GetCertHash())
    $endDateTime = ($cert.NotAfter).ToUniversalTime().ToString( "yyyy-MM-ddTHH:mm:ssZ" )
    $startDateTime = ($cert.NotBefore).ToUniversalTime().ToString( "yyyy-MM-ddTHH:mm:ssZ" )

    Write-Warning "Adding certificate to the application $($application.DisplayName)"
    New-AzureADApplicationKeyCredential -ObjectId $appObjectId -CustomKeyIdentifier $base64Thumbprint -Type AsymmetricX509Cert -Usage Verify -Value $keyValue -StartDate $startDateTime -EndDate $endDateTime
}