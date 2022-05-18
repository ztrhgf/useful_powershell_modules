function Add-CMDeviceToCollection {
    <#
    .SYNOPSIS
    Function for easy adding of device(s) to SCCM collection.

    .DESCRIPTION
    Function for easy adding of device(s) to SCCM collection.
    It can be added using static or query rule type.

    .PARAMETER computerName
    Computer name(s).

    .PARAMETER collectionName
    Name of the SCCM collection.

    .PARAMETER asQuery
    Switch for adding computer using query rule (instead of static).
    Query rule add computer even after it was deleted and re-added to SCCM database.

    .EXAMPLE
    Add-CMDeviceToCollection -computerName ae-79-pc -collectionName 'windows 10 deploy' -asQuery
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ArgumentCompleter( {
                param ($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)

                Get-ADComputer -Filter "name -like '*$WordToComplete*' -and enabled -eq 'true'" -property Name, Enabled | select -exp Name | sort
            })]
        [string[]] $computerName,

        [Parameter(Mandatory = $true)]
        [ArgumentCompleter( {
                param ($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)

                Get-CMCollection -Name "*$WordToComplete*" | select -exp Name | sort | % { "'$_'" }
            })]
        [string] $collectionName,

        [switch] $asQuery
    )

    Connect-SCCM -ea Stop

    if (!(Get-CMCollection -Name $collectionName)) {
        throw "Collection '$collectionName' doesn't exist"
    }

    # get computer resourceId
    $computerHash = @{}
    $computerName | % {
        if (Get-CMCollectionMember -CollectionName $collectionName -Name $_) {
            Write-Warning "$_ is already in collection '$collectionName'. Skipping"
        } else {
            $computerId = Get-CMDevice -Name $_ -Fast | select -exp ResourceId
            if ($computerId) {
                $computerHash.$_ = $computerId
            } else {
                Write-Warning "Computer $_ wasn't found in SCCM database"
            }
        }
    }

    if ($computerHash.Keys) {
        if ($asQuery) {
            # add query rule (will survive computers removal from SCCM database)
            $computerHash.GetEnumerator() | % {
                Add-CMDeviceCollectionQueryMembershipRule -CollectionName $collectionName -QueryExpression "select SMS_R_System.ResourceId from SMS_R_System where SMS_R_System.Name = `"$($_.key)`"" -RuleName ($_.key).toupper()
            }
        } else {
            # add static rule
            $computerHash.GetEnumerator() | % {
                Add-CMDeviceCollectionDirectMembershipRule -CollectionName $collectionName -ResourceId $_.value
            }
        }

        # update membership
        Invoke-CMCollectionUpdate -Name $collectionName -Confirm:$false
    } else {
        Write-Warning "No such computer was found in SCCM database"
    }
}