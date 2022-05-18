#Requires -Module Microsoft.Graph.Identity.SignIns, AzureAD
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