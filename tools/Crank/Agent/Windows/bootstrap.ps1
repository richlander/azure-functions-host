param(
    [string]$ParametersJsonBase64,
    [string]$WindowsLocalAdminUserName,
    [string]$WindowsLocalAdminPasswordBase64
)

$ErrorActionPreference = 'Stop'

# Define the right to be granted
$right = "SeServiceLogonRight"

# Path to the temporary security template file
$templatePath = "C:\Temp\SecurityTemplate.inf"

# Create the security template file
@"
[Unicode]
Unicode=yes
[Version]
signature="\$CHICAGO\$"
Revision=1
[Privilege Rights]
$right = *$WindowsLocalAdminUserName
"@ | Out-File -FilePath $templatePath -Encoding Unicode

# Apply the security template
secedit /configure /db secedit.sdb /cfg $templatePath /areas USER_RIGHTS

# Clean up
Remove-Item -Path $templatePath

Write-Output "Logon as a service right granted to $WindowsLocalAdminUserName"

# Install chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
$chocoCmd = "$env:ProgramData\chocolatey\bin\choco.exe"

& $chocoCmd install -y git
$env:PATH += ";$env:ProgramFiles\Git\cmd"

& $chocoCmd install -y powershell-core
$env:PATH += ";$env:ProgramFiles\PowerShell\7"

& $chocoCmd install -y sysinternals --version 2024.12.16

# Clone azure-functions-host repo
$githubPath = 'C:\github'
New-Item -Path $githubPath -ItemType Directory
Set-Location -Path $githubPath
& git clone --single-branch --branch shkr/crank https://github.com/Azure/azure-functions-host.git
Set-Location -Path azure-functions-host

# Setup Crank agent
$plaintextPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($WindowsLocalAdminPasswordBase64))

# This is for debugging purposes only.
Write-Output "1.Username: $WindowsLocalAdminUserName Password: $plaintextPassword"
Write-Verbose "2.Username: $WindowsLocalAdminUserName Password: $plaintextPassword"
Set-Content -Path "C:\github\WindowsLocalAdmin.txt" -Value "Username: $WindowsLocalAdminUserName Password: $plaintextPassword"

psexec -accepteula -h -u $WindowsLocalAdminUserName -p $plaintextPassword `
    pwsh.exe -NoProfile -NonInteractive `
    -File "$githubPath\azure-functions-host\tools\Crank\Agent\setup-crank-agent-raw.ps1" `
    -ParametersJsonBase64 $ParametersJsonBase64 `
    -WindowsLocalAdminUserName $WindowsLocalAdminUserName `
    -WindowsLocalAdminPasswordBase64 $WindowsLocalAdminPasswordBase64 `
    -Verbose

if (-not $?) {
    throw "psexec exit code: $LASTEXITCODE"
}
