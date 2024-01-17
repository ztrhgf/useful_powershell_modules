function Remove-AzureUserMemberOfDirectoryRole {
    <#
    .SYNOPSIS
    Function for removing given user from given Directory role.

    .DESCRIPTION
    Function for removing given user from given Directory role.

    .PARAMETER userId
    ID of the user.

    Can be retrieved using Get-MgUser.

    .PARAMETER roleId
    ID of the Directory role.

    Can be retrieved using Get-MgUserMemberOf.

    .EXAMPLE
    $aadUser = Get-MgUser -Filter "userPrincipalName eq '$UPN'"

    Get-MgUserMemberOf -UserId $aadUser.id -All | ? { $_.AdditionalProperties.'@odata.type' -eq "#microsoft.graph.directoryRole" } | % {
        Remove-AzureUserMemberOfDirectoryRole -userId $aadUser.id -roleId $_.id
    }
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $userId,
        [Parameter(Mandatory = $true)]
        [string] $roleId
    )

    # Use this endpoint when using the role Id
    $uri = "https://graph.microsoft.com/v1.0/directoryRoles/$roleId/members/$userId/`$ref"

    # Use this endpoint when using the role template ID
    # $uri = "https://graph.microsoft.com/v1.0/directoryRoles/roleTemplateId=$roleTemplateId/members/$userId/`$ref"

    $params = @{
        Headers = (New-GraphAPIAuthHeader -ea Stop)
        Method  = "Delete"
        Uri     = $uri
    }

    Write-Verbose "Invoking DELETE method against '$uri'"
    Invoke-RestMethod @params
}