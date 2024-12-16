param(
    [string]$ParametersJsonBase64,
    [string]$WindowsLocalAdminUserName,
    [string]$WindowsLocalAdminPasswordBase64)

$ErrorActionPreference = 'Stop'

Write-Output "Hello from bootstrap."
Write-Output "WindowsLocalAdminUserName: $WindowsLocalAdminUserName"
