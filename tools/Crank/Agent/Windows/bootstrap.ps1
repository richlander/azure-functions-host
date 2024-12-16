param(
    [string]$ParametersJsonBase64,
    [string]$WindowsLocalAdminUserName,
    [string]$WindowsLocalAdminPasswordBase64)

$ErrorActionPreference = 'Stop'

Write-Output "$WindowsLocalAdminUserName: $WindowsLocalAdminPasswordBase64"
Write-Output "ParametersJsonBase64: $ParametersJsonBase64"

