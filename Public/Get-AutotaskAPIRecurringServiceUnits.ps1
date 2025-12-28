<#
.SYNOPSIS
    Used to gather output of recurring services
.DESCRIPTION
    Queries the Contracts, ContractServices, and ContractServiceUnits entities to obtain all services against recurring service contracts including their quantity, period type, and other key information.
.EXAMPLE
    PS C:\> Get-AutotaskRecurringServiceUnits | Select CompanyName,ContractName,ServiceName,ServiceCode,Units,PeriodType
    Provides a list of all services on active Recurring Services contracts, with quantity and period type.
.INPUTS
    -CompanyId
    -ContractId
    -IncludeInactiveContracts
    -ContractCategoryId
    -ChangedSince
    -PeriodTypeAsLabel
    -Mode
.OUTPUTS
    none
.NOTES
    none
#>
function Get-AutotaskAPIRecurringServiceUnits {
    [CmdletBinding()]
    param(
        # Limit dataset to specific Company IDs
        [int[]]$CompanyId,

        # Limit dataset to specific Contract IDs
        [int[]]$ContractId,

        # Use this switch to include inactive contracts (only active are included by default)
        [switch]$IncludeInactiveContracts,

        # Contract category filter (single ID).
        [int]$ContractCategoryId,

        # Only return rows where the Contract row has changed since this time
        [datetime]$ChangedSince,

        # If set, PeriodType (and other picklists on Services) will be resolved as labels instead of raw numeric values
        [switch]$PeriodTypeAsLabel,

        # Detail: one row per ContractServiceUnits entry (default)
        # Summary: grouped by Company + ServiceName (+ PeriodType), Units summed
        [ValidateSet('Detail', 'Summary')]
        [string]$Mode = 'Detail'
    )

    if (-not $Script:AutotaskBaseURI -or -not $Script:AutotaskAuthHeader) {
        throw "You must run Add-AutotaskAPIAuth first."
    }

    Write-Information "Loading contracts..."

    # Get Contracts

    $contractFilter = @()

    # Limit to Recurring Service contracts
    $contractFilter += @{
        field = 'contractType'
        op    = 'eq'
        value = 7
    }

    # Contract status: default Active only
    if (-not $IncludeInactiveContracts.IsPresent) {
        $contractFilter += @{
            field = 'status'
            op    = 'eq'
            value = 1
        }
    }

    # Contract category (optional)
    if ($ContractCategoryId) {
        $contractFilter += @{
            field = 'contractCategory'
            op    = 'eq'
            value = $ContractCategoryId
        }
    }

    # Contract filter by CompanyId(s)
    if ($CompanyId) {
        foreach ($cid in $CompanyId) {
            $contractFilter += @{
                field = 'companyID'
                op    = 'eq'
                value = $cid
            }
        }
    }

    # Contract filter by ContractId(s)
    if ($ContractId) {
        foreach ($id in $ContractId) {
            $contractFilter += @{
                field = 'id'
                op    = 'eq'
                value = $id
            }
        }
    }

    # Contract delta filter (ChangedSince)
    if ($ChangedSince) {
        $changedSinceString = $ChangedSince.ToUniversalTime().ToString("o")
        $contractFilter += @{
            field = 'lastModifiedDateTime'
            op    = 'gte'
            value = $changedSinceString
        }
        Write-Verbose "Filtering Contracts where lastModifiedDateTime >= $changedSinceString"
    }

    if (-not $contractFilter) {
        Write-Verbose "No contract filter supplied; getting all contracts (this is unlikely with current defaults)."
        $contracts = Get-AutotaskAPIResource -Resource Contracts -Base -LocalTime
    }
    else {
        $contractQuery = @{ filter = $contractFilter } | ConvertTo-Json -Compress -Depth 10
        $contracts     = Get-AutotaskAPIResource -Resource Contracts -SearchQuery $contractQuery -LocalTime
    }

    if (-not $contracts) {
        Write-Warning "No contracts returned, exiting."
        return
    }

    # Index contracts by ID for quick lookup
    $contractIndex = @{}
    foreach ($c in $contracts) {
        $contractIndex[$c.id] = $c
    }

    $contractIds = $contracts.id | Sort-Object -Unique
    Write-Information "Found $($contractIds.Count) contracts."

    # Map companyID from contracts to companyName

    Write-Information "Loading Companies for referenced contracts..."
    $companyIds = $contracts.companyID | Sort-Object -Unique
    $companyQuery = @{
        filter = @(@{ field='id'; op='in'; value=@($companyIds) })
    } | ConvertTo-Json -Compress -Depth 10
    
    $companies = Get-AutotaskAPIResource -Resource Companies -SearchQuery $companyQuery

    $companyIndex = @{}
    foreach ($co in $companies) {
        $companyIndex[$co.id] = $co
    }

    Write-Information "Found $($companies.Count) Companies."

    # Get ContractServices for the contracts

    Write-Information "Loading ContractServices..."

    $allContractServices = @()

    $contractIds = $contracts.id | Sort-Object -Unique
    $csQuery = @{
        filter = @(@{ field='contractID'; op='in'; value=@($contractIds) })
    } | ConvertTo-Json -Compress -Depth 10
    
    $allContractServices = Get-AutotaskAPIResource -Resource ContractServices -SearchQuery $csQuery

    if (-not $allContractServices) {
        Write-Verbose "No ContractServices found, exiting."
        return
    }

    $csIndex = @{}
    foreach ($cs in $allContractServices) {
        $csIndex[$cs.id] = $cs
    }

    Write-Information "Found $($allContractServices.Count) ContractServices rows."

    # Get ContractServiceUnits for the ContractServices

    Write-Information "Loading ContractServiceUnits..."

    $allUnits = @()
    $csIds    = $allContractServices.id | Sort-Object -Unique

    $unitsQuery = @{
        filter = @(@{ field='contractServiceID'; op='in'; value=@($csIds) })
    } | ConvertTo-Json -Compress -Depth 10
    
    $allUnits = Get-AutotaskAPIResource -Resource ContractServiceUnits -SearchQuery $unitsQuery

    if (-not $allUnits) {
        Write-Verbose "No ContractServiceUnits matched the criteria, exiting."
        return
    }

    Write-Information "Found $($allUnits.Count) ContractServiceUnits rows after filtering."

    # Get Services for the Service IDs referenced

    Write-Information "Loading Services..."

    $serviceIds = $allContractServices.serviceID | Sort-Object -Unique
    $services   = @()

    $svcQuery = @{
        filter = @(@{ field='id'; op='in'; value=$serviceIds })
    } | ConvertTo-Json -Compress -Depth 10
    
    $services = if ($PeriodTypeAsLabel) {
        Get-AutotaskAPIResource -Resource Services -SearchQuery $svcQuery -ResolveLabels
    } else {
        Get-AutotaskAPIResource -Resource Services -SearchQuery $svcQuery
    }

    $serviceIndex = @{}
    foreach ($svc in $services) {
        $serviceIndex[$svc.id] = $svc
    }

    Write-Information "Found $($services.Count) Services rows."

    # Build detail rows in memory

    $detailRows = @()

    foreach ($u in $allUnits) {
        $cs = $csIndex[$u.contractServiceID]
        if (-not $cs) { continue }

        $contract = $contractIndex[$cs.contractID]
        if (-not $contract) { continue }

        $svc     = $serviceIndex[$cs.serviceID]
        $company = $companyIndex[$contract.companyID]

        if (-not $svc) { continue }

        $detailRows += [PSCustomObject]@{
            CompanyId      = $contract.companyID
            CompanyName    = $company.companyName
            ContractId     = $contract.id
            ContractName   = $contract.contractName
            LastActivity   = $contract.lastModifiedDateTime
            ContractServiceId   = $cs.id
            ContractServiceName = $cs.serviceName
            ServiceId      = $svc.id
            ServiceName    = $svc.name
            ServiceMPN     = $svc.manufacturerServiceProviderProductNumber
            PeriodType     = $svc.periodType   # numeric or label depending on -PeriodTypeAsLabel switch
            Units          = $u.units
            EffectiveDate  = $u.startDate
        }
    }

    if (-not $detailRows) {
        Write-Verbose "No detail rows built, exiting."
        return
    }

    # Output based on Mode parameter (default to Detail)

    if ($Mode -eq 'Detail') {
        return $detailRows
    }

    # Summary mode

    $grouped = $detailRows | Group-Object CompanyId, CompanyName, ContractId, ContractName, ServiceId, ServiceName, ServiceMPN, PeriodType, EffectiveDate

$summaryRows = foreach ($g in $grouped) {
    $any = $g.Group | Select-Object -First 1

    $qty = ($g.Group | Measure-Object -Property Units -Sum).Sum

    [PSCustomObject]@{
        CompanyName                    = $any.CompanyName
        ContractName                   = $any.ContractName
        ServiceName                    = $any.ServiceName
        ServiceMPN                     = $any.ServiceMPN
        ServiceQuantity                = $qty
        PeriodType                     = $any.PeriodType
        EffectiveDate                  = $any.EffectiveDate
    }
}

return $summaryRows | Sort-Object `
    CompanyName, ContractName, ServiceName, ServiceMPN, PeriodType
}