import Foundation
import Testing

@testable import supacode

struct JjClientParsingTests {
  // MARK: - parseWorkspaceNames

  @Test func parseWorkspaceNamesSingleDefault() {
    let output = "default: rlvkpntz 3a7b2c1e (no description set)"
    let names = JjClient.parseWorkspaceNames(output)

    #expect(names.count == 1)
    #expect(names[0] == "default")
  }

  @Test func parseWorkspaceNamesMultipleWorkspaces() {
    let output = """
      default: rlvkpntz 3a7b2c1e (no description set)
      feature-a: xyzwvuts 1b2c3d4e implement login
      bugfix: abcdefgh 5f6g7h8i fix crash on startup
      """
    let names = JjClient.parseWorkspaceNames(output)

    #expect(names.count == 3)
    #expect(names[0] == "default")
    #expect(names[1] == "feature-a")
    #expect(names[2] == "bugfix")
  }

  @Test func parseWorkspaceNamesSkipsEmptyLines() {
    let output = """
      default: rlvkpntz 3a7b2c1e (no description set)

      feature: xyzwvuts 1b2c3d4e implement feature

      """
    let names = JjClient.parseWorkspaceNames(output)

    #expect(names.count == 2)
  }

  @Test func parseWorkspaceNamesEmptyOutput() {
    let names = JjClient.parseWorkspaceNames("")

    #expect(names.isEmpty)
  }

  @Test func parseWorkspaceNamesSkipsMalformedLines() {
    let output = """
      default: rlvkpntz 3a7b2c1e (no description set)
      no-colon-here
      feature: xyzwvuts 1b2c3d4e implement feature
      """
    let names = JjClient.parseWorkspaceNames(output)

    #expect(names.count == 2)
    #expect(names[0] == "default")
    #expect(names[1] == "feature")
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
