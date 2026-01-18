<#
.SYNOPSIS
    Helper function used by Get-AutotaskAPIResource to convert SQL style queries into JSON search operators
.DESCRIPTION
    Allows you to structure a search query similar to a SQL query, to simplify queries where there are multiple AND/OR operators.
.EXAMPLE
    PS C:\> Get-AutotaskAPIResource -Resource Tickets -Where "ticketType IN (1,2,3) AND status -ne 5"
.INPUTS
    none
.OUTPUTS
    none
.NOTES
    none
#>
function ConvertTo-SearchQueryFromSQL {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Where
    )

    # Tokeniser: identifiers, operators, strings, numbers, parens, commas, AND/OR
    $pattern = "(?<ws>\s+)|" +
           "(?<lpar>\()|(?<rpar>\))|(?<comma>,)|" +
           "(?<str>'[^']*'|""[^""]*"")|" +
           "(?<op>\b(?:and|or|eq|ne|gt|ge|lt|le|like|contains|in)\b|-(?:and|or|eq|ne|gt|ge|lt|le|like|contains))|" +
           "(?<num>[+-]?\d+(?:\.\d+)?)|" +
           "(?<id>[A-Za-z_][A-Za-z0-9_\.]*)"

           $rawTokens = New-Object System.Collections.Generic.List[string]
           $match = [regex]::Matches($Where, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
           foreach ($m in $match) {
            if ($m.Groups['ws'].Success) { continue }
            $rawTokens.Add($m.Value)
        }
        $rawTokens = $rawTokens.ToArray()
        Write-Verbose ("SQL-style query tokens: " + ($rawTokens -join ' | '))

        # Use script-scoped cursor so nested functions share the same index reliably
        $script:i = 0
        function Peek {
    if ($script:i -lt $rawTokens.Count) { 
        return $rawTokens[$script:i] 
    }
    return $null
}
function Next {
    $t = Peek
    $script:i++
    return $t
}

    function ToValue($tok) {
        $tok = $tok.Trim()
        if ($tok -match '^".*"$' -or $tok -match "^'.*'$") { return $tok.Substring(1, $tok.Length-2) }
        if ($tok -match '^[+-]?\d+$') { return [int]$tok }
        if ($tok -match '^[+-]?\d+\.\d+$') { return [double]$tok }
        return $tok
    }

    function MapOp($opTok, $val) {
        $op = $opTok.ToLowerInvariant()
        if ($op.StartsWith('-')) { $op = $op.Substring(1) }

        switch ($op) {
            'eq' { 'eq' }
            'ne' { 'noteq' }
            'gt' { 'gt' }
            'ge' { 'gte' }
            'lt' { 'lt' }
            'le' { 'lte' }
            'contains' { 'contains' }
            'in' { 'in' }
            'like' {
                # Translate PowerShell wildcard * into Autotask-friendly ops
                if ($val -is [string]) {
                    $s = $val
                    $starts = $s.StartsWith('*')
                    $ends   = $s.EndsWith('*')
                    if ($starts -and $ends) { return 'contains' }
                    if ($ends -and -not $starts) { return 'beginsWith' }
                    if ($starts -and -not $ends) { return 'endsWith' }
                }
                'contains'
            }
            default { throw "Unsupported operator: $opTok" }
        }
    }

    function ParseComparison {
        $field = Next
        if (-not $field) { throw "Unexpected end of query (expected field name)." }

        $opTok = Next
        if (-not $opTok) { throw "Unexpected end of query (expected operator after '$field')." }

        if ($opTok.ToLowerInvariant().TrimStart('-') -eq 'in') {
            if ((Peek) -ne '(') { throw "Expected '(' after IN." }
            [void](Next) # '('

            $vals = @()
            while ($true) {
                $t = Peek
                if (-not $t) { throw "Unexpected end of query inside IN(...)." }
                if ($t -eq ')') { [void](Next); break }
                if ($t -eq ',') { [void](Next); continue }
                $vals += ToValue (Next)
            }

            return @{ op='in'; field=$field; value=@($vals) }
        }

        $valTok = Next
        if (-not $valTok) { throw "Unexpected end of query (expected value after '$field $opTok')." }

        $val = ToValue $valTok
        $op  = MapOp $opTok $val

        return @{ op=$op; field=$field; value=$val }
    }

    function ParseFactor {
        if ((Peek) -eq '(') {
            [void](Next)
            $node = ParseExpr
            if ((Peek) -ne ')') { throw "Expected ')'" }
            [void](Next)
            return $node
        }
        return ParseComparison
    }

    function ParseTerm {
        $left = ParseFactor
        while ($true) {
            $t = Peek
            if ($t -and ($t.ToUpperInvariant() -eq 'AND' -or $t.ToLowerInvariant() -eq '-and')) {
                [void](Next)
                $right = ParseFactor
                if ($left.op -eq 'and' -and $left.items) { $left.items += @($right) }
                else { $left = @{ op='and'; items=@($left, $right) } }
            } else { break }
        }
        $left
    }

    function ParseExpr {
        $left = ParseTerm
        while ($true) {
            $t = Peek
            if ($t -and ($t.ToUpperInvariant() -eq 'OR' -or $t.ToLowerInvariant() -eq '-or')) {
                [void](Next)
                $right = ParseTerm
                if ($left.op -eq 'or' -and $left.items) { $left.items += @($right) }
                else { $left = @{ op='or'; items=@($left, $right) } }
            } else { break }
        }
        $left
    }

    $tree = ParseExpr
    if ($i -lt $rawTokens.Count) { throw "Unexpected token near: '$($rawTokens[$i])'" }

    @{ filter = @($tree) } | ConvertTo-Json -Compress -Depth 10
}