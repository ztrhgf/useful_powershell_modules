#requires -modules ActiveDirectory, ExchangeOnlineManagement, MSOnline
function Remove-O365OrphanedMailbox {
    <#
    .SYNOPSIS
    Function for removal of O365 user mailbox for dir-synced user accounts that gets orphaned in AzureAD.

    .DESCRIPTION
    Function for removal of O365 user mailbox for dir-synced user accounts that gets orphaned in AzureAD.

    The function will:
    - move user account to OU that is not synchronized to AzureAD
    - initialize dir-sync, so the user account gets deleted in AzureAD
    - restore user in AzureAD, but now it is not dir-synced i.e. we can modify it in AzureAD
    - remove litigation hold settings
    - remove user mailbox
    - clear user connection-with-mailbox data
    - clear immutableId
    - move account to original OU
    - attach on-premises account with AzureAD account

    .PARAMETER samAccountName
    User samAccountName.

    .PARAMETER notSyncedOUDN
    Distinguished name of the OU that is NOT synchronized to your AzureAD.

    .EXAMPLE
    Remove-O365OrphanedMailbox -samAccountName ondrejs4 -notSyncedOUDN "OU=notSynedToAAD,DC=contoso,DC=com"

    Fixes orphaned mailbox problem for user ondrejs4.

    .NOTES
    https://www.reddit.com/r/Office365/comments/mgfh1u/office_365_removing_litigation_hold_mailboxes_in/
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $samAccountName,

        [Parameter(Mandatory = $true)]
        [ValidateScript( {
                if (Get-ADOrganizationalUnit $_) {
                    $true
                } else {
                    throw "$_ is not a valid OU distinguished name. Enter distinguished name of the OU that is NOT synced into AzureAD."
                }
            })]
        [string] $notSyncedOUDN
    )

    if (!(Get-Module ActiveDirectory -ListAvailable)) {
        if ((Get-WmiObject win32_operatingsystem -Property caption).caption -match "server") {
            throw "Module ActiveDirectory is missing. Use: Install-WindowsFeature RSAT-AD-PowerShell -IncludeManagementTools" 
        } else {
            throw "Module ActiveDirectory is missing. Use: Get-WindowsCapability -Name RSAT* -Online | Add-WindowsCapability -Online"
        }
    }

    if (!(Get-Module ExchangeOnlineManagement -ListAvailable)) {
        throw "Module ExchangeOnlineManagement is missing. To get it, use: Install-Module ExchangeOnlineManagement" 
    }

    if (!(Get-Module MSOnline -ListAvailable)) {
        throw "Module MSOnline is missing. To get it, use: Install-Module MSOnline" 
    }

    $userADObj = Get-ADUser $samAccountName -ErrorAction Stop

    $originalOU = ($userADObj.DistinguishedName -split ",")[1..1000] -join ','

    if ($userADObj.enabled) {
        throw "User $samAccountName is enabled. There is high probability you don't want to do this!"
    }

    $UPN = $userADObj.UserPrincipalName

    Connect-ExchangeOnline -ErrorAction Stop
    Connect-MsolService -ErrorAction Stop

    # move account to NOT-AzureAD-synchronized OU
    "Moving user to '$notSyncedOUDN' OU (OU that MUST NOT be synchronized to AzureAD)"
    Move-ADObject -Identity $userADObj.ObjectGUID -TargetPath $notSyncedOUDN

    # synchronize these changes to AzureAD >> user should be deleted there automatically
    "Starting AzureAD directory sync"
    Start-AzureADSync

    # wait for user deletion in AzureAD
    do {
        "..waiting for user $UPN removal in AzureAD"
        Start-Sleep 10
    } while (Get-MsolUser -UserPrincipalName $UPN -ErrorAction SilentlyContinue)

    # restore deleted user
    "Restoring user"
    Restore-MsolUser -UserPrincipalName $UPN | Out-Null

    # wait for user restoration in AzureAD
    do {
        "..waiting for (now not dir-synced) $UPN user restoration in AzureAD"
        Start-Sleep 10
    } while (!(Get-MsolUser -UserPrincipalName $UPN -ErrorAction SilentlyContinue))

    "Removing litigation hold settings"
    Set-mailbox -identity $UPN -removedelayholdapplied
    Set-mailbox -identity $UPN -removedelayreleaseholdapplied

    "..waiting for changes to apply"
    Start-Sleep 60

    # remove mailbox
    if (Get-Mailbox -identity $UPN -ErrorAction SilentlyContinue) {
        "Removing mailbox for $UPN"
        Disable-Mailbox -identity $UPN -permanentlyDisable -confirm:$false

        do {
            "..waiting for mailbox to disappear"
            Start-Sleep 10
        } while (Get-Mailbox -identity $UPN -ErrorAction SilentlyContinue)
    } else {
        "Mailbox for $UPN was removed"
    }

    #region steps to make sure mailbox won't be attached/recreated to this account again
    if ((Get-User -identity $UPN).PreviousRecipientTypeDetails -eq 'UserMailbox') {
        "Clearing connection to old mailbox"
        Set-user -identity $UPN -permanentlyclearpreviousmailboxinfo -confirm:$false
    }

    if ((Get-MsolUser -UserPrincipalName $UPN).ImmutableId) {
        "Clearing ImmutableId"
        Get-MsolUser -UserPrincipalName $UPN | Set-MsolUser -ImmutableId ""
    }
    #endregion steps to make sure mailbox won't be attached/recreated to this account again

    # move account back to original OU
    "Moving account back to $originalOU OU"
    Move-ADObject -Identity $userADObj.ObjectGUID -TargetPath $originalOU

    # synchronize these changes to AzureAD >> user should be deleted there automatically

    "Starting AzureAD directory sync, to 'attach' on-premises account with the AzureAD account representation"
    Start-AzureADSync -type initial

    do {
        "..waiting for user to be attached"
        Start-Sleep 10
    } while (!(Get-MsolUser -Synchronized -All -SearchString $UPN))
}