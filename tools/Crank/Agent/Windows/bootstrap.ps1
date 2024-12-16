param(
    [string]$ParametersJsonBase64,
    [string]$WindowsLocalAdminUserName,
    [string]$WindowsLocalAdminPasswordBase64)

$ErrorActionPreference = 'Stop'

function Clone-Repository {
    param (
        [string]$repoUrl,
        [string]$branch,
        [string]$clonePath
    )

    if (-not (Test-Path -Path $clonePath)) {
        New-Item -ItemType Directory -Path $clonePath -Force
    }
    git clone --branch $branch $repoUrl $clonePath
}

# Install chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
$chocoCmd = "$env:ProgramData\chocolatey\bin\choco.exe"

& $chocoCmd install -y git
$env:PATH += ";$env:ProgramFiles\Git\cmd"

Write-Output "INSTALLED GIT."

& $chocoCmd install -y powershell-core
$env:PATH += ";$env:ProgramFiles\PowerShell\7"

& $chocoCmd install -y sysinternals

Write-Host "INSTALLED sysinternals."

# Clone azure-functions-host repo
Clone-Repository -repoUrl "https://github.com/Azure/azure-functions-host.git" -branch "shkr/crank" -clonePath "C:\github\azure-functions-host"

Write-Host "Cloned host repo"


# Setup Crank agent
$plaintextPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($WindowsLocalAdminPasswordBase64))

psexec -accepteula -h -u $WindowsLocalAdminUserName -p $plaintextPassword `
    pwsh.exe -NoProfile -NonInteractive `
    -File "C:\github\azure-functions-host\tools\Crank\Agent\setup-crank-agent-raw.ps1" `
    -ParametersJsonBase64 $ParametersJsonBase64 `
    -WindowsLocalAdminUserName $WindowsLocalAdminUserName `
    -WindowsLocalAdminPasswordBase64 $WindowsLocalAdminPasswordBase64 `
    -Verbose

if (-not $?) {
    throw "psexec exit code: $LASTEXITCODE"
}
