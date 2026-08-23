import Foundation
import WoiceCore

struct ModelCatalogRuntimeConfiguration: Equatable, Sendable {
  let url: URL
  let catalogID: String
  let trustedKeys: [String: String]
  let policy: ModelCatalogFetchPolicy
  let modelDownloadAllowedHosts: Set<String>

  init(
    url: URL,
    catalogID: String,
    trustedKeys: [String: String],
    allowedHosts: Set<String>? = nil,
    modelDownloadAllowedHosts: Set<String>? = nil
  ) throws {
    guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
      let host = url.host?.lowercased(), !host.isEmpty
    else {
      throw ModelCatalogTransportError.disallowedURL(url.absoluteString)
    }
    let hosts = allowedHosts ?? [host]
    guard hosts.contains(host) else {
      throw ModelCatalogTransportError.disallowedURL(url.absoluteString)
    }
    self.url = url
    self.catalogID = catalogID
    self.trustedKeys = trustedKeys
    self.policy = ModelCatalogFetchPolicy(allowedHosts: hosts)
    self.modelDownloadAllowedHosts = Set(
      (modelDownloadAllowedHosts ?? hosts).map { $0.lowercased() })
  }

  static func fromBundle(_ bundle: Bundle = .main) -> Self? {
    guard let urlString = bundle.object(forInfoDictionaryKey: "WOICEModelCatalogURL") as? String,
      let url = URL(string: urlString),
      let catalogID = bundle.object(forInfoDictionaryKey: "WOICEModelCatalogID") as? String,
      let trustedKeys = bundle.object(forInfoDictionaryKey: "WOICEModelCatalogTrustedKeys")
        as? [String: String]
    else { return nil }
    let allowedHosts =
      (bundle.object(forInfoDictionaryKey: "WOICEModelCatalogAllowedHosts") as? [String])
      .map(Set.init)
    let modelDownloadAllowedHosts =
      (bundle.object(forInfoDictionaryKey: "WOICEModelDownloadAllowedHosts") as? [String])
      .map(Set.init)
    return try? Self(
      url: url, catalogID: catalogID, trustedKeys: trustedKeys, allowedHosts: allowedHosts,
      modelDownloadAllowedHosts: modelDownloadAllowedHosts)
  }
}

enum ModelCatalogRuntimeState: Equatable, Sendable {
  case unavailable
  case loadingLocal
  case ready(version: Int)
  case updating
  case failed(String)

  var title: String {
    switch self {
    case .unavailable: "当前发行包未配置远程模型清单"
    case .loadingLocal: "正在读取本机模型清单"
    case .ready(let version): "模型清单 v\(version) 已验证"
    case .updating: "正在检查模型清单更新"
    case .failed(let message): "更新失败：\(message)"
    }
  }

  var systemImage: String {
    switch self {
    case .unavailable: "questionmark.circle"
    case .loadingLocal, .updating: "arrow.triangle.2.circlepath"
    case .ready: "checkmark.seal.fill"
    case .failed: "exclamationmark.triangle.fill"
    }
  }
}
