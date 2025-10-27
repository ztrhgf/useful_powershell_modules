function New-AzureLocalVMImage {
    <#
    .SYNOPSIS
    Creates a new Azure Local (HCI) VM image with a specific version.

    .DESCRIPTION
    This function creates VM images on Azure Local (HCI) infrastructure using either
    marketplace images with specific versions or custom VHD/VHDX files.

    .PARAMETER ResourceGroupName
    The resource group where the image will be created.

    .PARAMETER CustomLocationId
    The custom location ID for the Azure Local environment.

    .PARAMETER ImageName
    The name for the new VM image.

    Dots are not allowed, because anything behind the dot is considered as file extension.

    .PARAMETER Publisher
    The publisher of the marketplace image (e.g., 'MicrosoftWindowsServer').

    .PARAMETER Offer
    The offer name (e.g., 'WindowsServer').

    .PARAMETER SKU
    The SKU name (e.g., '2022-datacenter-azure-edition').

    .PARAMETER Version
    The specific version to use. Use 'latest' for the most recent version.

    .PARAMETER VhdPath
    Path to a custom VHD/VHDX file (alternative to marketplace image).

    .PARAMETER OSType
    Operating system type. Defaults to 'Windows'.

    .PARAMETER StoragePathId
    Storage path ID for the image storage location.

    .EXAMPLE
    $cluster = $_azureLocalClusterList[0]
    $publisher = "MicrosoftWindowsServer"
    $offer = "WindowsServer"
    $sku = "2022-datacenter-azure-edition"

    az account set --subscription $cluster.SubscriptionName
    $customLocationID = az customlocation show --resource-group $cluster.ResourceGroupName --name $cluster.CustomLocation --query id -o tsv

    $imageVersionList = Get-AzureLocalMarketplaceImageVersion -Publisher $publisher -Offer $offer -SKU $sku -Location westeurope

    New-AzureLocalVMImage -ResourceGroupName $cluster.ResourceGroupName -CustomLocationId $customLocationID -ImageName "WinServer2022-v1" -Publisher $publisher -Offer $offer -SKU $sku -Version $imageVersionList[0].Version

    Create newest available version of Windows Server 2022 image.

    .EXAMPLE
    New-AzureLocalVMImage -ResourceGroupName "rg-azlocal" -CustomLocationId "/subscriptions/.../customLocations/cl-hci" -ImageName "CustomWin11" -VhdPath "\\storage\images\Win11Custom.vhdx"

    .NOTES
    Requires Azure CLI with stack-hci-vm extension installed.
    #>

    [CmdletBinding(DefaultParameterSetName = 'Marketplace')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]$CustomLocationId,

        [Parameter(Mandatory = $true)]
        [ValidateScript( {
                if ($_ -like '*.*') {
                    throw "$_ contains dots, which are not allowed in image names."
                } else {
                    $true
                }
            })]
        [string]$ImageName,

        [Parameter(Mandatory = $true, ParameterSetName = 'Marketplace')]
        [string]$Publisher,

        [Parameter(Mandatory = $true, ParameterSetName = 'Marketplace')]
        [string]$Offer,

        [Parameter(Mandatory = $true, ParameterSetName = 'Marketplace')]
        [string]$SKU,

        [Parameter(Mandatory = $false, ParameterSetName = 'Marketplace')]
        [string]$Version = 'latest',

        [Parameter(Mandatory = $true, ParameterSetName = 'CustomVHD')]
        [string]$VhdPath,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Windows', 'Linux')]
        [string]$OSType = 'Windows',

        [Parameter(Mandatory = $false)]
        [string]$StoragePathId
    )

    Write-Verbose "Creating Azure Local VM image: $ImageName"

    # Check if Azure CLI is available
    $azVersion = az version --output json 2>$null
    if (-not $azVersion) {
        throw "Azure CLI is not available or not properly configured"
    }

    # Build the base command
    $azCommand = @(
        'az', 'stack-hci-vm', 'image', 'create',
        '--resource-group', $ResourceGroupName,
        '--custom-location', $CustomLocationId,
        '--name', $ImageName,
        '--os-type', $OSType
    )

    # Add marketplace-specific parameters
    if ($PSCmdlet.ParameterSetName -eq 'Marketplace') {
        $azCommand += @(
            '--publisher', $Publisher,
            '--offer', $Offer,
            '--sku', $SKU,
            '--version', $Version
        )

        Write-Verbose "Using marketplace image: $Publisher/$Offer/$SKU/$Version"
    }

    # Add custom VHD parameters
    if ($PSCmdlet.ParameterSetName -eq 'CustomVHD') {
        if (-not (Test-Path $VhdPath)) {
            throw "VHD file not found: $VhdPath"
        }
        $azCommand += @('--image-path', $VhdPath)

        Write-Verbose "Using custom VHD: $VhdPath"
    }

    # Add storage path if specified
    if ($StoragePathId) {
        $azCommand += @('--storage-path-id', $StoragePathId)
    }

    # Output the results in JSON format
    $azCommand += @('--output', 'json')

    # Execute the command
    $command = $azCommand -join ' '
    Write-Verbose "Executing: $command"
    $errOutput = $($imageInfo = Invoke-Expression $command | ConvertFrom-Json ) 2>&1 # redirect error stream to success stream, so we can capture it

    if ($LASTEXITCODE -eq 0) {
        Write-Verbose "Successfully created VM image '$($imageInfo.name)'"

        return $imageInfo
    } else {
        throw "Failed to create VM image '$ImageName'. Error was: $errOutput"
    }
}