@description('The location of the resources')
param location string = 'WestUS'

@description('The name of the virtual machine')
param vmName string

@description('The admin username for the virtual machine')
param adminUsername string

@description('The admin password for the virtual machine')
@secure()
param adminPassword string

@description('Base64 encoded JSON parameters')
param parametersJsonBase64 string

@description('Windows local admin username')
param windowsLocalAdminUserName string

@description('Base64 encoded Windows local admin password')
param windowsLocalAdminPasswordBase64 string

@description('The directory where the logs will be stored')
param logDirectory string = 'C:\\CrankDeploymentLogs'

@description('The name of the Azure Bastion resource')
param bastionName string = '${vmName}-bastion'

@description('The operating system type')
param osType string = 'Windows'

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: '${vmName}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' = {
  name: 'default'
  parent: virtualNetwork
  properties: {
    addressPrefix: '10.0.0.0/24'
  }
}

resource bastionSubnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' = {
  name: 'AzureBastionSubnet'
  parent: virtualNetwork
  properties: {
    addressPrefix: '10.0.1.0/24'
  }
}

resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: '${vmName}-pip'
  location: location
  properties: {
    publicIPAllocationMethod: 'Dynamic'
  }
}

resource bastionPublicIPAddress 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: '${bastionName}-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2021-02-01' = {
  name: '${vmName}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowInternetOutbound'
        properties: {
          priority: 100
          protocol: '*'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '*'
        }
      }, {
        name: 'SSH'
        properties: {
          priority: 1000
          protocol: 'TCP'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }, {
        name: 'RDP'
        properties: {
          priority: 1001
          protocol: 'TCP'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }, {
        name: 'DotNet-Crank'
        properties: {
          priority: 1011
          protocol: '*'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5010'
        }
      }, {
        name: 'Benchmark-App'
        properties: {
          priority: 1012
          protocol: '*'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5000'
        }
      }
    ]
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2021-02-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnet.id
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIPAddress.id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
  }
}

resource virtualMachine 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D4s_v3'
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-Datacenter'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
  }
}

resource grantUserRightsExtension 'Microsoft.Compute/virtualMachines/extensions@2021-03-01' = if (osType == 'Windows') {
  name: '${vmName}-grantUserRights'
  parent: virtualMachine
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        'https://raw.githubusercontent.com/Azure/azure-functions-host/refs/heads/shkr/crank/tools/Crank/Agent/Windows/grant-userrights.ps1'
      ]
      commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -NoProfile -NonInteractive -File .\\grant-userrights.ps1 -UserName ${windowsLocalAdminUserName}'
    }
  }
}

resource customScriptExtension 'Microsoft.Compute/virtualMachines/extensions@2021-03-01' = if (osType == 'Windows') {
  name: '${vmName}-bootstrap'
  parent: virtualMachine
  location: location
  dependsOn: [
    grantUserRightsExtension
  ]
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        'https://raw.githubusercontent.com/Azure/azure-functions-host/refs/heads/shkr/crank/tools/Crank/Agent/Windows/bootstrap.ps1'
      ]
      commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -NoProfile -NonInteractive -File .\\bootstrap.ps1 -ParametersJsonBase64 ${parametersJsonBase64} -WindowsLocalAdminUserName ${windowsLocalAdminUserName} -WindowsLocalAdminPasswordBase64 ${windowsLocalAdminPasswordBase64}'
    }
  }
}

resource bastionHost 'Microsoft.Network/bastionHosts@2021-05-01' = {
  name: bastionName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'bastionHostIpConfiguration'
        properties: {
          subnet: {
            id: bastionSubnet.id
          }
          publicIPAddress: {
            id: bastionPublicIPAddress.id
          }
        }
      }
    ]
  }
}
