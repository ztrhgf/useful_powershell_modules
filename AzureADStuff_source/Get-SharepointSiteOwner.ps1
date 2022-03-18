#Requires -Module Pnp.PowerShell
function Get-SharepointSiteOwner {
    <#
    .SYNOPSIS
    Get all Sharepoint sites and their owners.
    For O365 group sites, group owners will be outputted instead of the site one.

    .DESCRIPTION
    Get all Sharepoint sites and their owners.
    For O365 group sites, group owners will be outputted instead of the site one.

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
    param ()

    try {
        $null = Get-PnPConnection -ea Stop
    } catch {
        throw "You must call the Connect-PnPOnline cmdlet before calling any other cmdlets."
    }

    #Get All Site collections - Exclude: Search Center, Mysite Host, App Catalog, Content Type Hub, eDiscovery and Bot Sites
    $SitesCollection = Get-PnPTenantSite | where Template -NotIn ("SRCHCEN#0", "SPSMSITEHOST#0", "APPCATALOG#0", "POINTPUBLISHINGHUB#0", "EDISC#0", "STS#-1")

    ForEach ($site in $sitesCollection) {
        $owner = $null

        if ($site.Template -like 'GROUP*') {
            #Get Group Owners
            try {
                $owner = Get-PnPMicrosoft365GroupOwners -Identity ($site.GroupId) -ErrorAction Stop | select -ExpandProperty Email
            } catch {
                if ($_ -match "does not exist or one of its queried reference-property objects are not present") {
                    # group doesn't have any owner
                } elseif ($_ -match "Group not found") {
                    $owner = "<<source group is missing>>"
                    Write-Error $_
                } else {
                    Write-Error $_
                }
            }
        } else {
            #Get Site Owner
            $owner = $site.Owner
        }

        [PSCustomObject]@{
            Site  = $site.Url
            Owner = $owner
            Title = $site.Title
        }
    }
}