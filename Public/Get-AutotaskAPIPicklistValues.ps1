<#
.SYNOPSIS
    Gets a list of available values for a specified picklist field from a specific resource in the API.
.DESCRIPTION
    Gets a list of available values for a specified picklist field from a specific resource in the API. You can then use these to set/change values.
.EXAMPLE
    PS C:\>  Get-AutotaskAPIPicklistValues -Entity Tickets -FieldName status
    Outputs all picklist values available from the 'Tickets' resource for a field called 'status'
    i.e. None, Good, Bad, Ok, etc

.INPUTS
    -Entity: Search by Resource
    -FieldName: Search by FieldName
.OUTPUTS
    Picklist Values
.NOTES
    None
#>
function Get-AutotaskAPIPicklistValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Entity,
        [Parameter(Mandatory)][string] $FieldName,
        [Parameter()][object[]] $Fields   # optional: pre-fetched entityInformation/fields
    )

    if (-not $Script:AutotaskBaseURI -or -not $Script:AutotaskAuthHeader) {
        throw "WARNING: You must run Add-AutotaskAPIAuth first."
    }

    if (-not $Fields) {
    $uri = "$($Script:AutotaskBaseURI)/V1.0/$Entity/entityInformation/fields"
    $resp = Invoke-WebRequest -Method GET -UseBasicParsing -Uri $uri -Headers $Script:AutotaskAuthHeader
    $fields = ($resp | ConvertFrom-Json).fields
    }
    $f = $fields | Where-Object { $_.name -eq $FieldName }
    if (-not $f) { throw "WARNING: Field '$FieldName' not found on '$Entity'." }
    if (-not $f.isPickList) { throw "WARNING: '$Entity.$FieldName' is not a picklist field." }

    if ($f.picklistValues) {
        $f.picklistValues |
            Select-Object value, label, isActive, isDefaultValue, sortOrder, parentValue
    } else {
        Write-Warning "No inline picklistValues. Some entities document a dedicated picklist endpoint."
        @()
    }
}