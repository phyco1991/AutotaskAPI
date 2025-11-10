<#
.SYNOPSIS
    Gets a list of available entities from a specific resource in the API.
.DESCRIPTION
    Gets a list of available entities from a specific resource in the API. You can use these to filter results for the target resource type.
.EXAMPLE
    PS C:\>  Get-AutotaskAPIEntityInfo -Entity Tickets
    Outputs all entities available from the 'Tickets' resource that can be queried via the API
    i.e. ID, issueType, TicketType, TicketCategory, etc

    PS C:\>  Get-AutotaskAPIEntityInfo -AllFields -Entity Tickets
    Outputs all entities available from the 'Tickets' resource, whether they can be queried or not (default does not include picklists)
    i.e. ID, issueType, TicketType, TicketCategory, etc

.INPUTS
    -Entity: Search by Resource
    -AllFields: Show all entities available from a specified resource, whether they can be queried or not
.OUTPUTS
    Entity List
.NOTES
    None
#>
function Get-AutotaskAPIEntityInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Entity,
        [switch] $AllFields            # ignore isQueryable filter and show everything
    )

    if (-not $Script:AutotaskBaseURI -or -not $Script:AutotaskAuthHeader) {
        throw "You must run Add-AutotaskAPIAuth first."
    }

    $uri = "$($Script:AutotaskBaseURI)/V1.0/$Entity/entityInformation/fields"
    $fields = (Invoke-RestMethod -Method GET -Uri $uri -Headers $Script:AutotaskAuthHeader).fields

    if (-not $AllFields) {
        $fields = $fields | Where-Object { $_.isQueryable -eq $true }
    }

    $fields |
        Select-Object name, dataType, isQueryable, referenceEntityType, isPickList, length |
        Sort-Object name
}