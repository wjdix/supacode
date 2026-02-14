import Foundation
import Sentry

enum JjOperation: String {
  case repoRoot = "repo_root"
  case workspaceList = "workspace_list"
  case workspaceAdd = "workspace_add"
  case workspaceForget = "workspace_forget"
  case bookmarkList = "bookmark_list"
  case bookmarkRename = "bookmark_rename"
  case bookmarkDelete = "bookmark_delete"
  case diff = "diff"
  case log = "log"
  case remoteList = "remote_list"
}

enum JjClientError: LocalizedError {
  case commandFailed(command: String, message: String)

  var errorDescription: String? {
    switch self {
    case .commandFailed(let command, let message):
      if message.isEmpty {
        return "jj command failed: \(command)"
      }
      return "jj command failed: \(command)\n\(message)"
    }
  }
}

struct JjClient {
  private let shell: ShellClient
  private let colocatedGitClient: GitClient

  init(shell: ShellClient = .liveValue) {
    self.shell = shell
    self.colocatedGitClient = GitClient(shell: shell)
  }

  nonisolated func repoRoot(for path: URL) async throws -> URL {
    let normalizedPath = path.hasDirectoryPath ? path : path.deletingLastPathComponent()
    let output = try await runJj(
      operation: .repoRoot,
      arguments: ["root", "--ignore-working-copy"],
      currentDirectoryURL: normalizedPath
    )
    if output.isEmpty {
      throw JjClientError.commandFailed(command: "jj root", message: "Empty output")
    }
    return URL(fileURLWithPath: output).standardizedFileURL
  }

  nonisolated func worktrees(for repoRoot: URL) async throws -> [Worktree] {
    let repositoryRootURL = repoRoot.standardizedFileURL
    let output = try await runJj(
      operation: .workspaceList,
      arguments: ["workspace", "list", "--ignore-working-copy"],
      currentDirectoryURL: repoRoot
    )
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return []
    }
    return Self.parseWorkspaceList(trimmed, repositoryRootURL: repositoryRootURL)
  }

  nonisolated func pruneWorktrees(for repoRoot: URL) async throws {
    // jj does not have a prune equivalent; workspaces are always consistent
  }

  nonisolated func localBranchNames(for repoRoot: URL) async throws -> Set<String> {
    let output = try await runJj(
      operation: .bookmarkList,
      arguments: ["bookmark", "list", "--ignore-working-copy", "-T", "name ++ \"\\n\""],
      currentDirectoryURL: repoRoot
    )
    let names =
      output
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
      .filter { !$0.isEmpty }
    return Set(names)
  }

  nonisolated func branchRefs(for repoRoot: URL) async throws -> [String] {
    let output = try await runJj(
      operation: .bookmarkList,
      arguments: ["bookmark", "list", "--ignore-working-copy", "-T", "name ++ \"\\n\""],
      currentDirectoryURL: repoRoot
    )
    let refs =
      output
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    return refs
  }

  nonisolated func defaultRemoteBranchRef(for repoRoot: URL) async throws -> String? {
    let bookmarks = try await branchRefs(for: repoRoot)
    let lowered = bookmarks.map { $0.lowercased() }
    if lowered.contains("main") {
      return "main"
    }
    if lowered.contains("trunk") {
      return "trunk"
    }
    return bookmarks.first
  }

  nonisolated func automaticWorktreeBaseRef(for repoRoot: URL) async -> String? {
    guard let defaultRef = try? await defaultRemoteBranchRef(for: repoRoot) else {
      return "trunk()"
    }
    return defaultRef
  }

  nonisolated func ignoredFileCount(for repoRoot: URL) async throws -> Int {
    0
  }

  nonisolated func untrackedFileCount(for repoRoot: URL) async throws -> Int {
    0
  }

  nonisolated func createWorktree(
    named name: String,
    in repoRoot: URL,
    copyIgnored: Bool,
    copyUntracked: Bool,
    baseRef: String
  ) async throws -> Worktree {
    let repositoryRootURL = repoRoot.standardizedFileURL
    let baseDir = SupacodePaths.repositoryDirectory(for: repositoryRootURL)
    let workspacePath = baseDir.appending(path: name, directoryHint: .isDirectory)

    try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

    var arguments = [
      "workspace", "add",
      workspacePath.path(percentEncoded: false),
      "--name", name,
      "--ignore-working-copy",
    ]
    if !baseRef.isEmpty {
      arguments.append(contentsOf: ["-r", baseRef])
    }

    _ = try await runJj(
      operation: .workspaceAdd,
      arguments: arguments,
      currentDirectoryURL: repoRoot
    )

    let worktreeURL = workspacePath.standardizedFileURL
    let detail = Self.relativePath(from: repositoryRootURL, to: worktreeURL)
    let id = worktreeURL.path(percentEncoded: false)
    let resourceValues = try? worktreeURL.resourceValues(forKeys: [
      .creationDateKey, .contentModificationDateKey,
    ])
    let createdAt = resourceValues?.creationDate ?? resourceValues?.contentModificationDate
    return Worktree(
      id: id,
      name: name,
      detail: detail,
      workingDirectory: worktreeURL,
      repositoryRootURL: repositoryRootURL,
      createdAt: createdAt
    )
  }

  nonisolated func removeWorktree(_ worktree: Worktree, deleteBranch: Bool) async throws -> URL {
    let worktreeURL = worktree.workingDirectory.standardizedFileURL

    _ = try await runJj(
      operation: .workspaceForget,
      arguments: ["workspace", "forget", worktree.name, "--ignore-working-copy"],
      currentDirectoryURL: worktree.repositoryRootURL
    )

    let relocatedURL = Self.relocateWorktreeDirectory(worktreeURL)

    if deleteBranch, !worktree.name.isEmpty {
      let bookmarks = try await localBranchNames(for: worktree.repositoryRootURL)
      if bookmarks.contains(worktree.name.lowercased()) {
        _ = try? await runJj(
          operation: .bookmarkDelete,
          arguments: ["bookmark", "delete", worktree.name, "--ignore-working-copy"],
          currentDirectoryURL: worktree.repositoryRootURL
        )
      }
    }

    if let relocatedURL {
      Task.detached {
        try? FileManager.default.removeItem(at: relocatedURL)
      }
    }

    return worktree.workingDirectory
  }

  nonisolated func isBareRepository(for repoRoot: URL) async throws -> Bool {
    false
  }

  nonisolated func branchName(for worktreeURL: URL) async -> String? {
    do {
      let output = try await runJj(
        operation: .log,
        arguments: [
          "log", "-r", "@", "--no-graph", "--ignore-working-copy",
          "-T", "coalesce(bookmarks, \"(no bookmark)\")",
        ],
        currentDirectoryURL: worktreeURL
      )
      let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty || trimmed == "(no bookmark)" {
        return nil
      }
      return trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init)
    } catch {
      return nil
    }
  }

  nonisolated func lineChanges(at worktreeURL: URL) async -> (added: Int, removed: Int)? {
    do {
      let output = try await runJj(
        operation: .diff,
        arguments: ["diff", "--stat", "--ignore-working-copy"],
        currentDirectoryURL: worktreeURL
      )
      return Self.parseDiffStat(output)
    } catch {
      return nil
    }
  }

  nonisolated func renameBranch(in worktreeURL: URL, to branchName: String) async throws {
    guard let currentBranch = await self.branchName(for: worktreeURL) else {
      throw JjClientError.commandFailed(
        command: "jj bookmark rename",
        message: "No bookmark on current change to rename"
      )
    }
    _ = try await runJj(
      operation: .bookmarkRename,
      arguments: ["bookmark", "rename", currentBranch, branchName, "--ignore-working-copy"],
      currentDirectoryURL: worktreeURL
    )
  }

  nonisolated func remoteInfo(for repositoryRoot: URL) async -> GithubRemoteInfo? {
    let vcsType = VCSType.detect(at: repositoryRoot)
    if vcsType == .jujutsuColocated {
      return await colocatedGitClient.remoteInfo(for: repositoryRoot)
    }
    do {
      let output = try await runJj(
        operation: .remoteList,
        arguments: ["git", "remote", "list", "--ignore-working-copy"],
        currentDirectoryURL: repositoryRoot
      )
      return Self.parseJjRemoteList(output)
    } catch {
      return nil
    }
  }

  // MARK: - Parsing

  nonisolated static func parseWorkspaceList(
    _ output: String,
    repositoryRootURL: URL
  ) -> [Worktree] {
    output
      .split(whereSeparator: \.isNewline)
      .compactMap { line -> Worktree? in
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else { return nil }
        guard let colonRange = trimmedLine.range(of: ": ") else { return nil }
        let name = String(trimmedLine[trimmedLine.startIndex..<colonRange.lowerBound])
          .trimmingCharacters(in: .whitespacesAndNewlines)
        let path = String(trimmedLine[colonRange.upperBound...])
          .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !path.isEmpty else { return nil }
        let worktreeURL = URL(fileURLWithPath: path).standardizedFileURL
        let detail = relativePath(from: repositoryRootURL, to: worktreeURL)
        let id = worktreeURL.path(percentEncoded: false)
        let resourceValues = try? worktreeURL.resourceValues(forKeys: [
          .creationDateKey, .contentModificationDateKey,
        ])
        let createdAt = resourceValues?.creationDate ?? resourceValues?.contentModificationDate
        return Worktree(
          id: id,
          name: name,
          detail: detail,
          workingDirectory: worktreeURL,
          repositoryRootURL: repositoryRootURL,
          createdAt: createdAt
        )
      }
  }

  nonisolated static func parseDiffStat(_ output: String) -> (added: Int, removed: Int)? {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return (0, 0) }
    guard let lastLine = trimmed.split(whereSeparator: \.isNewline).last else {
      return (0, 0)
    }
    let line = String(lastLine)
    var added = 0
    var removed = 0
    if let match = line.firstMatch(of: /(\d+)\s+insertions?\(\+\)/) {
      added = Int(match.1) ?? 0
    }
    if let match = line.firstMatch(of: /(\d+)\s+deletions?\(-\)/) {
      removed = Int(match.1) ?? 0
    }
    return (added, removed)
  }

  nonisolated static func parseJjRemoteList(_ output: String) -> GithubRemoteInfo? {
    let lines = output.split(whereSeparator: \.isNewline)
    var originURL: String?
    var firstURL: String?
    for line in lines {
      let parts = line.split(whereSeparator: \.isWhitespace, maxSplits: 1)
      guard parts.count == 2 else { continue }
      let remoteName = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
      let remoteURL = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
      if remoteName == "origin" {
        originURL = remoteURL
      }
      if firstURL == nil {
        firstURL = remoteURL
      }
    }
    let urlToCheck = originURL ?? firstURL
    guard let urlToCheck else { return nil }
    return GitClient.parseGithubRemoteInfo(urlToCheck)
  }

  // MARK: - Internal

  nonisolated private func runJj(
    operation: JjOperation,
    arguments: [String],
    currentDirectoryURL: URL?
  ) async throws -> String {
    let env = URL(fileURLWithPath: "/usr/bin/env")
    let fullArgs = ["jj"] + arguments
    let command = ([env.path(percentEncoded: false)] + fullArgs).joined(separator: " ")
    do {
      return try await shell.run(env, fullArgs, currentDirectoryURL).stdout
    } catch {
      throw wrapShellError(error, operation: operation, command: command)
    }
  }

  nonisolated private func wrapShellError(
    _ error: Error,
    operation: JjOperation,
    command: String
  ) -> JjClientError {
    let jjError: JjClientError
    var exitCode: Int32 = -1
    if let shellError = error as? ShellClientError {
      exitCode = shellError.exitCode
      var messageParts: [String] = []
      if !shellError.stdout.isEmpty {
        messageParts.append("stdout:\n\(shellError.stdout)")
      }
      if !shellError.stderr.isEmpty {
        messageParts.append("stderr:\n\(shellError.stderr)")
      }
      let message = messageParts.joined(separator: "\n")
      jjError = .commandFailed(command: command, message: message)
    } else {
      jjError = .commandFailed(command: command, message: error.localizedDescription)
    }
    jjLogger.warning("jj command failed operation=\(operation.rawValue) exit_code=\(exitCode)")
    #if !DEBUG
      SentrySDK.logger.error(
        "jj command failed",
        attributes: [
          "operation": operation.rawValue,
          "exit_code": Int(exitCode),
        ]
      )
    #endif
    return jjError
  }

  nonisolated static func relativePath(from base: URL, to target: URL) -> String {
    let baseComponents = base.standardizedFileURL.pathComponents
    let targetComponents = target.standardizedFileURL.pathComponents
    var index = 0
    while index < min(baseComponents.count, targetComponents.count),
      baseComponents[index] == targetComponents[index]
    {
      index += 1
    }
    var result: [String] = []
    if index < baseComponents.count {
      result.append(contentsOf: Array(repeating: "..", count: baseComponents.count - index))
    }
    if index < targetComponents.count {
      result.append(contentsOf: targetComponents[index...])
    }
    if result.isEmpty {
      return "."
    }
    return result.joined(separator: "/")
  }

  nonisolated private static func relocateWorktreeDirectory(_ worktreeURL: URL) -> URL? {
    let fileManager = FileManager.default
    let worktreePath = worktreeURL.path(percentEncoded: false)
    guard fileManager.fileExists(atPath: worktreePath) else {
      return nil
    }
    let candidates = [
      URL(filePath: "/tmp", directoryHint: .isDirectory),
      fileManager.temporaryDirectory,
    ]
    for baseURL in candidates {
      let trashBaseURL = baseURL.appending(
        path: "supacode-worktree-trash",
        directoryHint: URL.DirectoryHint.isDirectory
      )
      do {
        try fileManager.createDirectory(at: trashBaseURL, withIntermediateDirectories: true)
      } catch {
        continue
      }
      let destinationURL = trashBaseURL.appending(
        path: "\(worktreeURL.lastPathComponent)-\(UUID().uuidString)",
        directoryHint: URL.DirectoryHint.isDirectory
      )
      do {
        try fileManager.moveItem(at: worktreeURL, to: destinationURL)
        return destinationURL
      } catch {
        continue
      }
    }
    return nil
  }
}

private nonisolated let jjLogger = SupaLogger("Jj")
