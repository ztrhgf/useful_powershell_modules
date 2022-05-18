function Get-CMComputerComplianceStatus {
    <#
    .SYNOPSIS
    Function gets status of SCCM compliance baselines on given client.

    .DESCRIPTION
    Function gets status of SCCM compliance baselines on given client.
    Shows user and device compliances (thanks to Invoke-AsCurrentUser).

    If run locally, returns object with all user (which run this function) and device CB status.
    If run remotely, returns string with all (there logged) user and device CB status.

    .PARAMETER computerName
    Name of remote computer to connect.

    .PARAMETER onlyComputerCB
    Switch for showing just device targeted CB not user ones.
    But as advantage, object will be returned instead of string.

    .EXAMPLE
    Get-CMComputerComplianceStatus

    Returns configuration baselines status as object.
    User and device ones.

    .EXAMPLE
    Get-CMComputerComplianceStatus -computerName pc-01

    Returns configuration baselines status as string.
    User and device ones.

    .EXAMPLE
    Get-CMComputerComplianceStatus -computerName pc-01 -onlyComputerCB

    Returns configuration baselines status as object. Just device CB ones.
    #>

    [CmdletBinding()]
    param (
        [string] $computerName
        ,
        [switch] $onlyComputerCB
    )

    #region prepare param for Invoke-AsLoggedUser
    $param = @{ReturnTranscript = $true }

    if ($computerName -and $computerName -notmatch "localhost|$env:COMPUTERNAME") {
        $param.computerName = $computerName
    }
    #endregion prepare param for Invoke-AsLoggedUser

    $scriptBlockText = @'
$Baselines = Get-CimInstance -Namespace root\ccm\dcm -Class SMS_DesiredConfiguration
ForEach ($Baseline in $Baselines) {
    $bsDisplayName = $Baseline.DisplayName
    $name = $Baseline.Name
    $IsMachineTarget = $Baseline.IsMachineTarget
    $IsEnforced = $Baseline.IsEnforced
    $PolicyType = $Baseline.PolicyType
    $version = $Baseline.Version

    switch ($Baseline.LastComplianceStatus) {
        0 { $bsStatus = "Noncompliant" }
        1 { $bsStatus = "Compliant" }
        2 { $bsStatus = "NotApplicable" }
        3 { $bsStatus = "Unknown" }
        4 { $bsStatus = "Error" }
        5 { $bsStatus = "NotEvaluated" }
        default {$bsStatus = "*Unknown*"}
    }

    [xml]$ComplianceDetails = $baseline.ComplianceDetails

    [PSCustomObject]@{
        DisplayName = $bsDisplayName
        Status = $bsStatus
        LastEvaluated = $Baseline.LastEvalTime
        CI = $ComplianceDetails.ConfigurationItemReport.ReferencedConfigurationItems.ConfigurationItemReport | ? { $_ } | % {
            $property = [ordered]@{
                Name                = $_.CIProperties.name.'#text'
                State               = $_.CIComplianceState
            }
            $DiscoveryViolations = $_.DiscoveryViolations.DiscoveryViolation.SettingInformation.Errors.Error.ErrorDescription
            if ($DiscoveryViolations) {
                $property.DiscoveryViolations = $DiscoveryViolations
            }
            New-Object -TypeName PSObject -Property $property
        }
        IsMachineTarget = $IsMachineTarget
        Version = $version
    }
}
'@ # end of scriptBlock text


    $scriptBlock = [Scriptblock]::Create($scriptBlockText)

    if ($param.computerName) {
        if ($onlyComputerCB) {
            Invoke-Command -ComputerName $computerName -ScriptBlock $scriptBlock
        } else {
            Invoke-AsLoggedUser -ScriptBlock $scriptBlock @param
        }
    } else {
        Invoke-Command -ScriptBlock $scriptBlock
    }
}