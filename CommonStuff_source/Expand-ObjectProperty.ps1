
function Expand-ObjectProperty {
    <#
    .SYNOPSIS
    Function integrates selected object property into the main object a.k.a flattens the main object.

    .DESCRIPTION
    Function integrates selected object property into the main object a.k.a flattens the main object.

    Moreover if the integrated property contain '@odata.type' child property, ObjectType

    .PARAMETER inputObject
    Object(s) with that should be flattened.

    .PARAMETER propertyName
    Name opf the object property you want to integrate into the main object.
    Beware that any same-named existing properties in the main object will be overwritten!

    .PARAMETER addObjectType
    (make sense only for MS Graph related objects)
    Switch to add extra 'ObjectType' property in case there is '@odata.type' property in the integrated object that contains type of the object (for example 'user instead of '#microsoft.graph.user' etc).

    .EXAMPLE
    $managementGroupNameList = (Get-AzManagementGroup).Name
    New-AzureBatchRequest -url "https://management.azure.com/providers/Microsoft.Management/managementGroups/<placeholder>/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01" -placeholder $managementGroupNameList | Invoke-AzureBatchRequest | Expand-ObjectProperty -propertyName Properties

    .EXAMPLE
    Get-MgDirectoryObjectById -ids 34568a12-8861-45ff-afef-9282cd9871c6 | Expand-ObjectProperty -propertyName AdditionalProperties -addObjectType
    #>

    [CmdletBinding()]
    param(
        [parameter(ValueFromPipeline)]
        [object[]] $inputObject,

        [Parameter(Mandatory = $true)]
        [string] $propertyName,

        [switch] $addObjectType
    )

    process {
        foreach ($object in $inputObject) {
            if ($object.$propertyName) {
                $propertyType = $object.$propertyName.gettype().name

                if ($propertyType -eq 'PSCustomObject') {
                    ($object.$propertyName | Get-Member -MemberType NoteProperty).Name | % {
                        $pName = $_
                        $pValue = $object.$propertyName.$pName

                        Write-Verbose "Adding property '$pName' to the pipeline object"
                        $object | Add-Member -MemberType NoteProperty -Name $pName -Value $pValue -Force
                    }
                } elseif ($propertyType -in 'Dictionary`2', 'Hashtable') {
                    $object.$propertyName.GetEnumerator() | % {
                        $pName = $_.key
                        $pValue = $_.value

                        $object | Add-Member -MemberType NoteProperty -Name $pName -Value $pValue -Force

                        if ($addObjectType -and $pName -eq "@odata.type") {
                            Write-Verbose "Adding extra property 'ObjectType' to the pipeline object"
                            $object | Add-Member -MemberType NoteProperty -Name 'ObjectType' -Value ($pValue -replace [regex]::Escape("#microsoft.graph.")) -Force
                        }
                    }
                } else {
                    throw "Undefined property type '$propertyType'"
                }

                $object | Select-Object -Property * -ExcludeProperty $propertyName
            } else {
                Write-Warning "There is no '$propertyName' property"
                $object
            }
        }
    }
}