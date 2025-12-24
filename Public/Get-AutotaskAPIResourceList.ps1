<#
.SYNOPSIS
    Gets a list of available resources in the API.
.DESCRIPTION
    Gets a list of available resources in the API. If the list can't be retrieved locally, a Swagger URL can be specified.
.EXAMPLE
    PS C:\>  Get-AutotaskAPIResourceList
    Outputs all available resources

    PS C:\>  Get-AutotaskAPIResourceList -SwaggerUrl 'https://webservicesXX.autotask.net/atservicesrest/swagger/v1/swagger.json'
    Outputs all available resources from the Swagger URL provided

.INPUTS
    none
.OUTPUTS
    Resource List
.NOTES
    None
#>
function Get-AutotaskAPIResourceList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string] $SwaggerUrl # e.g. 'https://webservicesXX.autotask.net/atservicesrest/swagger/v1/swagger.json'
    )

    if (-not $Script:AutotaskBaseURI -or -not $Script:AutotaskAuthHeader) {
        Write-Warning "You must run Add-AutotaskAPIAuth first."
        return
    }

    $headers = $Script:AutotaskAuthHeader

    $fromQueries = $false
    $entities = @()

    # Use module-parsed Swagger first
    if ($Script:Queries) {
        try {
            $entities =
                $Script:Queries |
                Where-Object { $_.Get } |
                Select-Object -Property @{
                    n='Name';e={$_.Get}
                }, @{
                    n='Path';e={$_.name}
                } |
                Sort-Object Name -Unique
            $fromQueries = $true
        } catch { }
    }

    # Otherwise (or if -SwaggerUrl supplied), read Swagger JSON directly from supplied URL
    if ($SwaggerUrl -and (-not $fromQueries -or $PSBoundParameters.ContainsKey('SwaggerUrl'))) {
        try {
            $spec = Invoke-WebRequest -Method GET -Uri $SwaggerUrl -Headers $headers -UseBasicParsing
            $names = $spec.paths.PSObject.Properties.Name |
                     ForEach-Object { ($_ -split '/')[1] } |
                     Where-Object { $_ -and ($_ -notmatch '^{') } |
                     Select-Object -Unique
            $entities = $names | ForEach-Object {
                [pscustomobject]@{ Name = $_; Path = "/$_" }
            } | Sort-Object Name
        } catch {
            Write-Warning "Failed to read Swagger at $SwaggerUrl ($($_.Exception.Message))."
        }
    }

    if (-not $entities -or $entities.Count -eq 0) {
        # Fallback
        $entities = @('Tickets','Companies','Contacts','Resources','Projects','Tasks',
                      'TimeEntries','Departments','Contracts','ConfigurationItems',
                      'Quotes','Opportunities','SubscriptionPeriods','Services') |
                    Sort-Object | ForEach-Object { [pscustomobject]@{Name=$_; Path="/$_"} }
    }

    $entities
}