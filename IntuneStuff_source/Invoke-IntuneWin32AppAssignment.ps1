#requires -modules Microsoft.Graph.Devices.CorporateManagement, Microsoft.Graph.Groups
function Invoke-IntuneWin32AppAssignment {
    <#
    .SYNOPSIS
    Function for assigning Intune Win32App(s).

    .DESCRIPTION
    Function for assigning Intune Win32App(s).

    Assignment to all users / all devices / selected groups is supported.

    .PARAMETER appId
    ID of the app(s) to assign.

    If not specified, all apps will be shown using Out-GridView, so you can pick some.

    .PARAMETER intent
    Assignment type.

    Available options: 'available', 'required', 'uninstall', 'availableWithoutEnrollment'

    By default 'required'.

    .PARAMETER targetGroupId
    ID of the group(s) you want to assign the app.

    If not specified (and targetAllDevices nor targetAllDevices is used), all groups will be shown using Out-GridView, so you can pick some.

    .PARAMETER targetAllUsers
    Switch for assigning the app to 'all users' instead of specific group.

    .PARAMETER targetAllDevices
    Switch for assigning the app to 'all devices' instead of specific group.

    .PARAMETER notification
    What post-installation notification should be shown.
    Available options: 'showReboot', 'showAll'

    By default 'showReboot'.

    .EXAMPLE
    Invoke-IntuneWin32AppAssignment

    Let you pick the app you want to assign, the group(s) you want to assign an app to and do the assignment.

    .EXAMPLE
    Invoke-IntuneWin32AppAssignment -appId d3b5581f-4342-49e5-a9ae-03c04aacccc1 -targetAllDevices

    Assigns the app to all devices.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [Alias("Assign-IntuneWin32App")]
    param (
        [guid[]] $appId,

        [ValidateSet('available', 'required', 'uninstall', 'availableWithoutEnrollment')]
        [string] $intent = "required",

        [Parameter(Mandatory = $false, ParameterSetName = "Default")]
        [guid] $targetGroupId,

        [Parameter(Mandatory = $false, ParameterSetName = "AllUsers")]
        [switch] $targetAllUsers,

        [Parameter(Mandatory = $false, ParameterSetName = "AllDevices")]
        [switch] $targetAllDevices,

        [ValidateSet('showReboot', 'showAll')]
        [string] $notification = "showReboot"
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

        $appId = Get-MgDeviceAppMgtMobileApp -Filter "isof('microsoft.graph.win32LobApp')" -ExpandProperty Assignments | select DisplayName, Id, @{n = 'Assignments'; e = { _assignments $_.Assignments | Sort-Object } } | Out-GridView -PassThru -Title "Select Win32App you want to assign" | select -ExpandProperty Id
        if (!$appId) { throw "You haven't selected any app" }
    }

    if ($targetGroupId) {
        if (Get-MgGroup -GroupId $targetGroupId -ea SilentlyContinue) {
            $target = @{
                '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                'groupId'     = $targetGroupId
            }
        } else {
            throw "Group with ID $targetGroupId doesn't exist"
        }
    } elseif ($targetAllUsers) {
        $target = @{
            '@odata.type' = "#microsoft.graph.allLicensedUsersAssignmentTarget"
        }
    } elseif ($targetAllDevices) {
        $target = @{
            '@odata.type' = "#microsoft.graph.allDevicesAssignmentTarget"
        }
    } else {
        $targetGroupId = Get-MgGroup -All -Property DisplayName, Id | Out-GridView -PassThru -Title "Select group you want to assign an app to" | select -ExpandProperty Id
        if (!$targetGroupId) { throw "You haven't selected any group" }
        $target = @{
            '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
            'groupId'     = $targetGroupId
        }
    }

    $params = @{
        "@odata.type" = "#microsoft.graph.mobileAppAssignment"
        intent        = $intent
        target        = $target
        settings      = @{
            '@odata.type'                  = '#microsoft.graph.win32LobAppAssignmentSettings'
            'notifications'                = $notification
            'deliveryOptimizationPriority' = 'notConfigured'
        }
    }

    foreach ($id in $appId) {
        "Assign app $id to $($target.'@odata.type'.split('\.')[-1]) (id:$($target.groupId))"
        $null = New-MgDeviceAppManagementMobileAppAssignment -MobileAppId $id -BodyParameter $params
    }
}