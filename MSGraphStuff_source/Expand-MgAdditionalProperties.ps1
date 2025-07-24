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
    Get-MgDirectoryObjectById -ids 34568a12-8861-45ff-afef-9282cd9871c6 | Expand-MgAdditionalProperties
    #>

    [CmdletBinding()]
    param(
        [parameter(ValueFromPipeline)]
        [object[]] $inputObject
    )

    process {
        foreach ($object in $inputObject) {
            $object | Expand-ObjectProperty -Property AdditionalProperties -addObjectType
        }
    }
}