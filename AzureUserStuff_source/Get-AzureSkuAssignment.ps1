#requires -modules Microsoft.Graph.Authentication, Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Users
function Get-AzureSkuAssignment {
    <#
    .SYNOPSIS
    Function returns users with selected Sku license.

    .DESCRIPTION
    Function returns users with selected Sku license.

    .PARAMETER sku
    SkuId or SkuPartNumber of the O365 license Sku.
    If not provided, all users and their Skus will be outputted.

    SkuId/SkuPartNumber can be found via: Get-MgSubscribedSku -All

    .PARAMETER assignmentType
    Limit what kind of license assignment the user needs to have.

    Possible values are: 'direct', 'inherited'

    By default users with both types are displayed.

    .EXAMPLE
    Get-AzureSkuAssignment -sku "f8a1db68-be16-40ed-86d5-cb42ce701560"

    Get all users with selected sku (defined by id).

    .EXAMPLE
    Get-AzureSkuAssignment -sku "POWER_BI_PRO"

    Get all users with selected sku.

    .EXAMPLE
    Get-AzureSkuAssignment

    Get all users and their skus.

    .EXAMPLE
    Get-AzureSkuAssignment -assignmentType direct

    Get all users which have some sku assigned directly.

    .EXAMPLE
    Get-AzureSkuAssignment -sku "POWER_BI_PRO" -assignmentType inherited

    Get all users with selected sku if it is inherited.
    #>

    [CmdletBinding()]
    param (
        [ArgumentCompleter( {
                param ($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)

                Get-MgSubscribedSku -Property SkuPartNumber, SkuId -All | ? SkuPartNumber -Like "*$WordToComplete*" | select -ExpandProperty SkuPartNumber
            })]
        [string] $sku,

        [ValidateSet('direct', 'inherited')]
        [string[]] $assignmentType = ('direct', 'inherited'),

        [string[]] $userProperty = ('id', 'userprincipalname', 'assignedLicenses', 'LicenseAssignmentStates')
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): The context is invalid. Please login using Connect-MgGraph."
    }

    # add mandatory property
    if ($userProperty -notcontains 'assignedLicenses') { $userProperty += 'assignedLicenses' }
    if ($userProperty -notcontains 'LicenseAssignmentStates') { $userProperty += 'LicenseAssignmentStates' }

    $param = @{
        Select = $userProperty
        All    = $true
    }

    if ($sku) {
        $skuId = Get-MgSubscribedSku -Property SkuPartNumber, SkuId -All | ? { $_.SkuId -eq $sku -or $_.SkuPartNumber -eq $sku } | select -ExpandProperty SkuId
        if (!$skuId) {
            throw "Sku with id $skuId doesn't exist"
        }
        $param.Filter = "assignedLicenses/any(u:u/skuId eq $skuId)"
    }

    if ($assignmentType.count -eq 2) {
        # has some license
        $whereFilter = { $_.assignedLicenses }
    } elseif ($assignmentType -contains 'direct') {
        # direct assignment
        if ($sku) {
            $whereFilter = { $_.assignedLicenses -and ($_.LicenseAssignmentStates | ? { $_.SkuId -eq $skuId -and $null -eq $_.AssignedByGroup }) }
        } else {
            $whereFilter = { $_.assignedLicenses -and ($null -eq $_.LicenseAssignmentStates.AssignedByGroup).count -ge 1 }
        }
    } else {
        # inherited assignment
        if ($sku) {
            $whereFilter = { $_.assignedLicenses -and ($_.LicenseAssignmentStates | ? { $_.SkuId -eq $skuId -and $null -eq $_.AssignedByGroup }) }
        } else {
            $whereFilter = { $_.assignedLicenses -and $null -eq $_.LicenseAssignmentStates.AssignedByGroup }
        }
    }

    Get-MgUser @param | select $userProperty | ? $whereFilter
}