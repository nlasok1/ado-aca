targetScope = 'resourceGroup'

param location string = 'westeurope'

param acrName string = 'adoagentsacr${uniqueString(resourceGroup().id)}'
param imageVersion string = 'v1.0.0'
param imageName string = 'adoagent'

param laWorkspaceName string = 'ado-agents-la'

@description('Cron config of daily image updates. Default: "0 4 * * *"')
param cronSchedule string = '0 4 * * *'

@secure()
param ghToken string = ''
param ghUser string = 'nlasok1'
param ghPath string = 'ado-aca.git#main:src/agent'

param isTriggeredByTime bool = false
param isTriggeredBySource bool = false
param isTriggeredByBaseImage bool = false

param forceUpdateTag string = utcNow('yyyyMMddHHmmss')

var fullImageName = '${imageName}:${imageVersion}'
var ghRepositoryUrl = 'https://github.com/${ghUser}/${ghPath}'

resource laWorkspace 'Microsoft.OperationalInsights/workspaces@2020-10-01' = {
  name: laWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      immediatePurgeDataOn30Days: true
    }
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2021-09-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource acrDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'acrSendAllLogsToLogAnalytics'
  scope: acr
  properties: {
    workspaceId: laWorkspace.id
    logs: [
      {
        enabled: true
        categoryGroup: 'allLogs'
      }
    ]
  }
}

resource acrTask 'Microsoft.ContainerRegistry/registries/tasks@2019-04-01' = {
  name: 'adoagent-build-task'
  parent: acr
  location: location
  properties: {
    status: 'Enabled'
    agentConfiguration: {
      cpu: 2
    }
    platform: {
      os: 'Linux'
      architecture: 'amd64'
    }
    step: {
      type: 'Docker'
      contextAccessToken: !empty(ghToken) ? ghToken : null
      contextPath: ghRepositoryUrl
      dockerFilePath: 'Dockerfile'
      imageNames:[
        fullImageName
      ]
      isPushEnabled: true
    }
    trigger: {
      timerTriggers: isTriggeredByTime ? [
        {
          name: 'adoagent-build-task-timer'
          schedule: cronSchedule
        }
      ] : null
      baseImageTrigger: isTriggeredByBaseImage ? {
        name: 'adoagent-build-task-base-image-trigger'
        baseImageTriggerType: 'All'
        status: 'Enabled'
      } : null
      sourceTriggers: isTriggeredBySource ? [
        {
          name: 'adoagent-build-task-source-trigger'
          sourceTriggerEvents: [
            'pullrequest'
            'commit'
          ]
          sourceRepository: {
            repositoryUrl: ghRepositoryUrl
            sourceControlType: 'Github'
            branch: 'main'
            sourceControlAuthProperties: !empty(ghToken) ? {
              token:  ghToken
              tokenType: 'PAT'
            } : null
          }
        }
      ] : null
    }
  }
}

resource acrTaskRun 'Microsoft.ContainerRegistry/registries/taskRuns@2019-06-01-preview' = {
  name: 'adoagent-taskrun'
  parent: acr
  location: location
  properties: {
    forceUpdateTag: forceUpdateTag
    runRequest: {
      type: 'TaskRunRequest'
      taskId: acrTask.id
      isArchiveEnabled: false
    }
  }
}

@description('Output the login server property for later use')
output acrLoginServer string = acr.properties.loginServer

@description('Output the name of the built image')
output acrImageName string = acrTask.properties.step.imageNames[0]

@description('Output the name of the task run')
output acrTaskRunName string = acrTaskRun.name
