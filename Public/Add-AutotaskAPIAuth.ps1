<#
.SYNOPSIS
    Sets the API authentication information.
.DESCRIPTION
 Sets the API Authentication headers, and automatically tries to find the correct URL based on your username.
.EXAMPLE
    PS C:\> Add-AutotaskAPIAuth -ApiIntegrationcode 'ABCDEFGH00100244MMEEE333' -credentials $Creds
    Creates header information for Autotask API.
.INPUTS
    -ApiIntegrationcode: The API Integration code found in Autotask
    -Credentials : The API user credentials
.OUTPUTS
    none
.NOTES
    Function might be changed at release of new API.
#>
function Add-AutotaskAPIAuth (
    [Parameter(Mandatory = $true)]$ApiIntegrationcode,
    [Parameter(Mandatory = $true)][PSCredential]$credentials
) {
    #We convert the securestring...back to a normal string :'( Why basic auth AT? why?!
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credentials.Password)
    $Secret = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
    $Script:AutotaskAuthHeader = @{
        'ApiIntegrationcode' = $ApiIntegrationcode
        'UserName'           = $credentials.UserName
        'Secret'             = $secret
        'Content-Type'       = 'application/json'
    }
    write-host "Retrieving webservices URI based on username" -ForegroundColor Green
    try {
        $Version = (Invoke-WebRequest -UseBasicParsing -Uri "https://webservices2.autotask.net/atservicesrest/versioninformation").apiversions | select-object -last 1
        $AutotaskBaseURI = Invoke-WebRequest -UseBasicParsing -Uri "https://webservices2.autotask.net/atservicesrest/$($Version)/zoneInformation?user=$($Script:AutotaskAuthHeader.UserName)"
        $BaseURI = $AutotaskBaseURI.url
        write-host "Setting AutotaskBaseURI to $BaseURI using version $Version" -ForegroundColor green
        Add-AutotaskBaseURI -BaseURI $BaseURI
    }
    catch {
        write-host "Could not Retrieve baseuri. E-mail address might be incorrect. You can manually add the baseuri via the Add-AutotaskBaseURI cmdlet. $($_.Exception.Message)" -ForegroundColor red
    }

    $testUri = "$BaseURI$Version/Version"
    Write-Host "Validating Autotask API authentication against $testUri"

    try {
        $null = Invoke-WebRequest -UseBasicParsing -Uri $testUri -Headers $Script:AutotaskAuthHeader -Method Get -TimeoutSec 20
        Write-Host "Autotask API authentication validated successfully."
    }
    catch {
        $ex   = $_.Exception
        $resp = $ex.Response

        if ($resp -is [System.Net.HttpWebResponse]) {
            $status = [int]$resp.StatusCode
            $desc   = $resp.StatusDescription

            if ($status -eq 401) {
                throw "Autotask API authentication failed (HTTP 401 $desc) when validating against $testUri. Check UserName, ApiIntegrationCode and Secret."
            }
            else {
                throw "Autotask API validation call to $testUri failed with HTTP $status $desc. $($ex.Message)"
            }
        }
        else {
            throw "Autotask API validation call to $testUri failed: $($ex.Message)"
        }
    }

}