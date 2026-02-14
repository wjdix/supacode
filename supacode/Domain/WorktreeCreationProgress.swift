nonisolated struct WorktreeCreationProgress: Hashable, Sendable {
  var stage: WorktreeCreationStage
  var worktreeName: String?
  var baseRef: String?
  var copyIgnored: Bool?
  var copyUntracked: Bool?
  var ignoredFilesToCopyCount: Int?
  var untrackedFilesToCopyCount: Int?
  var vcsType: VCSType

  init(
    stage: WorktreeCreationStage,
    worktreeName: String? = nil,
    baseRef: String? = nil,
    copyIgnored: Bool? = nil,
    copyUntracked: Bool? = nil,
    ignoredFilesToCopyCount: Int? = nil,
    untrackedFilesToCopyCount: Int? = nil,
    vcsType: VCSType = .git
  ) {
    self.stage = stage
    self.worktreeName = worktreeName
    self.baseRef = baseRef
    self.copyIgnored = copyIgnored
    self.copyUntracked = copyUntracked
    self.ignoredFilesToCopyCount = ignoredFilesToCopyCount
    self.untrackedFilesToCopyCount = untrackedFilesToCopyCount
    self.vcsType = vcsType
  }

  var titleText: String {
    if let worktreeName, !worktreeName.isEmpty {
      return "Creating \(worktreeName)"
    }
    return "Creating \(vcsType.worktreeLabelLowercased)"
  }

  var detailText: String {
    switch stage {
    case .loadingLocalBranches:
      return vcsType.isJujutsu ? "Reading bookmarks" : "Reading local branches"
    case .choosingWorktreeName:
      return "Choosing available \(vcsType.worktreeLabelLowercased) name"
    case .checkingRepositoryMode:
      return "Checking repository mode"
    case .resolvingBaseReference:
      return "Resolving base reference (\(baseRefDisplay))"
    case .creatingWorktree:
      if vcsType.isJujutsu {
        return "Creating from \(baseRefBranchDisplay)"
      }
      let ignoredCount = copyIgnored == true ? (ignoredFilesToCopyCount ?? 0) : 0
      let untrackedCount = copyUntracked == true ? (untrackedFilesToCopyCount ?? 0) : 0
      let copySummary =
        "Copying \(ignoredCount) ignored files and copying \(untrackedCount) untracked files"
      return
        "Creating from \(baseRefBranchDisplay). \(copySummary)"
    }
  }

  private var baseRefDisplay: String {
    guard let baseRef, !baseRef.isEmpty else {
      return vcsType.isJujutsu ? "@" : "HEAD"
    }
    return baseRef
  }

  private var baseRefBranchDisplay: String {
    let normalized = baseRefDisplay.lowercased()
    if normalized == "main" || normalized == "origin/main" {
      return "main branch"
    }
    if normalized == "head" || normalized == "@" {
      return vcsType.isJujutsu ? "@" : "HEAD"
    }
    if vcsType.isJujutsu {
      return "\(baseRefDisplay) bookmark"
    }
    return "\(baseRefDisplay) branch"
  }
}

nonisolated enum WorktreeCreationStage: Hashable, Sendable {
  case loadingLocalBranches
  case choosingWorktreeName
  case checkingRepositoryMode
  case resolvingBaseReference
  case creatingWorktree
}
