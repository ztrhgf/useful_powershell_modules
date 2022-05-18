function Disable-AzureADGuest {
    <#
    .SYNOPSIS
    Function for disabling guest user in Azure AD.

    .DESCRIPTION
    Function for disabling guest user in Azure AD.

    Do NOT REMOVE the account, because lot of connected systems use UPN as identifier instead of SID.
    Therefore if someone in the future add such guest again, he would get access to all stuff, previous guest had access to.

    .PARAMETER displayName
    Display name of the user.

    If not specified, GUI with all guests will popup.

    .EXAMPLE
    Disable-AzureADGuest -displayName "Jan Novak (guest)"

    Disables "Jan Novak (guest)" guest Azure AD account.

    .EXAMPLE
    Disable-AzureADGuest

    Show GUI with all available guest accounts. The selected one will be disabled.
    #>

    [CmdletBinding()]
    [Alias("Remove-AzureADGuest")]
    param (
        [string[]] $displayName
    )

    Connect-AzureAD2 -ea Stop

    $guestId = @()

    if (!$displayName) {
        # Get all the Guest Users
        $guest = Get-AzureADUser -Filter "UserType eq 'Guest' and AccountEnabled eq true" | select DisplayName, Mail, ObjectId | Out-GridView -OutputMode Multiple -Title "Select accounts for disable"
        $guestId = $guest.ObjectId
    } else {
        $displayName | % {
            $guest = Get-AzureADUser -Filter "DisplayName eq '$_' and UserType eq 'Guest' and AccountEnabled eq true"
            if ($guest) {
                $guestId += $guest.ObjectId
            } else {
                Write-Warning "$_ wasn't found or it is not guest account or is disabled already"
            }
        }
    }

    if ($guestId) {
        # block Sign-In
        Set-AzureADUser -ObjectId $_ -AccountEnabled $false

        # invalidate Azure AD Tokens
        Revoke-AzureADUserAllRefreshToken -ObjectId $_
    } else {
        Write-Warning "No guest to disable"
    }
}