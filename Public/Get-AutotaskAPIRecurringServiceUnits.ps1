<#
.SYNOPSIS
    Used to gather output of recurring services
.DESCRIPTION
    TBA
.EXAMPLE
    PS C:\> Get-AutotaskRecurringServiceUnits | Select-Object CompanyName, ContractName, ServiceName, ServiceCode, Units, PeriodType
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

        # Only return rows where the ContractServiceUnits row has changed since this time
        [datetime]$ChangedSince,

        # If set, PeriodType (and other picklists on Services) will be labels instead of numeric values
        [switch]$PeriodTypeAsLabel,

        # Detail: one row per ContractServiceUnits entry (default)
        # Summary: grouped by Company + ServiceCode (+ PeriodType), Units summed
        [ValidateSet('Detail', 'Summary')]
        [string]$Mode = 'Detail'
    )

    Write-Verbose "Loading contracts..."

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

    # Contract category
    if ($ContractCategoryId) {
        $contractFilter += @{
            field = 'contractCategory'
            op    = 'eq'
            value = $ContractCategoryId
        }
    }

    if ($CompanyId) {
        foreach ($cid in $CompanyId) {
            $contractFilter += @{
                field = 'companyID'
                op    = 'eq'
                value = $cid
            }
        }
    }

    if ($ContractId) {
        foreach ($id in $ContractId) {
            $contractFilter += @{
                field = 'id'
                op    = 'eq'
                value = $id
            }
        }
    }

    if (-not $contractFilter) {
        Write-Verbose "No contract filter supplied; getting all contracts (this is unlikely with current defaults)."
        $contracts = Get-AutotaskAPIResource -Resource Contracts
    }
    else {
        $contractQuery = @{ filter = $contractFilter } | ConvertTo-Json -Compress
        $contracts     = Get-AutotaskAPIResource -Resource Contracts -SearchQuery $contractQuery
    }

    if (-not $contracts) {
        Write-Verbose "No contracts returned, exiting."
        return
    }

    # Index contracts by ID for quick lookup
    $contractIndex = @{}
    foreach ($c in $contracts) {
        $contractIndex[$c.id] = $c
    }

    $contractIds = $contracts.id | Sort-Object -Unique
    Write-Verbose "Found $($contractIds.Count) contracts."

    # Map companyID from contracts to companyName

    Write-Verbose "Loading Companies for referenced contracts..."
    $companyIds = $contracts.companyID | Sort-Object -Unique
    $companies  = @()
    
    foreach ($cid in $companyIds) {
        $companies += Get-AutotaskAPIResource -Resource Companies -SimpleSearch "id eq $cid"
    }
    $companyIndex = @{}
    foreach ($co in $companies) {
        $companyIndex[$co.id] = $co
    }
    Write-Verbose "Found $($companies.Count) Companies."

    # Get ContractServices for the contracts

    Write-Verbose "Loading ContractServices..."

    $allContractServices = @()

    foreach ($cid in $contractIds) {
        $allContractServices += Get-AutotaskAPIResource -Resource ContractServices `
            -SimpleSearch "contractID eq $cid"
    }

    if (-not $allContractServices) {
        Write-Verbose "No ContractServices found, exiting."
        return
    }

    $csIndex = @{}
    foreach ($cs in $allContractServices) {
        $csIndex[$cs.id] = $cs
    }

    Write-Verbose "Found $($allContractServices.Count) ContractServices rows."

    # Get ContractServiceUnits for the ContractServices

    Write-Verbose "Loading ContractServiceUnits..."

    $allUnits = @()
    $csIds    = $allContractServices.id | Sort-Object -Unique

    # Autotask "last modified" field name for ContractServiceUnits.
    $lastModifiedField = 'lastActivityDate'

    # Format ChangedSince for the API (ISO 8601)
    $changedSinceString = $null
    if ($ChangedSince) {
        $changedSinceString = $ChangedSince.ToUniversalTime().ToString("o")
        Write-Verbose "Filtering ContractServiceUnits where $lastModifiedField >= $changedSinceString"
    }

    foreach ($csid in $csIds) {
        if ($changedSinceString) {
            # Use SearchQuery to AND contractServiceID + lastActivityDate >= ChangedSince
            $filter = @(
                @{
                    field = 'contractServiceID'
                    op    = 'eq'
                    value = $csid
                },
                @{
                    field = $lastModifiedField
                    op    = 'gte'
                    value = $changedSinceString
                }
            )

            $search = @{ filter = $filter } | ConvertTo-Json -Compress

            $allUnits += Get-AutotaskAPIResource -Resource ContractServiceUnits -SearchQuery $search
        }
        else {
            # No delta filter – just pull all units for this ContractService
            $allUnits += Get-AutotaskAPIResource -Resource ContractServiceUnits `
                -SimpleSearch "contractServiceID eq $csid"
        }
    }

    if (-not $allUnits) {
        Write-Verbose "No ContractServiceUnits matched the criteria, exiting."
        return
    }

    Write-Verbose "Found $($allUnits.Count) ContractServiceUnits rows after filtering."

    # Get Services for the Service IDs referenced

    Write-Verbose "Loading Services..."

    $serviceIds = $allContractServices.serviceID | Sort-Object -Unique
    $services   = @()

    foreach ($sid in $serviceIds) {
        if ($PeriodTypeAsLabel) {
            $services += Get-AutotaskAPIResource -Resource Services `
                -SimpleSearch "id eq $sid" -ResolveLabels
        }
        else {
            $services += Get-AutotaskAPIResource -Resource Services `
                -SimpleSearch "id eq $sid"
        }
    }

    $serviceIndex = @{}
    foreach ($svc in $services) {
        $serviceIndex[$svc.id] = $svc
    }

    Write-Verbose "Found $($services.Count) Services rows."

    # Build detail rows in memory

    $detailRows = @()

    foreach ($u in $allUnits) {
        $cs = $csIndex[$u.contractServiceID]
        if (-not $cs) { continue }

        $contract = $contractIndex[$cs.contractID]
        $svc      = $serviceIndex[$cs.serviceID]
        $company  = $companyIndex[$contract.companyID]

        if (-not $contract -or -not $svc) { continue }

        $detailRows += [PSCustomObject]@{
            CompanyId      = $contract.companyID
            CompanyName    = $company.companyName
            ContractId     = $contract.id
            ContractName   = $contract.contractName
            ContractNumber = $contract.contractNumber

            ContractServiceId   = $cs.id
            ContractServiceName = $cs.serviceName

            ServiceId      = $svc.id
            ServiceName    = $svc.description
            ServiceCode    = $svc.manufacturerServiceProviderProductNumber

            PeriodType     = $svc.periodType   # numeric or label depending on -PeriodTypeAsLabel
            BillingCodeId  = $svc.billingCodeID

            Units          = $u.units
            EffectiveDate  = $u.effectiveDate
            LastActivity   = $u.$lastModifiedField
        }
    }

    if (-not $detailRows) {
        Write-Verbose "No detail rows built, exiting."
        return
    }

    # Output base on mode parameter (default to Detail)

    if ($Mode -eq 'Detail') {
        return $detailRows
    }

    # Summary mode: collapse to Company + ServiceCode (+ PeriodType),
    # summing Units and taking latest LastActivity.
    $grouped = $detailRows |
        Group-Object CompanyId, CompanyName, ServiceCode, ServiceName, PeriodType

    foreach ($g in $grouped) {
        $any = $g.Group | Select-Object -First 1

        $totalUnits  = ($g.Group | Measure-Object Units -Sum).Sum
        $lastAct     = ($g.Group | Measure-Object LastActivity -Maximum).Maximum

        [PSCustomObject]@{
            CompanyId    = $any.CompanyId
            CompanyName  = $any.CompanyName

            ServiceCode  = $any.ServiceCode
            ServiceName  = $any.ServiceName
            PeriodType   = $any.PeriodType

            TotalUnits   = $totalUnits
            LastActivity = $lastAct
        }
    }
}