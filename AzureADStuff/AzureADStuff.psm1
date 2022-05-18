#Requires -Modules AzureAD

function Add-AzureADAppCertificate {
    <#
    .SYNOPSIS
    Function for (creating and) adding authentication certificate to selected AzureAD Application.

    .DESCRIPTION
    Function for (creating and) adding authentication certificate to selected AzureAD Application.

    Use this function with cerPath parameter (if you already have existing certificate you want to add) or rest of the parameters (if you want to create it first). If new certificate will be create, it will be named as application ID of the corresponding enterprise app.

    .PARAMETER appObjectId
    ObjectId of the Azure application registration, to which you want to assign certificate.

    .PARAMETER cerPath
    Path to existing '.cer' certificate which should be added to the application.

    .PARAMETER StartDate
    Datetime object defining since when certificate will be valid.

    Default value is now.

    .PARAMETER EndDate
    Datetime object defining to when certificate will be valid.

    Default value is 2 years from now.

    .PARAMETER Password
    Secure string with password that will protect certificate private key.

    Choose strong one!

    .PARAMETER directory
    Path to folder where pfx (cert. with private key) certificate will be exported.

    .PARAMETER dontRemoveFromCertStore
    Switch to NOT remove certificate from the local cert. store after it is created&exported to pfx.

    .EXAMPLE
    Add-AzureADAppCertificate -appObjectId cc210920-4c75-48ad-868b-6aa2dbcd1d51 -cerPath C:\cert\appCert.cer

    Adds certificate 'appCert' to the Azure application cc210920-4c75-48ad-868b-6aa2dbcd1d51.

    .EXAMPLE
    Add-AzureADAppCertificate -appObjectId cc210920-4c75-48ad-868b-6aa2dbcd1d51 -password (Read-Host -AsSecureString)

    Creates new self signed certificate, export it as pfx (cert with private key) into working directory and adds its public counterpart (.cer) it to the Azure application cc210920-4c75-48ad-868b-6aa2dbcd1d51.
    Certificate private key will be protected by entered password and it will be valid 2 years from now.

    .NOTES
    http://vcloud-lab.com/entries/microsoft-azure/create-an-azure-app-registrations-in-azure-active-directory-using-powershell-azurecli
    https://docs.microsoft.com/en-us/sharepoint/dev/solution-guidance/security-apponly-azuread
    #>

    [CmdletBinding(DefaultParameterSetName = 'createCert')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "cerExists")]
        [Parameter(Mandatory = $true, ParameterSetName = "createCert")]
        [string] $appObjectId,

        [Parameter(Mandatory = $true, ParameterSetName = "cerExists")]
        [ValidateScript( {
                if ($_ -match ".cer$" -and (Test-Path -Path $_)) {
                    $true
                } else {
                    throw "$_ is not a .cer file or doesn't exist"
                }
            })]
        [string] $cerPath,

        [Parameter(Mandatory = $false, ParameterSetName = "createCert")]
        [DateTime] $startDate = (Get-Date),

        [Parameter(Mandatory = $false, ParameterSetName = "createCert")]
        [ValidateScript( {
                if ($_ -gt (Get-Date)) {
                    $true
                } else {
                    throw "$_ has to be in the future"
                }
            })]
        [DateTime] $endDate = (Get-Date).AddYears(2),

        [Parameter(Mandatory = $true, ParameterSetName = "createCert")]
        [SecureString]$password,

        [Parameter(Mandatory = $false, ParameterSetName = "createCert")]
        [ValidateScript( {
                if (Test-Path -Path $_ -PathType Container) {
                    $true
                } else {
                    throw "$_ is not a folder or doesn't exist"
                }
            })]
        [string] $directory = (Get-Location),

        [switch] $dontRemoveFromCertStore
    )

    try {
        # test if connection already exists
        $null = Get-AzureADCurrentSessionInfo -ea Stop
    } catch {
        throw "You must call the Connect-AzureAD cmdlet before calling any other cmdlets."
    }

    # test that app exists
    try {
        $application = Get-AzureADApplication -ObjectId $appObjectId -ErrorAction Stop
        # corresponding enterprise app ID
        $entAppId = $application.AppId
    } catch {
        throw "Application registration with ObjectId $appObjectId doesn't exist"
    }

    if ($cerPath) {
        $cert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2($cerPath)
    } else {
        Write-Warning "Creating self signed certificate named '$entAppId'"
        $cert = New-SelfSignedCertificate -CertStoreLocation 'cert:\currentuser\my' -Subject "CN=$entAppId" -NotBefore $startDate -NotAfter $endDate -KeySpec Signature -KeyLength 2048 -KeyAlgorithm RSA -HashAlgorithm SHA256

        Write-Warning "Exporting '$entAppId.pfx' to '$directory'"
        $pfxFile = Join-Path $directory "$entAppId.pfx"
        $path = 'cert:\currentuser\my\' + $cert.Thumbprint
        $null = Export-PfxCertificate -Cert $path -FilePath $pfxFile -Password $password

        if (!$dontRemoveFromCertStore) {
            Write-Verbose "Removing created certificate from cert. store"
            Get-ChildItem 'cert:\currentuser\my' | ? { $_.thumbprint -eq $cert.Thumbprint } | Remove-Item
        }
    }

    $keyValue = [System.Convert]::ToBase64String($cert.GetRawCertData())
    $base64Thumbprint = [System.Convert]::ToBase64String($cert.GetCertHash())
    $endDateTime = ($cert.NotAfter).ToUniversalTime().ToString( "yyyy-MM-ddTHH:mm:ssZ" )
    $startDateTime = ($cert.NotBefore).ToUniversalTime().ToString( "yyyy-MM-ddTHH:mm:ssZ" )

    Write-Warning "Adding certificate to the application $($application.DisplayName)"
    New-AzureADApplicationKeyCredential -ObjectId $appObjectId -CustomKeyIdentifier $base64Thumbprint -Type AsymmetricX509Cert -Usage Verify -Value $keyValue -StartDate $startDateTime -EndDate $endDateTime
}

#Requires -Modules Microsoft.Graph.Authentication,Microsoft.Graph.Applications,Microsoft.Graph.Users,Microsoft.Graph.Identity.SignIns

function Add-AzureADAppUserConsent {
    <#
    .SYNOPSIS
    Function for granting consent on behalf of a user to chosen application over selected resource(s) (enterprise app(s)) and permission(s) and assign the user default app role to be able to see the app in his 'My Apps'.

    .DESCRIPTION
    Function for granting consent on behalf of a user to chosen application over selected resource(s) (enterprise app(s)) and permission(s) and assign the user default app role to be able to see the app in his 'My Apps'.

    Consent can be explicitly specified or copied from some existing one.

    .PARAMETER clientAppId
    ID of application you want to grant consent on behalf of a user.

    .PARAMETER consent
    Hashtable where:
    - key is objectId of the resource (enterprise app) you are granting permissions to
    - value is list of permissions strings (scopes)

    Both can be found at Permissions tab of the enterprise app in Azure portal, when you select particular permission.

    For example:
    $consent = @{
        "02ad85cd-02ce-4902-a319-1af611526021" = "User.Read", "Contacts.ReadWrite", "Calendars.ReadWrite", "Mail.Send", "Mail.ReadWrite", "EWS.AccessAsUser.All"
    }

    .PARAMETER copyExistingConsent
    Switch for getting consent details (resource ObjectId and permissions) from existing user consent.
    You will be asked for confirmation before proceeding.

    .PARAMETER userUpnOrId
    User UPN or ID.

    .EXAMPLE
    $consent = @{
        "88690023-f9e1-4728-9028-cdcc6bf67d22" = "User.Read"
        "02ad85cd-02ce-4902-a319-1af611526021" = "User.Read", "Contacts.ReadWrite", "Calendars.ReadWrite", "Mail.Send", "Mail.ReadWrite", "EWS.AccessAsUser.All"
    }

    Add-AzureADAppUserConsent -clientAppId "00b263e4-3497-4650-b082-3197cfdfdd7c" -consent $consent -userUpnOrId "dealdesk@contoso.onmicrosoft.com"

    Grants consent on behalf of the "dealdesk@contoso.onmicrosoft.com" user to application "Salesforce Inbox" (00b263e4-3497-4650-b082-3197cfdfdd7c) and given permissions on resource (ent. application) "Office 365 Exchange Online" (02ad85cd-02ce-4902-a319-1af611526021) and "Windows Azure Active Directory" (88690023-f9e1-4728-9028-cdcc6bf67d22).

    .EXAMPLE
    Add-AzureADAppUserConsent -clientAppId "00b263e4-3497-4650-b082-3197cfdfdd7c" -copyExistingConsent -userUpnOrId "dealdesk@contoso.onmicrosoft.com"

    Grants consent on behalf of the "dealdesk@contoso.onmicrosoft.com" user to application "Salesforce Inbox" (00b263e4-3497-4650-b082-3197cfdfdd7c) based on one of the existing consents.

    .NOTES
    https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/grant-consent-single-user
    #>

    [CmdletBinding()]
    param (
        # The app for which consent is being granted
        [Parameter(Mandatory = $true)]
        [string] $clientAppId,

        [Parameter(Mandatory = $true, ParameterSetName = "explicit")]
        [hashtable] $consent,

        [Parameter(ParameterSetName = "copyConsent")]
        [switch] $copyExistingConsent,

        [Parameter(Mandatory = $true)]
        # The user on behalf of whom access will be granted. The app will be able to access the API on behalf of this user.
        [string] $userUpnOrId
    )

    $ErrorActionPreference = "Stop"

    #region connect to Microsoft Graph PowerShell
    # we need User.ReadBasic.All to get
    # users' IDs, Application.ReadWrite.All to list and create service principals,
    # DelegatedPermissionGrant.ReadWrite.All to create delegated permission grants,
    # and AppRoleAssignment.ReadWrite.All to assign an app role.
    # WARNING: These are high-privilege permissions!

    Import-Module Microsoft.Graph.Authentication
    Import-Module Microsoft.Graph.Applications
    Import-Module Microsoft.Graph.Users
    Import-Module Microsoft.Graph.Identity.SignIns

    Connect-AzureAD -asYourself

    $null = Connect-MgGraph -Scopes ("User.ReadBasic.All", "Application.ReadWrite.All", "DelegatedPermissionGrant.ReadWrite.All", "AppRoleAssignment.ReadWrite.All")
    #endregion connect to Microsoft Graph PowerShell

    $clientSp = Get-MgServicePrincipal -Filter "appId eq '$($clientAppId)'"
    if (-not $clientSp) {
        throw "Enterprise application with Application ID $clientAppId doesn't exist"
    }

    # prepare consent from the existing one
    if ($copyExistingConsent) {
        $consent = @{}

        Get-AzureADServicePrincipalOAuth2PermissionGrant -ObjectId $clientSp.id -All:$true | group resourceId | select @{n = 'ResourceId'; e = { $_.Name } }, @{n = 'ScopeToGrant'; e = { $_.group | select -First 1 | select -ExpandProperty scope } } | % {
            $consent.($_.ResourceId) = $_.ScopeToGrant
        }

        if (!$consent.Keys) {
            throw "There is no existing user consent that can be cloned. Use parameter consent instead."
        } else {
            "Following consent(s) will be added:"
            $consent.GetEnumerator() | % {
                $resourceSp = Get-MgServicePrincipal -Filter "id eq '$($_.key)'"
                if (!$resourceSp) {
                    throw "Resource with ObjectId $($_.key) doesn't exist"
                }
                " - resource '$($resourceSp.DisplayName)' permission: $(($_.value | sort) -join ', ')"
            }

            $choice = ""
            while ($choice -notmatch "^[Y|N]$") {
                $choice = Read-Host "`nContinue? (Y|N)"
            }
            if ($choice -eq "N") {
                break
            }
        }
    }

    #region create a delegated permission that grants the client app access to the API, on behalf of the user.
    $user = Get-MgUser -UserId $userUpnOrId
    if (!$user) {
        throw "User $userUpnOrId doesn't exist"
    }

    foreach ($item in $consent.GetEnumerator()) {
        $resourceId = $item.key
        $scope = $item.value

        if (!$scope) {
            throw "You haven't specified any scope for resource $resourceId"
        }

        $resourceSp = Get-MgServicePrincipal -Filter "id eq '$resourceId'"
        if (!$resourceSp) {
            throw "Resource with ObjectId $resourceId doesn't exist"
        }

        # convert scope string (perm1 perm2) i.e. permission joined by empty space (returned by Get-AzureADServicePrincipalOAuth2PermissionGrant) into array
        if ($scope -match "\s+") {
            $scope = $scope -split "\s+" | ? { $_ }
        }

        $scopeToGrant = $scope

        # check if user already granted some permissions to this app for such resource
        # and skip such permissions to avoid errors
        $scopeAlreadyGranted = Get-MgOauth2PermissionGrant -Filter "principalId eq '$($user.Id)' and clientId eq '$($clientSp.Id)' and resourceId eq '$resourceId'" | select -ExpandProperty Scope
        if ($scopeAlreadyGranted) {
            Write-Verbose "Some permission(s) ($($scopeAlreadyGranted.trim())) are already granted to an app '$($clientSp.Id)' and resourceId '$resourceId'"
            $scopeAlreadyGrantedList = $scopeAlreadyGranted.trim() -split "\s+"

            $scopeToGrant = $scope | ? { $_ } | % {
                if ($_ -in $scopeAlreadyGrantedList) {
                    Write-Warning "Permission '$_' is already granted. Skipping"
                } else {
                    $_
                }
            }

            if (!$scopeToGrant) {
                Write-Warning "All permissions for resource $resourceId are already granted. Skipping"
                continue
            }
        }

        Write-Warning "Grant user consent on behalf of '$userUpnOrId' for application '$($clientSp.DisplayName)' to have following permission(s) '$(($scopeToGrant.trim() | sort) -join ', ')' over API '$($resourceSp.DisplayName)'"

        $grant = New-MgOauth2PermissionGrant -ResourceId $resourceSp.Id -Scope ($scopeToGrant -join " ") -ClientId $clientSp.Id -ConsentType "Principal" -PrincipalId $user.Id
    }
    #endregion create a delegated permission that grants the client app access to the API, on behalf of the user.

    #region assign the app to the user.
    # this ensures that the user can sign in if assignment is required, and ensures that the app shows up under the user's My Apps.
    $userAssignableRole = $clientSp.AppRoles | ? { $_.AllowedMemberTypes -contains "User" }
    if ($userAssignableRole) {
        Write-Warning "A default app role assignment cannot be created because the client application exposes user-assignable app roles ($($userAssignableRole.DisplayName -join ', ')). You must assign the user a specific app role for the app to be listed in the user's My Apps access panel."
    } else {
        if (Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $clientSp.Id -Property AppRoleId, PrincipalId | ? PrincipalId -EQ $user.Id) {
            # user already have some app role assigned
            Write-Verbose "User already have some app role assigned. Skipping default app role assignment."
        } else {
            # the app role ID 00000000-0000-0000-0000-000000000000 is the default app role
            # indicating that the app is assigned to the user, but not for any specific app role.
            Write-Verbose "Assigning default app role to the user"
            $assignment = New-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $clientSp.Id -ResourceId $clientSp.Id -PrincipalId $user.Id -AppRoleId "00000000-0000-0000-0000-000000000000"
        }
    }
    #endregion assign the app to the user.
}

#Requires -Modules Az.Accounts

function Connect-AzAccount2 {
    <#
    .SYNOPSIS
    Function for connecting to Azure using Connect-AzAccount command (Az.Accounts module).

    .DESCRIPTION
    Function for connecting to Azure using Connect-AzAccount command (Az.Accounts module).
    In case there is already existing connection, stop.

    .PARAMETER credential
    Credentials (User or App) for connecting to Azure.
    For App credentials tenantId must be set too!

    .PARAMETER servicePrincipal
    Switch for using App/Service Principal authentication instead of User auth.

    .PARAMETER tenantId
    Azure tenant ID.
    Mandatory when App authentication is used .

    .EXAMPLE
    Connect-AzAccount2

    Authenticate to Azure interactively using user credentials. Doesn't work for accounts with MFA!

    .EXAMPLE
    $credential = get-credential
    Connect-AzAccount2 -credential $credential

    Authenticate to Azure using given user credentials. Doesn't work for accounts with MFA!

    .EXAMPLE
    $credential = get-credential
    Connect-AzAccount2 -servicePrincipal -credential $credential -tenantId 1234-1234-1234

    Authenticate to Azure using given app credentials (service principal).

    .NOTES
    Requires module Az.Accounts.
    #>

    [CmdletBinding()]
    param (
        [System.Management.Automation.PSCredential] $credential,

        [switch] $servicePrincipal,

        [string] $tenantId = $_tenantId
    )

    if (Get-AzContext) {
        Write-Verbose "Already connected to Azure"
        return
    } else {
        if ($servicePrincipal -and !$tenantId) {
            throw "When servicePrincipal auth is used tenantId has to be set"
        }

        $param = @{}
        if ($servicePrincipal) { $param.servicePrincipal = $true }
        if ($tenantId) { $param.tenantId = $tenantId }
        if ($credential) { $param.credential = $credential }

        Connect-AzAccount @param
    }
}

function Connect-AzureAD2 {
    <#
    .SYNOPSIS
    Function for connecting to Azure AD. Reuse already existing session if possible.
    Supports user and app authentication.

    .DESCRIPTION
    Function for connecting to Azure AD. Reuse already existing session if possible.
    Supports user and app authentication.

    .PARAMETER tenantId
    Azure AD tenant domain name/id.
    It is optional for user auth. but mandatory for app. auth!

    Default is $_tenantId.

    .PARAMETER credential
    User credentials for connecting to AzureAD.

    .PARAMETER asYourself
    Switch for user authentication using current user credentials.

    .PARAMETER applicationId
    Application ID of the enterprise application.
    Mandatory for app. auth.

    .PARAMETER certificateThumbprint
    Thumbprint of the certificate that should be used for app. auth.
    Corresponding certificate has to exists in machine certificate store and user must have permissions to read its private key!

    .PARAMETER returnConnection
    Switch for returning connection info (like original Connect-AzureAD command do).

    How to create such certificate:
    $pwd = "nejakeheslo"
    $notAfter = (Get-Date).AddMonths(60)
    $thumb = (New-SelfSignedCertificate -DnsName "someDNSname" -CertStoreLocation "cert:\LocalMachine\My" -KeyExportPolicy Exportable -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider" -NotAfter $notAfter).Thumbprint
    $pwd = ConvertTo-SecureString -String $pwd -Force -AsPlainText
    Export-PfxCertificate -Cert "cert:\localmachine\my\$thumb" -FilePath c:\temp\examplecert.pfx -Password $pwd
    udelat export public casti certifikatu (.cer) a naimportovat k vybrane aplikaci v Azure portalu

    .EXAMPLE
    Connect-AzureAD2 -asYourself

    Connect using current user credentials.

    .EXAMPLE
    Connect-AzureAD2 -credential (Get-Credential)

    Connect using user credentials.

    .EXAMPLE
    $thumbprint = Get-ChildItem Cert:\LocalMachine\My | ? subject -EQ "CN=kenticosoftware.onmicrosoft.com" | select -ExpandProperty Thumbprint
    Connect-AzureAD2 -ApplicationId 'cd2ae428-35f9-21b4-a527-7d3gf8f1e5cf' -CertificateThumbprint $thumbprint

    Connect using app. authentication (certificate).
    #>

    [CmdletBinding(DefaultParameterSetName = 'userAuth')]
    param (
        [Parameter(ParameterSetName = "userAuth")]
        [System.Management.Automation.PSCredential] $credential,

        [Parameter(ParameterSetName = "userAuth")]
        [switch] $asYourself,

        [Parameter(ParameterSetName = "appAuth")]
        [Parameter(ParameterSetName = "userAuth")]
        [Alias("tenantDomain")]
        [string] $tenantId = $_tenantId,

        [Parameter(Mandatory = $true, ParameterSetName = "appAuth")]
        [string] $applicationId,

        [Parameter(Mandatory = $true, ParameterSetName = "appAuth")]
        [string] $certificateThumbprint,

        [switch] $returnConnection
    )

    if (!(Get-Command Connect-AzureAD -ea SilentlyContinue)) { throw "Module AzureAD is missing" }

    if ([Microsoft.Open.Azure.AD.CommonLibrary.AzureSession]::AccessTokens) {
        $token = [Microsoft.Open.Azure.AD.CommonLibrary.AzureSession]::AccessTokens
        Write-Verbose "Connected to tenant: $($token.AccessToken.TenantId) with user: $($token.AccessToken.UserId)"
    } else {
        if ($applicationId) {
            # app auth
            if (!$tenantId) { throw "tenantId parameter is undefined" }

            # check certificate
            foreach ($store in ('CurrentUser', 'LocalMachine')) {
                $cert = Get-Item "Cert:\$store\My\$certificateThumbprint" -ErrorAction SilentlyContinue
                if ($cert) {
                    if (!$cert.HasPrivateKey) {
                        throw "Certificate $certificateThumbprint doesn't contain private key!"
                    }
                    try {
                        $rsaCert = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
                    } catch {
                        throw "Account $env:USERNAME doesn't have right to read private key of certificate $certificateThumbprint (use Add-CertificatePermission to fix it)!"
                    }

                    break
                }
            }
            if (!$cert) { throw "Certificate $certificateThumbprint isn't located in $env:USERNAME nor $env:COMPUTERNAME Personal store" }

            $param = @{
                ErrorAction           = "Stop"
                TenantId              = $tenantId
                ApplicationId         = $applicationId
                CertificateThumbprint = $certificateThumbprint
            }

            if ($returnConnection) {
                Connect-AzureAD @param
            } else {
                $null = Connect-AzureAD @param
            }
        } else {
            # user auth
            $param = @{ errorAction = "Stop" }
            if ($credential) { $param.credential = $credential }
            if ($tenantId) { $param.TenantId = $tenantId }
            if ($asYourself) {
                $upn = whoami -upn
                if ($upn) {
                    $param.AccountId = $upn
                } else {
                    Write-Error "Unable to obtain your UPN. Run again without 'asYourself' switch"
                    return
                }
            }

            if ($returnConnection) {
                Connect-AzureAD @param
            } else {
                $null = Connect-AzureAD @param
            }
        }
    }
}

#Requires -Modules Pnp.PowerShell

function Connect-PnPOnline2 {
    <#
    .SYNOPSIS
    Proxy function for Connect-PnPOnline with some enhancements like: automatic MFA auth if MFA detected, skipping authentication if already authenticated etc.

    .DESCRIPTION
    Proxy function for Connect-PnPOnline with some enhancements like: automatic MFA auth if MFA detected, skipping authentication if already authenticated etc.

    .PARAMETER credential
    Credential object you want to use to authenticate to Sharepoint Online

    .PARAMETER appAuth
    Switch for using application authentication instead of the user one.

    .PARAMETER asMFAUser
    Switch for using user with MFA enabled authentication (i.e. interactive auth)

    .PARAMETER url
    Your sharepoint online url ("https://contoso-admin.sharepoint.com")

    .EXAMPLE
    Connect-PnPOnline2

    Connect to Sharepoint Online using user interactive authentication.

    .EXAMPLE
    Connect-PnPOnline2 -asMFAUser

    Connect to Sharepoint Online using (MFA-enabled) user interactive authentication.

    .EXAMPLE
    Connect-PnPOnline2 -appAuth

    Connect to Sharepoint Online using application interactive authentication.

    .EXAMPLE
    Connect-PnPOnline2 -appAuth -credential $cred

    Connect to Sharepoint Online using application non-interactive authentication.

    .EXAMPLE
    Connect-PnPOnline2 -credential $cred

    Connect to Sharepoint Online using (non-MFA enabled!) user non-interactive authentication.

    .NOTES
    Requires Pnp.PowerShell module.
    #>

    [CmdletBinding()]
    param (
        [System.Management.Automation.PSCredential] $credential,

        [switch] $appAuth,

        [switch] $asMFAUser,

        [ValidateNotNullOrEmpty()]
        [string] $url = $_SPOConnectionUri
    )

    if (!$url) {
        throw "Url parameter is not defined. It should contain your sharepoint URL (for example https://contoso-admin.sharepoint.com)"
    }

    if ($appAuth -and $asMFAUser) {
        Write-Warning "asMFAUser switch cannot be used with appAuth. Ignoring asMFAUser."
        $asMFAUser = $false
    }

    if ($credential -and $asMFAUser) {
        Write-Warning "When logging using MFA-enabled user, credentials cannot be passed i.e. it has to be interactive login"
        $credential = $null
    }

    try {
        Write-Verbose "Already connected to Sharepoint"
        $null = Get-PnPConnection -ea Stop
    } catch {
        Write-Verbose "Connecting to Sharepoint"
        if ($credential -and !$appAuth) {
            try {
                Connect-PnPOnline -Url $url -Credentials $credential -ea Stop
            } catch {
                if ($_ -match "you must use multi-factor authentication to access") {
                    Write-Error "Account $($credential.UserName) has MFA enabled, therefore interactive logon is needed"
                    Connect-PnPOnline -Url $url -Interactive -ForceAuthentication
                } else {
                    throw $_
                }
            }
        } elseif ($credential -and $appAuth) {
            Connect-PnPOnline -Url $url -ClientId $credential.UserName -ClientSecret $credential.GetNetworkCredential().password
        } else {
            # credential is missing
            if ($asMFAUser) {
                Connect-PnPOnline -Url $url -Interactive -ForceAuthentication
            } elseif ($appAuth) {
                $credential = Get-Credential -Message "Using App auth. Enter ClientId and ClientSecret."
                Connect-PnPOnline -Url $url -ClientId $credential.UserName -ClientSecret $credential.GetNetworkCredential().password
            } else {
                Connect-PnPOnline -Url $url
            }
        }
    }
}

#Requires -Modules AzureAD,Az.Accounts,Pnp.PowerShell,MSAL.PS

function Get-AzureADAccountOccurrence {
    <#
    .SYNOPSIS
    Function for getting AzureAD account occurrences through various parts of Azure.

    Only Azure based objects are scanned (not dir-synced ones).

    .DESCRIPTION
    Function for getting AzureAD account occurrences through various parts of AzureAD.

    Only Azure based objects are scanned (not dir-synced ones).

    You can search occurrences of 'user', 'group', 'servicePrincipal', 'device' objects.

    These Azure parts are searched by default: 'IAM', 'GroupMembership', 'DirectoryRoleMembership', 'UserConsent', 'Manager', 'Owner', 'SharepointSiteOwner', 'Users&GroupsRoleAssignment'

    .PARAMETER userPrincipalName
    UPN of the user you want to search occurrences for.

    .PARAMETER objectId
    ObjectId of the 'user', 'group', 'servicePrincipal' or 'device' you want to search occurrences for.

    .PARAMETER data
    Array of Azure parts you want to search in.

    By default:
    'IAM' - IAM assignments of the root, subscriptions, management groups, resource groups, resources where searched account is assigned
    'GroupMembership' - groups where searched account is a member
    'DirectoryRoleMembership' - directory roles where searched account is a member
    'UserConsent' - user granted consents
    'Manager' - accounts where searched user is manager
    'Owner' - accounts where searched user is owner
    'SharepointSiteOwner' - sharepoint sites where searched account is owner
    'Users&GroupsRoleAssignment' - applications Users and groups tab where searched account is assigned
    'DevOps' - occurrences in DevOps organizations

    Based on the object type you are searching occurrences for, this can be automatically trimmed. Because for example device cannot be manager etc.

    .EXAMPLE
    Get-AzureADAccountOccurrence -objectId 1234-1234-1234

    Search for all occurrences of the account with id 1234-1234-1234.

    .EXAMPLE
    Get-AzureADAccountOccurrence -objectId 1234-1234-1234 -data UserConsent, Manager

    Search just for user perm. consents which searched account has given and accounts where searched account is manager of.

    .EXAMPLE
    Get-AzureADAccountOccurrence -userPrincipalName novak@contoso.com

    Search for all occurrences of the account with UPN novak@contoso.com.

    .NOTES
    In case of 'data' parameter edit, don't forget to modify _getAllowedSearchType and Remove-AzureADAccountOccurrence functions too
    #>

    [CmdletBinding()]
    param (
        [ValidateNotNullOrEmpty()]
        [ValidateScript( {
                If ($_ -notmatch "@") {
                    throw "Username isn't UPN"
                } else {
                    $true
                }
            })]
        [string[]] $userPrincipalName,

        [string[]] $objectId,

        [ValidateSet('IAM', 'GroupMembership', 'DirectoryRoleMembership', 'UserConsent', 'Manager', 'Owner', 'SharepointSiteOwner', 'Users&GroupsRoleAssignment', 'DevOps')]
        [ValidateNotNullOrEmpty()]
        [string[]] $data = @('IAM', 'GroupMembership', 'DirectoryRoleMembership', 'UserConsent', 'Manager', 'Owner', 'SharepointSiteOwner', 'Users&GroupsRoleAssignment', 'DevOps')
    )

    if (!$userPrincipalName -and !$objectId) {
        throw "You haven't specified userPrincipalname nor objectId parameter"
    }

    #region connect
    # connect to AzureAD
    Write-Verbose "Connecting to Azure for use with cmdlets from the AzureAD PowerShell modules"
    $null = Connect-AzureAD2 -asYourself -ea Stop

    Write-Verbose "Connecting to Azure for use with cmdlets from the Az PowerShell modules"
    $null = Connect-AzAccount2 -ea Stop

    # connect Graph API
    Write-Verbose "Creating Graph API auth header"
    $header = New-GraphAPIAuthHeader -reuseExistingAzureADSession -ea Stop

    # connect sharepoint online
    if ($data -contains 'SharepointSiteOwner') {
        Write-Verbose "Connecting to Sharepoint"
        Connect-PnPOnline2 -asMFAUser -ea Stop
    }
    #endregion connect

    # translate UPN to ObjectId
    if ($userPrincipalName) {
        $userPrincipalName | % {
            $UPN = $_

            $AADUserobj = Get-AzureADUser -Filter "userprincipalname eq '$UPN'"
            if (!$AADUserobj) {
                Write-Error "Account $UPN was not found in AAD"
            } else {
                Write-Verbose "Translating $UPN to $($AADUserobj.ObjectId) ObjectId"
                $objectId += $AADUserobj.ObjectId
            }
        }
    }

    #region helper functions
    # function for deciding what kind of data make sense to search through when you have object of specific kind
    function _getAllowedSearchType {
        param ($searchedData)

        switch ($searchedData) {
            'IAM' {
                $allowedObjType = 'user', 'group', 'servicePrincipal'
            }

            'GroupMembership' {
                $allowedObjType = 'user', 'group', 'servicePrincipal', 'device'
            }

            'DirectoryRoleMembership' {
                $allowedObjType = 'user', 'group', 'servicePrincipal'
            }

            'UserConsent' {
                $allowedObjType = 'user'
            }

            'Manager' {
                $allowedObjType = 'user'
            }

            'Owner' {
                $allowedObjType = 'user', 'servicePrincipal'
            }

            'SharepointSiteOwner' {
                $allowedObjType = 'user', 'group', 'servicePrincipal', 'device'
            }

            'Users&GroupsRoleAssignment' {
                $allowedObjType = 'user', 'group'
            }

            'DevOps' {
                $allowedObjType = 'user', 'group'
            }

            default { throw "Undefined data to search $searchedData (edit _getAllowedSearchType function)" }
        }

        if ($objectType -in $allowedObjType) {
            return $true
        } else {
            Write-Warning "Skipping '$searchedData' data search because object of type $objectType cannot be there"

            return $false
        }
    }

    # function for translating DevOps membership hrefs to actual groups
    function _getMembership {
        param ([string[]] $membershipHref, [string] $organizationName)

        $membershipHref | % {
            Invoke-WebRequest -Uri $_ -Method get -ContentType "application/json" -Headers $header | select -exp content | ConvertFrom-Json | select -exp value | select -exp containerDescriptor | % {
                $groupOrg = $devOpsOrganization | ? { $_.OrganizationName -eq $organizationName }
                $group = $groupOrg.groups | ? descriptor -EQ $_
                if ($group) {
                    $group
                } else {
                    Write-Error "Group with descriptor $_ wasn't found"
                    [PSCustomObject]@{
                        ContainerDescriptor = $_
                    }
                }
            }
        }
    }
    #endregion helper functions

    #region pre-cache data
    if ('IAM' -in $data) {
        Write-Warning "Caching AzureAD Role Assignments. This can take several minutes!"
        $azureADRoleAssignments = Get-AzureADRoleAssignments
    }
    if ('SharepointSiteOwner' -in $data) {
        Write-Warning "Caching Sharepoint sites ownership. This can take several minutes!"
        $sharepointSiteOwner = Get-SharepointSiteOwner
    }

    if ('DevOps' -in $data) {
        Write-Warning "Caching DevOps organizations."
        $devOpsOrganization = Get-AzureDevOpsOrganizationOverview

        #TODO poresit strankovani!
        Write-Warning "Caching DevOps organizations groups."
        $header = New-AzureDevOpsAuthHeader
        $devOpsOrganization | % {
            $organizationName = $_.OrganizationName
            Write-Verbose "Getting groups for DevOps organization $organizationName"
            $groups = $null # in case of error this wouldn't be nulled
            try {
                $groups = Invoke-WebRequest -Uri "https://vssps.dev.azure.com/$organizationName/_apis/graph/groups?api-version=7.1-preview.1" -Method get -ContentType "application/json" -Headers $header -ea Stop | select -exp content | ConvertFrom-Json | select -exp value
            } catch {
                if ($_ -match "is not authorized to access this resource|UnauthorizedRequestException") {
                    Write-Warning "You don't have rights to get groups data for DevOps organization $organizationName."
                } else {
                    Write-Error $_
                }
            }

            $_ | Add-Member -MemberType NoteProperty -Name Groups -Value $groups
        }

        #TODO poresit strankovani!
        Write-Warning "Caching DevOps organizations users."
        $header = New-AzureDevOpsAuthHeader
        $devOpsOrganization | % {
            $organizationName = $_.OrganizationName
            Write-Verbose "Getting users for DevOps organization $organizationName"
            $users = $null # in case of error this wouldn't be nulled
            try {
                $users = Invoke-WebRequest -Uri "https://vssps.dev.azure.com/$organizationName/_apis/graph/users?api-version=7.1-preview.1" -Method get -ContentType "application/json" -Headers $header -ea Stop | select -exp content | ConvertFrom-Json | select -exp value
            } catch {
                if ($_ -match "is not authorized to access this resource|UnauthorizedRequestException") {
                    Write-Warning "You don't have rights to get users data for DevOps organization $organizationName."
                } else {
                    Write-Error $_
                }
            }

            $_ | Add-Member -MemberType NoteProperty -Name Users -Value $users
        }
    }
    #endregion pre-cache data

    # object types that are allowed for searching
    $allowedObjectType = 'user', 'group', 'servicePrincipal', 'device'

    foreach ($id in $objectId) {
        $AADAccountObj = Get-AzureADObjectByObjectId -ObjectId $id
        if (!$AADAccountObj) {
            Write-Error "Account $id was not found in AAD"
        }

        # progress variables
        $i = 0
        $progressActivity = "Account '$($AADAccountObj.DisplayName)' ($id) occurrences"

        $objectType = $AADAccountObj.ObjectType

        if ($objectType -notin $allowedObjectType) {
            Write-Warning "Skipping '$($AADAccountObj.DisplayName)' ($id) because it is disallowed object type ($objectType)"
            continue
        } else {
            Write-Warning "Processing '$($AADAccountObj.DisplayName)' ($id)"
        }

        # define base object
        $result = [PSCustomObject]@{
            UPN                             = $AADAccountObj.UserPrincipalName
            DisplayName                     = $AADAccountObj.DisplayName
            ObjectType                      = $objectType
            ObjectId                        = $id
            IAM                             = @()
            MemberOfDirectoryRole           = @()
            MemberOfGroup                   = @()
            Manager                         = @()
            PermissionConsent               = @()
            Owner                           = @()
            SharepointSiteOwner             = @()
            AppUsersAndGroupsRoleAssignment = @()
            DevOpsOrganizationOwner         = @()
            DevOpsMemberOf                  = @()
        }

        #region get AAD account occurrences

        #region IAM
        if ('IAM' -in $data -and (_getAllowedSearchType 'IAM')) {
            Write-Verbose "Getting IAM assignments"
            Write-Progress -Activity $progressActivity -Status "Getting IAM assignments" -PercentComplete (($i++ / $data.Count) * 100)

            $azureADRoleAssignments | ? objectId -EQ $id | % {
                $result.IAM += $_
            }
        }
        #endregion IAM

        #region DirectoryRoleMembership
        if ('DirectoryRoleMembership' -in $data -and (_getAllowedSearchType 'DirectoryRoleMembership')) {
            Write-Verbose "Getting Directory Role Membership assignments"
            Write-Progress -Activity $progressActivity -Status "Getting Directory Role Membership assignments" -PercentComplete (($i++ / $data.Count) * 100)

            Get-AzureADMSRoleAssignment -Filter "principalId eq '$id'" | % {
                $_ | Add-Member -Name RoleName -MemberType NoteProperty -Value (Get-AzureADMSRoleDefinition -Id $_.roleDefinitionId | select -ExpandProperty DisplayName)
                $result.MemberOfDirectoryRole += $_
            }
        }
        #endregion DirectoryRoleMembership

        #region Group membership
        if ('GroupMembership' -in $data -and (_getAllowedSearchType 'GroupMembership')) {
            Write-Verbose "Getting Group memberships (just Cloud based groups are evaluated!)"
            Write-Progress -Activity $progressActivity -Status "Getting Group memberships" -PercentComplete (($i++ / $data.Count) * 100)

            Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/v1.0/users/$id/transitiveMemberOf" -header $header -ErrorAction SilentlyContinue | ? onPremisesSyncEnabled -NE $true | % {
                if ($_.'@odata.type' -eq '#microsoft.graph.directoryRole') {
                    # directory roles are added in different IF, moreover this query doesn't return custom roles
                } elseif ($_.'@odata.context') {
                    # not a member
                } else {
                    $result.MemberOfGroup += $_
                }
            }
        }
        #endregion Group membership

        #region user perm consents
        if ('UserConsent' -in $data -and (_getAllowedSearchType 'UserConsent')) {
            Write-Verbose "Getting permission consents"
            Write-Progress -Activity $progressActivity -Status "Getting permission consents" -PercentComplete (($i++ / $data.Count) * 100)

            Get-AzureADUserOAuth2PermissionGrant -ObjectId $id -All:$true | % {
                $result.PermissionConsent += $_ | select *, @{name = 'AppName'; expression = { (Get-AzureADServicePrincipal -ObjectId $_.ClientId).DisplayName } }, @{name = 'ResourceDisplayName'; expression = { (Get-AzureADServicePrincipal -ObjectId $_.ResourceId).DisplayName } }
            }
        }
        #endregion user perm consents

        #region is manager
        if ('Manager' -in $data -and (_getAllowedSearchType 'Manager')) {
            Write-Verbose "Getting Direct report"
            Write-Verbose "Just Cloud based objects are outputted"
            Write-Progress -Activity $progressActivity -Status "Getting Direct Report (managedBy)" -PercentComplete (($i++ / $data.Count) * 100)

            Get-AzureADUserDirectReport -ObjectId $id | ? DirSyncEnabled -NE 'True' | % {
                $result.Manager += $_
            }
        }
        #endregion is manager

        #region is owner
        # group, ent. app, app reg. and device ownership
        if ('Owner' -in $data -and (_getAllowedSearchType 'Owner')) {
            Write-Verbose "Getting application, group etc ownership"
            Write-Progress -Activity $progressActivity -Status "Getting group, app and device ownership" -PercentComplete (($i++ / $data.Count) * 100)
            switch ($objectType) {
                'user' {
                    Get-AzureADUserOwnedObject -ObjectId $id | % {
                        $result.Owner += $_
                    }

                    Write-Verbose "Getting device(s) ownership"
                    Get-AzureADUserOwnedDevice -ObjectId $id | % {
                        $result.Owner += $_
                    }
                }

                'servicePrincipal' {
                    Get-AzureADServicePrincipalOwnedObject -ObjectId $id | % {
                        $result.Owner += $_
                    }
                }

                default {
                    throw "Undefined condition for $objectType objectType when searching for 'Owner'"
                }
            }
        }

        #sharepoint sites owner
        if ('SharepointSiteOwner' -in $data -and (_getAllowedSearchType 'SharepointSiteOwner')) {
            Write-Verbose "Getting Sharepoint sites ownership"
            Write-Progress -Activity $progressActivity -Status "Getting Sharepoint sites ownership" -PercentComplete (($i++ / $data.Count) * 100)

            $sharepointSiteOwner | ? Owner -Contains $UPN | % {
                $result.SharepointSiteOwner += $_
            }
        }
        #endregion is owner

        #region App Users and groups role assignments
        if ('Users&GroupsRoleAssignment' -in $data -and (_getAllowedSearchType 'Users&GroupsRoleAssignment')) {
            Write-Verbose "Getting applications 'Users and groups' role assignments"
            Write-Progress -Activity $progressActivity -Status "Getting applications 'Users and groups' role assignments" -PercentComplete (($i++ / $data.Count) * 100)

            function GetRoleName {
                param ($objectId, $roleId)
                if ($roleId -eq '00000000-0000-0000-0000-000000000000') {
                    return 'default'
                } else {
                    Get-AzureADServicePrincipal -ObjectId $objectId | select -ExpandProperty AppRoles | ? id -EQ $roleId | select -ExpandProperty DisplayName
                }
            }

            switch ($objectType) {
                'user' {
                    # filter out assignments based on group membership
                    Get-AzureADUserAppRoleAssignment -ObjectId $id -All:$true | ? PrincipalDisplayName -EQ $AADAccountObj.DisplayName | select *, @{name = 'AppRoleDisplayName'; expression = { GetRoleName -objectId $_.ResourceId -roleId $_.Id } } | % {
                        $result.AppUsersAndGroupsRoleAssignment += $_
                    }
                }

                'group' {
                    Get-AzureADGroupAppRoleAssignment -ObjectId $id -All:$true | select *, @{name = 'AppRoleDisplayName'; expression = { GetRoleName -objectId $_.ResourceId -roleId $_.Id } } | % {
                        $result.AppUsersAndGroupsRoleAssignment += $_
                    }
                }

                default {
                    throw "Undefined condition for $objectType objectType when searching for 'Users&GroupsRoleAssignment'"
                }
            }
        }
        #endregion App Users and groups role assignments

        #region devops
        # https://docs.microsoft.com/en-us/rest/api/azure/devops/
        if ('DevOps' -in $data -and (_getAllowedSearchType 'DevOps')) {
            Write-Verbose "Getting DevOps occurrences"
            Write-Progress -Activity $progressActivity -Status "Getting DevOps occurrences" -PercentComplete (($i++ / $data.Count) * 100)

            $header = New-AzureDevOpsAuthHeader # auth. token has just minutes lifetime!
            $devOpsOrganization | % {
                $organization = $_
                $organizationName = $organization.OrganizationName
                $organizationOwner = $organization.Owner

                if ($organizationOwner -eq $AADAccountObj.UserPrincipalName -or $organizationOwner -eq $AADAccountObj.DisplayName) {
                    $result.DevOpsOrganizationOwner += $organization
                }

                if ($objectType -eq 'user') {
                    $userInOrg = $organization.users | ? originId -EQ $AADAccountObj.ObjectId

                    if ($userInOrg) {
                        # user is used in this DevOps organization
                        $memberOf = _getMembership $userInOrg._links.memberships.href $organizationName
                        $result.DevOpsMemberOf += [PSCustomObject]@{
                            OrganizationName = $organizationName
                            MemberOf         = $memberOf
                            Descriptor       = $userInOrg.descriptor
                        }
                    } else {
                        # try to find it as an orphaned guest (has special principalname)
                        $orphanGuestUserInOrg = $organization.users | ? { $_.displayName -EQ $AADAccountObj.displayName -and $_.directoryAlias -Match "#EXT#$" -and $_.principalName -Match "OIDCONFLICT_UpnReuse_" }
                        if ($orphanGuestUserInOrg) {
                            Write-Warning "$($AADAccountObj.displayName) guest user is used in DevOps organization '$organizationName' but it is orphaned record (guest user was assigned to this organization than deleted and than invited again with the same UPN"
                        }
                    }
                } elseif ($objectType -eq 'group') {
                    $groupInOrg = $organization.groups | ? originId -EQ $AADAccountObj.ObjectId

                    if ($groupInOrg) {
                        # group is used in this DevOps organization
                        $memberOf = _getMembership $groupInOrg._links.memberships.href $organizationName
                        $result.DevOpsMemberOf += [PSCustomObject]@{
                            OrganizationName = $organizationName
                            MemberOf         = $memberOf
                            Descriptor       = $groupInOrg.descriptor
                        }
                    }
                } else {
                    throw "Undefined object type $objectType"
                }

                # # uzivatele vcetne clenstvi ve skupinach
                # Invoke-WebRequest -Uri "https://vssps.dev.azure.com/ondrejs4/_apis/identities?searchFilter=General&filterValue=$UPN&queryMembership=Direct&api-version=7.1-preview.1" -Method get -ContentType "application/json" -Headers $header | select -exp content | ConvertFrom-Json | select -exp value
                # # skupiny a urovne pristupu (ale jen to nejake orezane, jen 3 skupiny)
                # Invoke-WebRequest -Uri "https://vsaex.dev.azure.com/ondrejs4/_apis/userentitlementsummary" -Method get -ContentType "application/json" -Headers $h | select -exp content | ConvertFrom-Json
                # # ziskani podrobnych user dat vcetne lastlogin atd dle zadaneho ID uzivatele (ale projectEntitlements zase neukazuje vse)
                # Invoke-WebRequest -Uri "https://vsaex.dev.azure.com/ondrejs4/_apis/userentitlements/24cc0ecb-fd00-6302-b3a9-03cf4a0cb8ad" -Method get -ContentType "application/json" -Headers $h | select -exp content | ConvertFrom-Json
            }
        }
        #endregion devops

        #endregion get AAD account occurrences

        Write-Progress -Completed -Activity $progressActivity

        $result
    }
}

function Get-AzureADAppConsentRequest {
    <#
    .SYNOPSIS
    Function for getting AzureAD app consent requests.

    .DESCRIPTION
    Function for getting AzureAD app consent requests.

    .PARAMETER header
    Graph api authentication header.
    Can be create via New-GraphAPIAuthHeader.

    .PARAMETER openAdminConsentPage
    Switch for opening web page with form for granting admin consent for each not yet review application.

    .EXAMPLE
    $header = New-GraphAPIAuthHeader
    Get-AzureADAppConsentRequest -header $header

    .NOTES
    Requires at least permission ConsentRequest.Read.All (to get requests), Directory.Read.All (to get service principal publisher)
    https://docs.microsoft.com/en-us/graph/api/appconsentapprovalroute-list-appconsentrequests?view=graph-rest-1.0&tabs=http
    https://docs.microsoft.com/en-us/graph/api/resources/consentrequests-overview?view=graph-rest-1.0
    #>

    [CmdletBinding()]
    param (
        $header,

        [switch] $openAdminConsentPage
    )

    if (!$header) {
        try {
            $header = New-GraphAPIAuthHeader -reuseExistingAzureADSession -ErrorAction Stop
        } catch {
            throw "Unable to retrieve authentication header for graph api. Create it using New-GraphAPIAuthHeader and pass it using header parameter"
        }
    }

    Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/identityGovernance/appConsent/appConsentRequests" -header $Header | % {
        $userConsentRequestsUri = $_.'userConsentRequests@odata.context' -replace [regex]::escape('$metadata#')
        Write-Verbose "Getting user consent requests via '$userConsentRequestsUri'"
        $userConsentRequests = Invoke-GraphAPIRequest -uri $userConsentRequestsUri -header $Header

        $userConsentRequests = $userConsentRequests | select status, reason, @{name = 'createdBy'; expression = { $_.createdBy.user.userPrincipalName } }, createdDateTime, @{name = 'approval'; expression = { $_.approval.steps | select @{name = 'reviewedBy'; expression = { $_.reviewedBy.userPrincipalName } }, reviewResult, reviewedDateTime, justification } }, @{name = 'RequestId'; expression = { $_.Id } }

        $appVerifiedPublisher = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$filter=(appId%20eq%20%27$($_.appId)%27)&`$select=verifiedPublisher" -header $Header
        if ($appVerifiedPublisher | Get-Member | ? Name -EQ 'verifiedPublisher') {
            $appVerifiedPublisher = $appVerifiedPublisher.verifiedPublisher.DisplayName
        } else {
            # service principal wasn't found (new application)
            $appVerifiedPublisher = "*unknown*"
        }

        $_ | select appDisplayName, consentType, @{name = 'verifiedPublisher'; expression = { $appVerifiedPublisher } }, @{name = 'pendingScopes'; e = { $_.pendingScopes.displayName } }, @{name = 'consentRequest'; expression = { $userConsentRequests } }

        if ($openAdminConsentPage -and $userConsentRequests.status -eq 'InProgress') {
            Open-AzureADAdminConsentPage -appId $_.appId
        }
    }
}

#Requires -Modules Az.Accounts,Az.Resources

function Get-AzureADRoleAssignments {
    <#
    .SYNOPSIS
    Returns RBAC role assignments (IAM tab for root, subscriptions, management groups, resource groups, resources) from all or just selected Azure subscription(s). It is possible to filter just roles assigned to user, group or service principal.

    .DESCRIPTION
    Returns RBAC role assignments (IAM tab for root, subscriptions, management groups, resource groups, resources) from all or just selected Azure subscription(s). It is possible to filter just roles assigned to user, group or service principal.

    From security perspective these roles are important:
    Owner
    Contributor
    User Access Administrator
    Virtual Machine Contributor
    Virtual Machine Administrator
    Avere Contributor

    When given to managed identity and scope is whole resource group or subscription (because of lateral movement)!

    .PARAMETER subscriptionId
    ID of subscription you want to get role assignments for.

    .PARAMETER selectCurrentSubscription
    Switch for getting data just for currently set subscription.

    .PARAMETER userPrincipalName
    UPN of the User whose assignments you want to get.

    .PARAMETER objectId
    ObjectId of the User, Group or Service Principal whose assignments you want to get.

    .EXAMPLE
    Get-AzureADRoleAssignments

    Returns RBAC role assignments for all subscriptions.

    .EXAMPLE
    Get-AzureADRoleAssignments -subscriptionId 1234-1234-1234-1234

    Returns RBAC role assignments for subscription with ID 1234-1234-1234-1234.

    .EXAMPLE
    Get-AzureADRoleAssignments -selectCurrentSubscription

    Returns RBAC role assignments just for current subscription.

    .EXAMPLE
    Get-AzureADRoleAssignments -selectCurrentSubscription -userPrincipalName john@contoso.com

    Returns RBAC role assignments of the user john@contoso.com just for current subscription.

    .NOTES
    Required Azure permissions:
    - Global reader
    - Security Reader assigned at 'Tenant Root Group'

    https://m365internals.com/2021/11/30/lateral-movement-with-managed-identities-of-azure-virtual-machines/?s=09
    https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
    #>

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [Alias("Get-AzureADRBACRoleAssignments", "Get-AzureADIAMRoleAssignments")]
    param (
        [Parameter(ParameterSetName = "subscriptionId")]
        [string] $subscriptionId,

        [Parameter(ParameterSetName = "currentSubscription")]
        [Switch] $selectCurrentSubscription,

        [string] $userPrincipalName,

        [string] $objectId
    )

    if ($objectId -and $userPrincipalName) {
        throw "You cannot use parameters objectId and userPrincipalName at the same time"
    }

    Connect-AzAccount2 -ErrorAction Stop

    # get Current Context
    $CurrentContext = Get-AzContext

    # get Azure Subscriptions
    if ($selectCurrentSubscription) {
        Write-Verbose "Only running for current subscription $($CurrentContext.Subscription.Name)"
        $Subscriptions = Get-AzSubscription -SubscriptionId $CurrentContext.Subscription.Id -TenantId $CurrentContext.Tenant.Id
    } elseif ($subscriptionId) {
        Write-Verbose "Only running for selected subscription $subscriptionId"
        $Subscriptions = Get-AzSubscription -SubscriptionId $subscriptionId -TenantId $CurrentContext.Tenant.Id
    } else {
        Write-Verbose "Running for all subscriptions in tenant"
        $Subscriptions = Get-AzSubscription -TenantId $CurrentContext.Tenant.Id
    }

    function _scopeType {
        param ([string] $scope)

        if ($scope -match "^/$") {
            return 'root'
        } elseif ($scope -match "^/subscriptions/[^/]+$") {
            return 'subscription'
        } elseif ($scope -match "^/subscriptions/[^/]+/resourceGroups/[^/]+$") {
            return "resourceGroup"
        } elseif ($scope -match "^/subscriptions/[^/]+/resourceGroups/[^/]+/.+$") {
            return 'resource'
        } elseif ($scope -match "^/providers/Microsoft.Management/managementGroups/.+") {
            return 'managementGroup'
        } else {
            throw 'undefined type'
        }
    }

    Write-Verbose "Getting Role Definitions..."
    $roleDefinition = Get-AzRoleDefinition

    foreach ($Subscription in $Subscriptions) {
        Write-Verbose "Changing to Subscription $($Subscription.Name)"

        $Context = Set-AzContext -TenantId $Subscription.TenantId -SubscriptionId $Subscription.Id -Force

        # getting information about Role Assignments for chosen subscription
        Write-Verbose "Getting information about Role Assignments..."
        try {
            $param = @{
                ErrorAction = 'Stop'
            }
            if ($objectId) {
                $param.objectId = $objectId
            } elseif ($userPrincipalName) {
                # -ExpandPrincipalGroups for also assignments based on group membership
                $param.SignInName = $userPrincipalName
            }

            Get-AzRoleAssignment @param | Select-Object RoleDefinitionName, DisplayName, SignInName, ObjectType, ObjectId, @{n = 'AssignmentScope'; e = { $_.Scope } }, @{n = "SubscriptionId"; e = { $Subscription.SubscriptionId } }, @{n = 'ScopeType'; e = { _scopeType  $_.scope } }, @{n = 'CustomRole'; e = { ($roleDefinition | ? { $_.Name -eq $_.RoleDefinitionName }).IsCustom } }, @{n = "SubscriptionName"; e = { $Subscription.Name } }
        } catch {
            if ($_ -match "The current subscription type is not permitted to perform operations on any provider namespace. Please use a different subscription") {
                Write-Warning "At subscription $($Subscription.Name) there is no resource provider registered"
            } else {
                Write-Error $_
            }
        }
    }
}

function Get-AzureDevOpsOrganizationOverview {
    <#
    .SYNOPSIS
    Function for getting list of all Azure DevOps organizations that uses your AzureAD directory.

    .DESCRIPTION
    Function for getting list of all Azure DevOps organizations that uses your AzureAD directory.
    It is the same data as downloaded csv from https://dev.azure.com/<organizationName>/_settings/organizationAad.

    Function uses MSAL to authenticate (requires MSAL.PS module).

    .PARAMETER tenantId
    (optional) ID of your Azure tenant.
    Of omitted, tenantId from MSAL auth. ticket will be used.

    .EXAMPLE
    Get-AzureDevOpsOrganizationOverview

    Returns all DevOps organizations in your Azure tenant.

    .NOTES
    PowerShell module AzSK.ADO > ContextHelper.ps1 > GetCurrentContext
    https://stackoverflow.com/questions/56355274/getting-oauth-tokens-for-azure-devops-api-consumption
    https://stackoverflow.com/questions/52896114/use-azure-ad-token-to-authenticate-with-azure-devops
    #>

    [CmdletBinding()]
    param (
        [string] $tenantId = $_tenantId
    )

    $header = New-AzureDevOpsAuthHeader -ErrorAction Stop

    if (!$tenantId) {
        $tenantId = $msalToken.tenantId
        Write-Verbose "Set TenantId to $tenantId (retrieved from MSAL token)"
    }

    # URL retrieved thanks to developer mod at page https://dev.azure.com/<organizationName>/_settings/organizationAad
    Invoke-WebRequest -Uri "https://aexprodweu1.vsaex.visualstudio.com/_apis/EnterpriseCatalog/Organizations?tenantId=$tenantId" -Method get -ContentType "application/json" -Headers $header | select -ExpandProperty content | ConvertFrom-Csv | select @{name = 'OrganizationName'; expression = { $_.'Organization Name' } }, @{name = 'OrganizationId'; expression = { $_.'Organization Id' } }, Url, Owner, @{name = 'ExceptionType'; expression = { $_.'Exception Type' } }, @{name = 'ErrorMessage'; expression = { $_.'Error Message' } } -ExcludeProperty 'Organization Name', 'Organization Id', 'Exception Type', 'Error Message'
}

#Requires -Modules Pnp.PowerShell

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

function Invoke-GraphAPIRequest {
    <#
    .SYNOPSIS
    Function for creating request against Microsoft Graph API.

    .DESCRIPTION
    Function for creating request against Microsoft Graph API.

    It supports paging (needed in Azure).

    .PARAMETER uri
    Request URI.

    https://graph.microsoft.com/v1.0/me/
    https://graph.microsoft.com/v1.0/devices
    https://graph.microsoft.com/v1.0/users
    https://graph.microsoft.com/v1.0/groups
    https://graph.microsoft.com/beta/servicePrincipals?&$expand=appRoleAssignedTo
    https://graph.microsoft.com/beta/servicePrincipals?$select=id,appId,servicePrincipalType,displayName
    https://graph.microsoft.com/beta/servicePrincipals?$filter=(servicePrincipalType%20eq%20%27ManagedIdentity%27)
    https://graph.microsoft.com/beta/servicePrincipals?$filter=contains(serialNumber,'$encoded')
    https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicySettingStateSummaries/1234/deviceComplianceSettingStates?`$filter=NOT(state eq 'compliant')
    https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$select=id&`$filter=complianceState eq 'compliant'
    https://graph.microsoft.com/beta/users?`$select=id,userPrincipalName,displayName,mail,otherMails,proxyAddresses&`$filter=proxyAddresses/any(c:c eq 'smtp:$technicalNotificationMail') or otherMails/any(c:c eq 'smtp:$technicalNotificationMail')

    .PARAMETER credential
    Credentials used for creating authentication header for request.

    .PARAMETER header
    Authentication header for request.

    .PARAMETER method
    Default is GET.

    .PARAMETER waitTime
    Number of seconds before new try in case of 'Too Many Requests' error.

    Default is 5 seconds.

    .EXAMPLE
    $header = New-GraphAPIAuthHeader -credential $intuneCredential
    $aadDevice = Invoke-GraphAPIRequest -Uri "https://graph.microsoft.com/v1.0/devices" -header $header

    .EXAMPLE
    $aadDevice = Invoke-GraphAPIRequest -Uri "https://graph.microsoft.com/v1.0/devices" -credential $intuneCredential

    .NOTES
    https://configmgrblog.com/2017/12/05/so-what-can-we-do-with-microsoft-intune-via-microsoft-graph-api/
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $uri,

        [Parameter(Mandatory = $true, ParameterSetName = "credential")]
        [System.Management.Automation.PSCredential] $credential,

        [Parameter(Mandatory = $true, ParameterSetName = "header")]
        $header,

        [ValidateSet('GET', 'POST', 'DELETE', 'UPDATE')]
        [string] $method = "GET",

        [ValidateRange(1, 999)]
        [int] $waitTime = 5
    )

    Write-Verbose "uri $uri"

    if ($credential) {
        $header = New-GraphAPIAuthHeader -credential $credential
    }

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $header -Method $method -ErrorAction Stop
    } catch {
        switch ($_) {
            { $_ -like "*(429) Too Many Requests*" } {
                Write-Warning "(429) Too Many Requests. Waiting $waitTime seconds to avoid further throttling and try again"
                Start-Sleep $waitTime
                Invoke-GraphAPIRequest -uri $uri -header $header -method $method
            }
            { $_ -like "*(400) Bad Request*" } { throw "(400) Bad Request. There has to be some syntax/logic mistake in this request ($uri)" }
            { $_ -like "*(401) Unauthorized*" } { throw "(401) Unauthorized Request (new auth header has to be created?)" }
            { $_ -like "*Forbidden*" } { throw "Forbidden access. Use account with correct API permissions for this request ($uri)" }
            default { throw $_ }
        }
    }

    if ($response.Value) {
        $response.Value
    } else {
        $response
    }

    # understand if top parameter is used in the URI
    try {
        $prevErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Stop"
        $topValue = ([regex]"top=(\d+)").Matches($uri).captures.groups[1].value
    } catch {
        Write-Verbose "uri ($uri) doesn't contain TOP"
    } finally {
        $ErrorActionPreference = $prevErrorActionPreference
    }

    if (!$topValue -or ($topValue -and $topValue -gt 100)) {
        # there can be more results to return, check that
        # need to loop the requests because only 100 results are returned each time
        $nextLink = $response.'@odata.nextLink'
        while ($nextLink) {
            Write-Verbose "Next uri $nextLink"
            try {
                $response = Invoke-RestMethod -Uri $NextLink -Headers $header -Method $method -ErrorAction Stop
            } catch {
                switch ($_) {
                    { $_ -like "*(429) Too Many Requests*" } {
                        Write-Warning "(429) Too Many Requests. Waiting $waitTime seconds to avoid further throttling and try again"
                        Start-Sleep $waitTime
                        Invoke-GraphAPIRequest -uri $NextLink -header $header -method $method
                    }
                    { $_ -like "*(400) Bad Request*" } { throw "(400) Bad Request. There has to be some syntax/logic mistake in this request ($uri)" }
                    { $_ -like "*(401) Unauthorized*" } { throw "(401) Unauthorized Request (new auth header has to be created?)" }
                    { $_ -like "*Forbidden*" } { throw "Forbidden access. Use account with correct API permissions for this request ($uri)" }
                    default { throw $_ }
                }
            }

            if ($response.Value) {
                $response.Value
            } else {
                $response
            }

            $nextLink = $response.'@odata.nextLink'
        }
    } else {
        # to avoid 'Too Many Requests' error when working with Graph API (/auditLogs/signIns) and using top parameter
        Write-Verbose "There is no need to check if more results can be returned. I.e. if parameter 'top' is used in the URI it is lower than 100 (so all results will be returned in the first request anyway)"
    }
}

#Requires -Modules MSAL.PS

function New-AzureDevOpsAuthHeader {
    <#
    .SYNOPSIS
    Function for getting authentication header for web requests against Azure DevOps.

    .DESCRIPTION
    Function for getting authentication header for web requests against Azure DevOps.

    Function uses MSAL to authenticate (requires MSAL.PS module).

    .EXAMPLE
    $header = New-AzureDevOpsAuthHeader
    Invoke-WebRequest -Uri $uri -Headers $header

    .NOTES
    https://docs.microsoft.com/en-us/rest/api/azure/devops/?view=azure-devops-rest-7.1
    PowerShell module AzSK.ADO > ContextHelper.ps1 > GetCurrentContext
    https://stackoverflow.com/questions/56355274/getting-oauth-tokens-for-azure-devops-api-consumption
    https://stackoverflow.com/questions/52896114/use-azure-ad-token-to-authenticate-with-azure-devops
    #>

    [CmdletBinding()]
    param ()

    # TODO oAuth auth https://github.com/microsoft/azure-devops-auth-samples/tree/master/OAuthWebSample
    # $msalToken = Get-MsalToken -TenantId $TenantID -ClientId $ClientID -UserCredential $Credential -Scopes ([String]::Concat($($ApplicationIdUri), '/user_impersonation')) -ErrorAction Stop

    $clientId = "872cd9fa-d31f-45e0-9eab-6e460a02d1f1" # Visual Studio
    $adoResourceId = "499b84ac-1321-427f-aa17-267ca6975798" # Azure DevOps app ID
    $msalToken = Get-MsalToken -Scopes "$adoResourceId/.default" -ClientId $clientId

    if ($msalToken.accessToken) {
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f "", $msalToken.accessToken)))
        return @{Authorization = "Basic $base64AuthInfo" }
    } else {
        throw "Unable to obtain DevOps MSAL token"
    }
}

function New-GraphAPIAuthHeader {
    <#
    .SYNOPSIS
    Function for generating header that can be used for authentication of Graph API requests.

    .DESCRIPTION
    Function for generating header that can be used for authentication of Graph API requests.
    Credentials can be given or existing AzureAD session can be reused to obtain auth. header.

    .PARAMETER credential
    Credentials for Graph API authentication (AppID + AppSecret) that will be used to obtain auth. header.

    .PARAMETER reuseExistingAzureADSession
    Switch for using existing AzureAD session (created via Connect-AzureAD) to obtain auth. header.

    .PARAMETER TenantDomainName
    Name of your Azure tenant.

    .PARAMETER showDialogType
    Modify behavior of auth. dialog window.

    Possible values are: auto, always, never.

    Default is 'never'.

    .EXAMPLE
    $header = New-GraphAPIAuthHeader -credential $cred
    $URI = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/'
    $managedDevices = (Invoke-RestMethod -Headers $header -Uri $URI -Method Get).value

    .EXAMPLE
    (there is existing AzureAD session already (made via Connect-AzureAD))
    $header = New-GraphAPIAuthHeader -reuseExistingAzureADSession
    $URI = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/'
    $managedDevices = (Invoke-RestMethod -Headers $header -Uri $URI -Method Get).value

    .NOTES
    https://adamtheautomator.com/powershell-graph-api/#AppIdSecret
    https://thesleepyadmins.com/2020/10/24/connecting-to-microsoft-graphapi-using-powershell/
    https://github.com/microsoftgraph/powershell-intune-samples
    https://tech.nicolonsky.ch/explaining-microsoft-graph-access-token-acquisition/
    https://gist.github.com/psignoret/9d73b00b377002456b24fcb808265c23
    #>

    [CmdletBinding()]
    [Alias("New-IntuneAuthHeader", "Get-IntuneAuthHeader")]
    param (
        [Parameter(ParameterSetName = "authenticate")]
        [System.Management.Automation.PSCredential] $credential,

        [Parameter(ParameterSetName = "reuseSession")]
        [switch] $reuseExistingAzureADSession,

        [ValidateNotNullOrEmpty()]
        $tenantDomainName = $_tenantDomain,

        [ValidateSet('auto', 'always', 'never')]
        [string] $showDialogType = 'never'
    )

    if (!$credential -and !$reuseExistingAzureADSession) {
        $credential = (Get-Credential -Message "Enter AppID as UserName and AppSecret as Password")
    }
    if (!$credential -and !$reuseExistingAzureADSession) { throw "Credentials for creating Graph API authentication header is missing" }

    if (!$tenantDomainName -and !$reuseExistingAzureADSession) { throw "TenantDomainName is missing" }

    Write-Verbose "Getting token"

    if ($reuseExistingAzureADSession) {
        # get auth. token using the existing session created by the AzureAD PowerShell module
        try {
            # test if connection already exists
            $c = Get-AzureADCurrentSessionInfo -ea Stop
        } catch {
            throw "There is no active session to AzureAD. Omit reuseExistingAzureADSession parameter or call this function after Connect-AzureAD."
        }

        try {
            $ErrorActionPreference = "Stop"

            $context = [Microsoft.Open.Azure.AD.CommonLibrary.AzureRmProfileProvider]::Instance.Profile.Context
            $authenticationFactory = [Microsoft.Open.Azure.AD.CommonLibrary.AzureSession]::AuthenticationFactory
            $msGraphEndpointResourceId = "MsGraphEndpointResourceId"
            $msGraphEndpoint = $context.Environment.Endpoints[$msGraphEndpointResourceId]
            $auth = $authenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id.ToString(), $null, [Microsoft.Open.Azure.AD.CommonLibrary.ShowDialog]::$showDialogType, $null, $msGraphEndpointResourceId)

            $token = $auth.AuthorizeRequest($msGraphEndpointResourceId)

            return @{ Authorization = $token }
        } catch {
            throw "Unable to obtain auth. token:`n`n$($_.exception.message)`n`n$($_.invocationInfo.PositionMessage)`n`nTry change of showDialogType parameter?"
        }
    } else {
        # authenticate to obtain the token
        $body = @{
            Grant_Type    = "client_credentials"
            Scope         = "https://graph.microsoft.com/.default"
            Client_Id     = $credential.username
            Client_Secret = $credential.GetNetworkCredential().password
        }

        $connectGraph = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantDomainName/oauth2/v2.0/token" -Method POST -Body $body

        $token = $connectGraph.access_token

        if ($token) {
            return @{ Authorization = "Bearer $($token)" }
        } else {
            throw "Unable to obtain token"
        }
    }
}

function Open-AzureADAdminConsentPage {
    <#
    .SYNOPSIS
    Function for opening web page with admin consent to requested/selected permissions to selected application.

    .DESCRIPTION
    Function for opening web page with admin consent to requested/selected permissions to selected application.

    .PARAMETER appId
    Application (client) ID.

    .PARAMETER tenantId
    Your Azure tenant ID.

    .EXAMPLE
    Open-AzureADAdminConsentPage -appId 123412341234 -scope openid, profile, email, user.read, Mail.Send -tenantId 111122223333

    Grant admin consent for selected permissions to app with client ID 123412341234.

    .EXAMPLE
    Open-AzureADAdminConsentPage -appId 123412341234 -tenantId 111122223333

    Grant admin consent for requested permissions to app with client ID 123412341234.

    .NOTES
    https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/grant-admin-consent
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $appId,

        [Parameter(Mandatory = $true)]
        [string] $tenantId,

        [string[]] $scope,

        [switch] $justURL
    )

    if ($scope) {
        # grant custom permission
        $scope = $scope.trim() -join "%20"
        $URL = "https://login.microsoftonline.com/$tenantId/v2.0/adminconsent?client_id=$appId&scope=$scope"

        if ($justURL) {
            return $URL
        } else {
            Start-Process $URL
        }
    } else {
        # grant requested permissions
        $URL = "https://login.microsoftonline.com/$tenantId/adminconsent?client_id=$appId"
        if ($justURL) {
            return $URL
        } else {
            Start-Process $URL
        }
    }
}

Export-ModuleMember -function Add-AzureADAppCertificate, Add-AzureADAppUserConsent, Connect-AzAccount2, Connect-AzureAD2, Connect-PnPOnline2, Get-AzureADAccountOccurrence, Get-AzureADAppConsentRequest, Get-AzureADRoleAssignments, Get-AzureDevOpsOrganizationOverview, Get-SharepointSiteOwner, Invoke-GraphAPIRequest, New-AzureDevOpsAuthHeader, New-GraphAPIAuthHeader, Open-AzureADAdminConsentPage

Export-ModuleMember -alias Get-AzureADIAMRoleAssignments, Get-AzureADRBACRoleAssignments, Get-IntuneAuthHeader, New-IntuneAuthHeader
