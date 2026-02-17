import Testing

@testable import supacode

struct WorktreeCreationProgressTests {
  @Test func resolvingBaseReferenceUsesHeadFallback() {
    let progress = WorktreeCreationProgress(
      stage: .resolvingBaseReference,
      worktreeName: "swift-otter"
    )

    #expect(progress.titleText == "Creating swift-otter")
    #expect(progress.detailText == "Resolving base reference (HEAD)")
  }

  @Test func creatingWorktreeIncludesBaseRefAndCopyFlags() {
    let progress = WorktreeCreationProgress(
      stage: .creatingWorktree,
      worktreeName: "swift-otter",
      baseRef: "origin/main",
      copyIgnored: true,
      copyUntracked: false,
      ignoredFilesToCopyCount: 12,
      untrackedFilesToCopyCount: 5
    )

    #expect(progress.titleText == "Creating swift-otter")
    #expect(
      progress.detailText
        == "Creating from main branch. Copying 12 ignored files and copying 0 untracked files"
    )
  }

  // MARK: - Jujutsu-specific

  @Test func jujutsuTitleFallsBackToWorkspace() {
    let progress = WorktreeCreationProgress(stage: .loadingLocalBranches, vcsType: .jujutsu)

    #expect(progress.titleText == "Creating workspace")
  }

  @Test func jujutsuLoadingLocalBranchesShowsBookmarks() {
    let progress = WorktreeCreationProgress(stage: .loadingLocalBranches, vcsType: .jujutsu)

    #expect(progress.detailText == "Reading bookmarks")
  }

  @Test func jujutsuChoosingNameShowsWorkspace() {
    let progress = WorktreeCreationProgress(stage: .choosingWorktreeName, vcsType: .jujutsu)

    #expect(progress.detailText == "Choosing available workspace name")
  }

  @Test func jujutsuResolvingBaseReferenceShowsAtSign() {
    let progress = WorktreeCreationProgress(stage: .resolvingBaseReference, vcsType: .jujutsu)

    #expect(progress.detailText == "Resolving base reference (@)")
  }

  @Test func jujutsuResolvingBaseReferenceShowsExplicitRef() {
    let progress = WorktreeCreationProgress(
      stage: .resolvingBaseReference,
      baseRef: "main",
      vcsType: .jujutsu
    )

    #expect(progress.detailText == "Resolving base reference (main)")
  }

  @Test func jujutsuCreatingWorktreeSkipsCopyInfo() {
    let progress = WorktreeCreationProgress(
      stage: .creatingWorktree,
      worktreeName: "feature",
      baseRef: "main",
      copyIgnored: true,
      ignoredFilesToCopyCount: 10,
      vcsType: .jujutsu
    )

    #expect(progress.titleText == "Creating feature")
    #expect(progress.detailText == "Creating from main branch")
  }

  @Test func jujutsuCreatingWorktreeShowsBookmarkLabel() {
    let progress = WorktreeCreationProgress(
      stage: .creatingWorktree,
      baseRef: "feature-x",
      vcsType: .jujutsu
    )

    #expect(progress.detailText == "Creating from feature-x bookmark")
  }

  @Test func colocatedBehavesLikeJujutsu() {
    let progress = WorktreeCreationProgress(
      stage: .loadingLocalBranches,
      vcsType: .jujutsuColocated
    )

    #expect(progress.detailText == "Reading bookmarks")
  }
}
