#requires -modules Microsoft.Graph.Devices.CorporateManagement
function Remove-IntuneWin32AppAssignment {
    <#
    .SYNOPSIS
    Function for removing Win32App assignment(s).

    .DESCRIPTION
    Function for removing Win32App assignment(s).

    .PARAMETER appId
    ID of the app(s) to remove assignments from.

    If not specified, all apps with some assignment will be shown using Out-GridView, so you can pick some.

    .PARAMETER removeAllAssignments
    Switch for removing all assignments for selected app(s).

    .EXAMPLE
    Remove-IntuneWin32AppAssignment

    Let you pick the app you want to remove assignment from, the assignment(s) for removal and do the removal.

    .EXAMPLE
    Remove-IntuneWin32AppAssignment -appId d3b5581f-4342-49e5-a9ae-03c04aacccc1 -removeAllAssignments

    Removes all assignment of selected app.
    #>
    [CmdletBinding()]
    param (
        [guid[]] $appId,

        [switch] $removeAllAssignments
    )

    Connect-MgGraph -NoWelcome

    if ($appId) {
        $appId | % {
            $app = Get-MgDeviceAppMgtMobileApp -Filter "id eq '$_' and isof('microsoft.graph.win32LobApp')"
            if (!$app) {
                throw "Win32App with ID $_ doesn't exist"
            }
        }
    } else {
        function _assignments {
            param ($assignment)

            $assignment | % {
                $type = $_.Target.AdditionalProperties.'@odata.type'.split('\.')[-1]
                $groupId = $_.Target.AdditionalProperties.groupId

                if ($groupId) {
                    return $groupId
                } else {
                    return $type
                }
            }
        }

        $appId = Get-MgDeviceAppMgtMobileApp -Filter "isof('microsoft.graph.win32LobApp')" -ExpandProperty Assignments | ? Assignments | select DisplayName, Id, @{n = 'Assignments'; e = { _assignments $_.Assignments | Sort-Object } } | Out-GridView -Title "Select Win32App you want to de-assign" -PassThru | select -ExpandProperty Id
        if (!$appId) { throw "You haven't selected any app" }
    }

    foreach ($id in $appId) {
        $assignment = Get-MgDeviceAppManagementMobileAppAssignment -MobileAppId $id
        if (!$assignment) {
            return "No assignments available"
        }

        if (!$removeAllAssignments -and @($assignment).count -gt 1) {
            $assignment = $assignment | Out-GridView -PassThru -Title "Select assignment you want to remove"
        }

        $assignment | % {
            "Removing app $id assignment $($_.Target.AdditionalProperties.'@odata.type'.split('\.')[-1]) ($($_.Target.AdditionalProperties.groupId))"
            Remove-MgDeviceAppManagementMobileAppAssignment -MobileAppId $id -MobileAppAssignmentId $_.Id
        }
    }
}