param projectName string
param location string = resourceGroup().location
param adminUsername string
param adminPublicKey string
param vmSize string = 'Standard_D2s_v3'

var subnetName = 'subnet0'
var vmName = 'hamachi-${projectName}'

resource nsg 'Microsoft.Network/networkSecurityGroups@2020-08-01' = {
  name: '${projectName}-nsg'
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
            id: nsg.id
          }
        }
      }
    ]
  }
}

module mcvm 'myvm.bicep' = {
  name: 'whatever'
  params: {
    vmName: vmName
    vmSize: vmSize
    adminUsername: adminUsername
    adminPublicKey: adminPublicKey
    //identityId: identityId
    location: location
    //operatorId: operatorId
    subnetId: '${vNet.id}/subnets/${subnetName}'
    //commandToExecute: 'git clone https://github.com/sihde/mcazure.git /root/mcazure && cd /root/mcazure/setup && ./setup-vpn.sh >setup.log 2>setup.err'
    //bootDiagnosticsAccount: diagStorageAccount.properties.primaryEndpoints.blob
    cloudInitData: loadFileAsBase64('cloud-init.yaml')
  }
}
