import Foundation
import Security
import WoiceCore

struct ProviderTrustReport: Equatable, Sendable {
  let state: ProviderTrustState
  let identifier: String?
  let teamIdentifier: String?
  let errorCode: Int32?

  var isTrusted: Bool {
    state == .bundledSigned || state == .signatureVerified
  }
}

enum ProviderTrustVerifier {
  static func verify(
    manifest: ProcessProviderManifest, expectedTeamIdentifier: String? = nil
  ) -> ProviderTrustReport {
    let url = URL(fileURLWithPath: manifest.executablePath) as CFURL
    var staticCode: SecStaticCode?
    let createStatus = SecStaticCodeCreateWithPath(url, SecCSFlags(), &staticCode)
    guard createStatus == errSecSuccess, let staticCode else {
      return ProviderTrustReport(
        state: .rejected, identifier: nil, teamIdentifier: nil, errorCode: createStatus)
    }

    let validityStatus = SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil)
    guard validityStatus == errSecSuccess else {
      return ProviderTrustReport(
        state: .rejected, identifier: nil, teamIdentifier: nil, errorCode: validityStatus)
    }

    let signingInfo = signingInformation(for: staticCode)
    let identifier = signingInfo?[kSecCodeInfoIdentifier as String] as? String
    let teamIdentifier = signingInfo?[kSecCodeInfoTeamIdentifier as String] as? String
    if let expectedTeamIdentifier, teamIdentifier != expectedTeamIdentifier {
      return ProviderTrustReport(
        state: .rejected,
        identifier: identifier,
        teamIdentifier: teamIdentifier,
        errorCode: errSecCSHostReject
      )
    }

    let state: ProviderTrustState =
      manifest.source == .bundled ? .bundledSigned : .signatureVerified
    return ProviderTrustReport(
      state: state, identifier: identifier, teamIdentifier: teamIdentifier, errorCode: nil)
  }

  private static func signingInformation(for code: SecStaticCode) -> [String: Any]? {
    var information: CFDictionary?
    guard SecCodeCopySigningInformation(code, SecCSFlags(), &information) == errSecSuccess,
      let information
    else { return nil }
    return information as? [String: Any]
  }
}
