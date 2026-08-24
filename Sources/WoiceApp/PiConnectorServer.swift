import Darwin
import Foundation
import WoiceCore
import os

#if !WOICE_APP_STORE
  #if !WOICE_APP_STORE
    enum PiConnectorServerError: LocalizedError, Equatable {
      case socketPathTooLong
      case existingPathIsNotSocket
      case alreadyRunning
      case socketCreationFailed
      case bindFailed
      case listenFailed

      var errorDescription: String? {
        switch self {
        case .socketPathTooLong: "Woice 本地 Socket 路径过长，无法安全创建。"
        case .existingPathIsNotSocket: "Woice Socket 目标已存在但不是 Socket，已拒绝覆盖。"
        case .alreadyRunning: "Woice 本地 Connector 已在运行。"
        case .socketCreationFailed: "Woice 无法创建本地 Connector Socket。"
        case .bindFailed: "Woice 无法绑定本地 Connector Socket。"
        case .listenFailed: "Woice 无法监听本地 Connector Socket。"
        }
      }
    }

    /// Current-user-only JSON Lines transport for PI and future local connectors.
    /// POSIX accept/read keeps the transport independent from the AppKit main loop;
    /// only the Router call is marshalled onto MainActor.
    final class PiConnectorServer: @unchecked Sendable {
      nonisolated static let maximumRequestBytes = 64 * 1024
      nonisolated static let connectionTimeout: TimeInterval = 5
      private static let logger = Logger(subsystem: "com.woice.app", category: "pi-connector")

      let socketURL: URL
      private let router: PiConnectorRouter
      private let listenerQueue = DispatchQueue(label: "com.woice.pi-listener", qos: .utility)
      private let clientQueue = DispatchQueue(label: "com.woice.pi-client", qos: .utility)
      private let stateLock = NSLock()
      private var listenerFD: Int32 = -1
      private var clientFDs: Set<Int32> = []

      init(router: PiConnectorRouter, socketURL: URL) {
        self.router = router
        self.socketURL = socketURL
      }

      var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return listenerFD >= 0
      }

      func start() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard listenerFD < 0 else { throw PiConnectorServerError.alreadyRunning }
        guard socketURL.path.utf8.count < 104 else {
          throw PiConnectorServerError.socketPathTooLong
        }
        try prepareSocketPath()

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw PiConnectorServerError.socketCreationFailed }
        do {
          try bind(descriptor: descriptor)
          guard Darwin.listen(descriptor, 8) == 0 else {
            throw PiConnectorServerError.listenFailed
          }
          guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
            throw PiConnectorServerError.listenFailed
          }
        } catch {
          Darwin.close(descriptor)
          Self.removeSocketPathIfOwned(at: socketURL.path)
          throw error
        }

        _ = chmod(socketURL.path, S_IRUSR | S_IWUSR)
        listenerFD = descriptor
        listenerQueue.async { [weak self] in self?.acceptLoop() }
        Self.logger.info("PI Socket listener started")
      }

      func stop() {
        stateLock.lock()
        let descriptor = listenerFD
        listenerFD = -1
        let clients = clientFDs
        clientFDs.removeAll()
        stateLock.unlock()

        if descriptor >= 0 { Darwin.close(descriptor) }
        for descriptor in clients { Darwin.close(descriptor) }
        Self.removeSocketPathIfOwned(at: socketURL.path)
      }

      private func prepareSocketPath() throws {
        let path = socketURL.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        var info = stat()
        guard lstat(path, &info) == 0 else { return }
        guard (info.st_mode & S_IFMT) == S_IFSOCK else {
          throw PiConnectorServerError.existingPathIsNotSocket
        }
        _ = unlink(path)
      }

      private func bind(descriptor: Int32) throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketURL.path.utf8CString)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        // Darwin's sockaddr_un layout is sun_len (1), sun_family (1), sun_path (104).
        // Deriving the path offset from sa_family_t alone would overwrite sun_family.
        let pathOffset = MemoryLayout<UInt8>.size + MemoryLayout<sa_family_t>.size
        guard pathBytes.count <= capacity else {
          throw PiConnectorServerError.socketPathTooLong
        }
        address.sun_len = UInt8(pathOffset + pathBytes.count)
        withUnsafeMutablePointer(to: &address) { pointer in
          let rawPointer = UnsafeMutableRawPointer(pointer)
            .advanced(by: pathOffset)
          rawPointer.initializeMemory(as: UInt8.self, repeating: 0, count: capacity)
          pathBytes.withUnsafeBytes { source in
            guard let sourceBase = source.baseAddress else { return }
            memcpy(rawPointer, sourceBase, pathBytes.count)
          }
        }
        let addressLength = socklen_t(pathOffset + pathBytes.count)
        let result = withUnsafePointer(to: &address) { pointer in
          pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(descriptor, $0, addressLength)
          }
        }
        guard result == 0 else { throw PiConnectorServerError.bindFailed }
      }

      private func acceptLoop() {
        while true {
          stateLock.lock()
          let listenerFD = self.listenerFD
          stateLock.unlock()
          guard listenerFD >= 0 else { return }
          let descriptor = Darwin.accept(listenerFD, nil, nil)
          guard descriptor >= 0 else {
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK {
              usleep(10_000)
              continue
            }
            return
          }
          // The listener is non-blocking; make accepted clients blocking so the
          // bounded read loop can wait for the request body until its deadline.
          _ = fcntl(descriptor, F_SETFL, 0)
          stateLock.lock()
          clientFDs.insert(descriptor)
          stateLock.unlock()
          clientQueue.async { [weak self] in self?.handleClient(descriptor) }
        }
      }

      private func handleClient(_ descriptor: Int32) {
        var responsePending = false
        defer {
          if !responsePending { removeClient(descriptor) }
        }
        var buffer = Data()
        let deadline = Date().addingTimeInterval(Self.connectionTimeout)
        while buffer.count <= Self.maximumRequestBytes {
          guard waitForReadable(descriptor, until: deadline) else {
            sendErrorAndClose(descriptor: descriptor, code: "REQUEST_TIMEOUT")
            return
          }
          var bytes = [UInt8](repeating: 0, count: 4_096)
          let count = Darwin.read(descriptor, &bytes, bytes.count)
          if count > 0 {
            buffer.append(contentsOf: bytes.prefix(count))
            if buffer.contains(0x0A) { break }
            continue
          }
          if count == 0 { return }
          if errno == EINTR { continue }
          return
        }

        guard buffer.count <= Self.maximumRequestBytes else {
          sendErrorAndClose(descriptor: descriptor, code: "REQUEST_TOO_LARGE")
          return
        }
        guard let newline = buffer.firstIndex(of: 0x0A) else {
          sendErrorAndClose(descriptor: descriptor, code: "REQUEST_TIMEOUT")
          return
        }
        let line = Data(buffer[..<newline])
        Self.logger.debug("PI Socket received request bytes: \(line.count, privacy: .public)")
        responsePending = true
        Task { @MainActor [weak self] in
          guard let self else {
            Darwin.close(descriptor)
            return
          }
          let response = self.route(line)
          Self.write(response: response, to: descriptor)
          self.removeClient(descriptor)
        }
      }

      private func waitForReadable(_ descriptor: Int32, until deadline: Date) -> Bool {
        while true {
          let remaining = deadline.timeIntervalSinceNow
          guard remaining > 0 else { return false }
          let timeoutMilliseconds = Int32(
            min(Double(Int32.max), max(1, (remaining * 1_000).rounded(.up))))
          var event = pollfd(
            fd: descriptor,
            events: Int16(POLLIN),
            revents: 0
          )
          let result = Darwin.poll(&event, 1, timeoutMilliseconds)
          if result > 0 {
            let readableEvents = Int16(POLLIN | POLLHUP | POLLERR)
            return event.revents & readableEvents != 0
          }
          if result == 0 { return false }
          if errno != EINTR { return false }
        }
      }

      @MainActor
      private func route(_ line: Data) -> PiConnectorResponse {
        do {
          let request = try JSONDecoder().decode(PiConnectorRequest.self, from: line)
          return router.handle(request)
        } catch {
          return PiConnectorResponse(
            requestID: "",
            error: PiConnectorErrorPayload(
              code: "INVALID_REQUEST", message: error.localizedDescription)
          )
        }
      }

      private nonisolated static func write(response: PiConnectorResponse, to descriptor: Int32) {
        guard var data = try? JSONEncoder().encode(response) else { return }
        data.append(0x0A)
        data.withUnsafeBytes { rawBuffer in
          guard let baseAddress = rawBuffer.baseAddress else { return }
          var written = 0
          while written < rawBuffer.count {
            let result = Darwin.write(
              descriptor, baseAddress.advanced(by: written), rawBuffer.count - written)
            if result <= 0 {
              if errno == EINTR { continue }
              break
            }
            written += result
          }
        }
      }

      private func sendErrorAndClose(descriptor: Int32, code: String) {
        let message = code == "REQUEST_TOO_LARGE" ? "请求超过 64 KiB 限制。" : "请求无效或超时。"
        let response = PiConnectorResponse(
          requestID: "", error: PiConnectorErrorPayload(code: code, message: message))
        Self.write(response: response, to: descriptor)
      }

      private func removeClient(_ descriptor: Int32) {
        stateLock.lock()
        clientFDs.remove(descriptor)
        stateLock.unlock()
        Darwin.close(descriptor)
      }

      private nonisolated static func removeSocketPathIfOwned(at path: String) {
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK else { return }
        _ = unlink(path)
      }

      deinit {
        stop()
      }
    }
  #endif
#endif
