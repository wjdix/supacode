import ComposableArchitecture
import Foundation

struct VCSClientDependency {
  var repoRoot: @Sendable (URL) async throws -> URL
  var worktrees: @Sendable (URL) async throws -> [Worktree]
  var pruneWorktrees: @Sendable (URL) async throws -> Void
  var localBranchNames: @Sendable (URL) async throws -> Set<String>
  var branchRefs: @Sendable (URL) async throws -> [String]
  var defaultRemoteBranchRef: @Sendable (URL) async throws -> String?
  var automaticWorktreeBaseRef: @Sendable (URL) async -> String?
  var ignoredFileCount: @Sendable (URL) async throws -> Int
  var untrackedFileCount: @Sendable (URL) async throws -> Int
  var createWorktree:
    @Sendable (
      _ name: String,
      _ repoRoot: URL,
      _ copyIgnored: Bool,
      _ copyUntracked: Bool,
      _ baseRef: String
    ) async throws
      -> Worktree
  var removeWorktree: @Sendable (_ worktree: Worktree, _ deleteBranch: Bool) async throws -> URL
  var isBareRepository: @Sendable (_ repoRoot: URL) async throws -> Bool
  var branchName: @Sendable (URL) async -> String?
  var lineChanges: @Sendable (URL) async -> (added: Int, removed: Int)?
  var renameBranch: @Sendable (_ worktreeURL: URL, _ branchName: String) async throws -> Void
  var remoteInfo: @Sendable (_ repositoryRoot: URL) async -> GithubRemoteInfo?
}

extension VCSClientDependency: DependencyKey {
  private static func client(for url: URL) -> VCSClientAdapter {
    let vcsType = VCSType.detect(at: url)
    return vcsType.isJujutsu ? VCSClientAdapter(jj: JjClient()) : VCSClientAdapter(git: GitClient())
  }

  static let liveValue = VCSClientDependency(
    repoRoot: { url in
      // Try jj first if .jj/ exists at or above the given path
      if VCSType.detectWalkingUp(from: url).isJujutsu {
        return try await JjClient().repoRoot(for: url)
      }
      return try await GitClient().repoRoot(for: url)
    },
    worktrees: { try await client(for: $0).worktrees(for: $0) },
    pruneWorktrees: { try await client(for: $0).pruneWorktrees(for: $0) },
    localBranchNames: { try await client(for: $0).localBranchNames(for: $0) },
    branchRefs: { try await client(for: $0).branchRefs(for: $0) },
    defaultRemoteBranchRef: { try await client(for: $0).defaultRemoteBranchRef(for: $0) },
    automaticWorktreeBaseRef: { await client(for: $0).automaticWorktreeBaseRef(for: $0) },
    ignoredFileCount: { try await client(for: $0).ignoredFileCount(for: $0) },
    untrackedFileCount: { try await client(for: $0).untrackedFileCount(for: $0) },
    createWorktree: { name, repoRoot, copyIgnored, copyUntracked, baseRef in
      try await client(for: repoRoot).createWorktree(
        named: name,
        in: repoRoot,
        copyIgnored: copyIgnored,
        copyUntracked: copyUntracked,
        baseRef: baseRef
      )
    },
    removeWorktree: { worktree, deleteBranch in
      try await client(for: worktree.repositoryRootURL).removeWorktree(
        worktree,
        deleteBranch: deleteBranch
      )
    },
    isBareRepository: { repoRoot in
      try await client(for: repoRoot).isBareRepository(for: repoRoot)
    },
    branchName: { await client(for: $0).branchName(for: $0) },
    lineChanges: { await client(for: $0).lineChanges(at: $0) },
    renameBranch: { worktreeURL, branchName in
      try await client(for: worktreeURL).renameBranch(in: worktreeURL, to: branchName)
    },
    remoteInfo: { repositoryRoot in
      await client(for: repositoryRoot).remoteInfo(for: repositoryRoot)
    }
  )
  static let testValue = liveValue
}

extension DependencyValues {
  var vcsClient: VCSClientDependency {
    get { self[VCSClientDependency.self] }
    set { self[VCSClientDependency.self] = newValue }
  }
}

/// Adapter that wraps either a GitClient or JjClient to provide a uniform calling interface.
private enum VCSClientAdapter {
  case git(GitClient)
  case jj(JjClient)

  init(git: GitClient) { self = .git(git) }
  init(jj: JjClient) { self = .jj(jj) }

  func worktrees(for repoRoot: URL) async throws -> [Worktree] {
    switch self {
    case .git(let c): try await c.worktrees(for: repoRoot)
    case .jj(let c): try await c.worktrees(for: repoRoot)
    }
  }

  func pruneWorktrees(for repoRoot: URL) async throws {
    switch self {
    case .git(let c): try await c.pruneWorktrees(for: repoRoot)
    case .jj(let c): try await c.pruneWorktrees(for: repoRoot)
    }
  }

  func localBranchNames(for repoRoot: URL) async throws -> Set<String> {
    switch self {
    case .git(let c): try await c.localBranchNames(for: repoRoot)
    case .jj(let c): try await c.localBranchNames(for: repoRoot)
    }
  }

  func branchRefs(for repoRoot: URL) async throws -> [String] {
    switch self {
    case .git(let c): try await c.branchRefs(for: repoRoot)
    case .jj(let c): try await c.branchRefs(for: repoRoot)
    }
  }

  func defaultRemoteBranchRef(for repoRoot: URL) async throws -> String? {
    switch self {
    case .git(let c): try await c.defaultRemoteBranchRef(for: repoRoot)
    case .jj(let c): try await c.defaultRemoteBranchRef(for: repoRoot)
    }
  }

  func automaticWorktreeBaseRef(for repoRoot: URL) async -> String? {
    switch self {
    case .git(let c): await c.automaticWorktreeBaseRef(for: repoRoot)
    case .jj(let c): await c.automaticWorktreeBaseRef(for: repoRoot)
    }
  }

  func ignoredFileCount(for repoRoot: URL) async throws -> Int {
    switch self {
    case .git(let c): try await c.ignoredFileCount(for: repoRoot)
    case .jj(let c): try await c.ignoredFileCount(for: repoRoot)
    }
  }

  func untrackedFileCount(for repoRoot: URL) async throws -> Int {
    switch self {
    case .git(let c): try await c.untrackedFileCount(for: repoRoot)
    case .jj(let c): try await c.untrackedFileCount(for: repoRoot)
    }
  }

  func createWorktree(
    named name: String,
    in repoRoot: URL,
    copyIgnored: Bool,
    copyUntracked: Bool,
    baseRef: String
  ) async throws -> Worktree {
    switch self {
    case .git(let c):
      try await c.createWorktree(
        named: name, in: repoRoot, copyIgnored: copyIgnored,
        copyUntracked: copyUntracked, baseRef: baseRef
      )
    case .jj(let c):
      try await c.createWorktree(
        named: name, in: repoRoot, copyIgnored: copyIgnored,
        copyUntracked: copyUntracked, baseRef: baseRef
      )
    }
  }

  func removeWorktree(_ worktree: Worktree, deleteBranch: Bool) async throws -> URL {
    switch self {
    case .git(let c): try await c.removeWorktree(worktree, deleteBranch: deleteBranch)
    case .jj(let c): try await c.removeWorktree(worktree, deleteBranch: deleteBranch)
    }
  }

  func isBareRepository(for repoRoot: URL) async throws -> Bool {
    switch self {
    case .git(let c): try await c.isBareRepository(for: repoRoot)
    case .jj(let c): try await c.isBareRepository(for: repoRoot)
    }
  }

  func branchName(for worktreeURL: URL) async -> String? {
    switch self {
    case .git(let c): await c.branchName(for: worktreeURL)
    case .jj(let c): await c.branchName(for: worktreeURL)
    }
  }

  func lineChanges(at worktreeURL: URL) async -> (added: Int, removed: Int)? {
    switch self {
    case .git(let c): await c.lineChanges(at: worktreeURL)
    case .jj(let c): await c.lineChanges(at: worktreeURL)
    }
  }

  func renameBranch(in worktreeURL: URL, to branchName: String) async throws {
    switch self {
    case .git(let c): try await c.renameBranch(in: worktreeURL, to: branchName)
    case .jj(let c): try await c.renameBranch(in: worktreeURL, to: branchName)
    }
  }

  func remoteInfo(for repositoryRoot: URL) async -> GithubRemoteInfo? {
    switch self {
    case .git(let c): await c.remoteInfo(for: repositoryRoot)
    case .jj(let c): await c.remoteInfo(for: repositoryRoot)
    }
  }
}
