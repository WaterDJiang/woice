import Foundation

/// Capabilities selected by the App composition root for each distribution.
/// Domain and Runtime code must not inspect the distribution flag.
struct StoreCapabilityProfile: Equatable, Sendable {
  enum Edition: String, Equatable, Sendable {
    case website
    case appStore
  }

  let edition: Edition
  let allowsProcessProviders: Bool
  let allowsExternalAgentConnector: Bool
  let allowsSelfUpdater: Bool
  let allowsAutomaticPaste: Bool
  let allowsUserProvidedExecutables: Bool
  let allowsModelImport: Bool
  let allowsHTTPProviders: Bool

  var isStoreEdition: Bool { edition == .appStore }

  static let website = StoreCapabilityProfile(
    edition: .website,
    allowsProcessProviders: true,
    allowsExternalAgentConnector: true,
    allowsSelfUpdater: true,
    allowsAutomaticPaste: true,
    allowsUserProvidedExecutables: true,
    allowsModelImport: true,
    allowsHTTPProviders: true)

  static let appStore = StoreCapabilityProfile(
    edition: .appStore,
    allowsProcessProviders: false,
    allowsExternalAgentConnector: false,
    allowsSelfUpdater: false,
    allowsAutomaticPaste: false,
    allowsUserProvidedExecutables: false,
    allowsModelImport: true,
    allowsHTTPProviders: true)

  static var current: StoreCapabilityProfile {
    #if WOICE_APP_STORE
      return .appStore
    #else
      return .website
    #endif
  }
}
