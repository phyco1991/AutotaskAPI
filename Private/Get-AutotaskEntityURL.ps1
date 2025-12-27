<#
.SYNOPSIS
    Helper function used by Get-AutotaskAPIResource to resolve URLs and add to the body output for compatible Autotask entity queries
.DESCRIPTION
    Adds a URL to the GUI of your Autotask instance to the body output of any queries through specifying the '-URL' parameter on the Get-AutotaskAPIResource function.
.EXAMPLE
    PS C:\> Get-AutotaskAPIResource -Resource Tickets -ID 12345678 -URL
    Provides a URL for the matching ticket in the form of 'https://ww*.autotask.net/Autotask/AutotaskExtend/ExecuteCommand.aspx?Code=OpenTicketDetail&TicketID=12345678'
.INPUTS
    none
.OUTPUTS
    none
.NOTES
    none
#>
function Get-AutotaskEntityURL {
    [CmdletBinding()]
    param(
        # The objects returned from Get-AutotaskAPIResource
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [psobject]$InputObject,

        # Autotask entity name (matches -Resource values)
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'Tickets',
            'ConfigurationItems',
            'Contacts',
            'Companies',
            'Contracts',
            'Projects',
            'Opportunities',
            'SalesOrders',
            'Tasks'
        )]
        [string]$Entity,

        # Which property to read the ID from
        [Parameter(Mandatory = $false)]
        [string]$IdProperty = 'id',

        # Where to store the generated link
        [Parameter(Mandatory = $false)]
        [string]$UrlProperty = 'AutotaskUrl'
    )

    begin {
        if (-not $Script:AutotaskBaseURI) {
            throw "ERROR: Autotask base URI not set. Run Add-AutotaskAPIAuth first."
        }

        # Convert API base host to GUI host
        $apiHost = ([uri]$Script:AutotaskBaseURI).Host
        $uiHost  = if ($apiHost -match '^webservices(\d+)\.autotask\.net$') { "ww$($matches[1]).autotask.net" } else { $apiHost }
        $uiBase  = "https://$uiHost/Autotask/AutotaskExtend/ExecuteCommand.aspx"

        # Map entities to ExecuteCommand patterns
        $script:AT_ExecuteCommandMap = @{
            Tickets            = @{ Code = 'OpenTicketDetail';     Param = 'TicketID' }
            ConfigurationItems = @{ Code = 'OpenInstalledProduct'; Param = 'InstalledProductID' }
            Contacts           = @{ Code = 'OpenContact';          Param = 'ContactID' }
            Companies          = @{ Code = 'OpenAccount';          Param = 'AccountID' }          # Company = Account in Autotask
            Contracts          = @{ Code = 'OpenContract';         Param = 'ContractID' }
            Projects           = @{ Code = 'OpenProject';          Param = 'ProjectID' }
            Opportunities      = @{ Code = 'OpenOpportunity';      Param = 'OpportunityID' }
            SalesOrders        = @{ Code = 'OpenSalesOrder';       Param = 'SalesOrderID' }
            Tasks              = @{ Code = 'OpenTaskDetail';       Param = 'TaskID' }
        }

        $map = $script:AT_ExecuteCommandMap[$Entity]
        if (-not $map) { throw "ERROR: No ExecuteCommand mapping defined for resource '$Entity'. You cannot use the -URL parameter here." }
    }

    process {
        $obj = $InputObject

        # Get the ID value (support both id and Id etc.)
        $idProp = $obj.PSObject.Properties |
            Where-Object { $_.Name -ieq $IdProperty } |
            Select-Object -First 1

        if (-not $idProp -or -not $idProp.Value) {
            # No ID present, just pass through unchanged
            return $obj
        }

        $id = $idProp.Value

        $link = '{0}?Code={1}&{2}={3}' -f $uiBase, $map.Code, $map.Param, $id

        # Add or overwrite the URL property
        $obj | Add-Member -NotePropertyName $UrlProperty -NotePropertyValue $link -Force

        $obj
    }
}