import Foundation
import Testing

@testable import WoiceApp

private actor RetryAttemptCounter {
  private(set) var count = 0

  func increment() -> Int {
    count += 1
    return count
  }
}

@Test("瞬时模型下载错误会有限重试")
func transientModelDownloadErrorRetriesThenSucceeds() async throws {
  let counter = RetryAttemptCounter()
  let result: String = try await ModelDownloadRetry.run(
    attempts: 3, delayNanoseconds: 0
  ) {
    if await counter.increment() == 1 {
      throw URLError(.secureConnectionFailed)
    }
    return "installed"
  }

  #expect(result == "installed")
  #expect(await counter.count == 2)
}

@Test("不可恢复模型下载错误不会重试")
func permanentModelDownloadErrorIsNotRetried() async {
  let counter = RetryAttemptCounter()
  var didThrow = false
  do {
    let _: String = try await ModelDownloadRetry.run(
      attempts: 3, delayNanoseconds: 0
    ) {
      _ = await counter.increment()
      throw URLError(.badServerResponse)
    }
  } catch {
    didThrow = true
  }

  #expect(didThrow)
  #expect(await counter.count == 1)
}

@Test("取消模型下载不会重试")
func cancelledModelDownloadIsNotRetried() async {
  let counter = RetryAttemptCounter()
  var didThrow = false
  do {
    let _: String = try await ModelDownloadRetry.run(
      attempts: 3, delayNanoseconds: 0
    ) {
      _ = await counter.increment()
      throw CancellationError()
    }
  } catch is CancellationError {
    didThrow = true
  } catch {
    didThrow = true
  }

  #expect(didThrow)
  #expect(await counter.count == 1)
}
