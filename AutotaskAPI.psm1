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
Set-Alias get-at Get-AutotaskAPIResource
Set-Alias set-at Set-AutotaskAPIResource
Set-Alias new-at New-AutotaskAPIResource
Set-Alias delete-at Remove-AutotaskAPIResource