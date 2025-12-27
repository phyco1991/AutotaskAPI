<#
.SYNOPSIS
    Helper function used by Get-AutotaskAPIResource to gather an index of UDF Names associated with a specific entity
.DESCRIPTION
    When fields are queried using Get-AutotaskAPIResource and they are a UDF, this allows the function to automatically adjust the API call to resolve them (without needing to specify udf=true in your filter)
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
        Write-Information "INFO: Cached UDF index hit for resource '$Resource'."
        return $Script:AutotaskUdfIndex[$Resource]
    }

    if (-not $Script:AutotaskAuthHeader -or -not $Script:AutotaskBaseURI) {
        throw "ERROR: Autotask API auth is not initialised. Run Add-AutotaskAPIAuth first."
    }

    # Build the URL
    $uri = "$($Script:AutotaskBaseURI)/V1.0/$Resource/entityInformation/userDefinedFields"
    Write-Information "INFO: Building initial UDF index for '$Resource' from: $uri..."

    try {
        $udfInfo = Invoke-WebRequest -Method Get -UseBasicParsing -Uri $uri -Headers $Script:AutotaskAuthHeader
        $udfs = ($udfInfo.Content | ConvertFrom-Json).fields

        $names = @()
        foreach ($u in $udfs) {
            if ($u.label)  { $names += $u.label }
            elseif ($u.name) { $names += $u.name }
        }

        Write-Information "INFO: Wrote $($names.Count) UDF field names to local index for '$Resource'."

        $Script:AutotaskUdfIndex[$Resource] = $names
        return $names
    }
    catch {
        Write-Warning "WARNING: Failed to properly build local UDF index for resource '$Resource' from $uri : $_"
        return @()
    }
}