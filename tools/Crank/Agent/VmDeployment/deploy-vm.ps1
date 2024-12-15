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

    [Parameter(Mandatory = $true)]
    [string]
    $Password
)

$ErrorActionPreference = 'Stop'

$resourceGroupName = "FunctionsCrank-$OsType-$BaseName$NamePostfix"
$vmName = "func-crank-$BaseName$NamePostfix".ToLower()
Write-Verbose "Creating VM '$vmName' in resource group '$resourceGroupName'"

Set-AzContext -Subscription $SubscriptionName | Out-Null

New-AzResourceGroup -Name $resourceGroupName -Location $Location | Out-Null

$adminPasswordBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Password))

$customScriptParameters = @{
    CrankBranch = 'master'
    Docker = $Docker.IsPresent
}

# Convert custom script parameters to JSON and then to base64
$parametersJson = $customScriptParameters | ConvertTo-Json -Compress
$parametersJsonBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($parametersJson))

$parameters = @{
    location = $Location
    vmName = $vmName
    adminUsername = $UserName
    adminPassword = $Password
    windowsLocalAdminUserName = $UserName
    windowsLocalAdminPasswordBase64 = $adminPasswordBase64
    parametersJsonBase64 = $parametersJsonBase64
}

New-AzResourceGroupDeployment `
    -ResourceGroupName $resourceGroupName `
    -TemplateFile "$PSScriptRoot\create-resources.bicep" `
    -TemplateParameterObject $parameters `
    -Verbose

Write-Verbose 'Restarting the VM...'
Restart-AzVM -ResourceGroupName $resourceGroupName -Name $vmName | Out-Null
Start-Sleep -Seconds 30

Write-Host "The crank VM is ready: $vmName"
