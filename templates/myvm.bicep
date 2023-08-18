param vmName string
param vmSize string
param adminUsername string
param adminPublicKey string
param operatorId string = ''
param location string
param subnetId string
param identityId string = ''
param domainName string = vmName
param commandToExecute string = ''
param bootDiagnosticsAccount string = ''
param cloudInitData string = ''

resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: '${vmName}-pip'
  location: location
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Dynamic'
    dnsSettings: {
      domainNameLabel: domainName
    }
  }
  sku: {
    name: 'Basic'
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: '${vmName}-ipconfig'
        properties: {
          privateIPAddressVersion: 'IPv4'
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIPAddress.id
          }
          subnet: {
            id: subnetId
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2021-11-01' = {
  name: vmName
  location: location
  
  identity: (empty(identityId)) ? null : {
    type: 'UserAssigned'
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
      customData: cloudInitData
    }
    storageProfile: {
      imageReference: {
        // Debian 11 marketplace image has old cloud-init
        // and the azure waagent unit conflicts with the cloud-init unit
        // causing package installs to fail.
        publisher: 'Debian'
        offer: 'debian-12'
        sku: '12-gen2'
        // publisher: 'Canonical'
        // offer: '0001-com-ubuntu-server-jammy'
        // sku: '22_04-lts-gen2'
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
    diagnosticsProfile: (empty(bootDiagnosticsAccount)) ? null : {
      bootDiagnostics: {
        enabled: true
        storageUri: bootDiagnosticsAccount
      }
    }
  }

  resource customScriptExtension 'extensions@2021-11-01' = if (!empty(commandToExecute)) {
    name: 'config-app'
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
        commandToExecute: commandToExecute
      }
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
      time: '2100'
    }
    timeZoneId: 'Pacific Standard Time'
    notificationSettings: {
      status: 'Disabled'
      timeInMinutes: 30
    }
    targetResourceId: vm.id
  }
}

/* RBAC Assignments for Start/Stop VM */
var rolePrefix = '${subscription().id}/providers/Microsoft.Authorization/roleDefinitions/'
var roleVmContributor = '${rolePrefix}9980e02c-c2be-4d73-94e8-173b1dc7cf3c'

resource vmContributorRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = if (!empty(operatorId)) {
  name: guid(subscription().id, operatorId, vm.id, roleVmContributor)
  properties: {
    roleDefinitionId: roleVmContributor
    principalId: operatorId
  }
  scope: vm
}
