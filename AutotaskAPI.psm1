$script:WarningPreference     = 'Continue'
$script:InformationPreference = 'Continue'
$Public  = @(Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue) + @(Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue)
foreach ($import in @($Public))
{
    try
    {
        . $import.FullName
    }
    catch
    {
        Write-Error -Message "Failed to import function $($import.FullName): $_"
    }
}
Set-Alias get-atr Get-AutotaskAPIResource
Set-Alias set-atr Set-AutotaskAPIResource
Set-Alias new-atr New-AutotaskAPIResource
Set-Alias remove-atr Remove-AutotaskAPIResource