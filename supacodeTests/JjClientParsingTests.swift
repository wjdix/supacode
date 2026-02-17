import Foundation
import Testing

@testable import supacode

struct JjClientParsingTests {
  // MARK: - parseWorkspaceList

  @Test func parseWorkspaceListSingleDefault() {
    let output = "default: /Users/dev/myrepo"
    let root = URL(fileURLWithPath: "/Users/dev/myrepo")
    let worktrees = JjClient.parseWorkspaceList(output, repositoryRootURL: root)

    #expect(worktrees.count == 1)
    #expect(worktrees[0].name == "default")
    #expect(worktrees[0].workingDirectory.path(percentEncoded: false) == "/Users/dev/myrepo")
  }

  @Test func parseWorkspaceListMultipleWorkspaces() {
    let output = """
      default: /Users/dev/myrepo
      feature-a: /Users/dev/.supacode/myrepo/feature-a
      bugfix: /Users/dev/.supacode/myrepo/bugfix
      """
    let root = URL(fileURLWithPath: "/Users/dev/myrepo")
    let worktrees = JjClient.parseWorkspaceList(output, repositoryRootURL: root)

    #expect(worktrees.count == 3)
    #expect(worktrees[0].name == "default")
    #expect(worktrees[1].name == "feature-a")
    #expect(worktrees[2].name == "bugfix")
    #expect(worktrees[0].repositoryRootURL == root.standardizedFileURL)
  }

  @Test func parseWorkspaceListSkipsEmptyLines() {
    let output = """
      default: /Users/dev/myrepo

      feature: /Users/dev/.supacode/myrepo/feature

      """
    let root = URL(fileURLWithPath: "/Users/dev/myrepo")
    let worktrees = JjClient.parseWorkspaceList(output, repositoryRootURL: root)

    #expect(worktrees.count == 2)
  }

  @Test func parseWorkspaceListEmptyOutput() {
    let root = URL(fileURLWithPath: "/Users/dev/myrepo")
    let worktrees = JjClient.parseWorkspaceList("", repositoryRootURL: root)

    #expect(worktrees.isEmpty)
  }

  @Test func parseWorkspaceListSkipsMalformedLines() {
    let output = """
      default: /Users/dev/myrepo
      no-colon-here
      feature: /Users/dev/.supacode/myrepo/feature
      """
    let root = URL(fileURLWithPath: "/Users/dev/myrepo")
    let worktrees = JjClient.parseWorkspaceList(output, repositoryRootURL: root)

    #expect(worktrees.count == 2)
    #expect(worktrees[0].name == "default")
    #expect(worktrees[1].name == "feature")
  }

  @Test func parseWorkspaceListComputesRelativeDetail() {
    let output = "feature: /Users/dev/.supacode/myrepo/feature"
    let root = URL(fileURLWithPath: "/Users/dev/myrepo")
    let worktrees = JjClient.parseWorkspaceList(output, repositoryRootURL: root)

    #expect(worktrees.count == 1)
    #expect(worktrees[0].detail.contains("feature"))
  }

  // MARK: - parseDiffStat

  @Test func parseDiffStatTypicalOutput() {
    let output = """
       src/main.rs | 10 ++++------
       src/lib.rs  |  5 +++++
       2 files changed, 9 insertions(+), 6 deletions(-)
      """
    let result = JjClient.parseDiffStat(output)

    #expect(result?.added == 9)
    #expect(result?.removed == 6)
  }

  @Test func parseDiffStatInsertionsOnly() {
    let output = " 1 file changed, 5 insertions(+)\n"
    let result = JjClient.parseDiffStat(output)

    #expect(result?.added == 5)
    #expect(result?.removed == 0)
  }

  @Test func parseDiffStatDeletionsOnly() {
    let output = " 1 file changed, 3 deletions(-)\n"
    let result = JjClient.parseDiffStat(output)

    #expect(result?.added == 0)
    #expect(result?.removed == 3)
  }

  @Test func parseDiffStatSingularForms() {
    let output = " 1 file changed, 1 insertion(+), 1 deletion(-)\n"
    let result = JjClient.parseDiffStat(output)

    #expect(result?.added == 1)
    #expect(result?.removed == 1)
  }

  @Test func parseDiffStatEmptyOutput() {
    let result = JjClient.parseDiffStat("")

    #expect(result?.added == 0)
    #expect(result?.removed == 0)
  }

  @Test func parseDiffStatWhitespaceOnly() {
    let result = JjClient.parseDiffStat("   \n  \n")

    #expect(result?.added == 0)
    #expect(result?.removed == 0)
  }

  // MARK: - parseJjRemoteList

  @Test func parseJjRemoteListOriginSSH() {
    let output = "origin git@github.com:octo/repo.git\n"
    let info = JjClient.parseJjRemoteList(output)

    #expect(info == GithubRemoteInfo(host: "github.com", owner: "octo", repo: "repo"))
  }

  @Test func parseJjRemoteListOriginHTTPS() {
    let output = "origin https://github.com/octo/repo\n"
    let info = JjClient.parseJjRemoteList(output)

    #expect(info == GithubRemoteInfo(host: "github.com", owner: "octo", repo: "repo"))
  }

  @Test func parseJjRemoteListPrefersOrigin() {
    let output = """
      upstream https://github.com/other/fork
      origin git@github.com:octo/repo.git
      """
    let info = JjClient.parseJjRemoteList(output)

    #expect(info == GithubRemoteInfo(host: "github.com", owner: "octo", repo: "repo"))
  }

  @Test func parseJjRemoteListFallsBackToFirst() {
    let output = "upstream git@github.com:octo/repo.git\n"
    let info = JjClient.parseJjRemoteList(output)

    #expect(info == GithubRemoteInfo(host: "github.com", owner: "octo", repo: "repo"))
  }

  @Test func parseJjRemoteListEmptyOutput() {
    let info = JjClient.parseJjRemoteList("")

    #expect(info == nil)
  }

  @Test func parseJjRemoteListNonGithubRemote() {
    let output = "origin https://gitlab.com/group/repo.git\n"
    let info = JjClient.parseJjRemoteList(output)

    #expect(info == nil)
  }

  // MARK: - relativePath

  @Test func relativePathSameDirectory() {
    let base = URL(fileURLWithPath: "/Users/dev/repo")
    let target = URL(fileURLWithPath: "/Users/dev/repo")

    #expect(JjClient.relativePath(from: base, to: target) == ".")
  }

  @Test func relativePathSubdirectory() {
    let base = URL(fileURLWithPath: "/Users/dev/repo")
    let target = URL(fileURLWithPath: "/Users/dev/repo/sub/dir")

    #expect(JjClient.relativePath(from: base, to: target) == "sub/dir")
  }

  @Test func relativePathSiblingDirectory() {
    let base = URL(fileURLWithPath: "/Users/dev/repo")
    let target = URL(fileURLWithPath: "/Users/dev/other")

    #expect(JjClient.relativePath(from: base, to: target) == "../other")
  }
}
