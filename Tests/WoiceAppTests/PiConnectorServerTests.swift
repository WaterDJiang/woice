import Foundation
import Network
import Testing
import WoiceCore

@testable import WoiceApp

private enum PiTestError: Error {
  case emptyResponse
}

private final class DataContinuationGate: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Data, Error>?

  init(_ continuation: CheckedContinuation<Data, Error>) {
    self.continuation = continuation
  }

  func resume(returning value: Data) {
    lock.lock()
    let continuation = self.continuation
    self.continuation = nil
    lock.unlock()
    continuation?.resume(returning: value)
  }

  func resume(throwing error: Error) {
    lock.lock()
    let continuation = self.continuation
    self.continuation = nil
    lock.unlock()
    continuation?.resume(throwing: error)
  }
}

private func firstLine(_ data: Data) -> Data {
  guard let newline = data.firstIndex(of: 0x0A) else { return data }
  return Data(data[..<newline])
}

private func waitForSocket(_ url: URL) async throws {
  for _ in 0..<100 {
    if FileManager.default.fileExists(atPath: url.path) { return }
    try await Task.sleep(for: .milliseconds(20))
  }
  throw PiTestError.emptyResponse
}

private func roundTrip(socketURL: URL, request: Data) async throws -> Data {
  try await withCheckedThrowingContinuation { continuation in
    let gate = DataContinuationGate(continuation)
    let connection = NWConnection(to: .unix(path: socketURL.path), using: .tcp)
    let queue = DispatchQueue(label: "com.woice.pi-connector-test-client")
    let payload = request + Data([0x0A])
    connection.stateUpdateHandler = { state in
      switch state {
      case .ready:
        connection.send(
          content: payload,
          completion: .contentProcessed { error in
            if let error { gate.resume(throwing: error) }
          })
      case .failed(let error):
        gate.resume(throwing: error)
      default:
        break
      }
    }
    connection.receive(
      minimumIncompleteLength: 1,
      maximumLength: PiConnectorServer.maximumRequestBytes + 1
    ) { data, _, _, error in
      if let data, !data.isEmpty {
        gate.resume(returning: data)
      } else if let error {
        gate.resume(throwing: error)
      } else {
        gate.resume(throwing: PiTestError.emptyResponse)
      }
      connection.cancel()
    }
    connection.start(queue: queue)
  }
}

@Test("Unix Socket PI Server 返回 Router 响应并使用当前用户权限")
@MainActor
func piConnectorServerRoundTripsRequest() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-pi-server-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = WorkspaceStore(storageRootURL: root)
  let record = RecordingRecord(
    id: UUID(), createdAt: Date(), audioFileName: "a.wav", duration: 1,
    transcript: "Socket 原文", generatedMarkdown: nil, processingError: nil
  )
  try store.saveRecordings([record])
  let state = AppState(store: store)
  let socketURL = URL(fileURLWithPath: "/private/tmp/woice-pi-\(UUID().uuidString).sock")
  let server = PiConnectorServer(
    router: PiConnectorRouter(appState: state), socketURL: socketURL)
  try server.start()
  defer { server.stop() }
  try await waitForSocket(socketURL)

  let request = PiConnectorRequest(
    requestID: "socket-read",
    method: .readTranscript,
    parameters: ["recording_id": record.id.uuidString]
  )
  let responseData = try await roundTrip(
    socketURL: socketURL, request: try JSONEncoder().encode(request))
  let response = try #require(
    try? JSONDecoder().decode(PiConnectorResponse.self, from: firstLine(responseData)))
  #expect(response.result?["text"] == "Socket 原文")
  let attributes = try FileManager.default.attributesOfItem(atPath: socketURL.path)
  #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
  #expect(server.isRunning)
}

@Test("Unix Socket PI Server 拒绝超大请求和重复启动")
@MainActor
func piConnectorServerFailsClosed() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "woice-pi-server-limit-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: WorkspaceStore(storageRootURL: root))
  let socketURL = URL(fileURLWithPath: "/private/tmp/woice-pi-limit-\(UUID().uuidString).sock")
  let server = PiConnectorServer(
    router: PiConnectorRouter(appState: state), socketURL: socketURL)
  try server.start()
  defer { server.stop() }
  #expect(throws: PiConnectorServerError.alreadyRunning) { try server.start() }
  try await waitForSocket(socketURL)

  let oversized = Data(repeating: 0x78, count: PiConnectorServer.maximumRequestBytes + 1)
  let responseData = try await roundTrip(socketURL: socketURL, request: oversized)
  let response = try #require(
    try? JSONDecoder().decode(PiConnectorResponse.self, from: firstLine(responseData)))
  #expect(response.error?.code == "REQUEST_TOO_LARGE")
}
