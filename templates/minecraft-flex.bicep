

@description('Specifies a name for generating resource names.')
param projectName string

@description('Specifies the location for all resources.')
param location string = resourceGroup().location

@description('Specifies a username for the Virtual Machine.')
param adminUsername string

@description('Specifies the SSH rsa public key file as a string. Use "ssh-keygen -t rsa -b 2048" to generate your SSH key pairs.')
param adminPublicKey string

param vmSize string = 'Standard_D2s_v3'

@description('Sub ID for persistent stuff')
param persistentSubscriptionId string = subscription().subscriptionId

@description('Resource Group for persistent stuff')
param persistentResourceGroup string

@description('Resource Name for mananged identity')
param managedIdentityName string

@description('Operator principal ID')
param operatorId string

@description('Unused; remove when it can be removed from parameters file')
param diskResourceName string

var vNetAddressPrefixes = '10.0.0.0/16'
var vNetSubnetAddressPrefix = '10.0.0.0/24'
var vNetSubnetName = 'default'
var vmssName = '${projectName}-flex'
var identityId = resourceId(persistentSubscriptionId, persistentResourceGroup, 'Microsoft.ManagedIdentity/userAssignedIdentities', managedIdentityName)

// Copied from Azure sample template
param zones array = []

@allowed([
  1
  2
  3
  5
])
param platformFaultDomainCount int = 1
@maxValue(500)
param vmCount int = 3

var networkApiVersion = '2020-11-01'

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
      {
        name: 'minecraft-bedrock'
        properties: {
          description: 'Minecraft Bedrock port for Geyser'
          protocol: 'Udp'
          sourcePortRange: '*'
          destinationPortRange: '19132'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 202
          direction: 'Inbound'
        }
      }
      {
        name: 'ServerSync'
        properties: {
          description: 'ServerSync'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '38067'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 201
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
    subnets: [
      {
        name: vNetSubnetName
        properties: {
          addressPrefix: vNetSubnetAddressPrefix
          networkSecurityGroup: {
            id: vNetNSG.id
          }
        }
      }
    ]
  }
}

// Create a custom storage account for Boot Diagnostics so that Serial Console will work
resource diagStorageAccount 'Microsoft.Storage/storageAccounts@2021-01-01' = {
  name: 'diagstorage${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'Storage'
  sku: {
    name: 'Standard_LRS'
  }
}

resource vmssflex 'Microsoft.Compute/virtualMachineScaleSets@2021-03-01' = {
  name: vmssName
  location: location
  zones: zones
  sku: {
    name: vmSize
    tier: 'Standard'
    capacity: vmCount
  }
  // Managed identity. Only UserAssigned identity can be passed in to VMSS Profile
  // UserAssigned identity must be created before it can be assigned here
  // SystemAssigned identity can be assigned at the individual VM level
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    orchestrationMode: 'Flexible'
    singlePlacementGroup: false
    platformFaultDomainCount: platformFaultDomainCount

    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: 'mcvm'
        adminUsername: adminUsername
        linuxConfiguration: {
          disablePasswordAuthentication: true
          provisionVMAgent: true
          ssh: {
            publicKeys: [
              {
                path: '/home/${adminUsername}/.ssh/authorized_keys'
                keyData: adminPublicKey
              }
            ]
          }
        }
      }
      networkProfile: {
        networkApiVersion: networkApiVersion
        networkInterfaceConfigurations: [
          {
            name: '${vmssName}NicConfig01'
            properties: {
              primary: true
              enableAcceleratedNetworking: false
              ipConfigurations: [
                {
                  name: '${vmssName}IpConfig'
                  properties: {
                    publicIPAddressConfiguration: {
                      name: '${vmssName}PipConfig'
                      properties:{
                        publicIPAddressVersion: 'IPv4'
                        idleTimeoutInMinutes: 5
                        dnsSettings: {
                          domainNameLabel: vmssName
                        }
                      }
                    }
                    privateIPAddressVersion: 'IPv4'
                    subnet: {
                      id:  '${vNet.id}/subnets/${vNetSubnetName}'
                    }
                  }
                }
              ]
            }
          }
        ]
      }
      diagnosticsProfile: {
        bootDiagnostics: {
          enabled: true
          storageUri: diagStorageAccount.properties.primaryEndpoints.blob
        }
      }
      extensionProfile: {
        extensions: [
          {
            name: 'setup-mc'
            properties: {
              publisher: 'Microsoft.Azure.Extensions'
              type: 'CustomScript'
              typeHandlerVersion: '2.1'
              autoUpgradeMinorVersion: true
              settings: {
                skipDos2Unix: true
              }
              protectedSettings: {
                commandToExecute: '(apt-get -q -y install git && git clone https://github.com/sihde/mcazure.git /root/mcazure && cd /root/mcazure/setup && ./setup.sh) >/root/setup.log 2>/root/setup.err'
                //commandToExecute: '(echo I wuz here)>/root/setup.log'
              }
            }
          }
        ]
      }
      storageProfile: {
        imageReference: {
          // publisher: 'Canonical'
          // offer: 'UbuntuServer'
          // sku: '18.04-LTS'
          publisher: 'Debian'
          offer: 'debian-11'
          sku: '11'
          version: 'latest'
        }
        osDisk: {
          createOption: 'FromImage'
        }
      }
      // Enable Terminate notification
      // scheduledEventsProfile: {
      //   terminateNotificationProfile: {
      //     notBeforeTimeout: 'PT5M'
      //     enable: true
      //   }
      // }
    }
    // Ultra SSD not yet supported on VMSS Flex level
    // This can be assigned at the individual VM level
    // additionalCapabilities: {
    //   ultraSSDEnabled: false
    // }

  }
}

resource vm_minecraft 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  //parent: vmssflex
  name: '${vmssName}_022f979b'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    virtualMachineScaleSet: {
      id: vmssflex.id
    }
  }
}

resource vm_kittenz 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  //parent: vmssflex
  name: '${vmssName}_fb87e52f'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    virtualMachineScaleSet: {
      id: vmssflex.id
    }
  }
}

resource shutdownMC 'Microsoft.DevTestLab/schedules@2016-05-15' = {
  name: 'shutdown-computevm-${vm_minecraft.name}'
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
    targetResourceId: vm_minecraft.id
  }
}
resource shutdownSchedule 'Microsoft.DevTestLab/schedules@2016-05-15' = {
  name: 'shutdown-computevm-${vm_kittenz.name}'
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
    targetResourceId: vm_kittenz.id
  }
}


/* RBAC Assignments for Start/Stop VM */
var rolePrefix = '${subscription().id}/providers/Microsoft.Authorization/roleDefinitions/'
var roleReader = '${rolePrefix}acdd72a7-3385-48ef-bd42-f606fba81ae7'
var roleVmContributor = '${rolePrefix}9980e02c-c2be-4d73-94e8-173b1dc7cf3c'

resource subscriptionReaderRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(subscription().id, operatorId, resourceGroup().id, roleReader)
  properties: {
    description: 'Reader access on subscription'
    roleDefinitionId: roleReader
    principalId: operatorId
  }
  scope: resourceGroup()
}

resource vmContributorRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(subscription().id, operatorId, vm_minecraft.id, roleVmContributor)
  properties: {
    roleDefinitionId: roleVmContributor
    principalId: operatorId
  }
  scope: vm_minecraft
}
