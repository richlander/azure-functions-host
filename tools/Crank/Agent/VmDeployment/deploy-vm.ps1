#!/usr/bin/env pwsh

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]
    $SubscriptionName,

    [Parameter(Mandatory = $true)]
    [string]
    $BaseName,

    [string]
    $NamePostfix = '',

    [Parameter(Mandatory = $true)]
    [ValidateSet('Linux', 'Windows')]
    $OsType,

    [switch]
    $Docker,

    [string]
    $VmSize = 'Standard_E2s_v3',

    [string]
    $OsDiskType = 'Premium_LRS',

    [string]
    $Location = 'West Central US',

    [string]
    $UserName = 'Functions',

    [string]
    $KeyVaultName = 'functions-perf-crank-kv',

    [string]
    $VaultResourceGroupName = 'FunctionsCrank',

    [string]
    $VaultSubscriptionName = 'Functions Build Infra'
)

$ErrorActionPreference = 'Stop'

# Retrieve the Key Vault secret
# Determine the secret name based on the OS type
if ($OsType -eq 'Windows') {
    $secretName = 'CrankAgentVMAdminPassword'
} else {
    $secretName = 'LinuxCrankAgentVmSshKey-Public'
}
$vaultSubscriptionId = (Get-AzSubscription -SubscriptionName $VaultSubscriptionName).Id
$keyVault = Get-AzKeyVault -SubscriptionId $vaultSubscriptionId -ResourceGroupName $VaultResourceGroupName -VaultName $KeyVaultName

if (-not $keyVault) {
    throw "Key Vault '$KeyVaultName' not found in resource group '$VaultResourceGroupName' and SubscriptionId '$vaultSubscriptionId'"
}

$secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $secretName -AsPlainText

if (-not $secret) {
    throw "Secret '$secretName' not found in Key Vault '$KeyVaultName'."
}

$resourceGroupName = "FunctionsCrank-$OsType-$BaseName$NamePostfix"
$vmName = "crank-$BaseName$NamePostfix".ToLower()

# VM name must be less than 16 characters. If greater than 15, take the last 15 characters
if ($vmName.Length -gt 15) {
    Write-Warning "VM name '$vmName' is greater than 15 characters. Truncating to 15 characters."
    $vmName = $vmName.Substring($vmName.Length - 15)
}

Write-Verbose "Creating VM '$vmName' in resource group '$resourceGroupName'"

Set-AzContext -Subscription $SubscriptionName | Out-Null

New-AzResourceGroup -Name $resourceGroupName -Location $Location | Out-Null

$adminPassword = $secret
$adminPasswordBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($adminPassword))

$customScriptParameters = @{
    CrankBranch = 'main'
    Docker = $Docker.IsPresent
}

# Convert custom script parameters to JSON and then to base64
$parametersJson = $customScriptParameters | ConvertTo-Json -Compress
$parametersJsonBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($parametersJson))

$parameters = @{
    location = $Location
    vmName = $vmName
    adminUsername = $UserName
    adminPassword = $adminPassword
    windowsLocalAdminUserName = $UserName
    windowsLocalAdminPasswordBase64 = $adminPasswordBase64
    parametersJsonBase64 = $parametersJsonBase64
}

# Retry logic for deployment
$maxRetries = 3
$retryCount = 0
$retryDelay = 30

while ($retryCount -lt $maxRetries) {
    try {
        # Deploy the resources using the Bicep template
        New-AzResourceGroupDeployment `
            -ResourceGroupName $resourceGroupName `
            -TemplateFile "$PSScriptRoot\create-resources.bicep" `
            -TemplateParameterObject $parameters `
            -Verbose
        break
    } catch {
        Write-Error "Deployment failed: $_"
        $retryCount++
        if ($retryCount -lt $maxRetries) {
            Write-Verbose "Retrying deployment in $retryDelay seconds... (Attempt $retryCount of $maxRetries)"
            Start-Sleep -Seconds $retryDelay
        } else {
            throw "Deployment failed after $maxRetries attempts."
        }
    }
}

Write-Verbose 'Restarting the VM...'
Restart-AzVM -ResourceGroupName $resourceGroupName -Name $vmName | Out-Null
Start-Sleep -Seconds 30

Write-Host "The crank VM is ready: $vmName"
