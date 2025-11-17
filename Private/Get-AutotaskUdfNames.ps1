<#
.SYNOPSIS
    Used to gather an index of UDF Names associated with a specific entity
.DESCRIPTION
    TBA
.EXAMPLE
    PS C:\> Get-AutotaskUdfNames -Resource ConfigurationItems
    Stores an index of all UDF names that relate to the ConfigurationItems entity
.INPUTS
    -Resource
.OUTPUTS
    none
.NOTES
    none
#>
if (-not $Script:AutotaskUdfIndex) {
    $Script:AutotaskUdfIndex = @{}
}
function Get-AutotaskUdfNames {
    param(
        [Parameter(Mandatory)]
        [string]$Resource
    )

    if ($Script:AutotaskUdfIndex.ContainsKey($Resource)) {
        Write-Verbose "UDF cache hit for resource '$Resource'."
        return $Script:AutotaskUdfIndex[$Resource]
    }

    if (-not $Script:AutotaskAuthHeader -or -not $Script:AutotaskBaseURI) {
        throw "Autotask API auth is not initialised. Run Add-AutotaskAPIAuth first."
    }

    # Build the URL exactly as per the docs
    $uri = "$($Script:AutotaskBaseURI)/V1.0/$Resource/entityInformation/userDefinedFields"
    Write-Verbose "Querying UDF metadata for '$Resource' from: $uri"

    try {
        $udfInfo = Invoke-RestMethod -Method Get -Uri $uri -Headers $Script:AutotaskAuthHeader
        $udfs = $udfInfo.fields

        $names = @()
        foreach ($u in $udfs) {
            if ($u.name)  { $names += $u.name }
            if ($u.label) { $names += $u.label }
        }

        Write-Verbose "Found $($names.Count) UDF field names for '$Resource'."

        $Script:AutotaskUdfIndex[$Resource] = $names
        return $names
    }
    catch {
        Write-Verbose "Failed to query UDF metadata for resource '$Resource' from $uri : $_"
        return @()
    }
}