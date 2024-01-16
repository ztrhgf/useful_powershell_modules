#requires -modules Microsoft.Graph.Authentication, Microsoft.Graph.Reports, Microsoft.Graph.Beta.Identity.SignIns
function Get-AzureAuthenticatorLastUsedDate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$upnList
    )

    foreach ($upn in $upnList) {
        # filter is case sensitive in Get-MgAuditLogSignIn and UPNs seems to be always in lower case
        $upn = $upn.tolower()

        Write-Warning "Processing $upn"

        $mfaMethod = Get-MgBetaUserAuthenticationMethod -UserId $upn | Expand-MgAdditionalProperties

        $mobileAuthenticatorList = $mfaMethod | ? ObjectType -EQ "microsoftAuthenticatorAuthenticationMethod"

        if (!$mobileAuthenticatorList) {
            Write-Warning "$upn doesn't have an authenticator app set"
            continue
        }

        if ($mobileAuthenticatorList.count -lt 2) {
            Write-Warning "$upn doesn't have more than one authenticator set"
            continue
        }

        $mobileAuthenticatorList = $mobileAuthenticatorList | select *, @{n = 'LastTimeUsedUTC'; e = { $null } }, @{n = 'OperatingSystem'; e = { $null } } -ExcludeProperty '@odata.type', 'ObjectType'

        # get all successfully completed MFA prompts
        # 0 = Success
        # 50140 = "This occurred due to 'Keep me signed in' interrupt when the user was signing in."
        $successfulMFAPrompt = Get-MgBetaAuditLogSignIn -all -Filter "UserPrincipalName eq '$upn' and AuthenticationRequirement eq 'multiFactorAuthentication' and conditionalAccessStatus eq 'success'" -Property * | ? { $_.Status.ErrorCode -in 0, 50140 -and ($_.AuthenticationDetails.AuthenticationStepResultDetail | % { if ($_ -in 'MFA successfully completed', 'MFA completed in Azure AD', 'User approved', 'MFA required in Azure AD', 'MFA requirement satisfied by strong authentication') { $true } }) }

        if (!$successfulMFAPrompt) {
            Write-Warning "No completed MFA prompts found (in last 30 days?)"
        } else {
            foreach ($mfaPrompt in $successfulMFAPrompt) {
                if ($mobileAuthenticatorList.count -eq ($mobileAuthenticatorList.LastTimeUsedUTC | ? { $_ }).count) {
                    # I have last used date for each registered authenticator
                    Write-Verbose "I have LastTimeUsedUTC for each authenticator app"
                    break
                }
                # "### $($mfaPrompt.AppDisplayName)"
                $mobileAuthenticatorId = $mfaPrompt.AuthenticationAppDeviceDetails.DeviceId # je ve skutecnosti ID z Get-MgUserAuthenticationMethod
                if (!$mobileAuthenticatorId) {
                    Write-Verbose "This isn't event where authenticator was used, skipping"
                    continue
                }

                $correspondingAuthenticator = $mobileAuthenticatorList | ? Id -EQ $mobileAuthenticatorId

                if (!$correspondingAuthenticator) {
                    Write-Verbose "Authenticator with ID $mobileAuthenticatorId doesn't exist anymore"
                } else {
                    if ($correspondingAuthenticator.LastTimeUsedUTC) {
                        Write-Verbose "$mobileAuthenticatorId was already processed"
                        continue
                    } else {
                        Write-Verbose "$mobileAuthenticatorId setting LastTimeUsedUTC $($mfaPrompt.CreatedDateTime) OperatingSystem $($mfaPrompt.AuthenticationAppDeviceDetails.OperatingSystem)"
                        $correspondingAuthenticator.LastTimeUsedUTC = $mfaPrompt.CreatedDateTime
                        $correspondingAuthenticator.OperatingSystem = $mfaPrompt.AuthenticationAppDeviceDetails.OperatingSystem
                    }
                }
            }
        }

        #TODO u authenticatoru bez udaju zjistit kdy se zaregistroval, mozna je novy a jeste ho nepouzil

        [PSCustomObject]@{
            UPN                 = $upn
            MobileAuthenticator = $mobileAuthenticatorList
        }
    }
}