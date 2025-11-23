<#
.SYNOPSIS
    Gets a specified resource in the API.
.DESCRIPTION
    Gets a specified resource in the API. retrieves data based either on ID or specific JSON query.
.EXAMPLE
    PS C:\>  Get-AutotaskAPIResource -resource Companies -id 1234 -verbose
    Gets the company with ID 1234

    PS C:\>  Get-AutotaskAPIResource -Resource Companies -SearchQuery '{"filter":[{"op":"eq","field":"isactive","value":"true"}]}
    Gets all companies with the filter "Active = true"

    PS C:\>  Get-AutotaskAPIResource -resource Companies -SimpleSearch "isactive eq $true"
    Gets all companies with the filter "Active = true"

    PS C:\>  Get-AutotaskAPIResource -resource Companies -SimpleSearch "companyname beginswith A"
    Gets all companies that start with the letter A

.INPUTS
    -ID: Search by Autotask ID. Accept pipeline input.
    -SearchQuery: JSON search filter.
    -Method: Forces a GET or POST Request
    -SimpleSearch: a simple search filter, e.g. name eq Lime
    -Udf: Forces any query to be checked against the Udfs belonging to the entity
    -ResolveLabels: Resolves picklist field IDs to their label value
    -LocalTime: Any date/time responses will be returned in the local user time, rather than the default UTC
.OUTPUTS
    none
.NOTES
    TODO: Turns out some items have child URLS. figure that out.
#>
function Get-AutotaskAPIResource {
    [CmdletBinding()]
    Param(
        [Parameter(ParameterSetName = 'ID', Mandatory = $true)]
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [String]$ID,

        [Parameter(ParameterSetName = 'ID', Mandatory = $false)]
        [String]$ChildID,

        [Parameter(ParameterSetName = 'SearchQuery', Mandatory = $true)]
        [String]$SearchQuery,

        [Parameter(ParameterSetName = 'SearchQuery', Mandatory = $false)]
        [ValidateSet("GET", "POST")]
        [String]$Method,

        [Parameter(ParameterSetName = 'SimpleSearch', Mandatory = $true)]
        [String]$SimpleSearch,

        # Explicit UDF flag for SimpleSearch
        [Parameter(ParameterSetName = 'SimpleSearch', Mandatory = $false)]
        [switch]$Udf,

        # Query the picklist index to resolve labels from value
        [Parameter()]
        [switch]$ResolveLabels,

        # Convert output from UTC to local user time & date values
        [switch]$LocalTime
    )

    DynamicParam {
        $Script:GetParameter
    }

    begin {
        if (!$Script:AutotaskAuthHeader -or !$Script:AutotaskBaseURI) {
            Write-Warning "You must first run Add-AutotaskAPIAuth before calling any other cmdlets"
            break
        }

        $resource = $PSBoundParameters.resource
        $headers  = $Script:AutotaskAuthHeader

        $Script:Index = $Script:Queries | Group-Object Index -AsHashTable -AsString
        $ResourceURL  = @(($Script:Index[$resource] | Where-Object { $_.Get -eq $resource }))[0]

        $ResourceURL.name = $ResourceURL.name.replace("/query", "/{PARENTID}")
        # Fix path to InvoicePDF URL, must be unique vs. /Invoices in Swagger file
        $ResourceURL.name = $ResourceURL.name.replace("V1.0/InvoicePDF", "V1.0/Invoices/{id}/InvoicePDF")

        # Picklist metadata lookup
        $picklistFields = @()
        $picklistMap    = @{}
        if ($ResolveLabels.IsPresent) {
                try {
                        $pickMeta       = Get-AutotaskPicklistMeta -Entity $resource
                        $picklistFields = $pickMeta.PicklistFields
                        $picklistMap    = $pickMeta.PicklistMap
                        Write-Verbose "Picklist fields for $resource include: $($picklistFields -join ', ')"
                    }
                    catch {
                        Write-Verbose "Failed to get picklist metadata for '$resource': $_"
                        $picklistFields = @()
                        $picklistMap    = @{}
                    }
                }

        # UDF metadata lookup
        $udfNames = @()
        try {
            $udfNames = Get-AutotaskUdfNames -Resource $resource
            Write-Verbose "User defined fields for $resource include: $($udfNames -join ', ')"
        }
        catch {
            Write-Verbose "Could not build UDF index for '$resource': $_"
            $udfNames = @()
        }

        # SimpleSearch handling
        if ($SimpleSearch) {
            # Split into tokens, but keep quoted strings together
            $tokens = [regex]::Matches($SimpleSearch, '("[^"]+"|\S+)') | ForEach-Object { $_.Value }

            if ($tokens.Count -lt 3) {
                throw "SimpleSearch must be in the form: <field> <op> <value> (with quotes around field/value if they contain spaces)"
            }

            $field = $tokens[0].Trim('"')
            $op    = $tokens[1]
            $value = ($tokens[2..($tokens.Count - 1)] -join ' ').Trim('"')

            $filter = @{
                field = $field
                op    = $op
                value = $value
            }

            # Mark as UDF if:
            #  -Udf is specified
            #  The field matches known UDF metadata
            if ($Udf.IsPresent -or $udfNames -contains $field) {
                # UDF true must be specified as a string
                $filter.udf = "true"
            }

            $SearchQuery = ConvertTo-Json @{
                filter = @($filter)
            } -Compress
        }

        # SearchQuery handling
        if ($SearchQuery) {
            try {
                $sqObj = $SearchQuery | ConvertFrom-Json

                if ($sqObj.filter) {
                    foreach ($f in $sqObj.filter) {
                        if ($null -ne $f.field -and $udfNames -contains $f.field) {
                            if (-not ($f.PSObject.Properties.Name -contains 'udf')) {
                                # UDF true must be specified as a string
                                $f | Add-Member -NotePropertyName 'udf' -NotePropertyValue "true"
                            }
                        }
                    }

                    $SearchQuery = $sqObj | ConvertTo-Json -Depth 10 -Compress
                }
            }
            catch {
                Write-Verbose "Failed to parse/augment SearchQuery JSON for UDF detection: $_"
            }
        }
    }

    process {
        if ($resource -like "*child*" -and $SearchQuery) {
            Write-Warning "You cannot perform a JSON Search on child items. To find child items, use the parent ID."
            break
        }

        if ($ID) {
            $ResourceURL = ("$($ResourceURL.name)" -replace '{parentid}', "$($ID)")
        }
        if ($ChildID) {
            $ResourceURL = ("$($ResourceURL)/$ChildID")
        }

        if ($SearchQuery) {
            switch ($Method) {
                GET {
                    $ResourceURL = ("$($ResourceURL.name)query?search=$SearchQuery" -replace '{PARENTID}', '')
                }
                POST {
                    $ResourceURL = ("$($ResourceURL.name)query" -replace '{PARENTID}', '')
                    $body = $SearchQuery
                }
                Default {
                    if (($Script:AutotaskBaseURI.Length + $ResourceURL.name.Length + $SearchQuery.Length + 15 + 120 + 100) -ge 2048) {
                        Write-Information "Using POST-Request as Request exceeded limit of 2100 characters. You can use -Method GET/POST to set a fixed Method."
                        $ResourceURL = ("$($ResourceURL.name)query" -replace '{PARENTID}', '')
                        $body   = $SearchQuery
                        $Method = "POST"
                    }
                    else {
                        $ResourceURL = ("$($ResourceURL.name)query?search=$SearchQuery" -replace '{PARENTID}', '')
                    }
                }
            }
        }

        if ($resource -eq "InvoicePDF" -and $ID) {
            $ResourceURL = ("$($ResourceURL)" -replace '{id}', "$($ID)")
        }

        $SetURI = "$($Script:AutotaskBaseURI)$($ResourceURL)"

        try {
            do {
                if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
                    $safeHeaders = @{}
                    foreach ($key in $Headers.Keys) {
                        if ($key -eq 'Secret') {
                            # Mask the secret value from Verbose output
                            $val = $Headers[$key]
                            if ($val -and $val.Length -gt 4) {
                                $safeHeaders[$key] = ($val.Substring(0,2) + '*REDACTED*' + $val.Substring($val.Length-2,2))
                            } else {
                                $safeHeaders[$key] = '*REDACTED*'
                            }
                        }
                        else {
                            $safeHeaders[$key] = $Headers[$key]
                        }
                    }
                    $effectiveMethod = if ([string]::IsNullOrWhiteSpace($Method)) { 'GET' } else { $Method }
                    Write-Host "=========================" -ForegroundColor DarkGray
                    Write-Host "AUTOTASK API REQUEST" -ForegroundColor Cyan
                    Write-Host "Method : $effectiveMethod"
                    Write-Host "URL    : $SetURI"
                    Write-Host "Headers:" ($safeHeaders | ConvertTo-Json -Compress)
                    if ($Body) { Write-Host "Body   :" $Body }
                    Write-Host "=========================" -ForegroundColor DarkGray
                }

                switch ($Method) {
                    GET    { $items = Invoke-RestMethod -Uri $SetURI -Headers $Headers -Method Get }
                    POST   { $items = Invoke-RestMethod -Uri $SetURI -Headers $Headers -Method Post -Body $Body }
                    Default{ $items = Invoke-RestMethod -Uri $SetURI -Headers $Headers -Method Get }
                }

                $SetURI = $items.PageDetails.NextPageUrl

                if ($resource -eq "InvoicePDF") {
                    return $items
                }

                if ($items.items) {
                    foreach ($item in $items.items) {
                        if ($ResolveLabels.IsPresent -and $picklistFields -and $picklistMap) {
                            foreach ($fieldName in $picklistFields) {
                                # Skip if this object doesn't even have that property
                                if (-not ($item.PSObject.Properties.Name -contains $fieldName)) { continue }
                                $rawValue = $item.$fieldName
                                if ($null -eq $rawValue -or $rawValue -eq '') { continue }
                                $fieldMap = $picklistMap[$fieldName]
                                if (-not $fieldMap) { continue }
                                $label = $fieldMap["$rawValue"]
                                if (-not $label) { continue }
                                # Overwrite numeric picklist value output with the label
                                $item.$fieldName = $label
                            }
                        }
                        if ($LocalTime) {
                            foreach ($prop in $item.PSObject.Properties) {
                                $value = $prop.Value
                                if ($value -is [datetime]) {
                                    $dt = [datetime]$value
                                    if ($dt.Kind -ne [System.DateTimeKind]::Utc) {
                                        $dt = [System.DateTime]::SpecifyKind($dt, [System.DateTimeKind]::Utc)
                                    }
                                    $prop.Value = $dt.ToLocalTime()
                                    continue
                                }
                                if ($value -is [string] -and $value -match '^\d{4}-\d{2}-\d{2}T.*Z$') {
                                    try {
                                        $dt = [datetime]::Parse(
                                            $value,
                                            [System.Globalization.CultureInfo]::InvariantCulture,
                                            [System.Globalization.DateTimeStyles]::AssumeUniversal
                                            )
                                            $prop.Value = $dt.ToLocalTime()
                                        }
                                        catch {
                                            # If parsing fails, don't change the output
                                            }
                                        }
                            }
                        }
                        $item
                    }
                }

                if ($items.item) {
                    foreach ($item in $items.item) {
                        if ($ResolveLabels.IsPresent -and $picklistFields -and $picklistMap) {
                            foreach ($fieldName in $picklistFields) {
                                if (-not ($item.PSObject.Properties.Name -contains $fieldName)) { continue }
                                $rawValue = $item.$fieldName
                                if ($null -eq $rawValue -or $rawValue -eq '') { continue }
                                $fieldMap = $picklistMap[$fieldName]
                                if (-not $fieldMap) { continue }
                                $label = $fieldMap["$rawValue"]
                                if (-not $label) { continue }
                                $item.$fieldName = $label
                            }
                        }
                        if ($LocalTime) {
                            foreach ($prop in $item.PSObject.Properties) {
                                $value = $prop.Value
                                if ($value -is [datetime]) {
                                    $dt = [datetime]$value
                                    if ($dt.Kind -ne [System.DateTimeKind]::Utc) {
                                        $dt = [System.DateTime]::SpecifyKind($dt, [System.DateTimeKind]::Utc)
                                    }
                                    $prop.Value = $dt.ToLocalTime()
                                    continue
                                }
                                if ($value -is [string] -and $value -match '^\d{4}-\d{2}-\d{2}T.*Z$') {
                                    try {
                                        $dt = [datetime]::Parse(
                                            $value,
                                            [System.Globalization.CultureInfo]::InvariantCulture,
                                            [System.Globalization.DateTimeStyles]::AssumeUniversal
                                            )
                                            $prop.Value = $dt.ToLocalTime()
                                        }
                                        catch {
                                            # If parsing fails, don't change the output
                                        }
                                    }
                            }
                        }
                        $item
                    }
                }

            } while ($null -ne $SetURI)
        }
        catch {
            if ($psversiontable.psversion.major -lt 6) {
                $streamReader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
                $streamReader.BaseStream.Position = 0
                if ($streamReader.ReadToEnd() -like '*{*') { $ErrResp = $streamReader.ReadToEnd() | ConvertFrom-Json }
                $streamReader.Close()
            }
            if ($ErrResp.errors) {
                Write-Error "API Error: $($ErrResp.errors)"
            }
            else {
                Write-Error "Connecting to the Autotask API failed. $($_.Exception.Message)"
            }
        }
    }
}