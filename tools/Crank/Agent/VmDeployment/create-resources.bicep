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

resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: '${vmName}-pip'
  location: location
  properties: {
    publicIPAllocationMethod: 'Dynamic'
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
        sku: '2022-Datacenter-Azure-Edition'
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

resource customScriptExtension 'Microsoft.Compute/virtualMachines/extensions@2021-03-01' = {
  name: '${vmName}/CustomScriptExtension'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        'https://gist.githubusercontent.com/kshyju/e2a43a42c9b6b11c388a5077518ef4ec/raw/742ebbdc870aa2fe2b21c9df36191ed5fbc3ce33/win-bootstrap.ps1'
      ]
      commandToExecute: 'powershell -ExecutionPolicy Unrestricted -File win-bootstrap.ps1 -ParametersJsonBase64 ${parametersJsonBase64} -WindowsLocalAdminUserName ${windowsLocalAdminUserName} -WindowsLocalAdminPasswordBase64 ${windowsLocalAdminPasswordBase64}'
    }
  }
}
