function Get-SharepointSiteOwner {
    <#
    .SYNOPSIS
    Get all Sharepoint sites and their owners.
    For O365 group sites, group owners will be outputted instead of the site one.

    .DESCRIPTION
    Get all Sharepoint sites and their owners.
    For O365 group sites, group owners will be outputted instead of the site one.

    .PARAMETER templateToIgnore
    List of site templates that will be ignored.

    By default:
    "SRCHCEN#0", "SPSMSITEHOST#0", "APPCATALOG#0", "POINTPUBLISHINGHUB#0", "EDISC#0", "STS#-1" (Search Center, Mysite Host, App Catalog, Content Type Hub, eDiscovery and Bot Sites)

    .EXAMPLE
    Connect-PnPOnline -Url "https://contoso.sharepoint.com" -Tenant 'contoso.onmicrosoft.com' -Credentials (Get-Credential)

    Get-SharepointSiteOwner

    Authenticate using user credentials and get all sites and their owners.

    .EXAMPLE
    Connect-PnPOnline -Url "https://contoso.sharepoint.com" -Tenant 'contoso.onmicrosoft.com' -ClientId 6c5c98c7-e05a-4a0f-bcfa-0cfc65aa1f28 -Thumbprint 34CFAA860E5FB8C44335A38A097C1E41EEA206AA

    Get-SharepointSiteOwner

    Authenticate using service principal (certificate) and get all sites and their owners.

    .EXAMPLE
    Connect-PnPOnline -Url "https://contoso.sharepoint.com" -Tenant 'contoso.onmicrosoft.com' -ClientId cd2ae428-35f9-41b4-a527-71f2f8f1e5cf -CertificatePath 'c:\appCert.pfx' -CertificatePassword (Read-Host -AsSecureString)

    Get-SharepointSiteOwner

    Authenticate using service principal (certificate) and get all sites and their owners.

    .NOTES
    Requires permissions: Sites.ReadWrite.All, Group.Read.All, User.Read.All

    https://www.sharepointdiary.com/2018/02/get-sharepoint-online-site-owner-using-powershell.html#ixzz7KCF1aDQ7
    https://www.sharepointdiary.com/2016/02/get-all-site-collections-in-sharepoint-online-using-powershell.html#ixzz7KDTA4xem
    #>

    [CmdletBinding()]
    param (
        [string[]] $templateToIgnore = @("SRCHCEN#0", "SPSMSITEHOST#0", "APPCATALOG#0", "POINTPUBLISHINGHUB#0", "EDISC#0", "STS#-1")
    )

    try {
        $null = Get-PnPConnection -ea Stop
    } catch {
        throw "You must call the Connect-PnPOnline cmdlet before calling any other cmdlets."
    }

    #Get All Site collections
    $SitesCollection = Get-PnPTenantSite | where Template -NotIn $templateToIgnore

    ForEach ($site in $sitesCollection) {
        $owner = $null
        Write-Verbose "Processing $($site.Url) site"

        if ($site.Template -like 'GROUP*') {
            #Get Group Owners
            try {
                Write-Verbose "`t- is group site, searching for group $($site.GroupId) owners"
                $owner = Get-PnPMicrosoft365GroupOwners -Identity ($site.GroupId) -ErrorAction Stop | % { if ($_.UserPrincipalName) { $_.UserPrincipalName } else { $_.Email } }
            } catch {
                if (($_ -match "does not exist or one of its queried reference-property objects are not present") -or ($_ -match "Group not found")) {
                    # group doesn't have any owner
                    $owner = "<<source group is missing>>"
                } else {
                    Write-Error $_
                }
            }
        } else {
            #Get Site Owner
            $owner = $site.Owner
        }

        [PSCustomObject]@{
            Site     = $site.Url
            Owner    = $owner
            Title    = $site.Title
            Template = $site.Template
        }
    }
}

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
    Remove-O365OrphanedMailbox -samAccountName JohnD -notSyncedOUDN "OU=notSynedToAAD,DC=contoso,DC=com"

    Fixes orphaned mailbox problem for user JohnD.

    .NOTES
    https://www.reddit.com/r/Office365/comments/mgfh1u/office_365_removing_litigation_hold_mailboxes_in/
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $samAccountName,

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

    $userADObj = Get-ADUser $samAccountName -ErrorAction Stop

    $originalOU = ($userADObj.DistinguishedName -split ",")[1..1000] -join ','

    if ($userADObj.enabled) {
        throw "User $samAccountName is enabled. There is high probability you don't want to do this!"
    }

    $UPN = $userADObj.UserPrincipalName

    Connect-ExchangeOnline -ErrorAction Stop

    $null = Connect-MgGraph -Scopes User.ReadWrite.All -ea Stop

    $userAADObj = Get-MgUser -Filter "userPrincipalName eq '$UPN'"
    if (!$userAADObj) {
        throw "User $UPN doesn't exist in AAD"
    }

    # move account to NOT-AzureAD-synchronized OU
    "Moving user to '$notSyncedOUDN' OU (OU that MUST NOT be synchronized to AzureAD)"
    Move-ADObject -Identity $userADObj.ObjectGUID -TargetPath $notSyncedOUDN

    # synchronize these changes to AzureAD >> user should be deleted there automatically
    "Starting AzureAD directory sync"
    Start-AzureSync

    # wait for user deletion in AzureAD
    do {
        "..waiting for user $UPN removal in AzureAD"
        Start-Sleep 10
    } while (Get-MgUser -Filter "userPrincipalName eq '$UPN'")

    # restore deleted user
    "Restoring user"
    $null = Restore-MgDirectoryDeletedItem -DirectoryObjectId $userAADObj.Id

    # wait for user restoration in AzureAD
    do {
        "..waiting for (now not dir-synced) $UPN user restoration in AzureAD"
        Start-Sleep 10
    } while (!(Get-MgUser -Filter "userPrincipalName eq '$UPN'"))

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

    if ((Get-MgUser -Filter "userPrincipalName eq '$UPN'" -Property OnPremisesImmutableId).OnPremisesImmutableId) {
        "Clearing ImmutableId"
        $userId = (Get-MgUser -Filter "userPrincipalName eq '$UPN'" -Property Id).Id
        Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/users/$userId" -Body @{OnPremisesImmutableId = $null }
    }
    #endregion steps to make sure mailbox won't be attached/recreated to this account again

    # move account back to original OU
    "Moving account back to $originalOU OU"
    Move-ADObject -Identity $userADObj.ObjectGUID -TargetPath $originalOU

    # synchronize these changes to AzureAD >> user should be deleted there automatically

    "Starting AzureAD directory sync, to 'attach' on-premises account with the AzureAD account representation"
    Start-AzureSync -type initial

    do {
        "..waiting for user to be attached"
        Start-Sleep 10
    } while (!(Get-MgUser -Filter "userPrincipalName eq '$UPN'"))
}

Export-ModuleMember -function Get-SharepointSiteOwner, Remove-O365OrphanedMailbox

