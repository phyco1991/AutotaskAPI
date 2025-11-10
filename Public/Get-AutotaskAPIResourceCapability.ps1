<#
.SYNOPSIS
    Gets a list of capabilities for a specific resource in the API.
.DESCRIPTION
    Gets a list of capabilities for a specific resource in the API. This will show if the resource queried supports Query/Update/Delete etc.
.EXAMPLE
    PS C:\>  Get-AutotaskAPIResourceCapability -Entity Tickets
    Outputs all capababilities of the 'Tickets' resource
    i.e. canQuery, canCreate, canUpdate, canDelete, hasUserDefinedFields, supportsWebhookCallouts, etc

.INPUTS
    -Entity: Search by Resource
.OUTPUTS
    Resource Capabilities
.NOTES
    None
#>
function Get-AutotaskAPIResourceCapability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Entity
    )

    if (-not $Script:AutotaskBaseURI -or -not $Script:AutotaskAuthHeader) {
        throw "You must run Add-AutotaskAPIAuth first."
    }

    $uri = "$($Script:AutotaskBaseURI)/V1.0/$Entity/entityInformation"
    (Invoke-RestMethod -Method GET -Uri $uri -Headers $Script:AutotaskAuthHeader).info
}