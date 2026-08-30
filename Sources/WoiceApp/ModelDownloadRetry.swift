import Foundation

/// Retries only transport failures that are commonly transient for model
/// downloads. The caller remains responsible for preserving resumable state.
enum ModelDownloadRetry {
  static let defaultAttempts = 3
  static let defaultDelayNanoseconds: UInt64 = 1_000_000_000

  static func run<Value: Sendable>(
    attempts: Int = defaultAttempts,
    delayNanoseconds: UInt64 = defaultDelayNanoseconds,
    operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    let maximumAttempts = max(1, attempts)
    var attempt = 0

    while true {
      try Task.checkCancellation()
      do {
        return try await operation()
      } catch let error as CancellationError {
        throw error
      } catch {
        attempt += 1
        guard attempt < maximumAttempts, isTransient(error) else {
          throw error
        }
        let multiplier = UInt64(1 << min(attempt - 1, 2))
        try await Task.sleep(nanoseconds: delayNanoseconds * multiplier)
      }
    }
  }

  static func isTransient(_ error: Error) -> Bool {
    if error is CancellationError { return false }
    if let urlError = error as? URLError {
      return transientCodes.contains(urlError.code)
    }

    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
      let code = URLError.Code(rawValue: nsError.code)
      return transientCodes.contains(code)
    }

    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
      return isTransient(underlying)
    }
    return false
  }

  private static let transientCodes: Set<URLError.Code> = [
    .cannotConnectToHost,
    .cannotFindHost,
    .dataNotAllowed,
    .dnsLookupFailed,
    .networkConnectionLost,
    .notConnectedToInternet,
    .resourceUnavailable,
    .secureConnectionFailed,
    .timedOut,
    .internationalRoamingOff,
  ]
}
