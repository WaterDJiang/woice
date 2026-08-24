import Foundation

public enum PiConnectorMethod: String, Codable, Equatable, Hashable, Sendable {
  case status = "woice.status"
  case listRecordings = "woice.list_recordings"
  case readTranscript = "woice.read_transcript"
  case readMaterial = "woice.read_material"
  case searchMaterials = "woice.search_materials"
  case readMaterialPage = "woice.read_material_page"
  case requestTransform = "woice.request_transform"

  public var requiredPermission: AgentPermissionLevel? {
    switch self {
    case .status: nil
    case .listRecordings, .readTranscript, .readMaterial, .searchMaterials, .readMaterialPage:
      .readOnlyMaterials
    case .requestTransform: .createTasks
    }
  }
}

public struct PiConnectorRequest: Codable, Equatable, Sendable {
  public static let currentProtocolVersion = "1"

  public let protocolVersion: String
  public let requestID: String
  public let method: PiConnectorMethod
  public let parameters: [String: String]

  public init(
    requestID: String,
    method: PiConnectorMethod,
    parameters: [String: String] = [:],
    protocolVersion: String = PiConnectorRequest.currentProtocolVersion
  ) {
    self.protocolVersion = protocolVersion
    self.requestID = requestID
    self.method = method
    self.parameters = parameters
  }

  public func validated() throws -> Self {
    guard protocolVersion == Self.currentProtocolVersion, !requestID.isEmpty else {
      throw PiConnectorProtocolError.invalidEnvelope
    }
    guard parameters.count <= 12, parameters.values.allSatisfy({ $0.utf8.count <= 4_096 }) else {
      throw PiConnectorProtocolError.parameterLimitExceeded
    }
    return self
  }

  public var requiresUserConfirmation: Bool {
    switch method {
    case .requestTransform: true
    case .status, .listRecordings, .readTranscript, .readMaterial, .searchMaterials,
      .readMaterialPage:
      false
    }
  }
}

public struct PiConnectorResponse: Codable, Equatable, Sendable {
  public let protocolVersion: String
  public let requestID: String
  public let result: [String: String]?
  public let error: PiConnectorErrorPayload?

  public init(
    requestID: String,
    result: [String: String]? = nil,
    error: PiConnectorErrorPayload? = nil,
    protocolVersion: String = PiConnectorRequest.currentProtocolVersion
  ) {
    self.protocolVersion = protocolVersion
    self.requestID = requestID
    self.result = result
    self.error = error
  }
}

public struct PiConnectorErrorPayload: Codable, Equatable, Sendable {
  public let code: String
  public let message: String

  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }
}

public enum PiConnectorProtocolError: LocalizedError, Equatable, Sendable {
  case invalidEnvelope
  case parameterLimitExceeded

  public var errorDescription: String? {
    switch self {
    case .invalidEnvelope: "PI Connector 请求协议版本或 request_id 无效。"
    case .parameterLimitExceeded: "PI Connector 参数数量或单项大小超过限制。"
    }
  }
}
