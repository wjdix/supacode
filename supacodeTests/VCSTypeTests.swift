import Foundation
import Testing

@testable import supacode

struct VCSTypeTests {
  // MARK: - detect(at:)

  @Test func detectGitOnly() throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    try FileManager.default.createDirectory(
      at: tempDir.appending(path: ".git"),
      withIntermediateDirectories: true
    )

    #expect(VCSType.detect(at: tempDir) == .git)
  }

  @Test func detectJujutsuOnly() throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    try FileManager.default.createDirectory(
      at: tempDir.appending(path: ".jj"),
      withIntermediateDirectories: true
    )

    #expect(VCSType.detect(at: tempDir) == .jujutsu)
  }

  @Test func detectJujutsuColocated() throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    try FileManager.default.createDirectory(
      at: tempDir.appending(path: ".git"),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: tempDir.appending(path: ".jj"),
      withIntermediateDirectories: true
    )

    #expect(VCSType.detect(at: tempDir) == .jujutsuColocated)
  }

  @Test func detectFallsBackToGit() throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    #expect(VCSType.detect(at: tempDir) == .git)
  }

  // MARK: - detectWalkingUp(from:)

  @Test func detectWalkingUpFindsJjInParent() throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let subDir = tempDir.appending(path: "sub/dir")
    defer { try? FileManager.default.removeItem(at: tempDir) }
    try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: tempDir.appending(path: ".jj"),
      withIntermediateDirectories: true
    )

    #expect(VCSType.detectWalkingUp(from: subDir) == .jujutsu)
  }

  @Test func detectWalkingUpFindsColocatedInParent() throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let subDir = tempDir.appending(path: "sub")
    defer { try? FileManager.default.removeItem(at: tempDir) }
    try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: tempDir.appending(path: ".jj"),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: tempDir.appending(path: ".git"),
      withIntermediateDirectories: true
    )

    #expect(VCSType.detectWalkingUp(from: subDir) == .jujutsuColocated)
  }

  @Test func detectWalkingUpFallsBackToGit() throws {
    let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    #expect(VCSType.detectWalkingUp(from: tempDir) == .git)
  }

  // MARK: - Properties

  @Test func isJujutsuProperty() {
    #expect(VCSType.git.isJujutsu == false)
    #expect(VCSType.jujutsu.isJujutsu == true)
    #expect(VCSType.jujutsuColocated.isJujutsu == true)
  }

  @Test func worktreeLabelForGit() {
    #expect(VCSType.git.worktreeLabel == "Worktree")
    #expect(VCSType.git.worktreeLabelLowercased == "worktree")
  }

  @Test func worktreeLabelForJujutsu() {
    #expect(VCSType.jujutsu.worktreeLabel == "Workspace")
    #expect(VCSType.jujutsu.worktreeLabelLowercased == "workspace")
  }

  @Test func worktreeLabelForColocated() {
    #expect(VCSType.jujutsuColocated.worktreeLabel == "Workspace")
    #expect(VCSType.jujutsuColocated.worktreeLabelLowercased == "workspace")
  }
}
