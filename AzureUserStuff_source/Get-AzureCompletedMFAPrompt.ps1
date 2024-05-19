#requires -modules Microsoft.Graph.Authentication, Microsoft.Graph.Beta.Reports, Microsoft.Graph.Beta.Identity.SignIns, Microsoft.Graph.Users
function Get-AzureCompletedMFAPrompt {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$upnList
    )

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    foreach ($upn in $upnList) {
        # filter is case sensitive in Get-MgAuditLogSignIn
        $upn = $upn.tolower()

        Write-Warning "Processing $upn"

        try {
            $userId = (Get-MgUser -UserId $upn -Property Id).Id
        } catch {
            Write-Warning "User $upn doesn't exist. Skipping"
            continue
        }

        $mfaMethod = Get-MgBetaUserAuthenticationMethod -UserId $upn | Expand-MgAdditionalProperties

        # get all successfully completed MFA prompts
        # 0 = Success
        # 50140 = "This occurred due to 'Keep me signed in' interrupt when the user was signing in."
        # TIP: guest sign-ins cannot be searched using UPN
        $successfulMFAPrompt = Get-MgBetaAuditLogSignIn -All -Filter "userId eq '$userId' and AuthenticationRequirement eq 'multiFactorAuthentication' and conditionalAccessStatus eq 'success'" -Property * | ? { $_.Status.ErrorCode -in 0, 50140 -and ($_.AuthenticationDetails.AuthenticationStepResultDetail | % { if ($_ -in 'MFA successfully completed', 'MFA completed in Azure AD', 'User approved', 'MFA required in Azure AD', 'MFA requirement satisfied by strong authentication') { $true } }) }

        if (!$successfulMFAPrompt) {
            Write-Warning "No completed MFA prompts found"
            continue
        }

        foreach ($mfaPrompt in $successfulMFAPrompt) {
            $authenticationMethod = $mfaPrompt.AuthenticationDetails | ? { $_.AuthenticationMethod -notin "Previously satisfied", "Password" -and $_.Succeeded -eq $true }
            if ($authenticationMethod) {
                $authMethod = $authenticationMethod.AuthenticationMethod
                if (!$authMethod) {
                    # sometimes AuthenticationMethod is empty, but AuthenticationStepResultDetail contains 'MFA completed in Azure AD'
                    $authMethod = $authenticationMethod.AuthenticationStepResultDetail
                }
                $authDetail = $authenticationMethod.AuthenticationMethodDetail
                if (!$authDetail -and $mfaPrompt.AuthenticationAppDeviceDetails.DeviceId) {
                    $authDetail = $mfaPrompt.AuthenticationAppDeviceDetails
                }
            } else {
                $authMethod = $mfaPrompt.MfaDetail.AuthMethod
                $authDetail = $mfaPrompt.MfaDetail.AuthDetail
            }

            [PSCustomObject]@{
                UPN                = $upn
                CreatedDateTimeUTC = $mfaPrompt.CreatedDateTime
                AuthMethod         = $authMethod
                AuthDetail         = $authDetail
                AuthDeviceId       = $mfaPrompt.AuthenticationAppDeviceDetails.DeviceId
                AuditEvent         = $mfaPrompt
            }
        }
    }
}