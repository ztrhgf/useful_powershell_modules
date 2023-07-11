function Expand-MgAdditionalProperties {
    <#
    .SYNOPSIS
    Function for expanding 'AdditionalProperties' hash property to the main object aka flattens object.

    .DESCRIPTION
    Function for expanding 'AdditionalProperties' hash property to the main object aka flattens object.
    By default it is returned by commands like Get-MgDirectoryObjectById, Get-MgGroupMember etc.

    .PARAMETER inputObject
    Object returned by Mg* command that contains 'AdditionalProperties' property.

    .EXAMPLE
    Get-MgGroupMember -GroupId 90daa3a7-7fed-4fa7-a979-db74bcd7cbd0  | Expand-MgAdditionalProperties

    .EXAMPLE
    Get-MgDirectoryObjectById -ids 34568a12-8862-45cf-afef-9582cd9871c6 | Expand-MgAdditionalProperties
    #>

    [CmdletBinding()]
    param(
        [parameter(ValueFromPipeline)]
        [object] $inputObject
    )

    process {
        if ($inputObject.AdditionalProperties -and $inputObject.AdditionalProperties.gettype().name -eq 'Dictionary`2') {
            $inputObject.AdditionalProperties.GetEnumerator() | % {
                $item = $_
                Write-Verbose "Adding property '$($item.key)' to the pipeline object"
                $inputObject | Add-Member -MemberType NoteProperty -Name $item.key -Value $item.value

                if ($item.key -eq "@odata.type") {
                    Write-Verbose "Adding extra property 'ObjectType' to the pipeline object"
                    $inputObject | Add-Member -MemberType NoteProperty -Name 'ObjectType' -Value ($item.value -replace [regex]::Escape("#microsoft.graph."))
                }
            }

            $inputObject | Select-Object -Property * -ExcludeProperty AdditionalProperties
        } else {
            Write-Verbose "There is no 'AdditionalProperties' property"
            $inputObject
        }
    }
}