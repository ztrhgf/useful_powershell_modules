function FilterBy-AzureScope {
    <#
    .SYNOPSIS
    Function for filtering of Azure resources based on their scope (typically saved in ResourceId).

    .DESCRIPTION
    Function for filtering of Azure resources based on their scope (typically saved in ResourceId).

    .PARAMETER pipelineInput
    Azure object(s).

    .PARAMETER scope
    Scope(s) that will be used to filter.

    .PARAMETER property
    Name of the Azure object property that contains its scope (typically ResourceId)

    .EXAMPLE
    $scope = "subscriptions/b6e5e819-g33c-4ecf-b021-5fbd3ff2fead/resourceGroups/local-azure-test", "/subscriptions/1a17a321-7c64-3050-8cc5-42329bdac82b/resourceGroups/AHCI-TEST"

    Search-AzGraph -Query $Query | FilterBy-AzureScope -scope $scope -Property ResourceId
    #>

    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline = $true)]
        $pipelineInput,

        [string[]] $scope,

        [Parameter(Mandatory = $true)]
        [string] $property
    )

    begin {
        # standardize the scope format
        $scope = $scope | ? { $_ } | % {
            $_.trim() -replace "\**$" -replace "/*$" -replace "^/*"
        }
    }

    process {
        foreach ($object in $pipelineInput) {
            $object | ? {
                if (!$scope) {
                    return $true
                } else {
                    foreach ($scp in $scope) {
                        $scp = "/" + $scp + "/*"

                        Write-Verbose "Comparing '$($_.$property)' against '$scp'"

                        if ($_.$property -like $scp) {
                            return $true
                        }
                    }

                    return $false
                }
            }
        }
    }
}