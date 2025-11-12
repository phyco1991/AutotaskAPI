<#
.SYNOPSIS
    Sets the current API URL
.DESCRIPTION
 Sets the API URL to the selected URL. URLs parameters can be tab-completed.
.EXAMPLE
    PS C:\> Add-AutotaskBaseURI -BaseURI https://webservices2.autotask.net/atservicesrest
    Sets the autotask BaseURI to https://webservices2.autotask.net/atservicesrest
.INPUTS
    -BaseURI: examples of some working URLs in the following list:
        "https://webservices2.autotask.net/atservicesrest",
        "https://webservices11.autotask.net/atservicesrest",
        "https://webservices1.autotask.net/atservicesrest",
        "https://webservices17.autotask.net/atservicesrest",
        "https://webservices3.autotask.net/atservicesrest",
        "https://webservices14.autotask.net/atservicesrest",
        "https://webservices5.autotask.net/atservicesrest",
        "https://webservices15.autotask.net/atservicesrest",
        "https://webservices4.autotask.net/atservicesrest",
        "https://webservices16.autotask.net/atservicesrest",
        "https://webservices6.autotask.net/atservicesrest",
        "https://prde.autotask.net/atservicesrest",
        "https://pres.autotask.net/atservicesrest",
        "https://webservices18.autotask.net/atservicesrest",
        "https://webservices19.autotask.net/atservicesrest",
        "https://webservices12.autotask.net/atservicesrest",
        "https://webservices22.autotask.net/atservicesrest",
        "https://webservices24.autotask.net/atservicesrest",
        "https://webservices26.autotask.net/atservicesrest",
        "https://webservices28.autotask.net/atservicesrest"
.OUTPUTS
    none
.NOTES
    Each URI represents either a geographic zone or a sandbox/development instance of Autotask.
    You can generally work out the Web Services URI from the URL you use to access the Autotask GUI (i.e. https://ww6.autotask.net would be https://webservices6.autotask.net)
#>
function Add-AutotaskBaseURI {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^https://(webservices\d+|prde|pres)\.autotask\.net/ATServicesRest(/V\d+\.\d+)?/?$')]
        [string]$BaseURI
    )

    $root = $BaseURI.TrimEnd('/')
    $root = $root -replace '/V\d+\.\d+$', ''   # strip trailing version if present
    $Script:AutotaskBaseURI = $root

    Write-Host "Setting API resource parameters. This may take a moment." -ForegroundColor Green

    $Script:GetParameter       = New-ResourceDynamicParameter -Parametertype "Get"
    $Script:PatchParameter     = New-ResourceDynamicParameter -Parametertype "Patch"
    $Script:DeleteParameter    = New-ResourceDynamicParameter -Parametertype "Delete"
    $Script:POSTParameter      = New-ResourceDynamicParameter -Parametertype "Post"
    $Script:PostPatchParameter = New-ResourceDynamicParameter -Parametertype "Post Patch"
}