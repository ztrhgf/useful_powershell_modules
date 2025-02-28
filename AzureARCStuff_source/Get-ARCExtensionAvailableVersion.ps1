function Get-ARCExtensionAvailableVersion {
    <#
    .SYNOPSIS
    Returns all available versions of selected ARC extension.

    .DESCRIPTION
    Returns all available versions of selected ARC extension.

    .PARAMETER location
    Extension ARC machine location.
    Because extensions are rolled out gradually, different locations can show different results.

    .PARAMETER publisherName
    Extension publisher name.

    .PARAMETER type
    Extension type/name.

    .EXAMPLE
    # to get all extensions
    # Get-ARCExtensionOverview

    Get-ARCExtensionAvailableVersion -Location westeurope -PublisherName Microsoft.Compute -Type CustomScriptExtension
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $location,

        [Parameter(Mandatory = $true)]
        [string] $publisherName,

        [Parameter(Mandatory = $true)]
        [Alias("Name")]
        [string] $type
    )

    Get-AzVMExtensionImage -Location $location -PublisherName $publisherName -Type $type | Sort-Object -Property { [version]$_.version }
}