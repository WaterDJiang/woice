import Foundation
import Testing
import WoiceCore

@testable import WoiceApp

@Suite("Recording source selection")
struct RecordingSourceSelectionTests {
  @Test("default enables microphone and computer audio")
  func defaultEnablesBothSources() {
    let settings = AppSettings.default

    #expect(settings.captureMicrophone)
    #expect(settings.captureSystemAudio)
    #expect(settings.hasEnabledRecordingSource)
  }

  @Test("recording requires at least one selected source")
  func bothSourcesDisabledCannotRecord() {
    var settings = AppSettings.default
    settings.captureMicrophone = false
    settings.captureSystemAudio = false

    #expect(!settings.hasEnabledRecordingSource)
  }

  @Test("start recording fails closed when both sources are disabled")
  @MainActor
  func startRecordingFailsClosedWithoutCreatingAJournal() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "woice-no-source-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkspaceStore(storageRootURL: root)
    let state = AppState(store: store)
    state.settings.captureMicrophone = false
    state.settings.captureSystemAudio = false

    state.startRecording()

    #expect(!state.isRecording)
    #expect(state.processingState != .recording)
    #expect(store.loadRecordingSession() == nil)
    #expect(
      (try? FileManager.default.contentsOfDirectory(atPath: store.recordingsURL.path))?.isEmpty
        == true)
    #expect(state.errorMessage == "请至少开启一个音源。")
  }

  @Test("source summary distinguishes all four selections")
  func sourceSummaryDistinguishesSelections() {
    #expect(
      RecordingSourceSelectionPresentation.summary(
        microphoneEnabled: true, systemAudioEnabled: true) == "麦克风 + 电脑声音")
    #expect(
      RecordingSourceSelectionPresentation.summary(
        microphoneEnabled: true, systemAudioEnabled: false) == "仅麦克风")
    #expect(
      RecordingSourceSelectionPresentation.summary(
        microphoneEnabled: false, systemAudioEnabled: true) == "仅电脑声音")
    #expect(
      RecordingSourceSelectionPresentation.summary(
        microphoneEnabled: false, systemAudioEnabled: false) == "未选择音源")
  }
}
