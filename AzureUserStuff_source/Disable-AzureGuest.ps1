#requires -modules Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Users.Actions
function Disable-AzureGuest {
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
    Disable-AzureGuest -displayName "Jan Novak (guest)"

    Disables "Jan Novak (guest)" guest Azure AD account.

    .EXAMPLE
    Disable-AzureGuest

    Show GUI with all available guest accounts. The selected one will be disabled.
    #>

    [CmdletBinding()]
    [Alias("Remove-AzureADGuest")]
    param (
        [string[]] $displayName
    )

    $null = Connect-MgGraph -ea Stop

    $guestId = @()

    if (!$displayName) {
        # Get all the Guest Users
        $guest = Get-MgUser -All -Filter "UserType eq 'Guest' and AccountEnabled eq true" | select DisplayName, Mail, Id | Out-GridView -OutputMode Multiple -Title "Select accounts for disable"
        $guestId = $guest.id
    } else {
        $displayName | % {
            $guest = Get-MgUser -Filter "DisplayName eq '$_' and UserType eq 'Guest' and AccountEnabled eq true"
            if ($guest) {
                $guestId += $guest.Id
            } else {
                Write-Warning "$_ wasn't found or it is not guest account or is disabled already"
            }
        }
    }

    if ($guestId) {
        $guestId | % {
            "Blocking guest $_"

            # block Sign-In
            Update-MgUser -UserId $_ -AccountEnabled:$false

            # invalidate Azure AD Tokens
            $null = Revoke-MgUserSignInSession -UserId $_ -Confirm:$false
        }
    } else {
        Write-Warning "No guest to disable"
    }
}