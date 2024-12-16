param(
    [string]$ParametersJsonBase64,
    [string]$WindowsLocalAdminUserName,
    [string]$WindowsLocalAdminPasswordBase64)

$ErrorActionPreference = 'Stop'

Write-Output "HELLO FROM BOOTSTRAP!"

try {
    # Install chocolatey
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    $chocoCmd = "$env:ProgramData\chocolatey\bin\choco.exe"
    Write-Output "Chocolatey installed successfully."
} catch {
    Write-Error "Failed to install Chocolatey: $_"
}

try {
    & $chocoCmd install -y git
    $env:PATH += ";$env:ProgramFiles\Git\cmd"
    Write-Output "Git installed successfully."
} catch {
    Write-Error "Failed to install Git: $_"
}

try {
    & $chocoCmd install -y powershell-core
    $env:PATH += ";$env:ProgramFiles\PowerShell\7"
    Write-Output "PowerShell Core installed successfully."
} catch {
    exit 1
}

try {
    & $chocoCmd install -y sysinternals
    Write-Output "Sysinternals installed successfully."
} catch {
    Write-Error "Failed to install Sysinternals: $_"
}


