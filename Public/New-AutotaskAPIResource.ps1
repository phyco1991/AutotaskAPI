<#
.SYNOPSIS
    Creates a new resource in the API to the supplied object.
.DESCRIPTION
 Creates resource in the API to the supplied object. Uses the Post method.  Null values will not be published.
.EXAMPLE
    PS C:\>  New-AutotaskAPIResource -resource companies -body $body
    Creates a new company using the body $body

.INPUTS
    -Resource: Which resource to find. Tab completion is available.
    -Body: Body created based on the model of the API.  Accepts pipeline input.
   
.OUTPUTS
    none
.NOTES
    So the API actually contains a method to get the fields for a body. Thinking of using that instead. 
    /atservicesrest/v1.0/EntityName/entityInformation/field
#>
function New-AutotaskAPIResource {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]$Body,
        [Parameter(Mandatory = $false)][String]$ParentId
    )
    DynamicParam {
        $Script:POSTParameter
    }
    begin {
        if (!$Script:AutotaskAuthHeader -or !$Script:AutotaskBaseURI) {
            Write-Warning "You must first run Add-AutotaskAPIAuth before calling any other cmdlets" 
            break 
        }
        $resource = $PSBoundParameters.resource
        $headers = $Script:AutotaskAuthHeader
        # Resolve POST URL mapping; fall back to the resource name if no mapping exists
        $q = $Script:Queries | Where-Object { $_.Post -eq $resource } | Select-Object -First 1
        if ($q -and $q.Name) {
            $resourceUrl = ($q.Name -replace '/query','')
        }
        else {
            # Fallback: POST to /<Resource>
            $resourceUrl = $resource
        }
        # POST must not contain placeholders
        $resourceUrl = $resourceUrl -replace '/\{PARENTID\}', '' -replace '\{PARENTID\}', ''
        $resourceUrl = $resourceUrl -replace '/\{parentid\}', '' -replace '\{parentid\}', ''
        $resourceUrl = $resourceUrl -replace '/\{id\}', ''       -replace '\{id\}', ''
        $resourceUrl = $resourceUrl.TrimEnd('/')
    }
    
    process {
        if ($resource -like "*child*") {
            if (-not $ParentId) { throw "You must specify -ParentId when creating a child resource" }
            $resourceUrl = $resourceUrl -replace '\{parentid\}', $ParentId
            $resourceUrl = $resourceUrl -replace '\{PARENTID\}', $ParentId
        }

        $SendingBody = $body | ConvertTo-Json -Depth 10
        $body = [System.Text.Encoding]::UTF8.GetBytes($SendingBody)
        $resp        = $null
        $ErrResp     = $null
        $bodyText    = $null
        $statusCode  = $null
        $statusDesc  = $null
        $respUri     = $null
        $contentType = $null
        $base = $Script:AutotaskBaseURI.TrimEnd('/')
        $path = $resourceUrl.TrimStart('/')
        $setUri = "$base/$path"

        try {
    $resp = Invoke-WebRequest -Uri $setUri -UseBasicParsing -Headers $Headers -Method POST -Body $body -ContentType 'application/json'
    return ($resp.Content | ConvertFrom-Json)
}
catch {
    $ex = $_.Exception
    $resp = $ex.Response

    if ($resp -is [System.Net.HttpWebResponse]) {
        $statusCode  = [int]$resp.StatusCode
        $statusDesc  = $resp.StatusDescription
        $respUri     = $resp.ResponseUri
        $contentType = $resp.ContentType

        # Read response body
        try {
            $stream = $resp.GetResponseStream()
            if ($stream) {
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
        } catch {}

        # Only parse JSON if it actually looks like JSON
        if ($bodyText) {
            $trim = $bodyText.TrimStart()
            if ($trim.StartsWith('{') -or $trim.StartsWith('[')) {
                try { $ErrResp = $bodyText | ConvertFrom-Json } catch { $ErrResp = $null }
            }
        }

        # Always keep a snippet for diagnostics (500s often come back as HTML or plain text)
        if ($bodyText) {
            $len = [Math]::Min(1200, $bodyText.Length)
            $snippet = $bodyText.Substring(0, $len)
        } else {
            $snippet = $null
        }

        # Handle Error Responses
        if ($statusCode -ge 400) {
            Write-Error ("Autotask API call to '{0}' failed with HTTP {1} {2}. Response body (first {3} chars):`n{4}" -f `
            $respUri, $statusCode, $statusDesc, ($(if($snippet){$snippet.Length}else{0})), $snippet)
            return
        }

        # JSON error payload with .errors
        if ($ErrResp -and $ErrResp.errors) {
            Write-Error ("Autotask API call to '{0}' failed with HTTP {1} {2}.`n`n==== API ERRORS ====`n{3}" -f `
                        $respUri, $statusCode, $statusDesc, ($ErrResp.errors -join '; '))
            return
        }

        # Fallback snippet
        if ($bodyText) {
            $len     = [Math]::Min(300, $bodyText.Length)
            $snippet = $bodyText.Substring(0, $len)
            Write-Error (
                ("Autotask API call to '{0}' failed with HTTP {1} {2}. " +
                 "Response body (first {3} chars):`n{4}") -f `
                 $respUri, $statusCode, $statusDesc, $len, $snippet
            )
            return
        }

        Write-Error ("Autotask API call to '{0}' failed with HTTP {1} {2}. {3}" -f `
                    $respUri, $statusCode, $statusDesc, $ex.Message)
        return
    }

    # No HTTP response object received (DNS/TLS/network)
    Write-Error "Connecting to the Autotask API failed. $($ex.Message)"
    return
}
    }
}