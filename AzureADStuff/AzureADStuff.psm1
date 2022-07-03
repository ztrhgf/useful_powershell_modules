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

function Add-AzureADGuest {
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
    Add-AzureADGuest -displayName "Jan Novak" -emailAddress "novak@seznam.cz"
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

    Connect-AzureAD2

    # naming conventions
    (Get-Variable displayName).Attributes.Clear()
    $displayName = $displayName.trim() + " (guest)"
    $emailAddress = $emailAddress.trim()

    "Creating Guest: $displayName EMAIL: $emailaddress"

    $null = New-AzureADMSInvitation -InvitedUserDisplayName $displayName -InvitedUserEmailAddress $emailAddress -InviteRedirectUrl "https://myapps.microsoft.com" -SendInvitationMessage $true -InvitedUserType Guest

    if ($parentTeamsGroup) {
        $groupID = Get-AzureADGroup -SearchString $parentTeamsGroup | select -exp ObjectId
        if (!$groupID) { throw "Unable to find group $parentTeamsGroup" }
        $userId = Get-AzureADUser -SearchString $emailaddress | select -exp ObjectId
        Add-AzureADGroupMember -ObjectId $groupID -RefObjectId $userId
    }
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
    $thumbprint = Get-ChildItem Cert:\LocalMachine\My | ? subject -EQ "CN=contoso.onmicrosoft.com" | select -ExpandProperty Thumbprint
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
                $allowedObjType = 'user'
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
            $sharepointSiteOwner | ? { $_.Owner -contains $userPrincipalName } | % {
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

function Get-AzureADAppRegistration {
    <#
    .SYNOPSIS
    Function for getting Azure AD App registration(s) as can be seen in Azure web portal.

    .DESCRIPTION
    Function for getting Azure AD App registration(s) as can be seen in Azure web portal.
    App registrations are global app representations with unique ID across all tenants. Enterprise app is then its local representation for specific tenant.

    .PARAMETER objectId
    (optional) objectID of app registration.

    If not specified, all app registrations will be processed.

    .PARAMETER credential
    Credentials for connecting to AzureAD.

    .PARAMETER data
    Type of extra data you want to get.

    Possible values:
     - owner
        get service principal owner
     - permission
        get delegated (OAuth2PermissionGrants) and application (AppRoleAssignments) permissions
     - users&Groups
        get explicit Users and Groups roles (omits users and groups listed because they gave permission consent)

    By default all these possible values are selected (this can take several minutes!).

    .EXAMPLE
    Get-AzureADAppRegistration

    Get all data for all AzureAD application registrations.

    .EXAMPLE
    Get-AzureADAppRegistration -objectId 1234-1234-1234 -data 'owner'

    Get basic + owner data for selected AzureAD application registration.
    #>

    [CmdletBinding()]
    param (
        [string] $objectId,

        [System.Management.Automation.PSCredential] $credential,

        [ValidateSet('owner', 'permission', 'users&Groups')]
        [string[]] $data = ('owner', 'permission', 'users&Groups')
    )

    if ($credential) {
        Connect-AzureAD2 -ErrorAction Stop -credential $credential
    } else {
        Connect-AzureAD2 -ErrorAction Stop
    }

    $param = @{}
    if ($objectId) { $param.objectId = $objectId }
    else { $param.all = $true }

    Get-AzureADApplication @param | % {
        $appObj = $_

        $appName = $appObj.DisplayName
        $appID = $appObj.AppId

        Write-Warning "Processing $appName"

        Write-Verbose "Getting corresponding Service Principal"
        $SPObject = Get-AzureADServicePrincipal -Filter "AppId eq '$appID'"
        $SPObjectId = $SPObject.ObjectId
        if ($SPObjectId) {
            Write-Verbose " - found service principal (enterprise app) with objectId: $SPObjectId"

            $appObj | Add-Member -MemberType NoteProperty -Name AppRoleAssignmentRequired -Value $SPObject.AppRoleAssignmentRequired
        } else {
            Write-Error "Registered app '$appName' doesn't have corresponding service principal (enterprise app). This shouldn't happen"
        }

        if ($data -contains 'owner') {
            Write-Verbose "Getting owner"

            $ownerResult = Get-AzureADApplicationOwner -ObjectId $appObj.ObjectId -All:$true | % {
                if ($_.UserPrincipalName) {
                    $name = $_.UserPrincipalName
                } elseif (!$_.UserPrincipalName -and $_.DisplayName) {
                    $name = $_.DisplayName + " **<This is an Application>**"
                } else {
                    $name = ""
                }

                $_ | select @{name = 'Name'; expression = { $name } }, ObjectId, ObjectType, AccountEnabled
            }

            $appObj | Add-Member -MemberType NoteProperty -Name Owner -Value $ownerResult
        }

        if ($data -contains 'permission') {
            Write-Verbose "Getting permission grants"

            if ($SPObjectId) {
                $SPPermission = Get-AzureADSPPermissions -objectId $SPObjectId
            } else {
                Write-Verbose "Unable to get permissions because corresponding ent. app is missing"
                $SPPermission = $null
            }

            $appObj | Add-Member -MemberType NoteProperty -Name Permission_AdminConsent -Value ($SPPermission | ? { $_.ConsentType -eq "AllPrincipals" -or $_.PermissionType -eq 'Application' } | select Permission, ResourceDisplayName, PermissionDisplayName, PermissionType)
            $appObj | Add-Member -MemberType NoteProperty -Name Permission_UserConsent -Value ($SPPermission | ? { $_.PermissionType -eq 'Delegated' -and $_.ConsentType -ne "AllPrincipals" } | select Permission, ResourceDisplayName, PermissionDisplayName, PrincipalObjectId, PrincipalDisplayName, PermissionType)
        }

        if ($data -contains 'users&Groups') {
            Write-Verbose "Getting users&Groups assignments"

            if ($SPObjectId) {
                $appObj | Add-Member -MemberType NoteProperty -Name UsersAndGroups -Value (Get-AzureADAppUsersAndGroups -objectId $SPObjectId | select * -ExcludeProperty ObjectId, DeletionTimestamp, ObjectType, Id, ResourceId, ResourceDisplayName)
            } else {
                Write-Verbose "Unable to get role assignments because corresponding ent. app is missing"
            }
        }

        $appObj | Add-Member -MemberType NoteProperty -Name EnterpriseAppId -Value $SPObjectId

        # expired secret?
        $expiredPasswordCredentials = $appObj.PasswordCredentials | ? { $_.EndDate -and ($_.EndDate -le (Get-Date) -and !($appObj.PasswordCredentials.EndDate -gt (Get-Date))) }
        if ($expiredPasswordCredentials) {
            $expiredPasswordCredentials = $true
        } else {
            if ($appObj.PasswordCredentials) {
                $expiredPasswordCredentials = $false
            } else {
                $expiredPasswordCredentials = $null
            }
        }
        $appObj | Add-Member -MemberType NoteProperty -Name ExpiredPasswordCredentials -Value $expiredPasswordCredentials

        # expired certificate?
        $expiredKeyCredentials = $appObj.KeyCredentials | ? { $_.EndDate -and ($_.EndDate -le (Get-Date) -and !($appObj.KeyCredentials.EndDate -gt (Get-Date))) }
        if ($expiredKeyCredentials) {
            $expiredKeyCredentials = $true
        } else {
            if ($appObj.KeyCredentials) {
                $expiredKeyCredentials = $false
            } else {
                $expiredKeyCredentials = $null
            }
        }
        $appObj | Add-Member -MemberType NoteProperty -Name ExpiredKeyCredentials -Value $expiredKeyCredentials
        #endregion add secret(s)

        # output
        $appObj
    }
}

function Get-AzureADAppUsersAndGroups {
    <#
    .SYNOPSIS
    Get users and groups roles of (selected) service principal.

    .DESCRIPTION
    Get users and groups roles of (selected) service principal.

    .PARAMETER objectId
    ObjectId of service principal.

    If not provided all service principals will be processed.

    .EXAMPLE
    Get-AzureADAppUsersAndGroups

    Returns all service principals and their users and groups roles assignments.

    .EXAMPLE
    Get-AzureADAppUsersAndGroups -objectId 123123

    Returns service principal with objectId 123123 and its users and groups roles assignments.

    .NOTES
    https://github.com/MicrosoftDocs/azure-docs/issues/48159
    #>

    [CmdletBinding()]
    [Alias("Get-AzureADServiceAppRoleAssignment2")]
    param (
        [string] $objectId
    )

    Connect-AzureAD2

    $sessionInfo = Get-AzureADCurrentSessionInfo -ea Stop

    $param = @{}
    if ($objectId) {
        Write-Verbose "Get $objectId service principal"
        $param.objectId = $objectId
    } else {
        Write-Verbose "Get all service principals"
        $param.all = $true
    }

    Get-AzureADServicePrincipal @param | % {
        # Build a hash table of the service principal's app roles. The 0-Guid is
        # used in an app role assignment to indicate that the principal is assigned
        # to the default app role (or rather, no app role).
        $appRoles = @{ [Guid]::Empty.ToString() = "(default)" }
        $_.AppRoles | % { $appRoles[$_.Id] = $_.DisplayName }

        # Get the app role assignments for this app, and add a field for the app role name

        if ($sessionInfo.Account.Type -eq 'user') {
            Get-AzureADServiceAppRoleAssignment -ObjectId $_.ObjectId -All:$true | % {
                $_ | Add-Member -Name "AppRoleDisplayName" -Value $appRoles[$_.Id] -MemberType NoteProperty -PassThru
            }
        } else {
            # running under service principal
            # there is super weird bug when under service principal Get-AzureADServiceAppRoleAssignedTo behaves like Get-AzureADServiceAppRoleAssignment and vice versa (https://github.com/Azure/azure-docs-powershell-azuread/issues/766)!!!
            Get-AzureADServiceAppRoleAssignedTo -ObjectId $_.ObjectId -All:$true | % {
                $_ | Add-Member -Name "AppRoleDisplayName" -Value $appRoles[$_.Id] -MemberType NoteProperty -PassThru
            }
        }
    }
}

function Get-AzureADAppVerificationStatus {
    param (
        [Parameter(Mandatory = $false, ParameterSetName = "entApp")]
        [string] $servicePrincipalObjectId,

        [Parameter(Mandatory = $false, ParameterSetName = "appReg")]
        [string] $appRegObjectId,

        $header
    )

    if (!$header) {
        try {
            $header = New-GraphAPIAuthHeader -reuseExistingAzureADSession -ErrorAction Stop
        } catch {
            throw "Unable to retrieve authentication header for graph api. Create it using New-GraphAPIAuthHeader and pass it using header parameter"
        }
    }

    if ($appRegObjectId) {
        $URL = "https://graph.microsoft.com/v1.0/applications/$appRegObjectId`?`$select=displayName,verifiedPublisher"
    } elseif ($servicePrincipalObjectId) {
        $URL = "https://graph.microsoft.com/v1.0/servicePrincipals/$servicePrincipalObjectId`?`$select=displayName,verifiedPublisher"
    } else {
        $URL = "https://graph.microsoft.com/v1.0/servicePrincipals?`$select=displayName,verifiedPublisher"
    }

    Invoke-GraphAPIRequest -uri $URL -header $header | select displayName, @{name = 'publisherName'; expression = { $_.verifiedPublisher.displayName } }, @{name = 'publisherId'; expression = { $_.verifiedPublisher.verifiedPublisherId } }, @{name = 'publisherAdded'; expression = { Get-Date $_.verifiedPublisher.addedDateTime } }
}

function Get-AzureADAssessNotificationEmail {
    <#
    .SYNOPSIS
    Function returns email(s) of organization technical contact(s) and privileged roles members.

    .DESCRIPTION
    Function returns email(s) of organization technical contact(s) and privileged roles members.

    .EXAMPLE
    $authHeader = New-GraphAPIAuthHeader -reuseExistingAzureADSession
    Get-AzureADAssessNotificationEmail -authHeader $authHeader

    .NOTES
    Stolen from Get-AADAssessNotificationEmailsReport function (module AzureADAssessment)
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $authHeader
    )

    #region get Organization Technical Contacts
    $OrganizationData = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/organization?`$select=technicalNotificationMails" -header $authHeader
    if ($OrganizationData) {
        foreach ($technicalNotificationMail in $OrganizationData.technicalNotificationMails) {
            $result = [PSCustomObject]@{
                notificationType           = "Technical Notification"
                notificationScope          = "Tenant"
                recipientType              = "emailAddress"
                recipientEmail             = $technicalNotificationMail
                recipientEmailAlternate    = $null
                recipientId                = $null
                recipientUserPrincipalName = $null
                recipientDisplayName       = $null
            }

            $user = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/users?`$select=id,userPrincipalName,displayName,mail,otherMails,proxyAddresses&`$filter=proxyAddresses/any(c:c eq 'smtp:$technicalNotificationMail') or otherMails/any(c:c eq 'smtp:$technicalNotificationMail')" -header $authHeader | Select-Object -First 1
        }

        if ($user) {
            $result.recipientType = 'user'
            $result.recipientId = $user.id
            $result.recipientUserPrincipalName = $user.userPrincipalName
            $result.recipientDisplayName = $user.displayName
            $result.recipientEmailAlternate = $user.otherMails -join ';'
        }

        $group = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/groups?`$filter=proxyAddresses/any(c:c eq 'smtp:$technicalNotificationMail')" -header $authHeader | Select-Object -First 1
        if ($group) {
            $result.recipientType = 'group'
            $result.recipientId = $group.id
            $result.recipientDisplayName = $group.displayName
        }

        Write-Output $result
    }
    #endregion get Organization Technical Contacts

    #region get email addresses of all users with privileged roles
    $DirectoryRoleData = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/directoryRoles?`$select=id,displayName&`$expand=members" -header $authHeader

    foreach ($role in $DirectoryRoleData) {
        foreach ($roleMember in $role.members) {
            $member = $null
            if ($roleMember.'@odata.type' -eq '#microsoft.graph.user') {
                $member = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/users?`$select=id,userPrincipalName,displayName,mail,otherMails,proxyAddresses&`$filter=id eq '$($roleMember.id)'" -header $authHeader | Select-Object -First 1
            } elseif ($roleMember.'@odata.type' -eq '#microsoft.graph.group') {
                $member = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/groups?`$select=id,displayName,mail,proxyAddresses&`$filter=id eq '$($roleMember.id)'" -header $authHeader | Select-Object -First 1
            } elseif ($roleMember.'@odata.type' -eq '#microsoft.graph.servicePrincipal') {
                $member = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=id,displayName&`$filter=id eq '$($roleMember.id)'" -header $authHeader | Select-Object -First 1
            } else {
                Write-Error "Undefined type $($roleMember.'@odata.type')"
            }

            [PSCustomObject]@{
                notificationType           = $role.displayName
                notificationScope          = 'Role'
                recipientType              = ($roleMember.'@odata.type') -replace '#microsoft.graph.', ''
                recipientEmail             = ($member.'mail')
                recipientEmailAlternate    = ($member.'otherMails') -join ';'
                recipientId                = ($member.'id')
                recipientUserPrincipalName = ($member.'userPrincipalName')
                recipientDisplayName       = ($member.'displayName')
            }
        }
    }
    #endregion get email addresses of all users with privileged roles
}

function Get-AzureADEnterpriseApplication {
    <#
    .SYNOPSIS
    Function for getting Azure AD Service Principal(s) \ Enterprise Application(s) as can be seen in Azure web portal.

    .DESCRIPTION
    Function for getting Azure AD Service Principal(s) \ Enterprise Application(s) as can be seen in Azure web portal.

    .PARAMETER objectId
    (optional) objectID(s) of Service Principal(s) \ Enterprise Application(s).

    If not specified, all enterprise applications will be processed.

    .PARAMETER data
    Type of extra data you want to get to the ones returned by Get-AzureADServicePrincipal.

    Possible values:
     - owner
        get service principal owner
     - permission
        get delegated (OAuth2PermissionGrants) and application (AppRoleAssignments) permissions
     - users&Groups
        get explicit Users and Groups roles (omits users and groups listed because they gave permission consent)

    By default all these possible values are selected (this can take several minutes!).

    .PARAMETER includeBuiltInApp
    Switch for including also builtin Azure apps.

    .PARAMETER excludeAppWithAppRegistration
    Switch for excluding enterprise app(s) for which exists corresponding app registration.

    .EXAMPLE
    Get-AzureADEnterpriseApplication

    Get all data for all AzureAD enterprise applications. Builtin apps are excluded.

    .EXAMPLE
    Get-AzureADEnterpriseApplication -excludeAppWithAppRegistration

    Get all data for all AzureAD enterprise applications. Builtin apps and apps for which app registration exists are excluded.

    .EXAMPLE
    Get-AzureADEnterpriseApplication -objectId 1234-1234-1234 -data 'owner'

    Get basic + owner data for selected AzureAD enterprise application.
    #>

    [CmdletBinding()]
    [Alias("Get-AzureADServicePrincipal2")]
    param (
        [string[]] $objectId,

        [ValidateSet('owner', 'permission', 'users&Groups')]
        [string[]] $data = ('owner', 'permission', 'users&Groups'),

        [switch] $includeBuiltInApp,

        [switch] $excludeAppWithAppRegistration
    )

    try {
        # test if connection already exists
        $null = Get-AzureADCurrentSessionInfo -ea Stop
    } catch {
        throw "You must call the Connect-AzureAD cmdlet before calling any other cmdlets."
    }

    $servicePrincipalList = $null

    if ($data -contains 'permission' -and !$objectId) {
        # it is much faster to get all SP permissions at once instead of one-by-one processing in foreach (thanks to caching)
        Write-Verbose "Getting granted permission(s)"

        $SPPermission = Get-AzureADSPPermissions -ErrorAction 'Continue'
    }

    if (!$objectId) {
        $enterpriseApp = Get-AzureADServicePrincipal -Filter "servicePrincipalType eq 'Application'" -All:$true

        if ($excludeAppWithAppRegistration) {
            $appRegistrationObj = Get-AzureADApplication -All:$true
            $enterpriseApp = $enterpriseApp | ? AppId -NotIn $appRegistrationObj.AppId
        }

        if (!$includeBuiltInApp) {
            $enterpriseApp = $enterpriseApp | ? tags -Contains 'WindowsAzureActiveDirectoryIntegratedApp'
        }

        $servicePrincipalList = $enterpriseApp
    } else {
        $objectId | % {
            $servicePrincipalList += Get-AzureADServicePrincipal -ObjectId $_
        }
    }

    $servicePrincipalList | ? { $_ } | % {
        $SPObj = $_

        Write-Verbose "Processing '$($SPObj.DisplayName)' ($($SPObj.ObjectId))"

        if ($data -contains 'owner') {
            Write-Verbose "Getting owner"

            $ownerResult = Get-AzureADServicePrincipalOwner -ObjectId $SPObj.ObjectId -All:$true | % {
                if ($_.UserPrincipalName) {
                    $name = $_.UserPrincipalName
                } elseif (!$_.UserPrincipalName -and $_.DisplayName) {
                    $name = $_.DisplayName + " **<This is an Application>**"
                } else {
                    $name = ""
                }

                $_ | select @{name = 'Name'; expression = { $name } }, ObjectId, ObjectType, AccountEnabled
            }

            $SPObj | Add-Member -MemberType NoteProperty -Name Owner -Value $ownerResult
        }

        if ($data -contains 'permission') {
            Write-Verbose "Getting permission grants"

            if ($SPPermission) {
                $permission = $SPPermission | ? ClientObjectId -EQ $SPObj.ObjectId
            } else {
                $permission = Get-AzureADSPPermissions -objectId $SPObj.ObjectId
            }

            $SPObj | Add-Member -MemberType NoteProperty -Name Permission_AdminConsent -Value ($permission | ? { $_.ConsentType -eq "AllPrincipals" -or $_.PermissionType -eq 'Application' } | select Permission, ResourceDisplayName, PermissionDisplayName, PermissionType)
            $SPObj | Add-Member -MemberType NoteProperty -Name Permission_UserConsent -Value ($permission | ? { $_.PermissionType -eq 'Delegated' -and $_.ConsentType -ne "AllPrincipals" } | select Permission, ResourceDisplayName, PermissionDisplayName, PrincipalObjectId, PrincipalDisplayName, PermissionType)
        }

        if ($data -contains 'users&Groups') {
            Write-Verbose "Getting users&Groups assignments"

            $SPObj | Add-Member -MemberType NoteProperty UsersAndGroups -Value (Get-AzureADAppUsersAndGroups -objectId $SPObj.ObjectId | select * -ExcludeProperty ObjectId, DeletionTimestamp, ObjectType, Id, ResourceId, ResourceDisplayName)
        }

        # expired secret?
        $expiredCertificate = $SPObj.PasswordCredentials | ? { $_.EndDate -and ($_.EndDate -le (Get-Date) -and !($SPObj.PasswordCredentials.EndDate -gt (Get-Date))) }
        if ($expiredSecret) {
            $expiredSecret = $true
        } else {
            if ($SPObj.PasswordCredentials) {
                $expiredSecret = $false
            } else {
                $expiredSecret = $null
            }
        }
        $SPObj | Add-Member -MemberType NoteProperty ExpiredSecret -Value $expiredSecret

        # expired certificate?
        $expiredCertificate = $SPObj.KeyCredentials | ? { $_.EndDate -and ($_.EndDate -le (Get-Date) -and !($SPObj.KeyCredentials.EndDate -gt (Get-Date))) }
        if ($expiredCertificate) {
            $expiredCertificate = $true
        } else {
            if ($SPObj.KeyCredentials) {
                $expiredCertificate = $false
            } else {
                $expiredCertificate = $null
            }
        }
        $SPObj | Add-Member -MemberType NoteProperty expiredCertificate -Value $expiredCertificate

        # output
        $SPObj
    }
}

function Get-AzureAdGroupMemberRecursive {
    <#
    .SYNOPSIS
    Function for recursive enumeration of all Azure AD group.

    .DESCRIPTION
    Function for recursive enumeration of all Azure AD group.
    Group can be identified via id or name.

    .PARAMETER azureGroupObj
    AzureAD group object.

    .PARAMETER azureGroupName
    AzureAD group name.

    .PARAMETER azureGroupId
    AzureAD group id.

    .PARAMETER includeNestedGroup
    Switch for outputting of nested groups (not just their members).

    .EXAMPLE
    Get-AzureAdGroupMemberRecursive -azureGroupName "IT RBAC"

    .EXAMPLE
    Get-AzureAdGroupMemberRecursive -azureGroupId 123412341234

    .NOTES
    #https://gist.github.com/alexmags/cb69108c65fb38614b6625b4400c98c2
    #>

    [cmdletbinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true, ParameterSetName = "azureGroupObj")]
        $azureGroupObj,

        [Parameter(Mandatory = $true, ParameterSetName = "azureGroupName")]
        [string] $azureGroupName,

        [Parameter(Mandatory = $true, ParameterSetName = "azureGroupId")]
        [string] $azureGroupId,

        [switch] $includeNestedGroup
    )

    Begin {
        Connect-AzureAD2
    }

    Process {
        if ($azureGroupObj) {
            $azureGroupName = $azureGroupObj.DisplayName
            $azureGroupId = $azureGroupObj.ObjectId
        } elseif ($azureGroupName) {
            $azureGroupId = Get-AzureADGroup -SearchString $azureGroupName | select -ExpandProperty ObjectId
        } elseif ($azureGroupId) {
            $azureGroupName = Get-AzureADGroup -ObjectId $azureGroupId | select -ExpandProperty DisplayName
        } else {
            throw "You haven't specified any parameter"
        }

        Write-Verbose -Message "Enumerating $azureGroupName ($azureGroupId)"

        Get-AzureADGroupMember -ObjectId $azureGroupId -All $true | % {
            if ($_.ObjectType -eq 'Group') {
                if ($includeNestedGroup) {
                    $_
                }

                Get-AzureAdGroupMemberRecursive -AzureGroupObj $_
            } else {
                $_
            }
        }
    }
}

function Get-AzureADManagedIdentity {
    <#
    .SYNOPSIS
    Function for getting Azure AD Managed Identity(ies).

    .DESCRIPTION
    Function for getting Azure AD Managed Identity(ies).

    .PARAMETER objectId
    (optional) objectID of Managed Identity(ies).

    If not specified, all app registrations will be processed.

    .EXAMPLE
    Get-AzureADManagedIdentity

    Get all Managed Identities.

    .EXAMPLE
    Get-AzureADManagedIdentity -objectId 1234-1234-1234

    Get selected Managed Identity.
    #>

    [CmdletBinding()]
    param (
        [string[]] $objectId
    )

    try {
        # test if connection already exists
        $null = Get-AzureADCurrentSessionInfo -ea Stop
    } catch {
        throw "You must call the Connect-AzureAD cmdlet before calling any other cmdlets."
    }

    $servicePrincipalList = @()

    if (!$objectId) {
        $servicePrincipalList = Get-AzureADServicePrincipal -Filter "servicePrincipalType eq 'ManagedIdentity'" -All:$true
    } else {
        $objectId | % {
            $servicePrincipalList += Get-AzureADServicePrincipal -ObjectId $_
        }
    }

    $azureSubscriptions = Get-AzSubscription

    $servicePrincipalList | % {
        $SPObj = $_

        # output
        $SPObj | select *, @{n = 'SubscriptionId'; e = { $_.alternativeNames | ? { $_ -Match "/subscriptions/([^/]+)/" } | % { ([regex]"/subscriptions/([^/]+)/").Matches($_).captures.groups[1].value } } }, @{name = 'SubscriptionName'; expression = { $alternativeNames = $_.alternativeNames; $azureSubscriptions | ? { $_.Id -eq ($alternativeNames | ? { $_ -Match "/subscriptions/([^/]+)/" } | % { ([regex]"/subscriptions/([^/]+)/").Matches($_).captures.groups[1].value }) } | select -exp Name } }, @{n = 'ResourceGroup'; e = { $_.alternativeNames | ? { $_ -Match "/resourcegroups/([^/]+)/" } | % { ([regex]"/resourcegroups/([^/]+)/").Matches($_).captures.groups[1].value } } },
        @{n = 'Type'; e = { if ($_.alternativeNames -match "/Microsoft.ManagedIdentity/userAssignedIdentities/") { 'UserManagedIdentity' } else { 'SystemManagedIdentity' } } }
    }
}

function Get-AzureADResource {
    <#
    .SYNOPSIS
    Returns resources for all or just selected Azure subscription(s).

    .DESCRIPTION
    Returns resources for all or just selected Azure subscription(s).

    .PARAMETER subscriptionId
    ID of subscription you want to get resources for.

    .PARAMETER selectCurrentSubscription
    Switch for getting data just for currently set subscription.

    .EXAMPLE
    Get-AzureADResource

    Returns resources for all subscriptions.

    .EXAMPLE
    Get-AzureADResource -subscriptionId 1234-1234-1234-1234

    Returns resources for subscription with ID 1234-1234-1234-1234.

    .EXAMPLE
    Get-AzureADResource -selectCurrentSubscription

    Returns resources just for current subscription.
    #>

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [Parameter(ParameterSetName = "subscriptionId")]
        [string] $subscriptionId,

        [Parameter(ParameterSetName = "currentSubscription")]
        [switch] $selectCurrentSubscription
    )

    # get Current Context
    $currentContext = Get-AzContext

    # get Azure Subscriptions
    if ($selectCurrentSubscription) {
        Write-Verbose "Only running for current subscription $($currentContext.Subscription.Name)"
        $subscriptions = Get-AzSubscription -SubscriptionId $currentContext.Subscription.Id -TenantId $currentContext.Tenant.Id
    } elseif ($subscriptionId) {
        Write-Verbose "Only running for selected subscription $subscriptionId"
        $subscriptions = Get-AzSubscription -SubscriptionId $subscriptionId -TenantId $currentContext.Tenant.Id
    } else {
        Write-Verbose "Running for all subscriptions in tenant"
        $subscriptions = Get-AzSubscription -TenantId $currentContext.Tenant.Id
    }

    Write-Verbose "Getting information about Role Definitions..."
    $allRoleDefinition = Get-AzRoleDefinition

    foreach ($subscription in $subscriptions) {
        Write-Verbose "Changing to Subscription $($subscription.Name)"

        $Context = Set-AzContext -TenantId $subscription.TenantId -SubscriptionId $subscription.Id -Force

        # getting information about Role Assignments for chosen subscription
        Write-Verbose "Getting information about Role Assignments..."
        $allRoleAssignment = Get-AzRoleAssignment

        Write-Verbose "Getting information about Resources..."

        Get-AzResource | % {
            $resourceId = $_.ResourceId
            Write-Verbose "Processing $resourceId"

            $roleAssignment = $allRoleAssignment | ? { $resourceId -match [regex]::escape($_.scope) -or $_.scope -like "/providers/Microsoft.Authorization/roleAssignments/*" -or $_.scope -like "/providers/Microsoft.Management/managementGroups/*" } | select RoleDefinitionName, DisplayName, Scope, SignInName, ObjectType, ObjectId, @{n = 'CustomRole'; e = { ($allRoleDefinition | ? Name -EQ $_.RoleDefinitionName).IsCustom } }, @{n = 'Inherited'; e = { if ($_.scope -eq $resourceId) { $false } else { $true } } }

            $_ | select *, @{n = "SubscriptionName"; e = { $subscription.Name } }, @{n = "SubscriptionId"; e = { $subscription.SubscriptionId } }, @{n = 'IAM'; e = { $roleAssignment } } -ExcludeProperty SubscriptionId, ResourceId, ResourceType
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

function Get-AzureADServicePrincipalOverview {
    <#
    .SYNOPSIS
    Function for getting overall information for AzureAD Service principal(s).

    .DESCRIPTION
    Function for getting overall information for AzureAD Service principal(s).

    .PARAMETER objectId
    (optional) objectId of the service principal you want information for.

    .PARAMETER data
    Type of extra data you want to get.

    Possible values:
     - owner
        get service principal owner
     - permission
        get delegated permissions (OAuth2PermissionGrants) and application permissions (AppRoleAssignments)
     - users&Groups
        get explicit Users and Groups roles (omits users and groups listed because they gave permission consent)
     - lastUsed
        get last date this service principal was used according the audit logs

    By default all these possible values are selected (this can take dozens of minutes!).

    .PARAMETER credential
    Credentials for AzureAD authentication.

    .PARAMETER header
    Header for authentication of graph calls.
    Use if calling Get-AzureADServicePrincipalOverview several times in short time period. Otherwise you will end with error: We couldn't sign you in.
    Header object can be created via New-GraphAPIAuthHeader function.

    .EXAMPLE
    Get-AzureADServicePrincipalOverview

    Get all data for all service principals.

    .EXAMPLE
    Get-AzureADServicePrincipalOverview -objectId 1234-1234-1234 -data 'owner', 'permission'

    Get basic service principal data plus owner and permissions for SP with given objectId.

    .NOTES
    Nice similar solution https://github.com/michevnew/PowerShell/blob/master/app_Permissions_inventory_GraphAPI.ps1
    #>

    [CmdletBinding()]
    param (
        [string] $objectId,

        [ValidateSet('owner', 'permission', 'users&Groups', 'lastUsed')]
        [string[]] $data = ('owner', 'permission', 'users&Groups', 'lastUsed'),

        [System.Management.Automation.PSCredential] $credential,

        $header
    )

    #region authenticate
    if ($credential) {
        Connect-AzureAD2 -credential $credential -ErrorAction Stop
    } else {
        Connect-AzureAD2 -ErrorAction Stop
    }
    if (!$header) {
        $header = New-GraphAPIAuthHeader -reuseExistingAzureADSession -ErrorAction Stop
    }
    #endregion authenticate

    if ($data -contains 'permission') {
        # it is much faster to get all SP permissions at once instead of one-by-one processing in foreach (thanks to caching)
        Write-Verbose "Getting granted permission(s)"

        $param = @{ ErrorAction = 'Continue' }
        if ($objectId) { $param.objectId = $objectId }

        $SPPermission = Get-AzureADSPPermissions @param
    }

    $param = @{}
    if ($objectId) { $param.objectId = $objectId }
    else { $param.all = $true }

    Get-AzureADServicePrincipal @param | % {
        $SP = $_

        $SPName = $SP.AppDisplayName
        if (!$SPName) { $SPName = $SP.DisplayName }
        Write-Warning "Processing '$SPName' ($($SP.AppId))"

        if ($data -contains 'owner') {
            Write-Verbose "Getting owner"
            $SP = $SP | select *, @{n = 'Owner'; e = { Get-AzureADServicePrincipalOwner -ObjectId $_.ObjectId -All:$true } }
        }

        if ($data -contains 'permission') {
            $permission = $SPPermission | ? ClientObjectId -EQ $SP.objectId

            $SP = $SP | select *, @{n = 'Permission_AdminConsent'; e = { $permission | ? { $_.ConsentType -eq "AllPrincipals" -or $_.PermissionType -eq 'Application' } | select Permission, ResourceDisplayName, PermissionDisplayName, PermissionType } }
            $SP = $SP | select *, @{n = 'Permission_UserConsent'; e = { $permission | ? { $_.PermissionType -eq 'Delegated' -and $_.ConsentType -ne "AllPrincipals" } | select Permission, ResourceDisplayName, PermissionDisplayName, PrincipalObjectId, PrincipalDisplayName, PermissionType } }
        }

        if ($data -contains 'users&Groups') {
            Write-Verbose "Getting explicitly assigned users and groups"
            # show just explicitly added members, not added via granting consent
            $consentPrincipalId = @($SP.Permission_AdminConsent.PrincipalObjectId) + @($SP.Permission_UserConsent.PrincipalObjectId)
            $SP = $SP | select *, @{n = 'UsersAndGroups'; e = { Get-AzureADAppUsersAndGroups -objectId $SP.objectId | select ObjectType , CreationTimestamp, PrincipalDisplayName, PrincipalId, PrincipalType | ? PrincipalId -NotIn $consentPrincipalId } }
        }

        #region check secrets
        $sResult = @()
        $cResult = @()

        #region process secret(s)
        $secret = $SP.PasswordCredentials
        $cert = $SP.KeyCredentials

        foreach ($s in $secret) {
            $startDate = $s.StartDate
            $endDate = $s.EndDate

            $sResult += [PSCustomObject]@{
                StartDate = $startDate
                EndDate   = $endDate
            }
        }

        foreach ($c in $cert) {
            $startDate = $c.StartDate
            $endDate = $c.EndDate

            $cResult += [PSCustomObject]@{
                StartDate = $startDate
                EndDate   = $endDate
            }
        }
        #endregion process secret(s)

        # expired secret
        $expiredSecret = $sResult | ? { $_.EndDate -and ($_.EndDate -le (Get-Date) -and !($_.EndDate -gt (Get-Date))) }
        if ($expiredSecret) {
            $expiredSecret = $true
        } else {
            if ($sResult) {
                $expiredSecret = $false
            } else {
                $expiredSecret = $null
            }
        }
        # $SP = $SP | Add-Member -MemberType NoteProperty -Name ExpiredSecret -Value $expiredSecret
        $SP = $SP | select *, @{n = 'ExpiredSecret'; e = { $expiredSecret } }

        # expired certificate
        $expiredCertificate = $cResult | ? { $_.EndDate -and ($_.EndDate -le (Get-Date) -and !($_.EndDate -gt (Get-Date))) }
        if ($expiredCertificate) {
            $expiredCertificate = $true
        } else {
            if ($cResult) {
                $expiredCertificate = $false
            } else {
                $expiredCertificate = $null
            }
        }
        # $SP = $SP | Add-Member -MemberType NoteProperty -Name ExpiredCertificate -Value $expiredCertificate
        $SP = $SP | select *, @{n = 'ExpiredCertificate'; e = { $expiredCertificate } }
        #endregion check secrets

        if ($data -contains 'lastUsed') {
            Write-Verbose "Getting last used date"
            # Get-AzureADAuditSignInLogs has problems with throttling 'Too Many Requests', Invoke-GraphAPIRequest has builtin fix for that
            $signInResult = Invoke-GraphAPIRequest -uri "https://graph.microsoft.com/beta/auditLogs/signIns?api-version=beta&`$filter=(appId eq '$($SP.AppId)')&`$top=1&`$orderby=createdDateTime desc" -header $header
            if ($signInResult.count -ge 1) {
                $SP = $SP | select *, @{n = 'LastUsed'; e = { $signInResult.CreatedDateTime } }
            } else {
                $SP = $SP | select *, @{n = 'LastUsed'; e = { $null } }
            }
        }

        #output
        $SP
    }
}

function Get-AzureADSPPermissions {
    <#
    .SYNOPSIS
        Lists granted delegated (OAuth2PermissionGrants) and application (AppRoleAssignments) permissions.

    .PARAMETER objectId
        Service principal objectId. If not specified, all service principals will be processed.

    .PARAMETER DelegatedPermissions
        If set, will return delegated permissions. If neither this switch nor the ApplicationPermissions switch is set,
        both application and delegated permissions will be returned.

    .PARAMETER ApplicationPermissions
        If set, will return application permissions. If neither this switch nor the DelegatedPermissions switch is set,
        both application and delegated permissions will be returned.

    .PARAMETER UserProperties
        The list of properties of user objects to include in the output. Defaults to DisplayName only.

    .PARAMETER ServicePrincipalProperties
        The list of properties of service principals (i.e. apps) to include in the output. Defaults to DisplayName only.

    .PARAMETER ShowProgress
        Whether or not to display a progress bar when retrieving application permissions (which could take some time).

    .PARAMETER PrecacheSize
        The number of users to pre-load into a cache. For tenants with over a thousand users,
        increasing this may improve performance of the script.
    .EXAMPLE
        PS C:\> Get-AzureADSPPermissions -objectId f1c5b03c-6605-46ac-8ddb-453b953af1fc
        Generates report of all permissions granted to app f1c5b03c-6605-46ac-8ddb-453b953af1fc.

    .EXAMPLE
        PS C:\> Get-AzureADSPPermissions | Export-Csv -Path "permissions.csv" -NoTypeInformation
        Generates a CSV report of all permissions granted to all apps.

    .EXAMPLE
        PS C:\> Get-AzureADSPPermissions -ApplicationPermissions -ShowProgress | Where-Object { $_.Permission -eq "Directory.Read.All" }
        Get all apps which have application permissions for Directory.Read.All.

    .EXAMPLE
        PS C:\> Get-AzureADSPPermissions -UserProperties @("DisplayName", "UserPrincipalName", "Mail") -ServicePrincipalProperties @("DisplayName", "AppId")
        Gets all permissions granted to all apps and includes additional properties for users and service principals.

    .NOTES
        https://docs.microsoft.com/en-us/microsoft-365/security/office-365-security/detect-and-remediate-illicit-consent-grants?view=o365-worldwide
    #>

    [CmdletBinding()]
    [Alias("Get-AzureADPSPermissionGrants", "Get-AzureADPSPermissions", "Get-AzureADServicePrincipalPermissions")]
    param(
        [string] $objectId,

        [switch] $DelegatedPermissions,

        [switch] $ApplicationPermissions,

        [string[]] $UserProperties = @("DisplayName"),

        [string[]] $ServicePrincipalProperties = @("DisplayName"),

        [switch] $ShowProgress,

        [int] $PrecacheSize = 999
    )

    Connect-AzureAD2

    $sessionInfo = Get-AzureADCurrentSessionInfo -ea Stop

    # An in-memory cache of objects by {object ID} and by {object class, object ID}
    $script:ObjectByObjectId = @{}
    $script:ObjectByObjectClassId = @{}

    #region helper functions
    # Function to add an object to the cache
    function CacheObject ($Object) {
        if ($Object) {
            if (-not $script:ObjectByObjectClassId.ContainsKey($Object.ObjectType)) {
                $script:ObjectByObjectClassId[$Object.ObjectType] = @{}
            }
            $script:ObjectByObjectClassId[$Object.ObjectType][$Object.ObjectId] = $Object
            $script:ObjectByObjectId[$Object.ObjectId] = $Object
        }
    }

    # Function to retrieve an object from the cache (if it's there), or from Azure AD (if not).
    function GetObjectByObjectId ($ObjectId) {
        if (-not $script:ObjectByObjectId.ContainsKey($ObjectId)) {
            Write-Verbose ("Querying Azure AD for object '{0}'" -f $ObjectId)
            try {
                $object = Get-AzureADObjectByObjectId -ObjectId $ObjectId
                CacheObject -Object $object
            } catch {
                Write-Verbose "Object not found."
            }
        }
        return $script:ObjectByObjectId[$ObjectId]
    }

    # Function to retrieve all OAuth2PermissionGrants, either by directly listing them (-FastMode)
    # or by iterating over all ServicePrincipal objects. The latter is required if there are more than
    # 999 OAuth2PermissionGrants in the tenant, due to a bug in Azure AD.
    function GetOAuth2PermissionGrants ([switch]$FastMode) {
        if ($FastMode) {
            Get-AzureADOAuth2PermissionGrant -All $true
        } else {
            # clone to avoid "An error occurred while enumerating through a collection: Collection was modified; enumeration operation may not execute.."
            $($script:ObjectByObjectClassId['ServicePrincipal'].GetEnumerator().Clone()) | ForEach-Object { $i = 0 } {
                if ($ShowProgress) {
                    Write-Progress -Activity "Retrieving delegated permissions..." `
                        -Status ("Checked {0}/{1} apps" -f $i++, $servicePrincipalCount) `
                        -PercentComplete (($i / $servicePrincipalCount) * 100)
                }

                $client = $_.Value
                Get-AzureADServicePrincipalOAuth2PermissionGrant -ObjectId $client.ObjectId
            }
        }
    }
    #endregion helper functions

    $empty = @{} # Used later to avoid null checks

    # Get ServicePrincipal object(s) and add to the cache
    if ($objectId) {
        Write-Verbose "Retrieving $objectId ServicePrincipal object..."
        Get-AzureADServicePrincipal -ObjectId $objectId | ForEach-Object {
            CacheObject -Object $_
        }
    } else {
        Write-Verbose "Retrieving all ServicePrincipal objects..."
        Get-AzureADServicePrincipal -All $true | ForEach-Object {
            CacheObject -Object $_
        }
    }

    $servicePrincipalCount = $script:ObjectByObjectClassId['ServicePrincipal'].Count

    if ($DelegatedPermissions -or (!$DelegatedPermissions -and !$ApplicationPermissions)) {
        # Get one page of User objects and add to the cache
        if (!$objectId) {
            Write-Verbose ("Retrieving up to {0} User objects..." -f $PrecacheSize)
            Get-AzureADUser -Top $PrecacheSize | Where-Object {
                CacheObject -Object $_
            }

            Write-Verbose "Testing for OAuth2PermissionGrants bug before querying..."
            $fastQueryMode = $false
            try {
                # There's a bug in Azure AD Graph which does not allow for directly listing
                # oauth2PermissionGrants if there are more than 999 of them. The following line will
                # trigger this bug (if it still exists) and throw an exception.
                $null = Get-AzureADOAuth2PermissionGrant -Top 999
                $fastQueryMode = $true
            } catch {
                if ($_.Exception.Message -and $_.Exception.Message.StartsWith("Unexpected end when deserializing array.")) {
                    Write-Verbose ("Fast query for delegated permissions failed, using slow method...")
                } else {
                    throw $_
                }
            }
        } else {
            # false means grants will be searched for just cached service principals i.e. those we actually need
            $fastQueryMode = $false
        }

        # Get all existing OAuth2 permission grants, get the client, resource and scope details
        Write-Verbose "Retrieving OAuth2PermissionGrants..."
        GetOAuth2PermissionGrants -FastMode:$fastQueryMode | ForEach-Object {
            $grant = $_
            if ($grant.Scope) {
                $grant.Scope.Split(" ") | Where-Object { $_ } | ForEach-Object {

                    $scope = $_
                    $resource = GetObjectByObjectId -ObjectId $grant.ResourceId
                    $permission = $resource.OAuth2Permissions | Where-Object { $_.Value -eq $scope }

                    $grantDetails = [ordered]@{
                        "PermissionType"        = "Delegated"
                        "ClientObjectId"        = $grant.ClientId
                        "ResourceObjectId"      = $grant.ResourceId
                        "GrantId"               = $grant.ObjectId
                        "Permission"            = $scope
                        # "PermissionId"          = $permission.Id
                        "PermissionDisplayName" = $permission.AdminConsentDisplayName
                        "PermissionDescription" = $permission.AdminConsentDescription
                        "ConsentType"           = $grant.ConsentType
                        "PrincipalObjectId"     = $grant.PrincipalId
                    }

                    # Add properties for client and resource service principals
                    if ($ServicePrincipalProperties.Count -gt 0) {

                        $client = GetObjectByObjectId -ObjectId $grant.ClientId
                        $resource = GetObjectByObjectId -ObjectId $grant.ResourceId

                        $insertAtClient = 2
                        $insertAtResource = 3
                        foreach ($propertyName in $ServicePrincipalProperties) {
                            $grantDetails.Insert($insertAtClient++, "Client$propertyName", $client.$propertyName)
                            $insertAtResource++
                            $grantDetails.Insert($insertAtResource, "Resource$propertyName", $resource.$propertyName)
                            $insertAtResource ++
                        }
                    }

                    # Add properties for principal (will all be null if there's no principal)
                    if ($UserProperties.Count -gt 0) {

                        $principal = $empty
                        if ($grant.PrincipalId) {
                            $principal = GetObjectByObjectId -ObjectId $grant.PrincipalId
                        }

                        foreach ($propertyName in $UserProperties) {
                            $grantDetails["Principal$propertyName"] = $principal.$propertyName
                        }
                    }

                    New-Object PSObject -Property $grantDetails
                }
            }
        }
    }

    if ($ApplicationPermissions -or (!$DelegatedPermissions -and !$ApplicationPermissions)) {
        # Iterate over all ServicePrincipal objects and get app permissions
        Write-Verbose "Retrieving AppRoleAssignments..."
        # clone to avoid "An error occurred while enumerating through a collection: Collection was modified; enumeration operation may not execute.."
        if ($objectId) {
            $spObjectId = $objectId
        } else {
            $spObjectId = $script:ObjectByObjectClassId['ServicePrincipal'].GetEnumerator() | % { $_.Value.ObjectId }
        }
        $spObjectId | ForEach-Object { $i = 0 } {
            Write-Progress "Processing $_ service principal"
            if ($ShowProgress) {
                Write-Progress -Activity "Retrieving application permissions..." `
                    -Status ("Checked {0}/{1} apps" -f $i++, $servicePrincipalCount) `
                    -PercentComplete (($i / $servicePrincipalCount) * 100)
            }

            if ($sessionInfo.Account.Type -eq 'user') {
                $serviceAppRoleAssignedTo = Get-AzureADServiceAppRoleAssignedTo -ObjectId $_ -All:$true
            } else {
                # running under service principal
                #FIXME this is some kind of bug, so probably will be fixed in the future
                # there is super weird bug when under service principal Get-AzureADServiceAppRoleAssignedTo behaves like Get-AzureADServiceAppRoleAssignment and vice versa (https://github.com/Azure/azure-docs-powershell-azuread/issues/766)!!!
                $serviceAppRoleAssignedTo = Get-AzureADServiceAppRoleAssignment -ObjectId $_ -All:$true
            }

            $serviceAppRoleAssignedTo | Where-Object { $_.PrincipalType -eq "ServicePrincipal" } | ForEach-Object {
                $assignment = $_

                $resource = GetObjectByObjectId -ObjectId $assignment.ResourceId
                $appRole = $resource.AppRoles | Where-Object { $_.Id -eq $assignment.Id }

                $grantDetails = [ordered]@{
                    "PermissionType"        = "Application"
                    "ClientObjectId"        = $assignment.PrincipalId
                    "ResourceObjectId"      = $assignment.ResourceId
                    "Permission"            = $appRole.Value
                    # "PermissionId"          = $assignment.appRoleId
                    "PermissionDisplayName" = $appRole.DisplayName
                    "PermissionDescription" = $appRole.Description
                }

                # Add properties for client and resource service principals
                if ($ServicePrincipalProperties.Count -gt 0) {

                    $client = GetObjectByObjectId -ObjectId $assignment.PrincipalId

                    $insertAtClient = 2
                    $insertAtResource = 3
                    foreach ($propertyName in $ServicePrincipalProperties) {
                        $grantDetails.Insert($insertAtClient++, "Client$propertyName", $client.$propertyName)
                        $insertAtResource++
                        $grantDetails.Insert($insertAtResource, "Resource$propertyName", $resource.$propertyName)
                        $insertAtResource ++
                    }
                }

                New-Object PSObject -Property $grantDetails
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

function New-AzureADMSIPConditionalAccessPolicy {
    <#
    .SYNOPSIS
    Function for creating new Azure Conditional Policy where access for given users/group/roles will be allowed only from given IP range(s) (Named Location(s)).

    .DESCRIPTION
    Function for creating new Azure Conditional Policy where access for given users/group/roles will be allowed only from given IP range(s) (Named Location(s)).

    .PARAMETER ruleName
    Name of new Conditional Access policy.
    Prefix '_' will be automatically added.
    Same name will be used for new Named Location if needed.

    .PARAMETER includeUsers
    Azure GUID of the user(s) to include in this policy.

    .PARAMETER excludeUsers
    Azure GUID of the user(s) to exclude from this policy.

    .PARAMETER includeGroups
    Azure GUID of the group(s) to include in this policy.

    .PARAMETER excludeGroups
    Azure GUID of the group(s) to exclude from this policy.

    .PARAMETER includeRoles
    Azure GUID of the role(s) to include in this policy.

    .PARAMETER excludeRoles
    Azure GUID of the role(s) to exclude from this policy.

    .PARAMETER ipRange
    List of IP ranges in CIDR notation (for example 1.1.1.1/32).
    New Named Location will be created and used.

    .PARAMETER ipRangeIsTrusted
    Switch for setting defined ipRange(s) as trusted.

    .PARAMETER namedLocation
    Name or ID of the existing Named Location that should be used.
    Can be used instead of ipRange parameter.

    .PARAMETER justReport
    Switch for using 'enabledForReportingButNotEnforced' instead of forcing application of the new policy.
    Therefore violations against the policy will be audited instead of denied.

    .PARAMETER force
    Switch for omitting warning in case justReport parameter wasn't specified.

    .EXAMPLE
    New-AzureADMSIPConditionalAccessPolicy -ruleName otestik -includeUsers 'e5834928-0f19-492d-8a69-3fbc98fd84eb' -ipRange 192.168.1.1/32

    New Named Location named _otestik will be created with IP range 192.168.1.1/32.
    New Conditional Policy named _otestik in forced mode will be created with these conditions:
     - user condition: user with ID 'e5834928-0f19-492d-8a69-3fbc98fd84eb'
     - location condition: created Named Location

    .EXAMPLE
    New-AzureADMSIPConditionalAccessPolicy -justReport -ruleName otestik -includeUsers 'e5834928-0f19-492d-8a69-3fbc98fd84eb', 'a3c58ecb-924c-4ae9-b90c-a5a423f8bd5d' -namedLocation HQ_Brno

    New Conditional Policy named _otestik in audit mode will be created with these conditions:
     - user condition: users with ID 'e5834928-0f19-492d-8a69-3fbc98fd84eb', 'a3c58ecb-924c-4ae9-b90c-a5a423f8bd5d'
     - location condition: existing Named Location 'HQ_Brno'

    .NOTES
    https://github.com/Azure-Samples/azure-ad-conditional-access-apis/tree/main/01-configure/powershell

    pokud bych chtel nastavovat 'workload identities' (ale vyzaduji P2 licenci!) tak zrejme pres JSON protoze $conditions to neukazuje https://github.com/MicrosoftDocs/azure-docs/blob/master/articles/active-directory/conditional-access/workload-identity.md viz https://github.com/Azure-Samples/azure-ad-conditional-access-apis/tree/main/01-configure/graphapi
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ruleName,

        [guid[]] $includeUsers,

        [guid[]] $excludeUsers,

        [guid[]] $includeGroups,

        [guid[]] $excludeGroups,

        [guid[]] $includeRoles,

        [guid[]] $excludeRoles,

        [ValidateScript( {
                if ($_ -match "/") {
                    $true
                } elseif ($_ -match '^[0-9a-d:.]+/\d+$') {
                    $true
                } else {
                    throw "IpRange $_ is not in correct form. It has to be in CIDR format (for example 1.2.3.4/32)"
                }
            })]
        [string[]] $ipRange,

        [switch] $ipRangeIsTrusted,

        [string] $namedLocation,

        [switch] $justReport,

        [switch] $force
    )

    $ErrorActionPreference = 'Stop'

    # required for creation of [Microsoft.Open.MSGraph.Model]
    Import-Module AzureADPreview

    #region validations
    if (!$ipRange -and !$namedLocation) {
        throw "You have to specify ipRange or namedLocation parameter."
    }
    if ($ipRange -and $namedLocation) {
        throw "You have to specify ipRange or namedLocation parameter. Not both!"
    }

    $ipRange | ? { $_ } | % {
        $ip = $_.Split("/")[0]
        $mask = $_.Split("/")[-1]

        if ($ip -ne [IPAddress]$ip) {
            throw "IP $ip isn't correct IP"
        }

        if ($mask -lt 24 -or $mask -gt 32) {
            throw "Mask ($mask) for IP $ip is too big or too small"
        }
    }

    if (!$includeUsers -and !$includeGroups -and !$includeRoles) {
        throw "You have to enter some user, group or role to apply this conditional rule for"
    }

    if (!$justReport -and !$force) {
        Write-Warning "You are going to create new Conditional Policy that will restrict access of selected users/groups/roles to all applications just from selected IPs/location."
        $choice = ""
        while ($choice -notmatch "^[Y|N]$") {
            $choice = Read-Host "Continue? (Y|N)"
        }
        if ($choice -eq "N") {
            return
        }
    }
    #endregion validations

    Connect-AzureAD2

    #region helper functions
    function _getObject {
        param ($id, $type)

        try {
            if (Get-AzureADObjectByObjectId -ObjectIds $id -ErrorAction Stop | ? ObjectType -EQ $type) {
                # ok
            } else {
                throw "'$id' Object Id doesn't exist in Azure"
            }
        } catch {
            throw "'$id' isn't correct Azure Object Id."
        }
    }

    #region named location
    #region validations
    if (Get-AzureADMSNamedLocationPolicy | ? DisplayName -EQ "_$ruleName") {
        throw "Named location with name '_$ruleName' already exists! Choose a different name."
    }
    if (Get-AzureADMSConditionalAccessPolicy | ? DisplayName -EQ "_$ruleName") {
        throw "Conditional policy with name '_$ruleName' already exists! Choose a different name."
    }
    if ($includeUsers -or $excludeUsers) {
        $includeUsers, $excludeUsers | ? { $_ } | % {
            _getObject -id $_ -type 'User'
        }
    }
    if ($includeGroups -or $excludeGroups) {
        $includeGroups, $excludeGroups | ? { $_ } | % {
            _getObject -id $_ -type 'Group'
        }
    }
    if ($includeRoles -or $excludeRoles) {
        $includeRoles, $excludeRoles | ? { $_ } | % {
            _getObject -id $_ -type 'Role'
        }
    }
    #endregion validations

    if ($namedLocation) {
        # use existing named location
        $namedLocationObj = Get-AzureADMSNamedLocationPolicy | ? { $_.id -eq $namedLocation -or $_.DisplayName -eq $namedLocation }
        #region validations
        if ($namedLocationObj.count -gt 1) {
            throw "There are multiple matching Named Locations ($($namedLocationObj.count)). Use ID instead."
        }
        if (!$namedLocationObj) {
            throw "Unable to find named location with name/id $namedLocation"
        }
        #endregion validations
    } else {
        # create new named location
        "Creating Named location '_$ruleName'"
        if ($ipRangeIsTrusted) {
            $namedLocationObj = New-AzureADMSNamedLocationPolicy -DisplayName "_$ruleName" -OdataType '#microsoft.graph.ipNamedLocation' -IpRanges $ipRange -IsTrusted:$true
        } else {
            $namedLocationObj = New-AzureADMSNamedLocationPolicy -DisplayName "_$ruleName" -OdataType '#microsoft.graph.ipNamedLocation' -IpRanges $ipRange -IsTrusted:$false
        }
    }
    #endregion named location

    #region conditional policy
    "Creating Conditional Rule '_$ruleName'"

    #region define conditions
    $conditions = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessConditionSet
    $conditions.ClientAppTypes = 'All'

    # conditions apps settings
    $conditions.Applications = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessApplicationCondition
    $conditions.Applications.IncludeApplications = "All"

    # conditions users settings
    $conditions.Users = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessUserCondition
    if ($includeUsers) {
        $conditions.Users.includeUsers = $includeUsers
    }
    if ($excludeUsers) {
        $conditions.Users.excludeUsers = $excludeUsers
    }
    if ($includeGroups) {
        $conditions.Users.includeGroups = $includeGroups
    }
    if ($excludeGroups) {
        $conditions.Users.excludeGroups = $excludeGroups
    }
    if ($includeRoles) {
        $conditions.Users.includeRoles = $includeRoles
    }
    if ($excludeRoles) {
        $conditions.Users.excludeRoles = $excludeRoles
    }

    # conditions location settings
    $conditions.Locations = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessLocationCondition
    Write-Verbose "Using named location $($namedLocationObj.id)"
    $conditions.Locations.IncludeLocations = "All"
    $conditions.Locations.ExcludeLocations = $namedLocationObj.id
    #endregion define conditions

    #region define controls
    $controls = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessGrantControls
    $controls._Operator = "OR"
    $controls.BuiltInControls = "Block"
    #endregion define controls

    if ($justReport) {
        $state = "enabledForReportingButNotEnforced"
    } else {
        $state = "enabled"
    }

    $null = New-AzureADMSConditionalAccessPolicy -DisplayName "_$ruleName" -State $state -Conditions $conditions -GrantControls $controls
    #endregion conditional policy
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

function Remove-AzureADAccountOccurrence {
    <#
    .SYNOPSIS
    Function for removal of selected AAD account occurrences in various parts of AAD.

    .DESCRIPTION
    Function for removal of selected AAD account occurrences in various parts of AAD.

    .PARAMETER inputObject
    PSCustomObject that is outputted by Get-AzureADAccountOccurrence function.
    Contains information about account and its occurrences i.e. is used in this function as information about what to remove and from where.

    Object (as a output of Get-AzureADAccountOccurrence) should have these properties:
        UPN
        DisplayName
        ObjectType
        ObjectId
        IAM
        MemberOfDirectoryRole
        MemberOfGroup
        PermissionConsent
        Owner
        SharepointSiteOwner
        AppUsersAndGroupsRoleAssignment

    .PARAMETER replaceByUser
    (optional) ObjectId or UPN of the AAD user that will replace processed user as a new owner/manager.
    But if there are other owners, the one being removed won't be replaced, just deleted!

    Cannot be used with replaceByManager.

    .PARAMETER replaceByManager
    Switch for using user's manager as a new owner/manager.
    Applies ONLY for processed USERS (because only users have managers) and not other object types!

    If there are other owners, the one being removed won't be replaced, just deleted!

    Cannot be used with replaceByUser.

    .PARAMETER whatIf
    Switch for omitting any changes, just output what would be done.

    .PARAMETER removeRegisteredDevice
    Switch for removal of registered devices. Otherwise registered devices stays intact.

    This doesn't apply to joined device.

    .PARAMETER informNewManOwn
    Switch for sending email notification to new owners/managers about what and why was transferred to them.

    .EXAMPLE
    Get-AzureADAccountOccurrence -userPrincipalName pavel@contoso.com | Remove-AzureADAccountOccurrence -whatIf

    Get all occurrences of specified user and just output what would be done with them.

    .EXAMPLE
    Get-AzureADAccountOccurrence -userPrincipalName pavel@contoso.com | Remove-AzureADAccountOccurrence

    Get all occurrences of specified user and remove them.
    In case user has registered some devices, they stay intact.

    .EXAMPLE
    Get-AzureADAccountOccurrence -userPrincipalName pavel@contoso.com | Remove-AzureADAccountOccurrence -removeRegisteredDevice

    Get all occurrences of specified user and remove them.
    In case user has registered some devices, they will be deleted.

    .EXAMPLE
    Get-AzureADAccountOccurrence -userPrincipalName pavel@contoso.com | Remove-AzureADAccountOccurrence -replaceByUser 1234-1234-1234-1234

    Get all occurrences of specified user and remove them.
    In case user is owner or manager on some object(s) he will be replaced there by specified user (for ownerships this apply only if removed user is last owner).
    In case user has registered some devices, they stay intact.

    .EXAMPLE
    Get-AzureADAccountOccurrence -userPrincipalName pavel@contoso.com | Remove-AzureADAccountOccurrence -replaceByManager

    Get all occurrences of specified user and remove them.
    In case user is owner or manager on some object(s) he will be replaced there by his manager (for ownerships this apply only if removed user is last owner).
    In case user has registered some devices, they stay intact.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject] $inputObject,

        [string] $replaceByUser,

        [switch] $replaceByManager,

        [switch] $whatIf,

        [switch] $removeRegisteredDevice,

        [switch] $informNewManOwn
    )

    begin {
        if ($replaceByUser -and $replaceByManager) {
            throw "replaceByUser and replaceByManager cannot be used together. Choose one of them."
        }

        if ($informNewManOwn -and (!$replaceByUser -and !$replaceByManager)) {
            Write-Warning "Parameter 'informNewManOwn' will be ignored because no replacements will be made."
            $informNewManOwn = $false
        }

        #region connect
        # connect to AzureAD
        Write-Verbose "Connecting to AzureAD"
        $null = Connect-AzureAD2 -asYourself -ea Stop

        Write-Verbose "Connecting to AzAccount"
        $null = Connect-AzAccount2 -ea Stop

        # connect sharepoint online
        if ($inputObject.SharepointSiteOwner) {
            Write-Verbose "Connecting to Sharepoint"
            Connect-PnPOnline2 -asMFAUser -ea Stop
        }
        #endregion connect

        if ($informNewManOwn) {
            $newManOwnReport = @()
        }
    }

    process {
        # check replacement user account
        if ($replaceByUser) {
            $replacementAADAccountObj = Get-AzureADUser -ObjectId $replaceByUser
            if (!$replacementAADAccountObj) {
                throw "Replacement account $replaceByUser was not found in AAD"
            } else {
                Write-Warning "'$($replacementAADAccountObj.DisplayName)' will be new manager/owner instead of account that is being removed"
            }
        }

        $inputObject | % {
            <#
            Object (as a output of Get-AzureADAccountOccurrence) should have these properties:
                UPN
                DisplayName
                ObjectType
                ObjectId
                IAM
                MemberOfDirectoryRole
                MemberOfGroup
                PermissionConsent
                Owner
                SharepointSiteOwner
                AppUsersAndGroupsRoleAssignment
            #>

            $accountId = $_.ObjectId
            $accountDisplayName = $_.DisplayName

            "Processing cleanup on account '$accountDisplayName' ($accountId)"

            $AADAccountObj = Get-AzureADObjectByObjectId -ObjectId $accountId
            if (!$AADAccountObj) {
                Write-Error "Account $accountId was not found in AAD"
            }

            if ($replaceByManager) {
                if ($_.ObjectType -eq 'user') {
                    $replacementAADAccountObj = Get-AzureADUserManager -ObjectId $accountId
                    if (!$replacementAADAccountObj) {
                        throw "Account '$accountDisplayName' doesn't have a manager. Specify replacement account via 'replaceByUser' parameter?"
                    } else {
                        Write-Warning "User's manager '$($replacementAADAccountObj.DisplayName)' will be new manager/owner instead of account that is being removed"
                    }
                } else {
                    Write-Warning "Account $accountId isn't a user ($($_.ObjectType)). Parameter 'replaceByManager' will be ignored."
                }
            }

            # prepare base object for storing data for later email notification
            if ($informNewManOwn -and $replacementAADAccountObj) {
                $newManOwnObj = [PSCustomObject]@{
                    replacedUserObjectId = $accountId
                    replacedUserName     = $accountDisplayName
                    newUserEmail         = $replacementAADAccountObj.mail
                    newUserName          = $replacementAADAccountObj.DisplayName
                    newUserObjectId      = $replacementAADAccountObj.ObjectId
                    message              = @()
                }
            }

            #region remove AAD account occurrences

            #region IAM
            if ($_.IAM) {
                Write-Verbose "Removing IAM assignments"
                $tenantId = (Get-AzContext).tenant.id

                $_.IAM | select ObjectId, AssignmentScope, RoleDefinitionName -Unique | % {
                    # $Context = Set-AzContext -TenantId $tenantId -SubscriptionId $_.SubscriptionId -Force
                    "Removing IAM role '$($_.RoleDefinitionName)' at scope '$($_.AssignmentScope)'"
                    if (!$whatIf) {
                        Remove-AzRoleAssignment -ObjectId $_.ObjectId -Scope $_.AssignmentScope -RoleDefinitionName $_.RoleDefinitionName
                    }
                }
            }
            #endregion IAM

            #region group membership
            if ($_.MemberOfGroup) {
                $_.MemberOfGroup | % {
                    "Removing from group '$($_.displayName)' ($($_.id))"
                    if (!$whatIf) {
                        Remove-AzureADGroupMember -ObjectId $_.id -MemberId $accountId
                    }
                }
            }
            #endregion group membership

            #region membership directory role
            if ($_.MemberOfDirectoryRole) {
                $_.MemberOfDirectoryRole | % {
                    "Removing from directory role '$($_.displayName)' ($($_.id))"
                    if (!$whatIf) {
                        Remove-AzureADDirectoryRoleMember -ObjectId $_.id -MemberId $accountId
                    }
                }
            }
            #endregion membership directory role

            #region user perm consents
            if ($_.PermissionConsent) {
                $_.PermissionConsent | % {
                    "Removing user consent from app '$($_.AppName)', permission '$($_.scope)' to '$($_.ResourceDisplayName)'"
                    if (!$whatIf) {
                        Remove-AzureADOAuth2PermissionGrant -ObjectId $_.ObjectId
                    }
                }
            }
            #endregion user perm consents

            #region manager
            if ($_.Manager) {
                $_.Manager | % {
                    $manager = $_
                    $managerObjectType = $_.ObjectType
                    $managerDisplayName = $_.DisplayName
                    $managerObjectId = $_.ObjectId

                    switch ($manager.ObjectType) {
                        User {
                            "Removing as a manager of the $managerObjectType '$managerDisplayName' ($managerObjectId)"
                            if (!$whatIf) {
                                Remove-AzureADUserManager -ObjectId $managerObjectId
                            }
                            if ($replacementAADAccountObj) {
                                "Adding '$($replacementAADAccountObj.DisplayName)' as a manager of the $managerObjectType '$managerDisplayName' ($managerObjectId)"
                                if (!$whatIf) {
                                    Set-AzureADUserManager -ObjectId $managerObjectId -RefObjectId $replacementAADAccountObj.ObjectId

                                    if ($informNewManOwn) {
                                        $newManOwnObj.message += @("new manager of the $managerObjectType '$managerDisplayName' ($managerObjectId)")
                                    }
                                }
                            }
                        }

                        Contact {
                            "Removing as a manager of the $managerObjectType '$managerDisplayName' ($managerObjectId)"
                            if (!$whatIf) {
                                Remove-AzureADContactManager -ObjectId $managerObjectId
                            }
                            if ($replacementAADAccountObj) {
                                Write-Warning "Add '$($replacementAADAccountObj.DisplayName)' as a manager of the $managerObjectType '$managerDisplayName' ($managerObjectId) manually!"
                            }
                        }

                        default {
                            Write-Error "Not defined action for object type $managerObjectType. User won't be removed as a manager of this object."
                        }
                    }
                }
            }
            #endregion manager

            #region ownership
            # application, group, .. owner
            if ($_.Owner) {
                $_.Owner | % {
                    $owner = $_
                    $ownerDisplayName = $_.DisplayName
                    $ownerObjectId = $_.ObjectId

                    switch ($owner.ObjectType) {
                        Application {
                            # app registration
                            "Removing owner from app registration '$ownerDisplayName'"
                            if (!$whatIf) {
                                Remove-AzureADApplicationOwner -ObjectId $ownerObjectId -OwnerId $accountId
                            }

                            if ($replacementAADAccountObj) {
                                $recentObjOwner = Get-AzureADApplicationOwner -ObjectId $ownerObjectId -All:$true | ? ObjectId -NE $accountId
                                if (!$recentObjOwner) {
                                    "Adding '$($replacementAADAccountObj.DisplayName)' as owner of the '$ownerDisplayName' application"
                                    if (!$whatIf) {
                                        Add-AzureADApplicationOwner -ObjectId $ownerObjectId -RefObjectId $replacementAADAccountObj.ObjectId

                                        if ($informNewManOwn) {
                                            $newManOwnObj.message += @("new owner of the '$ownerDisplayName' application ($ownerObjectId)")
                                        }
                                    }
                                } else {
                                    Write-Warning "App registration has some owners left. '$($replacementAADAccountObj.DisplayName)' won't be added."
                                }
                            }
                        }

                        ServicePrincipal {
                            # enterprise apps owner
                            "Removing owner from service principal '$ownerDisplayName'"
                            if (!$whatIf) {
                                Remove-AzureADServicePrincipalOwner -ObjectId $ownerObjectId -OwnerId $accountId
                            }

                            if ($replacementAADAccountObj) {
                                $recentObjOwner = Get-AzureADServicePrincipalOwner -ObjectId $ownerObjectId -All:$true | ? ObjectId -NE $accountId
                                if (!$recentObjOwner) {
                                    "Adding '$($replacementAADAccountObj.DisplayName)' as owner of the '$ownerDisplayName' service principal"
                                    if (!$whatIf) {
                                        Add-AzureADServicePrincipalOwner -ObjectId $ownerObjectId -RefObjectId $replacementAADAccountObj.ObjectId

                                        if ($informNewManOwn) {
                                            $newManOwnObj.message += @("new owner of the '$ownerDisplayName' service principal ($ownerObjectId)")
                                        }
                                    }
                                } else {
                                    Write-Warning "Service principal has some owners left. '$($replacementAADAccountObj.DisplayName)' won't be added."
                                }
                            }
                        }

                        Group {
                            # adding new owner before removing the old one because group won't let you remove last owner
                            if ($replacementAADAccountObj) {
                                $recentObjOwner = Get-AzureADGroupOwner -ObjectId $ownerObjectId -All:$true | ? ObjectId -NE $accountId
                                if (!$recentObjOwner) {
                                    "Adding '$($replacementAADAccountObj.DisplayName)' as owner of the '$ownerDisplayName' group"
                                    if (!$whatIf) {
                                        Add-AzureADGroupOwner -ObjectId $ownerObjectId -RefObjectId $replacementAADAccountObj.ObjectId

                                        if ($informNewManOwn) {
                                            $newManOwnObj.message += @("new owner of the '$ownerDisplayName' group ($ownerObjectId)")
                                        }
                                    }
                                } else {
                                    Write-Warning "Group has some owners left. '$($replacementAADAccountObj.DisplayName)' won't be added."
                                }
                            }

                            "Removing owner from group '$ownerDisplayName'"
                            if (!$whatIf) {
                                Remove-AzureADGroupOwner -ObjectId $ownerObjectId -OwnerId $accountId
                            }
                        }

                        Device {
                            if ($owner.DeviceTrustType -eq 'Workplace') {
                                # registered device
                                if ($removeRegisteredDevice) {
                                    "Removing registered device '$ownerDisplayName' ($ownerObjectId)"
                                    if (!$whatIf) {
                                        Remove-AzureADDevice -ObjectId $ownerObjectId
                                    }
                                } else {
                                    Write-Warning "Registered device '$ownerDisplayName' won't be deleted nor owner of this device will be removed"
                                }
                            } else {
                                # joined device
                                "Removing owner from device '$ownerDisplayName' ($ownerObjectId)"
                                if (!$whatIf) {
                                    Remove-AzureADDeviceRegisteredOwner -ObjectId $ownerObjectId -OwnerId $accountId
                                }
                            }

                            if ($replacementAADAccountObj) {
                                Write-Verbose "Device owner won't be replaced by '$($replacementAADAccountObj.DisplayName)' because I don't want to"
                            }
                        }

                        default {
                            Write-Error "Not defined action for object type $($owner.ObjectType). User won't be removed as a owner of this object."
                        }
                    }
                }
            }

            # sharepoint sites owner
            if ($_.SharepointSiteOwner) {
                $_.SharepointSiteOwner | % {
                    if ($_.template -like 'GROUP*') {
                        # it is sharepoint site based on group (owners are group members)
                        "Removing from group '$($_.Title)' that has owner rights on Sharepoint site '$($_.Site)'"
                        if (!$whatIf) {
                            Remove-PnPMicrosoft365GroupOwner -Identity $_.GroupId -Users $userPrincipalName
                        }

                        if ($replacementAADAccountObj) {
                            $recentObjOwner = Get-PnPMicrosoft365GroupOwner -Identity $_.GroupId -All:$true | ? Id -NE $accountId
                            if (!$recentObjOwner) {
                                "Adding '$($replacementAADAccountObj.DisplayName)' as owner of the '$($_.Title)' group"
                                if (!$whatIf) {
                                    Add-PnPMicrosoft365GroupOwner -Identity $_.GroupId -Users $replacementAADAccountObj.UserPrincipalName

                                    if ($informNewManOwn) {
                                        $newManOwnObj.message += @("new owner of the '$($_.Title)' group ($($_.GroupId))")
                                    }
                                }
                            } else {
                                Write-Warning "Sharepoint site has some owners left. '$($replacementAADAccountObj.DisplayName)' won't be added."
                            }
                        }
                    } else {
                        # it is common sharepoint site
                        Write-Warning "Remove owner from Sharepoint site '$($_.url)' manually"
                        # "Removing from sharepoint site '$($_.url)'"
                        # https://www.sharepointdiary.com/2018/02/change-site-owner-in-sharepoint-online-using-powershell.html
                        # https://www.sharepointdiary.com/2020/05/sharepoint-online-grant-site-owner-permission-to-user-with-powershell.html

                        if ($replacementAADAccountObj) {
                            Write-Warning "Add '$($replacementAADAccountObj.UserPrincipalName)' as new owner at Sharepoint site '$($_.url)' manually"
                            # "Adding '$($replacementAADAccountObj.DisplayName)' as owner of the '$($_.url)' sharepoint site"
                            # Set-PnPSite -Identity $_.url -Owners $replacementAADAccountObj.UserPrincipalName # prida jen jako admina..ne primary admina (ownera)
                            # Set-PnPTenantSite -Identity $_.url -Owners $replacementAADAccountObj.UserPrincipalName # prida jen jako admina..ne primary admina (ownera)
                        }
                    }
                }
            }
            #endregion ownership

            #region app Users and groups role assignments
            if ($_.AppUsersAndGroupsRoleAssignment) {
                $_.AppUsersAndGroupsRoleAssignment | % {
                    "Removing $($_.PrincipalType) from app's '$($_.ResourceDisplayName)' role '$($_.AppRoleDisplayName)'"
                    if (!$whatIf) {
                        Remove-AzureADServiceAppRoleAssignment -ObjectId $_.ResourceId -AppRoleAssignmentId $_.ObjectId
                    }
                }
            }
            #endregion app Users and groups role assignments

            #region devops
            if ($_.DevOpsOrganizationOwner) {
                $_.DevOpsOrganizationOwner | % {
                    Write-Warning "Remove owner of DevOps organization '$($_.OrganizationName))' manually"
                    if ($replacementAADAccountObj) {
                        Write-Warning "Add '$($replacementAADAccountObj.UserPrincipalName)' as new owner of the DevOps organization '$($_.OrganizationName))' manually"
                    }
                }
            }

            if ($_.DevOpsMemberOf) {
                $header = New-AzureDevOpsAuthHeader

                $_.DevOpsMemberOf | % {
                    $accountDescriptor = $_.Descriptor
                    $organizationName = $_.OrganizationName
                    $_.memberOf | % {
                        $groupDescriptor = $_.descriptor
                        "Removing from DevOps organization's '$organizationName' group '$($_.principalName)'"

                        if (!$whatIf) {
                            $result = Invoke-WebRequest -Uri "https://vssps.dev.azure.com/$organizationName/_apis/graph/memberships/$accountDescriptor/$($groupDescriptor)?api-version=7.1-preview.1" -Method delete -ContentType "application/json" -Headers $header
                            if ($result.StatusCode -ne 200) {
                                Write-Error "Removal of account '$accountDisplayName' in DevOps organization '$organizationName' from group '$($_.displayName)' wasn't successful. Do it manually."
                            }
                        }
                    }
                }
            }
            #endregion devops

            #endregion remove AAD account occurrences

            # save object with made changes for later email notification
            if ($informNewManOwn -and $replacementAADAccountObj) {
                $newManOwnReport += $newManOwnObj
            }
        }
    }

    end {
        if ($informNewManOwn -and $newManOwnReport.count) {
            $newManOwnReport | % {
                if ($_.message) {
                    # there were some changes in ownership
                    if ($_.newUserEmail) {
                        # new owner/manager has email address defined
                        $newUserRole = "as chosen successor"
                        if ($replaceByManager -or ((Get-AzureADUserManager -ObjectId $_.replacedUserObjectId).ObjectId -eq $_.newUserObjectId)) {
                            $newUserRole = "as his/her manager"
                        }

                        $body = "Hi,`nemployee '$($_.replacedUserName)' left the company and you $newUserRole are now:`n`n$(($_.message | % {" - $_"}) -join "`n")`n`nThese changes are related to Azure environment.`n`n`Sincerely your IT"

                        Write-Warning "Sending email to: $($_.newUserEmail) body:`n`n$body"
                        Send-Email -to $_.newUserEmail -subject "Notification of new Azure assets responsibility" -body $body
                    } else {
                        Write-Warning "Cannot inform new owner/manager '$($_.newUserName)' about transfer of Azure asset from '$($_.replacedUserName)'. Email address is missing.`n`n$($_.message -join "`n")"
                    }
                } else {
                    Write-Verbose "No asset was transferred to the '$($_.newUserName)' from the '$($_.replacedUserName)'"
                }
            }
        }
    }
}

#Requires -Modules Microsoft.Graph.Identity.SignIns,AzureAD

function Remove-AzureADAppUserConsent {
    <#
    .SYNOPSIS
    Function for removing permission consents.

    .DESCRIPTION
    Function for removing permission consents.

    For selected OAuth2PermissionGrantId(s) or OGV with filtered grants will be shown (based on servicePrincipalObjectId, principalObjectId, resourceObjectId you specify).

    .PARAMETER OAuth2PermissionGrantId
    ID of the OAuth permission grant(s).

    .PARAMETER servicePrincipalObjectId
    ObjectId of the enterprise app for which was the consent given.

    .PARAMETER principalObjectId
    ObjectId of the user which have given the consent.

    .PARAMETER resourceObjectId
    ObjectId of the resource to which the consent have given permission to.

    .EXAMPLE
    Remove-AzureADAppUserConsent -OAuth2PermissionGrantId L5awNI6RwE-QWiIIWcNMqYIrr-lfQ2BBnaYK1kev_X5Q2a7DBw0rSKTgiBsrZi4z

    Consent with ID L5awNI6RwE-QWiIIWcNMqYIrr-lfQ2BBnaYK1kev_X5Q2a7DBw0rSKTgiBsrZi4z will be deleted.

    .EXAMPLE
    Remove-AzureADAppUserConsent

    OGV with all grants will be shown and just selected consent(s) will be deleted.

    .EXAMPLE
    Remove-AzureADAppUserConsent -principalObjectId 1234 -servicePrincipalObjectId 5678

    OGV with consent(s) related to user with ID 1234 and enterprise application with ID 5678 will be shown and just selected consent(s) will be deleted.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "id")]
        [string[]] $OAuth2PermissionGrantId,

        [Parameter(ParameterSetName = "filter")]
        [string] $servicePrincipalObjectId,

        [Parameter(ParameterSetName = "filter")]
        [string] $principalObjectId,

        [Parameter(ParameterSetName = "filter")]
        [string] $resourceObjectId
    )

    Connect-AzureAD2
    Connect-MSGraph

    $objectByObjectId = @{}
    function GetObjectByObjectId ($objectId) {
        if (!$objectByObjectId.ContainsKey($objectId)) {
            Write-Verbose ("Querying Azure AD for object '{0}'" -f $objectId)
            try {
                $object = Get-AzureADObjectByObjectId -ObjectId $objectId -ea stop
                $objectByObjectId.$objectId = $object
                return $object
            } catch {
                Write-Verbose "Object not found."
            }
        }
        return $objectByObjectId.$objectId
    }

    if ($OAuth2PermissionGrantId) {
        $OAuth2PermissionGrantId | % {
            Remove-MgOauth2PermissionGrant -OAuth2PermissionGrantId $_ -Confirm:$true
        }
    } else {
        $filter = ""

        if ($servicePrincipalObjectId) {
            if ($filter) { $filter = $filter + " and " }
            $filter = $filter + "clientId eq '$servicePrincipalObjectId'"
        }
        if ($principalObjectId) {
            if ($filter) { $filter = $filter + " and " }
            $filter = $filter + "principalId eq '$principalObjectId'"
        }
        if ($resourceObjectId) {
            if ($filter) { $filter = $filter + " and " }
            $filter = $filter + "resourceId eq '$resourceObjectId'"
        }

        $param = @{}
        if ($filter) { $param.filter = $filter }

        Get-MgOauth2PermissionGrant @param -Property ClientId, ConsentType, PrincipalId, ResourceId, Scope, Id | select @{n = 'App'; e = { (GetObjectByObjectId $_.ClientId).DisplayName } }, ConsentType, @{n = 'Principal'; e = { (GetObjectByObjectId $_.PrincipalId).DisplayName } }, @{n = 'Resource'; e = { (GetObjectByObjectId $_.ResourceId).DisplayName } }, Scope, Id | Out-GridView -OutputMode Multiple | % {
            Remove-MgOauth2PermissionGrant -OAuth2PermissionGrantId $_.Id -Confirm:$true
        }
    }
}

function Start-AzureADSync {
    <#
        .SYNOPSIS
        Invoke Azure AD sync cycle command (Start-ADSyncSyncCycle) on the server where 'Azure AD Connect' is installed.

        .DESCRIPTION
        Invoke Azure AD sync cycle command (Start-ADSyncSyncCycle) on the server where 'Azure AD Connect' is installed.

        .PARAMETER Type
        Type of sync.

        Initial (full) or just delta.

        Delta is default.

        .PARAMETER ADSynchServer
        Name of the server where 'Azure AD Connect' is installed

        .EXAMPLE
        Start-AzureADSync -ADSynchServer ADSYNCSERVER
        Invokes synchronization between on-premises AD and AzureAD on server ADSYNCSERVER by running command Start-ADSyncSyncCycle there.
    #>

    [Alias("Sync-ADtoAzure")]
    [cmdletbinding()]
    param (
        [ValidateSet('delta', 'initial')]
        [string] $type = 'delta',

        [Parameter(Mandatory = $true)]
        [string] $ADSynchServer
    )

    $ErrState = $false
    do {
        try {
            Invoke-Command -ScriptBlock { Start-ADSyncSyncCycle -PolicyType $using:type } -ComputerName $ADSynchServer -ErrorAction Stop | Out-Null
            $ErrState = $false
        } catch {
            $ErrState = $true
            Write-Warning "Start-AzureADSync: Error in Sync:`n$_`nRetrying..."
            Start-Sleep 5
        }
    } while ($ErrState -eq $true)
}

Export-ModuleMember -function Add-AzureADAppCertificate, Add-AzureADAppUserConsent, Add-AzureADGuest, Connect-AzAccount2, Connect-AzureAD2, Connect-PnPOnline2, Disable-AzureADGuest, Get-AzureADAccountOccurrence, Get-AzureADAppConsentRequest, Get-AzureADAppRegistration, Get-AzureADAppUsersAndGroups, Get-AzureADAppVerificationStatus, Get-AzureADAssessNotificationEmail, Get-AzureADEnterpriseApplication, Get-AzureAdGroupMemberRecursive, Get-AzureADManagedIdentity, Get-AzureADResource, Get-AzureADRoleAssignments, Get-AzureADServicePrincipalOverview, Get-AzureADSPPermissions, Get-AzureDevOpsOrganizationOverview, Get-SharepointSiteOwner, Invoke-GraphAPIRequest, New-AzureADMSIPConditionalAccessPolicy, New-AzureDevOpsAuthHeader, New-GraphAPIAuthHeader, Open-AzureADAdminConsentPage, Remove-AzureADAccountOccurrence, Remove-AzureADAppUserConsent, Start-AzureADSync

Export-ModuleMember -alias Get-AzureADIAMRoleAssignments, Get-AzureADPSPermissionGrants, Get-AzureADPSPermissions, Get-AzureADRBACRoleAssignments, Get-AzureADServiceAppRoleAssignment2, Get-AzureADServicePrincipal2, Get-AzureADServicePrincipalPermissions, Get-IntuneAuthHeader, New-AzureADGuest, New-IntuneAuthHeader, Remove-AzureADGuest, Sync-ADtoAzure
