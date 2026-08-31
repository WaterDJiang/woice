import Foundation
import Security
import WoiceCore

enum KeychainStoreDiagnostics {
  static func failureMessage(operation: String, status: OSStatus) -> String {
    switch status {
    case errSecInteractionNotAllowed, errSecNotAvailable:
      return "钥匙串当前未解锁，无法\(operation)；请在“钥匙串访问”中解锁 login 后重试。"
    case errSecAuthFailed:
      return "macOS 拒绝了钥匙串访问，无法\(operation)；请确认 Woice 已被允许访问 login 钥匙串后重试。"
    case errSecMissingEntitlement:
      return "当前 Woice 安装包缺少钥匙串权限，无法\(operation)；请重新安装签名包后重试。"
    case errSecUserCanceled:
      return "你取消了钥匙串授权，本次设置未保存。"
    default:
      return "钥匙串\(operation)失败（\(status)）。本次设置未保存。"
    }
  }
}

protocol KeychainStoring {
  func read(account: String) -> String
  func write(_ value: String, account: String) throws
  func remove(account: String)
}

struct KeychainStore: KeychainStoring {
  private let service: String

  init(service: String = WoiceAppChannel.current.keychainService) {
    self.service = service
  }

  func read(account: String) -> String {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data,
      let value = String(data: data, encoding: .utf8)
    else {
      return ""
    }
    return value
  }

  func write(_ value: String, account: String) throws {
    let data = Data(value.utf8)
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
    ]
    let attributes: [CFString: Any] = [kSecValueData: data]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var item = query
      item[kSecValueData] = data
      let addStatus = SecItemAdd(item as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw WoiceError.storageFailure(
          KeychainStoreDiagnostics.failureMessage(operation: "写入", status: addStatus))
      }
    } else if status != errSecSuccess {
      throw WoiceError.storageFailure(
        KeychainStoreDiagnostics.failureMessage(operation: "更新", status: status))
    }
  }

  func remove(account: String) {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
    ]
    _ = SecItemDelete(query as CFDictionary)
  }
}
