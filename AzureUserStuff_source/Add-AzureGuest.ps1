#requires -modules Microsoft.Graph.Authentication, Microsoft.Graph.Identity.SignIns, Microsoft.Graph.Groups, Microsoft.Graph.Users
function Add-AzureGuest {
    <#
    .SYNOPSIS
    Function for inviting guest user to Azure AD.

    .DESCRIPTION
    Function for inviting guest user to Azure AD.

    .PARAMETER displayName
    Display name of the user.
    Suffix (guest) will be added automatically.

    a.k.a Jan Novak

    .PARAMETER emailAddress
    Email address of the user.

    a.k.a novak@seznam.cz

    .PARAMETER parentTeamsGroup
    Optional parameter.

    Name of Teams group, where the guest should be added as member. (it can take several minutes, before this change propagates!)

    .EXAMPLE
    Add-AzureGuest -displayName "Jan Novak" -emailAddress "novak@seznam.cz"
    #>

    [CmdletBinding()]
    [Alias("New-AzureADGuest")]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript( {
                If ($_ -match "\(guest\)") {
                    throw "$_ (guest) will be added automatically."
                } else {
                    $true
                }
            })]
        [string] $displayName
        ,
        [Parameter(Mandatory = $true)]
        [ValidateScript( {
                If ($_ -match "@") {
                    $true
                } else {
                    Throw "$_ isn't email address"
                }
            })]
        [string] $emailAddress
        ,
        [ValidateScript( {
                If ($_ -notmatch "^External_") {
                    throw "$_ doesn't allow guest members (doesn't start with External_ prefix, so guests will be automatically removed)"
                } else {
                    $true
                }
            })]
        [string] $parentTeamsGroup
    )

    $null = Connect-MgGraph

    # naming conventions
    (Get-Variable displayName).Attributes.Clear()
    $displayName = $displayName.trim() + " (guest)"
    $emailAddress = $emailAddress.trim()

    "Creating Guest: $displayName EMAIL: $emailaddress"

    $null = New-MgInvitation -InvitedUserDisplayName $displayName -InvitedUserEmailAddress $emailAddress -InviteRedirectUrl "https://myapps.microsoft.com" -SendInvitationMessage:$true -InvitedUserType Guest

    if ($parentTeamsGroup) {
        $groupID = Get-MgGroup -Filter "displayName eq '$parentTeamsGroup'" | select -exp Id
        if (!$groupID) { throw "Unable to find group $parentTeamsGroup" }
        $guestId = Get-MgUser -Filter "mail eq '$emailaddress'" | select -exp Id
        New-MgGroupMember -GroupId $groupID -DirectoryObjectId $guestId
    }
}