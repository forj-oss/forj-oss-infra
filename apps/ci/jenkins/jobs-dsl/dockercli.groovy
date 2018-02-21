
multibranchPipelineJob('dockercli') {
  description('Folder for Project dockercli generated and maintained by Forjj. To update it use forjj update')
  branchSources {
      github {
          repoOwner('forj-oss')
          scanCredentialsId('github-user')
          repository('dockercli')
      }
  }

  orphanedItemStrategy {
      discardOldItems {
          numToKeep(20)
      }
  }
}
