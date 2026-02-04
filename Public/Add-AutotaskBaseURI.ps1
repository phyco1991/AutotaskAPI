<#
.SYNOPSIS
    Sets the current API URL
.DESCRIPTION
 Sets the API URL to the selected URL. URLs parameters can be tab-completed.
.EXAMPLE
    PS C:\> Add-AutotaskBaseURI -BaseURI https://webservices2.autotask.net/atservicesrest
    Sets the autotask BaseURI to https://webservices2.autotask.net/atservicesrest
.INPUTS
    -BaseURI: examples of some working URL formats in the following list (anything between 1-29 should work):
        "https://webservices1.autotask.net/atservicesrest",
        "https://webservices29.autotask.net/atservicesrest",
        "https://prde.autotask.net/atservicesrest",
        "https://pres.autotask.net/atservicesrest"
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
        [ValidatePattern('(?i)^https://(webservices\d+|prde|pres)\.autotask\.net/atservicesrest(/V\d+\.\d+)?/?$')]
        [string]$BaseURI
    )

    $root = $BaseURI.Trim()
    $root = $BaseURI.TrimEnd('/')
    $root = $root -replace '(?i)/V\d+\.\d+$',''   # strip trailing version if present
    $Script:AutotaskBaseURI = $root

    Write-Host "Setting API resource parameters. This may take a moment." -ForegroundColor Green

    $Script:GetParameter       = New-ResourceDynamicParameter -Parametertype "Get"
    $Script:PatchParameter     = New-ResourceDynamicParameter -Parametertype "Patch"
    $Script:DeleteParameter    = New-ResourceDynamicParameter -Parametertype "Delete"
    $Script:POSTParameter      = New-ResourceDynamicParameter -Parametertype "Post"
    $Script:PostPatchParameter = New-ResourceDynamicParameter -Parametertype "Post Patch"
}