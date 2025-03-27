function Compare-IntuneSecurityBaseline {
    <#
    .SYNOPSIS
    Function to interactively select & compare two Intune security baseline policies.

    .DESCRIPTION
    Function to interactively select & compare two Intune security baseline policies.

    .EXAMPLE
    Compare-SecurityBaseline

    You will be asked to select baseline type and then two policies of such type.
    Object with comparison results will be returned.
    #>

    [CmdletBinding()]
    param ()

    #region get baselines to compare
    $oldBaselineObj, $newBaselineObj = $null

    if (!(Get-Command Get-MgContext -ErrorAction silentlycontinue) -or !(Get-MgContext)) {
        throw "$($MyInvocation.MyCommand): Authentication needed. Please call Connect-MgGraph."
    }

    $baselineTemplate = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicyTemplates?`$top=500&`$filter=(lifecycleState%20eq%20%27active%27)%20and%20(templateFamily%20eq%20%27Baseline%27)" | Get-MgGraphAllPages | select displayName, id, platforms | sort DisplayName | Out-GridView -OutputMode Single -Title "Select baseline type"

    while (!$oldBaselineObj) {
        $oldBaselineObj = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$select=id,name,description,platforms,lastModifiedDateTime,technologies,settingCount,roleScopeTagIds,isAssigned,templateReference" | Get-MgGraphAllPages | ? { $_.templateReference.TemplateId -like (($baselineTemplate.Id -replace "\d*$") + "*") }

        if (!$oldBaselineObj) {
            throw "No policy of the '$($baselineTemplate.DisplayName)' type exists"
        } else {
            $oldBaselineObj = $oldBaselineObj | select Name, Id, Description, LastModifiedDateTime | Out-GridView -OutputMode Single -Title "Select 'old' baseline"
        }
    }

    $oldBaseline = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($oldBaselineObj.Id)')/settings?`$expand=settingDefinitions&top=1000" | Get-MgGraphAllPages

    while (!$newBaselineObj) {
        $newBaselineObj = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$select=id,name,description,platforms,lastModifiedDateTime,technologies,settingCount,roleScopeTagIds,isAssigned,templateReference" | Get-MgGraphAllPages | ? Id -NE $oldBaselineObj.Id | ? { $_.templateReference.TemplateId -like (($baselineTemplate.Id -replace "\d*$") + "*") }

        if (!$newBaselineObj) {
            throw "No policy to compare with"
        } else {
            $newBaselineObj = $newBaselineObj | select Name, Id, Description, LastModifiedDateTime | Out-GridView -OutputMode Single -Title "Select 'new' baseline"
        }
    }

    $newBaseline = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($newBaselineObj.Id)')/settings?`$expand=settingDefinitions&top=1000" | Get-MgGraphAllPages
    #endregion get baselines to compare

    # get settings that differs
    foreach ($setting in $oldBaseline.settingInstance) {
        Write-Verbose "Processing '$($setting.settingDefinitionId)'"

        $settingDefinitionId = $setting.settingDefinitionId
        $correspondingSetting = $newBaseline.settingInstance | ? { $_.settingDefinitionId -eq $settingDefinitionId }

        if (!$correspondingSetting) {
            [PSCustomObject]@{
                Result       = "Missing"
                Setting      = $setting.settingDefinitionId
                OldBslnValue = ($setting | select * -ExcludeProperty '@odata.type', 'settingInstanceTemplateReference' | ConvertTo-Json -Depth 50)
                NewBslnValue = $null
            }
            continue
        } else {
            if ($setting.choiceSettingValue) {
                $oldBslnJson = $setting.choiceSettingValue | select * -ExcludeProperty settingValueTemplateReference | ConvertTo-Json -Depth 50
                $newBslnJson = $correspondingSetting.choiceSettingValue | select * -ExcludeProperty settingValueTemplateReference | ConvertTo-Json -Depth 50
            } elseif ($setting.simpleSettingCollectionValue) {
                $oldBslnJson = $setting.simpleSettingCollectionValue | ConvertTo-Json -Depth 50
                $newBslnJson = $correspondingSetting.simpleSettingCollectionValue | ConvertTo-Json -Depth 50
            } elseif ($setting.groupSettingCollectionValue) {
                $oldBslnJson = $setting.groupSettingCollectionValue | ConvertTo-Json -Depth 50
                $newBslnJson = $correspondingSetting.groupSettingCollectionValue | ConvertTo-Json -Depth 50
            } elseif ($setting.simpleSettingValue) {
                $oldBslnJson = $setting.simpleSettingValue | ConvertTo-Json -Depth 50
                $newBslnJson = $correspondingSetting.simpleSettingValue | ConvertTo-Json -Depth 50
            } else {
                $setting | fl *
                throw "Undefined property to compare. Neither 'choiceSettingValue', 'simpleSettingCollectionValue', 'simpleSettingValue' nor 'groupSettingCollectionValue' is set. This functions needs to be modified!"
            }

            if ($oldBslnJson -ne $newBslnJson) {
                $oldBslnValue, $newBslnValue = ""
                $oldBslnJsonLines = $oldBslnJson -split "`n"
                $newBslnJsonLines = $newBslnJson -split "`n"
                # get lines that differs
                for ($i = 0; $i -lt $oldBslnJsonLines.Length; $i++) {
                    if ($oldBslnJsonLines[$i] -ne $newBslnJsonLines[$i]) {
                        $oldBslnValue += (($oldBslnJsonLines[$i] -replace '"value": "' -replace '",\s*$').trim() + "`n")
                        $newBslnValue += (($newBslnJsonLines[$i] -replace '"value": "' -replace '",\s*$').trim() + "`n")
                    }
                }

                [PSCustomObject]@{
                    Result       = "Differs"
                    Setting      = $setting.settingDefinitionId
                    OldBslnValue = $oldBslnValue
                    NewBslnValue = $newBslnValue
                }
            }
        }
    }

    # get settings that are in the new baseline but missing from the old one
    foreach ($setting in $newBaseline.settingInstance) {
        $settingDefinitionId = $setting.settingDefinitionId
        $correspondingSetting = $oldBaseline.settingInstance | ? { $_.settingDefinitionId -eq $settingDefinitionId }

        if (!$correspondingSetting) {
            [PSCustomObject]@{
                Result       = "Missing"
                Setting      = $setting.settingDefinitionId
                OldBslnValue = $null
                NewBslnValue = ($setting | select * -ExcludeProperty '@odata.type', 'settingInstanceTemplateReference' | ConvertTo-Json -Depth 50)
            }
            continue
        }
    }
}