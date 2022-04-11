// ----- PARAMETERS

@minLength(3)
@maxLength(7)
@description('Prefix for a project resources.')
param projectPrefix string

@minLength(6)
@description('Specifies the Administrator login for SQL Server.')
param sqlServerLogin string

@minLength(12)
@secure()
@description('Specifies the Administrator password for SQL Server.')
param sqlServerPassword string

@minLength(6)
@description('Specifies the Administrator login name for VM.')
param localAdminUserName string

@minLength(12)
@secure()
@description('Specifies the Administrator password for VM.')
param localAdminPassword string

@minLength(32)
@description('Specifies the SPN ClientId.')
param clientId string

@minLength(32)
@description('Specifies the SPN ObjectId.')
param objectId string

@minLength(12)
@secure()
@description('Specifies the SPN password.')
param clientSecret string

// Optional Parameter
@description('Target region/location for deployment of resources.')
param location string = resourceGroup().location

// Optional Parameter
@description('Tags to be associated with deployed resources.')
param resourceTags object = (contains(resourceGroup(), 'tags') ? resourceGroup().tags : {} )

// Optional Parameter
@description('Address space of the Virtual Network.')
param vNetPrefix string = '10.0.0.0/16'

// Optional Parameter
@description('Address space of the Compute Plane subnet.')
param subnetComputePlanePrefix string = '10.0.0.0/20'

// Optional Parameter
@description('Address space of the Private Link subnet.')
param subnetPrivateLinkPrefix string = '10.0.32.0/23'

// Optional Parameter
@description('Number of days for which to retain logs.')
param logRetentionInDays int = 45

// ----- VARIABLES

var enable_private_endpoints = false

var lowerProjectPrefix = toLower(projectPrefix)

var plDfsDnsZone = 'privatelink.dfs.${environment().suffixes.storage}'
var plSnpsSqlDnsZone = 'privatelink.sql.azuresynapse.net'

var vNetName = '${lowerProjectPrefix}-synthea-vnet'

var laUniqueName = '${lowerProjectPrefix}-synthea-la'
var appInsightsUniqueName = '${lowerProjectPrefix}-synthea-appins'
var appSvcPlanUniqueName = '${lowerProjectPrefix}-synthea-appplan'
var appSvcFunctionUniqueName = '${lowerProjectPrefix}-synthea-appfce01'
var appSvcFunctionUniqueName2 = '${lowerProjectPrefix}-synthea-appfce02'

var synapseUniqueName = '${lowerProjectPrefix}synthea'

var saLakeUniqueName = '${lowerProjectPrefix}synthealakesa'
var saLakeContainerName = 'workspace'
var saUniqueName = '${lowerProjectPrefix}syntheasa'

var vmName = '${lowerProjectPrefix}syntheavm'
var vmSize = 'Standard_D2_v3'
var vmPIPName = '${lowerProjectPrefix}syntheavmpip'

var healthcareWksUniqueName = '${lowerProjectPrefix}syntheahcapi'
var fhirName = '${lowerProjectPrefix}fhir'
var loginURL = environment().authentication.loginEndpoint
var authority = '${loginURL}${tenant().tenantId}'
var audience = 'https://${healthcareWksUniqueName}-${fhirName}.fhir.azurehealthcareapis.com'

// ----- PRIVATE LINK

resource plDFSZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: plDfsDnsZone
  location: 'global'
  tags: resourceTags
  properties: {}
}

resource plDFSZoneVNetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${plDFSZone.name}/${plDFSZone.name}'
  location: 'global'
  tags: resourceTags
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

resource plSNPSZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (enable_private_endpoints) {
  name: plSnpsSqlDnsZone
  location: 'global'
  tags: resourceTags
  properties: {}
}

resource plSNPSZoneVNetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (enable_private_endpoints) {
  name: '${plSNPSZone.name}/${plSNPSZone.name}'
  location: 'global'
  tags: resourceTags
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

// ----- NETWORKING

resource vnet 'Microsoft.Network/virtualNetworks@2020-07-01' = {
  dependsOn: [
    plDFSZone
  ]
  name: vNetName
  location: location
  tags: resourceTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vNetPrefix
      ]
    }
    subnets: [
      {
        name: 'control-plane'
        properties: {
          addressPrefix: subnetComputePlanePrefix
          delegations: [
            {
              name: 'deleg-web-control-plane'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'private-link'
        properties: {
          addressPrefix: subnetPrivateLinkPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
    enableVmProtection: true
    enableDdosProtection: false
  }
}

// ----- STORAGE ACCOUNTS

resource salake 'Microsoft.Storage/storageAccounts@2021-08-01' = {
  name: saLakeUniqueName
  location: location
  tags: resourceTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  identity:{
    type: 'SystemAssigned'
  }
  properties: {
    accessTier: 'Hot'
    isHnsEnabled: true
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    // Next lines is needed for web UI access to default storage
    // ---
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    // ---
    encryption:{
      keySource: 'Microsoft.Storage'
      services: {
        file: {
          enabled: true
        }
        blob: {
           enabled: true
        }
      }
    }
  }
}

resource salake_privateLink 'Microsoft.Network/privateEndpoints@2020-08-01' = {
  name: '${saLakeUniqueName}-private-link'
  location: location
  tags: resourceTags
  properties: {
    subnet: {
      id: vnet.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: '${saLakeUniqueName}-private-link'
        properties: {
          privateLinkServiceId: salake.id
          groupIds: [
            'dfs'
          ]
        }
      }
    ]
  }
}

resource salake_privateLink_zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-08-01' = {
  name: '${salake_privateLink.name}/private-link'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: salake.name
        properties: {
          privateDnsZoneId: plDFSZone.id
        }
      }
    ]
  }
}

resource salake_blobs 'Microsoft.Storage/storageAccounts/blobServices@2021-08-01' = {
  name: 'default'
  parent: salake
  properties: {
    containerDeleteRetentionPolicy: {
      enabled: false
    }
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      enabled: false
    }
    isVersioningEnabled: false
    restorePolicy: {
      enabled: false
    }
  }
}

resource salake_container 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-08-01' = {
  dependsOn:[
    salake_blobs
  ]
  name: '${salake.name}/default/${saLakeContainerName}'
  properties: {
    //defaultEncryptionScope: 'string'
    //denyEncryptionScopeOverride: bool
    metadata: {}
    publicAccess: 'None'
  }
}

resource salake_blobContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  dependsOn:[
    salake_container
  ]
  name: guid(salake.id, deployment().name)
  scope: salake
  properties: {
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
    principalId: synapseWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
    canDelegate: false
    description: 'Read, write, and delete Azure Storage containers and blobs.'
    //condition: 'string'
    //conditionVersion: '2.0'
    //delegatedManagedIdentityResourceId
  }
}

// ----- LOG ANALYTICS

resource la 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: laUniqueName
  location: location
  tags: resourceTags
  //eTag: 'string'
  properties: {
    sku: {
      name: 'PerGB2018'
      //capacityReservationLevel: int
    }
    //features
    //forceCmkForQuery: bool
    retentionInDays: logRetentionInDays
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    /*workspaceCapping: {
      dailyQuotaGb: any('number')
    }*/
  }
}

// ----- SYNAPSE WORKSPACES

resource synapseWorkspace 'Microsoft.Synapse/workspaces@2021-06-01' = {
  name: synapseUniqueName
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    //azureADOnlyAuthentication: false
    defaultDataLakeStorage: {
      accountUrl: salake.properties.primaryEndpoints.dfs
      filesystem: saLakeContainerName
      //createManagedPrivateEndpoint: true
      //resourceId: salake.id
    }
    //managedResourceGroupName: 'string'
    //publicNetworkAccess: 'Disabled'
    sqlAdministratorLogin: sqlServerLogin
    sqlAdministratorLoginPassword: sqlServerPassword
    //trustedServiceBypassEnabled: false
    //virtualNetworkProfile: {
    //  computeSubnetId: vnet.properties.subnets[0].id
    //}
  }
}

resource synapseWorkspace_sql_privateLink 'Microsoft.Network/privateEndpoints@2020-08-01' = if (enable_private_endpoints) {
  name: '${synapseUniqueName}-sql-private-link'
  location: location
  tags: resourceTags
  properties: {
    subnet: {
      id: vnet.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: '${synapseUniqueName}-sql-private-link'
        properties: {
          privateLinkServiceId: synapseWorkspace.id
          groupIds: [
            'sql'
          ]
        }
      }
    ]
  }
}

resource synapseWorkspace_sql_privateLink_zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-08-01' = if (enable_private_endpoints) {
  name: '${synapseWorkspace_sql_privateLink.name}/private-link'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: synapseWorkspace.name
        properties: {
          privateDnsZoneId: plSNPSZone.id
        }
      }
    ]
  }
}

resource synapseWorkspace_srvlessSql_privateLink 'Microsoft.Network/privateEndpoints@2020-08-01' = if (enable_private_endpoints) {
  name: '${synapseUniqueName}-srvlessSql-private-link'
  location: location
  tags: resourceTags
  properties: {
    subnet: {
      id: vnet.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: '${synapseUniqueName}-srvlessSql-private-link'
        properties: {
          privateLinkServiceId: synapseWorkspace.id
          groupIds: [
            'sqlondemand'
          ]
        }
      }
    ]
  }
}

resource synapseWorkspace_srvlessSql_privateLink_zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-08-01' = if (enable_private_endpoints) {
  name: '${synapseWorkspace_srvlessSql_privateLink.name}/private-link'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: synapseWorkspace.name
        properties: {
          privateDnsZoneId: plSNPSZone.id
        }
      }
    ]
  }
}

resource synapseWorkspace_dev_privateLink 'Microsoft.Network/privateEndpoints@2020-08-01' = if (enable_private_endpoints) {
  name: '${synapseUniqueName}-dev-private-link'
  location: location
  tags: resourceTags
  properties: {
    subnet: {
      id: vnet.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: '${synapseUniqueName}-dev-private-link'
        properties: {
          privateLinkServiceId: synapseWorkspace.id
          groupIds: [
            'dev'
          ]
        }
      }
    ]
  }
}

resource synapseWorkspace_dev_privateLink_zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-08-01' = if (enable_private_endpoints) {
  name: '${synapseWorkspace_dev_privateLink.name}/private-link'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: synapseWorkspace.name
        properties: {
          privateDnsZoneId: plSNPSZone.id
        }
      }
    ]
  }
}

resource synapseWorkspace_FirewallAllowAllWindowsAzureIps 'Microsoft.Synapse/workspaces/firewallRules@2021-06-01' = if (!enable_private_endpoints) {
  name: 'AllowAllWindowsAzureIps'
  parent: synapseWorkspace
  properties: {
    endIpAddress: '0.0.0.0'
    startIpAddress: '0.0.0.0'
  }
}

resource synapseWorkspace_FirewallAllowAll 'Microsoft.Synapse/workspaces/firewallRules@2021-06-01' = if (!enable_private_endpoints) {
  name: 'AllowAll'
  parent: synapseWorkspace
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
  }
}

// ----- APP INSIGHTS

resource appSvc_insights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsUniqueName
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    DisableIpMasking: false
    // DisableLocalAuth: false
    //ImmediatePurgeDataOn30Days: false
    Flow_Type: 'Bluefield'
    //ForceCustomerStorageForProfiler: bool
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    Request_Source: 'rest'
    RetentionInDays: 30
    //SamplingPercentage: int
    WorkspaceResourceId: la.id
  }
}

// ----- APP SERVICES

resource appSvcPlan 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: appSvcPlanUniqueName
  location: location
  tags: resourceTags
  sku: {
    name: 'S1'
  }
  kind: 'App'
}

resource appSvc_functionApp 'Microsoft.Web/sites@2021-01-01' = {
  dependsOn:[
    appSvcPlan
  ]
  name: appSvcFunctionUniqueName
  kind: 'functionapp'
  location: location
  tags: resourceTags
  properties: {
    enabled: true
    serverFarmId: appSvcPlanUniqueName
    siteConfig: {
      requestTracingEnabled: true
      remoteDebuggingEnabled: false
      httpLoggingEnabled: true
      //logsDirectorySizeLimit: int
      detailedErrorLoggingEnabled: true
      //publishingUsername: 'string'
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~2'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: reference(appSvc_insights.id, appSvc_insights.apiVersion).InstrumentationKey
        }
        {
          name: 'WEBSITE_VNET_ROUTE_ALL'
          value: '1'
        }
        {
          name: 'WEBSITE_DNS_SERVER'
          value: '168.63.129.16'
        }
        {
            name: 'AzureWebJobsDashboard'
            value: 'DefaultEndpointsProtocol=https;AccountName=${saimporter.name};AccountKey=${listKeys(saimporter.id, saimporter.apiVersion).keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
            name: 'AzureWebJobsStorage'
            value: 'DefaultEndpointsProtocol=https;AccountName=${saimporter.name};AccountKey=${listKeys(saimporter.id, saimporter.apiVersion).keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
            name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
            value: 'DefaultEndpointsProtocol=https;AccountName=${saimporter.name};AccountKey=${listKeys(saimporter.id, saimporter.apiVersion).keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
            name: 'WEBSITE_CONTENTSHARE'
            value: '${toLower(appSvcFunctionUniqueName)}'
        }
        {
            name: 'WEBSITE_NODE_DEFAULT_VERSION'
            value: '8.11.1'
        }
        {
            name: 'APPINSIGHTS_PORTALINFO'
            value: 'ASP.NETCORE'
        }
        {
            name: 'APPINSIGHTS_PROFILERFEATURE_VERSION'
            value: '1.0.0'
        }
        {
            name: 'APPINSIGHTS_SNAPSHOTFEATURE_VERSION'
            value: '1.0.0'
        }
        {
            name: 'PROJECT'
            value: 'src/FhirImporter'
        }
        {
            name: 'ClientId'
            value: clientId
        }
        {
            name: 'ClientSecret'
            value: clientSecret
        }
        {
            name: 'Audience'
            value: audience
        }
        {
            name: 'Authority'
            value: '${environment().authentication.loginEndpoint}${tenant().tenantId}'
        }
        {
            name: 'FhirServerUrl'
            value: 'https://${healthcareWksUniqueName}.azurehealthcareapis.com'
        }
        {
            name: 'WEBSITE_MAX_DYNAMIC_APPLICATION_SCALE_OUT'
            value: '1'
        }
        {
            name: 'MaxDegreeOfParallelism'
            value: '16'
        }
      ]
      //azureStorageAccounts: {}
      connectionStrings: [
      ]
      alwaysOn: true
      //tracingOptions: 'string'
      http20Enabled: true
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      ftpsState: 'Disabled'
      preWarmedInstanceCount: 1
    }
    httpsOnly: true
    storageAccountRequired: false
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource appSvc_functionAppNet 'Microsoft.Web/sites/networkConfig@2021-01-01' = {
  dependsOn:[
    appSvc_functionApp
  ]
  name: '${appSvcFunctionUniqueName}/VirtualNetwork'
  properties:{
    swiftSupported:true
    subnetResourceId: vnet.properties.subnets[0].id
  }
}

// ----- VIRTUAL MACHINES

resource vm_nic 'Microsoft.Network/networkInterfaces@2021-03-01' = {
  name: '${vmName}-NIC'
  location: location
  tags: resourceTags
  properties: {
    enableAcceleratedNetworking: true
    ipConfigurations: [
      {
        name: 'IPCfg1'
        properties: {
          primary: true
          privateIPAddressVersion: 'IPv4'
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnet.properties.subnets[1].id
          }
          publicIPAddress: {
            id: vm_pip.id
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2021-11-01' = {
  name: vmName
  location: location
  tags: resourceTags
  properties: {
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
    hardwareProfile: {
      vmSize: vmSize
    }
    networkProfile: {
      networkInterfaces:[
        {
          id: vm_nic.id
          properties:{
            primary:true
            deleteOption:'Delete'
          }
        }
      ]
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-focal'
        sku: '20_04-lts' // Get-AzVMImage -Location "eastus" -PublisherName "Canonical" -Offer "UbuntuServer"
        version: 'latest'
      }
      osDisk: {
        name: '${vmName}-OSDISK'
        osType: 'Linux'
        createOption: 'FromImage'
        deleteOption:'Delete'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: localAdminUserName
      adminPassword: localAdminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
        provisionVMAgent: true
      }
    }
  }
}

resource vm_pip 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: vmPIPName
  location: location
  tags: resourceTags
  sku: {
    name: 'Basic'
  }
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    dnsSettings: {
      domainNameLabel: toLower('${vmName}-${uniqueString(resourceGroup().id, vmName)}')
    }
  }
}

resource vm_script 'Microsoft.Compute/virtualMachines/extensions@2021-07-01' = {
  name: 'Script'
  location: location
  parent: vm
  tags: resourceTags
  properties: {
    type: 'CustomScript'
    publisher: 'Microsoft.Azure.Extensions'
    typeHandlerVersion: '2.1'
    settings:{
    }
    protectedSettings:{
      commandToExecute: 'bash deploy.sh "DefaultEndpointsProtocol=https;AccountName=${saimporter.name};AccountKey=${listKeys(saimporter.id, saimporter.apiVersion).keys[0].value};EndpointSuffix=${environment().suffixes.storage}" 120 "/home/synthea/synthea/output/fhir" "out" "log" "fhirimport"'
      fileUris: [
        'https://raw.githubusercontent.com/djdean/PythonSyntheaFHIRClient/main/deployment/scripts/deploy.sh'
      ]
    }
    autoUpgradeMinorVersion: true
    //enableAutomaticUpgrade: true
  }
}

// ----- API FHIR (LEGACY)

resource fhir 'Microsoft.HealthcareApis/services@2021-06-01-preview' = {
  name: healthcareWksUniqueName
  location: location
  tags: resourceTags
  kind: 'fhir'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    accessPolicies: []
    //acrConfiguration: {}
    authenticationConfiguration: {
      audience: audience
      authority: authority
      smartProxyEnabled: true
    }
    //corsConfiguration: {}
    //cosmosDbConfiguration: {}
    //exportConfiguration: {}
    privateEndpointConnections: []
    //publicNetworkAccess: 'string'
  }
}

resource fhir_dataWriterRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(fhir.id, 'fhir_dataWriter', deployment().name)
  scope: fhir
  properties: {
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/3f88fce4-5892-4214-ae73-ba5294559913' // FHIR Data Writer
    principalId: objectId
    principalType: 'ServicePrincipal'
    canDelegate: false
    description: 'Read and write FHIR Data.'
    //condition: 'string'
    //conditionVersion: '2.0'
    //delegatedManagedIdentityResourceId
  }
}

resource fhir_contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(fhir.id, 'fhir_contributor', deployment().name)
  scope: fhir
  properties: {
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/5a1fc7df-4bf1-4951-a576-89034ee01acd' // FHIR Data Contributor
    principalId: objectId
    principalType: 'ServicePrincipal'
    canDelegate: false
    description: 'Full access to FHIR Data.'
    //condition: 'string'
    //conditionVersion: '2.0'
    //delegatedManagedIdentityResourceId
  }
}

// ----- FHIR IMPORTER

resource saimporter 'Microsoft.Storage/storageAccounts@2021-08-01' = {
  name: saUniqueName
  location: location
  tags: resourceTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  identity:{
    type: 'SystemAssigned'
  }
  properties: {
    accessTier: 'Hot'
    isHnsEnabled: false
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    // Next lines is needed for web UI access to default storage
    // ---
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    // ---
    encryption:{
      keySource: 'Microsoft.Storage'
      services: {
        file: {
          enabled: true
        }
        blob: {
           enabled: true
        }
      }
    }
  }
}

resource saimporter_blobs 'Microsoft.Storage/storageAccounts/blobServices@2021-08-01' = {
  name: 'default'
  parent: saimporter
  properties: {
    containerDeleteRetentionPolicy: {
      enabled: false
    }
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      enabled: false
    }
    isVersioningEnabled: false
    restorePolicy: {
      enabled: false
    }
  }
}

resource saimporter_container 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-08-01' = {
  dependsOn:[
    saimporter_blobs
  ]
  name: '${saimporter.name}/default/fhirimport'
  properties: {
    //defaultEncryptionScope: 'string'
    //denyEncryptionScopeOverride: bool
    metadata: {}
    publicAccess: 'None'
  }
}

resource saimporter_container2 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-08-01' = {
  dependsOn:[
    saimporter_blobs
  ]
  name: '${saimporter.name}/default/fhirrejected'
  properties: {
    //defaultEncryptionScope: 'string'
    //denyEncryptionScopeOverride: bool
    metadata: {}
    publicAccess: 'None'
  }
}

resource appSvc_src 'Microsoft.Web/sites/sourcecontrols@2021-03-01' = {
  dependsOn:[
    vm_script
  ]
  name: 'web'
  //kind: 'string'
  parent: appSvc_functionApp
  properties: {
    repoUrl: 'https://github.com/Microsoft/fhir-server-samples'
    branch: 'master'
    isManualIntegration: true
  }
}

// ----- FHIR SYNAPSE

resource appSvc_functionApp2 'Microsoft.Web/sites@2021-01-01' = {
  dependsOn:[
    appSvcPlan
  ]
  name: appSvcFunctionUniqueName2
  kind: 'functionapp'
  location: location
  tags: resourceTags
  properties: {
    enabled: true
    serverFarmId: appSvcPlanUniqueName
    siteConfig: {
      requestTracingEnabled: true
      remoteDebuggingEnabled: false
      httpLoggingEnabled: true
      //logsDirectorySizeLimit: int
      detailedErrorLoggingEnabled: true
      //publishingUsername: 'string'
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~2'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~10'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: reference(appSvc_insights.id, appSvc_insights.apiVersion).InstrumentationKey
        }
        {
          name: 'WEBSITE_VNET_ROUTE_ALL'
          value: '1'
        }
        {
          name: 'WEBSITE_DNS_SERVER'
          value: '168.63.129.16'
        }
        {
            name: 'AzureWebJobsDashboard'
            value: 'DefaultEndpointsProtocol=https;AccountName=${saimporter.name};AccountKey=${listKeys(saimporter.id, saimporter.apiVersion).keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
            name: 'AzureWebJobsStorage'
            value: 'DefaultEndpointsProtocol=https;AccountName=${saimporter.name};AccountKey=${listKeys(saimporter.id, saimporter.apiVersion).keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
            name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
            value: 'DefaultEndpointsProtocol=https;AccountName=${saimporter.name};AccountKey=${listKeys(saimporter.id, saimporter.apiVersion).keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
            name: 'WEBSITE_CONTENTSHARE'
            value: '${toLower(appSvcFunctionUniqueName2)}'
        }
        {
            name: 'APPINSIGHTS_PORTALINFO'
            value: 'ASP.NETCORE'
        }
        {
            name: 'APPINSIGHTS_PROFILERFEATURE_VERSION'
            value: '1.0.0'
        }
        {
            name: 'APPINSIGHTS_SNAPSHOTFEATURE_VERSION'
            value: '1.0.0'
        }
        {
          name: 'job__containerName'
          value: 'fhir'
        }
        {
          name: 'job__startTime'
          value: '1970-01-01 00:00:00 +00:00'
        }
        {
          name: 'job__endTime'
          value: json('null')
        }
        {
          name: 'dataLakeStore__storageUrl'
          value: salake.properties.primaryEndpoints.dfs
        }
        {
          name: 'fhirServer__serverUrl'
          value: 'https://${healthcareWksUniqueName}.azurehealthcareapis.com'
        }
        {
          name: 'fhirServer__version'
          value: 'R4'
        }
        {
          name: 'fhirServer__authentication'
          value: 'ManagedIdentity'
        }
        {
            name: 'WEBSITE_MAX_DYNAMIC_APPLICATION_SCALE_OUT'
            value: '1'
        }
      ]
      //azureStorageAccounts: {}
      connectionStrings: [
      ]
      alwaysOn: true
      //tracingOptions: 'string'
      http20Enabled: true
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      ftpsState: 'Disabled'
      preWarmedInstanceCount: 1
    }
    httpsOnly: true
    storageAccountRequired: false
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource appSvc_functionApp2_msdeploy 'Microsoft.Web/sites/extensions@2021-02-01' = {
  name: 'MSDeploy'
  parent: appSvc_functionApp2
  properties: {
    packageUri: 'https://fhiranalyticspipeline.blob.${environment().suffixes.storage}/builds/Microsoft.Health.Fhir.Synapse.FunctionApp.zip'
  }
}

resource salake_blobContributorRoleAssignment2 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  dependsOn:[
    salake_container
  ]
  name: guid(salake.id, deployment().name, 'salake_blobContributorRoleAssignment2')
  scope: salake
  properties: {
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
    principalId: appSvc_functionApp2.identity.principalId
    principalType: 'ServicePrincipal'
    canDelegate: false
    description: 'Read, write, and delete Azure Storage containers and blobs.'
    //condition: 'string'
    //conditionVersion: '2.0'
    //delegatedManagedIdentityResourceId
  }
}
