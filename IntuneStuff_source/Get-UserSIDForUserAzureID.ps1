function Get-UserSIDForUserAzureID {
    <#
    .SYNOPSIS
    Function finds SID for given user Azure ID.

    .DESCRIPTION
    Function finds SID for given user Azure ID.
    Uses client's Intune log to get this information.

    .PARAMETER userId
    Azure ID to translate.

    .EXAMPLE
    Get-UserSIDForUserAzureID -userId 91b91882-f81b-4ba4-9d7d-10cd49219b79

    Translates user Azure ID 91b91882-f81b-4ba4-9d7d-10cd49219b79 into local SID.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $userId
    )

    # create global variable for cache purposes
    if (!$azureUserIdList.keys) {
        $global:azureUserIdList = @{}
    }

    if ($azureUserIdList.keys -contains $userId) {
        # return cached information
        return $azureUserIdList.$userId
    }

    $intuneLogList = Get-ChildItem -Path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs" -Filter "IntuneManagementExtension*.log" -File | sort LastWriteTime -Descending | select -ExpandProperty FullName

    if (!$intuneLogList) {
        Write-Error "Unable to find any Intune log files. Redeploy will probably not work as expected."
        return
    }

    foreach ($intuneLog in $intuneLogList) {
        # how content of the log can looks like
        # [Win32App] ..................... Processing user session 1, userId: e5834928-0f19-492d-8a69-3fbc98fd84eb, userSID: S-1-5-21-2475586523-545188003-3344463812-8050 .....................
        # [Win32App] EspPreparation starts for userId: e5834928-0f19-442d-8a69-3fbc98fd84eb userSID: S-1-5-21-2475586523-545182003-3344463812-8050

        Write-Verbose "Searching $userId in '$intuneLog'"

        $userMatch = Select-String -Path $intuneLog -Pattern "(?:\[Win32App\] \.* Processing user session \d+, userId: $userId, userSID: (S-[0-9-]+) )|(?:\[Win32App\] EspPreparation starts for userId: $userId userSID: (S-[0-9-]+))" -List
        if ($userMatch) {
            # cache the results
            if ($azureUserIdList) {
                $azureUserIdList.$userId = $userMatch.matches.groups[1].value
            }
            # return user SID
            return $userMatch.matches.groups[1].value
        }
    }

    Write-Warning "Unable to find User '$userId' in any of the Intune log files. Unable to translate this AAD ID to local SID."
    # cache the results
    $azureUserIdList.$userId = $null
}