import AppKit
import UniformTypeIdentifiers

@MainActor
enum MaterialLibraryPanel {
  static func createMaterialLibrary() -> URL? {
    let panel = NSSavePanel()
    panel.title = "选择 Woice 素材保存位置"
    panel.message = "建议保留默认名称“Woice 素材”。录音、电脑声音和导入原件都保存在这里，你可以直接打开和备份。"
    panel.prompt = "创建并使用"
    panel.nameFieldLabel = "文件夹名称："
    panel.nameFieldStringValue = "Woice 素材"
    panel.allowedContentTypes = [.folder]
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK else { return nil }
    return panel.url
  }
}
