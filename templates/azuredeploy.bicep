param projectName string {
  metadata: {
    description: 'Specifies a name for generating resource names.'
  }
}
param location string {
  metadata: {
    description: 'Specifies the location for all resources.'
  }
  default: resourceGroup().location
}
param adminUsername string {
  metadata: {
    description: 'Specifies a username for the Virtual Machine.'
  }
}
param adminPublicKey string {
  metadata: {
    description: 'Specifies the SSH rsa public key file as a string. Use "ssh-keygen -t rsa -b 2048" to generate your SSH key pairs.'
  }
}
param vmSize string {
  metadata: {
    description: 'description'
  }
  default: 'Standard_D2s_v3'
}
param persistentSubscriptionId string {
  metadata: {
    description: 'Sub ID for persistent stuff'
  }
  default: subscription().subscriptionId
}
param persistentResourceGroup string {
  metadata: {
    description: 'Resource Group for persistent stuff'
  }
}
param diskResourceName string {
  metadata: {
    description: 'Resource Name for persistent storage disk'
  }
}
param managedIdentityName string {
  metadata: {
    description: 'Resource Name for mananged identity'
  }
}

var vNetAddressPrefixes = '10.0.0.0/16'
var vNetSubnetAddressPrefix = '10.0.0.0/24'
var vmName = '${projectName}-vm'
var diskId = resourceId(persistentSubscriptionId, persistentResourceGroup, 'Microsoft.Compute/disks', diskResourceName)
var identityId = resourceId(persistentSubscriptionId, persistentResourceGroup, 'Microsoft.ManagedIdentity/userAssignedIdentities', managedIdentityName)

resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2020-05-01' = {
  name: '${projectName}-ip'
  location: location
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    dnsSettings: {
      domainNameLabel: 'hamachi-mc'
    }
  }
  sku: {
    name: 'Basic'
  }
}

resource vNetNSG 'Microsoft.Network/networkSecurityGroups@2020-05-01' = {
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
        name: 'minecraft'
        properties: {
          description: 'Minecraft server port'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '25565'
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

resource vNet 'Microsoft.Network/virtualNetworks@2020-05-01' = {
  name: '${projectName}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vNetAddressPrefixes
      ]
    }
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2020-05-01' = {
  name: '${vNet.name}/default'
  properties: {
    addressPrefix: vNetSubnetAddressPrefix
    networkSecurityGroup: {
      id: vNetNSG.id
    }
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2020-05-01' = {
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
            id: subnet.id
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2020-12-01' = {
  name: vmName
  location: location
  identity: {
    type: 'userAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
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
        createOption: 'fromImage'
      }
      dataDisks: [
        {
          lun: 0
          name: diskResourceName
          createOption: 'attach'
          managedDisk: {
            id: diskId
          }
        }
      ]
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
      commandToExecute: 'git clone https://github.com/sihde/mcazure.git /root/mcazure && cd /root/mcazure/setup && ./setup.sh >setup.log 2>setup.err'
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