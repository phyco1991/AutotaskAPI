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
    -Base: Queries the base endpoint without any search filter. Used for entities where this is required such as ZoneInformation
.OUTPUTS
    none
.NOTES
    Some entities have 'Child Access URLs'. For example, TicketNotesChild is the entity through which you create/update notes on Autotask Tickets.
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

        [Parameter(ParameterSetName = 'Where', Mandatory = $true)]
        [String]$Where,

        [Parameter(ParameterSetName = 'SearchQuery', Mandatory = $false)]
        [Parameter(ParameterSetName = 'SimpleSearch', Mandatory = $false)]
        [Parameter(ParameterSetName = 'Where', Mandatory = $false)]
        [ValidateSet("GET", "POST")]
        [String]$Method,

        [Parameter(ParameterSetName = 'SimpleSearch', Mandatory = $true)]
        [String]$SimpleSearch,

        [Parameter(ParameterSetName = 'Base', Mandatory = $true)]
        [switch]$Base,

        # Explicit UDF flag for SimpleSearch
        [Parameter(ParameterSetName = 'SimpleSearch', Mandatory = $false)]
        [switch]$Udf,

        # Query the picklist index to resolve labels from value
        [Parameter()]
        [switch]$ResolveLabels,

        # Generate a URL to open selected entities in the Autotask GUI
        [Parameter(Mandatory = $false)]
        [switch]$URL,

        # Convert output from UTC to local user time & date values
        [Parameter()]
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
        # First, get the group for this resource (by Index / tag)
        $resourceGroup = $Script:Index[$resource]

        if (-not $resourceGroup) {
            $resourceGroup = $Script:Queries | Where-Object { $_.Get -eq $resource }
        } 

        if (-not $resourceGroup) {
            throw "WARNING: Resource '$resource' not found in the index."
        }

        # Try match where .Get == resource
        $ResourceURL = @($resourceGroup | Where-Object { $_.Get -eq $resource })[0]

        # If that fails, fall back to the first entry for this index
        if (-not $ResourceURL) {
            $ResourceURL = @($resourceGroup)[0]
        }

        $Script:BasePath = $ResourceURL.name
        $ResourceURL.name = $ResourceURL.name.replace("/query", "/{PARENTID}")

        # Picklist metadata lookup
        $picklistFields = @()
        $picklistMap    = @{}
        if ($ResolveLabels.IsPresent) {
                try {
                        $pickMeta       = Get-AutotaskPicklistMeta -Resource $resource
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
        
        if (-not $Base-and $resource -notlike '*Child*') {
            try {
                $udfNames = Get-AutotaskUdfNames -Resource $resource
                Write-Verbose "User Defined Fields for $resource include: $($udfNames -join ', ')"
            }
            catch {
                Write-Warning "WARNING: Could not build UDF index for '$resource': $_"
                $udfNames = @()
            }
        }
        else {
            Write-Verbose "Skipping UDF metadata lookup for base or child type resource '$resource'."
        }

        # SQLSearch handling
        if ($Where) {
            $SearchQuery = ConvertTo-SearchQueryFromSQL -Where $Where
            $Method = 'POST'  # avoids URL length limits
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

        $path = $ResourceURL.name

        $Body = $null
        $effectiveMethod = if ([string]::IsNullOrWhiteSpace($Method)) { 'GET' } else { $Method }

        if ($Base) {
            $path = $Script:BasePath
            if (-not $path) { $path = $ResourceURL.name }
            # Strip /query and any placeholders just in case
            $path = $path -replace '/query$', ''
            $path = $path -replace '\{PARENTID\}', '' -replace '\{parentid\}', '' -replace '\{id\}', ''
        }
        else {
            # Parent ID substitution (works for {parentId}, {PARENTID}, etc.)
            if ($ID) {
                $path = $path -replace '\{parentid\}', "$ID"
                $path = $path -replace '\{id\}', "$ID"  # some routes may use {id} rather than {parentId}
                }
                
            # Child item path append
                if ($ChildID) {
                    $path = "$path/$ChildID"
                }
                # SearchQuery handling
                if ($SearchQuery) {
                    switch ($Method) {
            'GET' {
                $path = ($ResourceURL.name + "query?search=$SearchQuery") -replace '\{PARENTID\}', ''
                $effectiveMethod = 'GET'
            }
            'POST' {
                $path = ($ResourceURL.name + "query") -replace '\{PARENTID\}', ''
                $Body = $SearchQuery
                $effectiveMethod = 'POST'
            }
            Default {
                if (($Script:AutotaskBaseURI.Length + $ResourceURL.name.Length + $SearchQuery.Length + 15 + 120 + 100) -ge 2048) {
                    Write-Information "Using POST-Request as Request exceeded limit of 2100 characters. You can use -Method GET/POST to set a fixed Method."
                    $path = ($ResourceURL.name + "query") -replace '\{PARENTID\}', ''
                    $Body = $SearchQuery
                    $effectiveMethod = 'POST'
                }
                else {
                    $path = ($ResourceURL.name + "query?search=$SearchQuery") -replace '\{PARENTID\}', ''
                    $effectiveMethod = 'GET'
                }
            }
        }
    }
}

$SetURI = "$($Script:AutotaskBaseURI)$path"

        try {
            do {
                if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') {
                    $safeHeaders = @{}
                    foreach ($key in $Headers.Keys) {
                        if (($key -eq 'Secret') -or ($key -eq'APIIntegrationcode')) {
                            # Masks the secret and integration code values from being displayed as plain text in Verbose output
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
                    Write-Host "=========================" -ForegroundColor DarkGray
                    Write-Host "AUTOTASK API REQUEST" -ForegroundColor Cyan
                    Write-Host "Method : $effectiveMethod"
                    Write-Host "URL    : $SetURI"
                    Write-Host "Headers:" ($safeHeaders | ConvertTo-Json -Compress)
                    if ($Body) {
                        $payloadBytes = [Text.Encoding]::UTF8.GetByteCount([string]$Body)
                        Write-Host "Body   : ($payloadBytes bytes) $Body"
                    }
                    Write-Host "=========================" -ForegroundColor DarkGray
                }

                $methodToUse = $effectiveMethod
                if ([string]::IsNullOrWhiteSpace($methodToUse)) { $methodToUse = 'GET' }
                $req = [System.Net.HttpWebRequest]::Create($SetURI)
                $req.Method  = $methodToUse
                $req.Accept  = 'application/json'
                $req.AutomaticDecompression = `
                [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
                
                # Apply headers (Autotask custom headers are OK here)
                foreach ($k in $Headers.Keys) {
                    try { $req.Headers[$k] = $Headers[$k] } catch {}
                }
                
                # Write body for POST
                if ($methodToUse -eq 'POST' -and $Body) {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Body)
                    $req.ContentType   = 'application/json; charset=utf-8'
                    $req.ContentLength = $bytes.Length
                    $rs = $req.GetRequestStream()
                    $rs.Write($bytes, 0, $bytes.Length)
                    $rs.Close()
                }
                
                $resp = $null
                try {
                    $resp = [System.Net.HttpWebResponse]$req.GetResponse()
                }
                catch [System.Net.WebException] {
                    # HTTP errors still provide a Response object here
                    $resp = $_.Exception.Response
                    if (-not $resp) { throw }  # network/TLS/DNS etc.
                    }
                    
                    # Read body text (works on success + error)
                    $rawBody = $null
                    try {
                        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
                        $rawBody = $sr.ReadToEnd()
                        $sr.Close()
                    } catch {}
                    
                    # Convert to the shape your code expects
                    $statusCode  = [int]$resp.StatusCode
                    $statusDesc  = $resp.StatusDescription
                    $respUri     = $resp.ResponseUri
                    $contentType = $resp.ContentType
                    $bodyText    = $rawBody
                    
                    # Error? Try parse JSON and throw so your existing catch block formats it
                    if ($statusCode -lt 200 -or $statusCode -ge 300) {
                        $ErrResp = $null
                        if ($bodyText -and $bodyText.TrimStart().StartsWith('{')) {
                            try { $ErrResp = $bodyText | ConvertFrom-Json } catch { $ErrResp = $null }
                        }
                        
                        # Throw a simple exception; your existing catch will now have status/body populated
                        throw "HTTP $statusCode $statusDesc"
                    }
                    
                    # Success path
                    $items = $bodyText | ConvertFrom-Json

                $SetURI = $items.PageDetails.NextPageUrl

                if ($Base) {
                    $items
                    break
                }

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
                        if ($URL) {
                            $item | Get-AutotaskEntityURL -Entity $resource
                        } else {
                            $item
                        }
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
                        if ($URL) {
                            $item | Get-AutotaskEntityURL -Entity $resource
                        } else {
                            $item
                        }
                    }
                }
            } while ($null -ne $SetURI)
        }
        catch {         
            $ex   = $_.Exception
            $resp = $ex.Response

            if (-not $ErrResp -and $bodyText -and $bodyText.TrimStart().StartsWith('{')) {
                try { $ErrResp = $bodyText | ConvertFrom-Json } catch { $ErrResp = $null }
            }
            
            if ($resp -is [System.Net.HttpWebResponse]) {
                $statusCode  = [int]$resp.StatusCode
                $statusDesc  = $resp.StatusDescription
                $respUri     = $resp.ResponseUri
                $contentType = $resp.ContentType
                
                try {
                    $stream = $resp.GetResponseStream()
                    if ($stream) {
                        # If the API returns a compressed error payload, decompress it before reading
                        $encoding = $null
                        try { $encoding = $resp.Headers['Content-Encoding'] } catch {}
                        
                        switch -Regex ($encoding) {
                            'gzip' {
                                $stream = New-Object System.IO.Compression.GZipStream(
                                    $stream, [System.IO.Compression.CompressionMode]::Decompress
                                    )
                                }
                                'deflate' {
                                    $stream = New-Object System.IO.Compression.DeflateStream(
                                        $stream, [System.IO.Compression.CompressionMode]::Decompress
                                        )
                                    }
                                }
                                
                                $reader   = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
                                $bodyText = $reader.ReadToEnd()
                                $reader.Close()
                            }
                        }
                        catch {
                            # ignore read failures, fall back to generic message
                            }
                    # Try parse JSON error body if present
                    if ($bodyText -and $bodyText.TrimStart().StartsWith('{')) {
                        try {
                            $ErrResp = $bodyText | ConvertFrom-Json
                        }
                        catch {
                            $ErrResp = $null
                        }
                    }
                }

    # 401 Error - Possible bad auth or incorrect permissions
    if ($statusCode -eq 401) {
        $401msg = ("Autotask API authentication/authorisation failed (HTTP 401 {0}) when calling '{1}'. " +
                     "Check the credentials and base URI configured via Add-AutotaskAPIAuth.") -f $statusDesc, $respUri
        Write-Error $401msg
        return
    }

    # 404 Error or HTML response - Indicative of an outage (Kaseya use a custom 404 page for scheduled maintenance windows)
    if ($statusCode -eq 404 -or $contentType -eq 'text/html') {
        $snippet = $null
        if ($bodyText) {
            $len     = [Math]::Min(300, $bodyText.Length)
            $snippet = $bodyText.Substring(0, $len)
        }
        $404msg = ("Autotask API returned HTTP 404 (HTML) for '{0}'. " +
        "This may indicate that the Autotask service or route is unavailable, or the BaseURI is incorrect. " +
        "HTML response snippet (if received) `n{1}") -f $respUri, $snippet
        Write-Error $404msg
        return
    }

    # JSON error payload with .errors
    if ($ErrResp -and $ErrResp.errors) {
        Write-Error ("Autotask API call to '{0}' failed with HTTP {1} {2}.`n`n==== API ERRORS ====`n{3}" -f `
                     $respUri, $statusCode, $statusDesc, ($ErrResp.errors -join '; '))
        return
    }

    # Fallback: show status, URL, and first few hundred chars of body if present
    if ($statusCode) {
        if ($bodyText) {
            $len     = [Math]::Min(300, $bodyText.Length)
            $snippet = $bodyText.Substring(0, $len)
            Write-Error ("Autotask API call to '{0}' failed with HTTP {1} {2}. " +
                         "Response body (first {3} chars):`n{4}") -f `
                        $respUri, $statusCode, $statusDesc, $len, $snippet
        }
        else {
            Write-Error ("Autotask API call to '{0}' failed with HTTP {1} {2}. {3}" -f `
                         $respUri, $statusCode, $statusDesc, $ex.Message)
        }
    }
    else {
        # No HTTP response object received at all
        Write-Error "Connecting to the Autotask API failed. $($ex.Message)"
    }
}

    }
}