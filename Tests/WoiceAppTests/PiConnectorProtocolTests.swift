import Foundation
import Testing
import WoiceCore

struct PiConnectorProtocolTests {
  @Test("PI 只读请求可编码，文本处理请求需要用户确认")
  func requestContractAndPolicy() throws {
    let status = try PiConnectorRequest(
      requestID: "req-1", method: .status
    ).validated()
    #expect(status.requiresUserConfirmation == false)
    #expect(status.method.requiredPermission == nil)
    let material = try PiConnectorRequest(
      requestID: "req-material", method: .readMaterial,
      parameters: ["recording_id": "record-1"]
    ).validated()
    #expect(material.requiresUserConfirmation == false)
    #expect(material.method.requiredPermission == .readOnlyMaterials)
    let search = try PiConnectorRequest(
      requestID: "req-search", method: .searchMaterials,
      parameters: ["query": "会议", "offset": "0", "limit": "20"]
    ).validated()
    #expect(search.requiresUserConfirmation == false)
    let page = try PiConnectorRequest(
      requestID: "req-page", method: .readMaterialPage,
      parameters: ["recording_id": "record-1", "field": "transcript", "offset": "0"]
    ).validated()
    #expect(page.requiresUserConfirmation == false)
    let transform = try PiConnectorRequest(
      requestID: "req-2",
      method: .requestTransform,
      parameters: ["recording_id": "record-1", "kind": "markdown"]
    ).validated()
    #expect(transform.requiresUserConfirmation)
    #expect(transform.method.requiredPermission == .createTasks)
    let data = try JSONEncoder().encode(transform)
    let decoded = try JSONDecoder().decode(PiConnectorRequest.self, from: data)
    #expect(decoded == transform)
  }

  @Test("PI 协议拒绝未知版本、空 request_id 和超大参数")
  func requestValidationFailsClosed() {
    #expect(throws: PiConnectorProtocolError.invalidEnvelope) {
      try PiConnectorRequest(requestID: "req", method: .status, protocolVersion: "2").validated()
    }
    #expect(throws: PiConnectorProtocolError.invalidEnvelope) {
      try PiConnectorRequest(requestID: "", method: .status).validated()
    }
    #expect(throws: PiConnectorProtocolError.parameterLimitExceeded) {
      try PiConnectorRequest(
        requestID: "req",
        method: .readTranscript,
        parameters: Dictionary(uniqueKeysWithValues: (0..<13).map { ("key\($0)", "value") })
      ).validated()
    }
  }
}
