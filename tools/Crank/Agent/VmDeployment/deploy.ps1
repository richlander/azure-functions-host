#!/usr/bin/env pwsh

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]
    $SubscriptionName ='Private Test Sub shkr',

    [Parameter(Mandatory = $true)]
    [string]
    $BaseName ='1',

    [Parameter(Mandatory = $true)]
    [ValidateSet('Linux', 'Windows')]
    $OsType ='Windows',

    [string]
    $NamePostfix = 'perf',

    [string]
    $VmSize = 'Standard_E2s_v3',

    [string]
    $OsDiskType = 'Premium_LRS',

    [string]
    $Location = 'West Central US',

    [string]
    $UserName = 'Functions'
)

$ErrorActionPreference = 'Stop'

# Call deploy-vm.ps1 with "app" as the value of NamePostfix
& "$PSScriptRoot/deploy-vm.ps1" `
    -SubscriptionName $SubscriptionName `
    -BaseName $BaseName `
    -NamePostfix $NamePostfix `
    -OsType $OsType `
    -VmSize $VmSize `
    -OsDiskType $OsDiskType `
    -Location $Location `
    -UserName $UserName `
    -Verbose:$VerbosePreference

# TODO: remove this warning when app deployment is automated
$appPath = if ($OsType -eq 'Linux') { "/home/$UserName/FunctionApps" } else { 'C:\FunctionApps' }
Write-Warning "Remember to deploy the Function apps to $appPath"
