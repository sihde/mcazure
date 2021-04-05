param projectName string
param location string = resourceGroup().location
param adminUsername string
param adminPublicKey string
param vmSize string = 'Standard_D2s_v3'

var subnetName = 'subnet0'
var vmName = '${projectName}-vm'

resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2020-08-01' = {
  name: '${projectName}-ip'
  location: location
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    dnsSettings: {
      domainNameLabel: 'hamachi-vpn'
    }
  }
  sku: {
    name: 'Basic'
  }
}

resource vNetNSG 'Microsoft.Network/networkSecurityGroups@2020-08-01' = {
  name: 'default-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'ssh'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '22'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'wireguard'
        properties: {
          protocol: 'Udp'
          sourcePortRange: '*'
          destinationPortRange: '51820'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 200
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource vNet 'Microsoft.Network/virtualNetworks@2020-08-01' = {
  name: '${projectName}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.0.0.0/24'
          networkSecurityGroup: {
            id: vNetNSG.id
          }
        }
      }
    ]
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2020-08-01' = {
  name: '${projectName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIPAddress.id
          }
          subnet: {
            id: '${vNet.id}/subnets/${subnetName}'
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2020-12-01' = {
  name: vmName
  location: location
/*
  identity: {
    type: 'userAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
*/
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminPublicKey
            }
          ]
        }
      }
      secrets: []
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: '18.04-LTS'
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

resource customScriptExtension 'Microsoft.Compute/virtualMachines/extensions@2020-12-01' = {
  name: '${vm.name}/config-app'
  location: location
  tags: {
    displayName: 'config-app'
  }
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      skipDos2Unix: true
    }
    protectedSettings: {
      //commandToExecute: 'git clone https://github.com/sihde/mcazure.git /root/mcazure && cd /root/mcazure/setup && ./setup.sh >setup.log 2>setup.err'
      commandToExecute: 'git clone https://github.com/sihde/mcazure.git /root/mcazure'
    }
  }
}

resource shutdownSchedule 'Microsoft.DevTestLab/schedules@2016-05-15' = {
  name: 'shutdown-computevm-${vm.name}'
  location: location
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: '2000'
    }
    timeZoneId: 'Pacific Standard Time'
    notificationSettings: {
      status: 'Disabled'
      timeInMinutes: 30
    }
    targetResourceId: vm.id
  }
}
