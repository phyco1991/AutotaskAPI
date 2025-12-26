<#
.SYNOPSIS
    Used to resolve picklist values to their label, to identify what they are without having to run additional queries
.DESCRIPTION
    TBA
.EXAMPLE
    PS C:\> Get-AutotaskPicklistMeta -Entity Tickets
    Stores an index of all picklist labels that relate to the Tickets entity
.INPUTS
    -Entity
.OUTPUTS
    none
.NOTES
    none
#>
if (-not $Script:AutotaskPicklistCache) {
    $Script:AutotaskPicklistCache = @{}
}
function Get-AutotaskPicklistMeta {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Entity
    )

    if ($Script:AutotaskPicklistCache.ContainsKey($Entity)) {
        Write-Verbose "Picklist cache hit for entity '$Entity'."
        return $Script:AutotaskPicklistCache[$Entity]
    }

    if (-not $Script:AutotaskAuthHeader -or -not $Script:AutotaskBaseURI) {
        throw "Autotask API auth is not initialised. Run Add-AutotaskAPIAuth first."
    }

    # Get field metadata
    $fieldsUri = "$($Script:AutotaskBaseURI)/V1.0/$Entity/entityInformation/fields"
    Write-Verbose "Querying field metadata for '$Entity' from: $fieldsUri"

    $fieldInfo = Invoke-WebRequest -Method Get -UseBasicParsing -Uri $fieldsUri -Headers $Script:AutotaskAuthHeader
    $fields    = ($fieldInfo.content | ConvertFrom-Json).fields

    # Picklist fields only
    $picklistFields = $fields | Where-Object { $_.isPickList -eq $true }

    $picklistMap = @{}
    foreach ($pf in $picklistFields) {
        $fieldName = $pf.name
        $values    = Get-AutotaskAPIPicklistValues -Entity $Entity -FieldName $fieldName

        $valMap = @{}
        foreach ($v in $values) {
            # As string so "5" and 5 behave the same way
            $valMap["$($v.value)"] = $v.label
        }

        $picklistMap[$fieldName] = $valMap
    }

    $meta = @{
        PicklistFields = $picklistFields.name
        PicklistMap    = $picklistMap
    }

    $Script:AutotaskPicklistCache[$Entity] = $meta
    return $meta
}