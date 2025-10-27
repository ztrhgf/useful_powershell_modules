function Get-AzureLocalMarketplaceImageVersion {
    <#
    .SYNOPSIS
        Retrieves the latest version of Azure local marketplace images.

    .DESCRIPTION
        The Get-AzureLocalMarketplaceImageVersion function queries the Azure local marketplace
        to determine the latest available version of specific images. This is useful for
        automation scripts that need to reference the most recent image versions.

    .PARAMETER PublisherName
        The publisher name of the Azure image to query.

    .PARAMETER Offer
        The offer name of the Azure image to query.

    .PARAMETER Sku
        The SKU of the Azure image to query.

    .PARAMETER Location
        The Azure region location to check for image availability.

    .PARAMETER Architecture
        The architecture of the image.

        Default is 'x64'. Other option is 'Arm64'.

    .EXAMPLE
        Get-AzureLocalMarketplaceImageVersion -Publisher 'microsoftwindowsserver' -Offer 'windowsserver' -SKU '2022-datacenter-azure-edition' -Location westeurope

    .LINK
        https://docs.microsoft.com/en-us/powershell/module/az.compute/get-azvmimagepublisher
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Publisher,

        [Parameter(Mandatory = $true)]
        [string]$Offer,

        [Parameter(Mandatory = $true)]
        [string]$SKU,

        [ValidateNotNullOrEmpty()]
        [string]$Location = $_azureLocation,

        [ValidateSet('Arm64', 'x64')]
        [string] $Architecture = "x64"
    )

    if (!$Location) { throw "Location is not set." }

    Write-Verbose "Retrieving marketplace image versions for $Publisher/$Offer/$SKU in $Location"

    # Get all versions for the specific SKU
    $result = Invoke-Expression "az vm image list --publisher '$Publisher' --offer '$Offer' --sku '$SKU' --location '$Location' --architecture '$Architecture' --all --output json"

    # from some reason even if --sku is used to filter just specific SKUs, even different ones are returned. Same goes for Offer.
    $result = $result | ConvertFrom-Json | ? { $_.Sku -eq $SKU -and $_.Offer -eq $Offer }

    $result | Sort-Object -Property { [version]$_.version } -Descending
}