import Foundation

enum VCSType: String, Codable, Hashable, Sendable {
  case git
  case jujutsu
  case jujutsuColocated

  var isJujutsu: Bool { self == .jujutsu || self == .jujutsuColocated }

  var worktreeLabel: String { isJujutsu ? "Workspace" : "Worktree" }
  var worktreeLabelLowercased: String { isJujutsu ? "workspace" : "worktree" }

  /// Detect VCS type by checking for `.jj/` and `.git/` at the given URL.
  /// Use this when the URL is known to be a repository root.
  static func detect(at url: URL) -> VCSType {
    let fileManager = FileManager.default
    let hasJj = fileManager.fileExists(atPath: url.appending(path: ".jj").path(percentEncoded: false))
    let hasGit = fileManager.fileExists(atPath: url.appending(path: ".git").path(percentEncoded: false))
    if hasJj && hasGit { return .jujutsuColocated }
    if hasJj { return .jujutsu }
    return .git
  }

  /// Walk up from the given URL to find VCS markers. Useful when the URL
  /// might be a subdirectory of a repository.
  static func detectWalkingUp(from url: URL) -> VCSType {
    let fileManager = FileManager.default
    var current = url.standardizedFileURL
    let root = URL(fileURLWithPath: "/")
    while current.path(percentEncoded: false) != root.path(percentEncoded: false) {
      let jjPath = current.appending(path: ".jj").path(percentEncoded: false)
      if fileManager.fileExists(atPath: jjPath) {
        let gitPath = current.appending(path: ".git").path(percentEncoded: false)
        return fileManager.fileExists(atPath: gitPath) ? .jujutsuColocated : .jujutsu
      }
      current = current.deletingLastPathComponent()
    }
    return .git
  }
}
