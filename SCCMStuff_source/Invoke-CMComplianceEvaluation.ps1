function Invoke-CMComplianceEvaluation {
    <#
    .SYNOPSIS
    Function triggers evaluation of available SCCM compliance baselines.

    .DESCRIPTION
    Function triggers evaluation of available SCCM compliance baselines.
    It supports evaluation of device and user compliance policies! Users part thanks to Invoke-AsCurrentUser.
    Disadvantage is, that function returns string as output, not object, but only in case, you run it against remote computer (locally is used classic Invoke-Command).

    .PARAMETER computerName
    Default is localhost.

    .PARAMETER baselineName
    Optional parameter for filtering baselines to evaluate.

    .EXAMPLE
    Invoke-CMComplianceEvaluation

    Trigger evaluation of all compliance baselines on localhost targeted to device and user, that run this function.

    .EXAMPLE
    Invoke-CMComplianceEvaluation -computerName ae-01-pc -baselineName "KTC_compliance_policy"

    Trigger evaluation of just KTC_compliance_policy compliance baseline on ae-01-pc. But only in case, such baseline is targeted to device, not user.

    .NOTES
    Modified from https://social.technet.microsoft.com/Forums/en-US/76afbba5-065e-4809-9720-024ea05d6cee/trigger-baseline-evaluation?forum=configmanagersdk
    #>

    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline = $true)]
        [string] $computerName
        ,
        [string[]] $baselineName
    )

    #region prepare param for Invoke-AsLoggedUser
    $param = @{ReturnTranscript = $true }

    if ($baselineName) {
        $param.argument = @{baselineName = $baselineName }
    }

    if ($computerName -and $computerName -notmatch "localhost|$env:COMPUTERNAME") {
        $param.computerName = $computerName
    }
    #endregion prepare param for Invoke-AsLoggedUser

    $scriptBlockText = @'
#Start-Transcript (Join-Path $env:TEMP ((Split-Path $PSCommandPath -Leaf) + ".log"))

$Baselines = Get-CimInstance -Namespace root\ccm\dcm -Class SMS_DesiredConfiguration
ForEach ($Baseline in $Baselines) {
    $bsDisplayName = $Baseline.DisplayName
    if ($baselineName -and $bsDisplayName -notin $baselineName) {
        Write-Verbose "Skipping $bsDisplayName baseline"
        continue
    }

    $name = $Baseline.Name
    $IsMachineTarget = $Baseline.IsMachineTarget
    $IsEnforced = $Baseline.IsEnforced
    $PolicyType = $Baseline.PolicyType
    $version = $Baseline.Version

    $MC = [WmiClass]"\\localhost\root\ccm\dcm:SMS_DesiredConfiguration"

    $Method = "TriggerEvaluation"
    $InParams = $MC.psbase.GetMethodParameters($Method)
    $InParams.IsEnforced = $IsEnforced
    $InParams.IsMachineTarget = $IsMachineTarget
    $InParams.Name = $name
    $InParams.Version = $version
    $InParams.PolicyType = $PolicyType

    switch ($Baseline.LastComplianceStatus) {
        0 {$bsStatus = "Noncompliant"}
        1 {$bsStatus = "Compliant"}
        default {$bsStatus = "Noncompliant"}
    }
    "Evaluating: '$bsDisplayName' Last status: $bsStatus Last evaluated: $($Baseline.LastEvalTime)"

    $result = $MC.InvokeMethod($Method, $InParams, $null)

    if ($result.ReturnValue -eq 0) {
        Write-Verbose "OK"
    } else {
        Write-Error "There was an error.`n$result"
    }
}
'@ # end of scriptBlock text

    $scriptBlock = [Scriptblock]::Create($scriptBlockText)

    if ($param.computerName) {
        Invoke-AsLoggedUser -ScriptBlock $scriptBlock @param
    } else {
        Invoke-Command -ScriptBlock $scriptBlock
    }
}