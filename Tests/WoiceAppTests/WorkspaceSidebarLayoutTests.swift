import Testing
import WoiceCore

@testable import WoiceApp

struct WorkspaceSidebarLayoutTests {
  @Test("工作台侧栏默认可见并可显式切换")
  @MainActor
  func sidebarVisibilityStartsVisibleAndCanToggle() {
    let router = WorkspaceRouter()

    #expect(router.isSidebarVisible)
    router.toggleSidebar()
    #expect(!router.isSidebarVisible)
    router.toggleSidebar()
    #expect(router.isSidebarVisible)
  }

  @Test("侧栏固定区域锚定，只有中部上下文区消耗可变高度")
  func fixedRegionsAndContextHeightAreDeterministic() {
    let layout = WorkspaceSidebarLayout(totalHeight: 760)
    #expect(layout.fixedRegionsFit)
    #expect(layout.contextHeight == 558)

    let compact = WorkspaceSidebarLayout(totalHeight: 160)
    #expect(compact.contextHeight == 0)
    #expect(!compact.fixedRegionsFit)
  }

  @Test("侧栏宽度和素材行文本契约覆盖最小/理想/最大宽度")
  func sidebarWidthContractStaysReadable() {
    #expect(WorkspaceSidebarLayout.minimumWidth == 280)
    #expect(WorkspaceSidebarLayout.idealWidth == 320)
    #expect(WorkspaceSidebarLayout.maximumWidth == 360)
    #expect(
      WorkspaceSidebarLayout.rowCanFitSingleLine(
        sidebarWidth: 280, titleWidth: 120, metadataWidth: 90, statusWidth: 20))
    #expect(
      !WorkspaceSidebarLayout.rowCanFitSingleLine(
        sidebarWidth: 279, titleWidth: 120, metadataWidth: 90, statusWidth: 20))
  }
}
