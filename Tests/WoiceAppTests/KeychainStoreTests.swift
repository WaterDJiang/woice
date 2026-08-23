import Security
import Testing

@testable import WoiceApp

@Test("Keychain 状态转换为可执行且不泄露密钥的文案")
func keychainStatusDiagnosticsAreActionable() {
  #expect(
    KeychainStoreDiagnostics.failureMessage(
      operation: "写入", status: errSecInteractionNotAllowed
    ).contains("解锁 login"))
  #expect(
    KeychainStoreDiagnostics.failureMessage(
      operation: "更新", status: errSecAuthFailed
    ).contains("Woice 已被允许访问"))
  #expect(
    KeychainStoreDiagnostics.failureMessage(
      operation: "写入", status: errSecMissingEntitlement
    ).contains("重新安装签名包"))
  #expect(
    KeychainStoreDiagnostics.failureMessage(
      operation: "写入", status: errSecUserCanceled
    ).contains("本次设置未保存"))

  let unknown = KeychainStoreDiagnostics.failureMessage(operation: "写入", status: -12345)
  #expect(unknown.contains("-12345"))
  #expect(!unknown.contains("secret"))
}
