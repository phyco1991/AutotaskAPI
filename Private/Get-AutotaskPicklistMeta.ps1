<#
.SYNOPSIS
    Helper function used by Get-AutotaskAPIResource to resolve picklist values to their label, to identify what they are without having to run additional queries
.DESCRIPTION
    TBA
.EXAMPLE
    PS C:\> Get-AutotaskPicklistMeta -Resource Tickets
    Stores an index of all picklist labels that relate to the Tickets entity
.INPUTS
    -Resource
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
        [string]$Resource
    )

    $key = $Resource.Trim().ToLowerInvariant()

    if ($Script:AutotaskPicklistCache.ContainsKey($key)) {
        Write-Information "INFO: Cached Picklist Field index hit for resource '$Resource'."
        return $Script:AutotaskPicklistCache[$key]
    }

    if (-not $Script:AutotaskAuthHeader -or -not $Script:AutotaskBaseURI) {
        throw "ERROR: Autotask API auth is not initialised. Run Add-AutotaskAPIAuth first."
    }

    # Build the URL
    $fieldsUri = "$($Script:AutotaskBaseURI)/V1.0/$Resource/entityInformation/fields"
    Write-Information "INFO: Building initial Picklist Field index for '$Resource' from: $fieldsUri..."

    # Get field metadata
    try {
    $fieldInfo = Invoke-WebRequest -Method Get -UseBasicParsing -Uri $fieldsUri -Headers $Script:AutotaskAuthHeader
    $fields    = ($fieldInfo.Content | ConvertFrom-Json).fields

    # Picklist fields only
    $picklistFields = $fields | Where-Object { $_.isPickList -eq $true }

    $picklistMap = @{}
        foreach ($pf in $picklistFields) {
        $fieldName = $pf.name
        $values    = Get-AutotaskAPIPicklistValues -Entity $Resource -FieldName $fieldName -Fields $fields

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

    $mappedCount = ($picklistMap.GetEnumerator() | Where-Object { $_.Value.Count -gt 0 }).Count
    Write-Information "INFO: Wrote $mappedCount Picklist Field names to local index for '$Resource'."

    $Script:AutotaskPicklistCache[$key] = $meta
    return $meta
    }
    catch {
        Write-Warning "Failed to query Picklist Field metadata for resource '$Resource' from $fieldsUri : $($_.Exception.Message)"
        return @()
    }
}