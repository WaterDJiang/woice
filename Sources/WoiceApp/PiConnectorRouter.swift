import Foundation
import WoiceCore

#if !WOICE_APP_STORE
  #if !WOICE_APP_STORE
    enum PiConnectorRouterError: LocalizedError, Equatable {
      case missingRecordingID
      case recordingNotFound
      case transcriptUnavailable
      case transformUnavailable
      case permissionDenied(AgentPermissionLevel)
      case invalidPagination
      case unsupportedMaterialField

      var errorDescription: String? {
        switch self {
        case .missingRecordingID: "PI 请求缺少 recording_id。"
        case .recordingNotFound: "找不到请求的录音。"
        case .transcriptUnavailable: "这条录音还没有原文。"
        case .transformUnavailable: "当前没有可用的 Markdown 处理服务。"
        case .permissionDenied(let level): "当前 Connector 未获准执行“\(level.label)”权限。"
        case .invalidPagination: "素材分页参数无效或超过安全上限。"
        case .unsupportedMaterialField: "当前只允许分页读取规范化原文。"
        }
      }
    }

    private struct ConnectorMaterialSegment: Codable {
      let start: TimeInterval
      let end: TimeInterval
      let text: String
      let sourceTrack: String?
    }

    private struct ConnectorMaterialSummary: Codable {
      let artifactID: String
      let recordingID: String
      let createdAt: Date
      let duration: TimeInterval
      let status: String
      let statusLabel: String
      let transcriptAvailable: Bool
      let preview: String
    }
  #endif

  @MainActor
  final class PiConnectorRouter {
    private unowned let appState: AppState

    init(appState: AppState) {
      self.appState = appState
    }

    func handle(_ request: PiConnectorRequest) -> PiConnectorResponse {
      do {
        let _ = try request.validated()
        if let requiredPermission = request.method.requiredPermission,
          !appState.settings.agentPermissions.allows(requiredPermission)
        {
          throw PiConnectorRouterError.permissionDenied(requiredPermission)
        }
        switch request.method {
        case .status:
          return response(
            request,
            result: [
              "state": appState.processingState.label,
              "recording_count": String(appState.recordings.count),
              "is_recording": appState.isRecording ? "true" : "false",
            ]
          )
        case .listRecordings:
          let ids = appState.recordings.map(\.id.uuidString).joined(separator: ",")
          return response(
            request,
            result: ["count": String(appState.recordings.count), "recording_ids": ids]
          )
        case .readTranscript:
          let record = try record(for: request)
          guard let transcript = record.transcript, !transcript.isEmpty else {
            throw PiConnectorRouterError.transcriptUnavailable
          }
          let readable = TranscriptTextNormalizer.normalize(transcript)
          guard !readable.isEmpty else { throw PiConnectorRouterError.transcriptUnavailable }
          let bounded = String(
            decoding: Data(readable.utf8).prefix(64 * 1024), as: UTF8.self)
          auditInbound(
            request: request,
            artifactIDs: ["recording:\(record.id.uuidString):transcript"],
            dataTypes: [.transcript])
          return response(
            request,
            result: ["recording_id": record.id.uuidString, "text": bounded]
          )
        case .readMaterial:
          let record = try record(for: request)
          auditInbound(
            request: request,
            artifactIDs: [
              "recording:\(record.id.uuidString):audio",
              "recording:\(record.id.uuidString):transcript",
            ],
            dataTypes: [.audio, .transcript])
          return response(request, result: materialResult(for: record))
        case .searchMaterials:
          return response(request, result: try searchResult(for: request))
        case .readMaterialPage:
          let record = try record(for: request)
          let result = try materialPageResult(for: record, request: request)
          auditInbound(
            request: request,
            artifactIDs: ["recording:\(record.id.uuidString):transcript"],
            dataTypes: [.transcript])
          return response(request, result: result)
        case .requestTransform:
          let record = try record(for: request)
          guard !appState.settings.llmEndpoint.isEmpty,
            let transcript = record.transcript, !transcript.isEmpty
          else { throw PiConnectorRouterError.transformUnavailable }
          appState.requestMarkdown(for: record)
          return response(
            request,
            result: [
              "recording_id": record.id.uuidString,
              "state": "awaiting_user_confirmation",
              "requires_user_confirmation": "true",
              "confirmation_stage": "user",
            ]
          )
        }
      } catch let error as PiConnectorRouterError {
        return failure(request, error: error)
      } catch let error as PiConnectorProtocolError {
        return PiConnectorResponse(
          requestID: request.requestID,
          error: PiConnectorErrorPayload(
            code: "INVALID_REQUEST", message: error.localizedDescription)
        )
      } catch {
        return PiConnectorResponse(
          requestID: request.requestID,
          error: PiConnectorErrorPayload(
            code: "INTERNAL_ERROR", message: error.localizedDescription)
        )
      }
    }

    private func record(for request: PiConnectorRequest) throws -> RecordingRecord {
      guard let idValue = request.parameters["recording_id"], let id = UUID(uuidString: idValue)
      else { throw PiConnectorRouterError.missingRecordingID }
      guard let record = appState.recordings.first(where: { $0.id == id }) else {
        throw PiConnectorRouterError.recordingNotFound
      }
      return record
    }

    private func response(_ request: PiConnectorRequest, result: [String: String])
      -> PiConnectorResponse
    {
      PiConnectorResponse(requestID: request.requestID, result: result)
    }

    private func materialResult(for record: RecordingRecord) -> [String: String] {
      let readableTranscript = TranscriptTextNormalizer.normalize(record.transcript ?? "")
      let segments = (record.transcriptSegments ?? []).map {
        ConnectorMaterialSegment(
          start: $0.start,
          end: $0.end,
          text: TranscriptTextNormalizer.normalize($0.text),
          sourceTrack: $0.sourceTrack?.rawValue)
      }
      let segmentsJSON = encodedBounded(segments) ?? "[]"
      let sourceFiles = [
        "microphone": record.audioFileName,
        "systemAudio": record.systemAudioFileName,
        "meetingMix": record.meetingMixFileName,
      ].compactMapValues { $0 }
      return [
        "artifact_id": "recording:\(record.id.uuidString)",
        "recording_id": record.id.uuidString,
        "created_at": record.createdAt.formatted(.iso8601),
        "duration": String(record.duration),
        "status": record.materialStatus.rawValue,
        "status_label": record.materialStatus.label,
        "transcript_available": readableTranscript.isEmpty ? "false" : "true",
        "transcript": bounded(readableTranscript),
        "segments_json": segmentsJSON,
        "source_files_json": encodedBounded(sourceFiles) ?? "{}",
      ]
    }

    private func searchResult(for request: PiConnectorRequest) throws -> [String: String] {
      let query = request.parameters["query"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let (offset, limit) = try collectionPagination(from: request)
      let matchingRecords = appState.recordings.filter { matches($0, query: query) }
      let page = Array(matchingRecords.dropFirst(offset).prefix(limit))
      auditInbound(
        request: request,
        artifactIDs: page.map { "recording:\($0.id.uuidString)" },
        dataTypes: [.audio, .transcript])
      let summaries = page.map { record in
        let transcript = TranscriptTextNormalizer.normalize(record.transcript ?? "")
        return ConnectorMaterialSummary(
          artifactID: "recording:\(record.id.uuidString)",
          recordingID: record.id.uuidString,
          createdAt: record.createdAt,
          duration: record.duration,
          status: record.materialStatus.rawValue,
          statusLabel: record.materialStatus.label,
          transcriptAvailable: !transcript.isEmpty,
          preview: String(transcript.prefix(240))
        )
      }
      return [
        "query": query,
        "count": String(matchingRecords.count),
        "offset": String(offset),
        "limit": String(limit),
        "has_more": (offset + page.count < matchingRecords.count) ? "true" : "false",
        "results_json": encodedBounded(summaries) ?? "[]",
      ]
    }

    private func materialPageResult(
      for record: RecordingRecord, request: PiConnectorRequest
    ) throws -> [String: String] {
      let field = request.parameters["field"] ?? "transcript"
      guard field == "transcript" else { throw PiConnectorRouterError.unsupportedMaterialField }
      let transcript = TranscriptTextNormalizer.normalize(record.transcript ?? "")
      guard !transcript.isEmpty else { throw PiConnectorRouterError.transcriptUnavailable }
      let (offset, requestedLimit) = try textPagination(from: request)
      let characters = Array(transcript)
      guard offset <= characters.count else { throw PiConnectorRouterError.invalidPagination }
      var end = min(characters.count, offset + requestedLimit)
      while end > offset && String(characters[offset..<end]).utf8.count > 64 * 1024 {
        end -= 1
      }
      let text = String(characters[offset..<end])
      let nextOffset = end
      return [
        "artifact_id": "recording:\(record.id.uuidString)",
        "recording_id": record.id.uuidString,
        "field": field,
        "offset": String(offset),
        "limit": String(requestedLimit),
        "total_characters": String(characters.count),
        "next_offset": String(nextOffset),
        "has_more": nextOffset < characters.count ? "true" : "false",
        "text": text,
      ]
    }

    private func collectionPagination(from request: PiConnectorRequest) throws -> (Int, Int) {
      let offset = Int(request.parameters["offset"] ?? "0") ?? -1
      let limit = Int(request.parameters["limit"] ?? "20") ?? -1
      guard offset >= 0, limit > 0, limit <= 100 else {
        throw PiConnectorRouterError.invalidPagination
      }
      return (offset, limit)
    }

    private func textPagination(from request: PiConnectorRequest) throws -> (Int, Int) {
      let offset = Int(request.parameters["offset"] ?? "0") ?? -1
      let limit = Int(request.parameters["limit"] ?? "16384") ?? -1
      guard offset >= 0, limit > 0, limit <= 16_384 else {
        throw PiConnectorRouterError.invalidPagination
      }
      return (offset, limit)
    }

    private func matches(_ record: RecordingRecord, query: String) -> Bool {
      let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
      guard !terms.isEmpty else { return true }
      let transcript = TranscriptTextNormalizer.normalize(record.transcript ?? "")
      let searchable = [
        transcript,
        record.generatedMarkdown ?? "",
        record.createdAt.formatted(.iso8601),
        record.materialStatus.rawValue,
        record.materialStatus.label,
        record.audioFileName,
        record.systemAudioFileName ?? "",
        record.meetingMixFileName ?? "",
        AudioTrackKind.microphone.label,
        AudioTrackKind.systemAudio.label,
        AudioTrackKind.meetingMix.label,
      ].joined(separator: " ")
      return terms.allSatisfy { searchable.localizedCaseInsensitiveContains($0) }
    }

    private func encodedBounded<T: Encodable>(_ value: T) -> String? {
      guard let data = try? JSONEncoder.woice.encode(value) else { return nil }
      return bounded(String(decoding: data.prefix(64 * 1024), as: UTF8.self))
    }

    private func bounded(_ value: String) -> String {
      String(decoding: Data(value.utf8).prefix(64 * 1024), as: UTF8.self)
    }

    private func failure(_ request: PiConnectorRequest, error: PiConnectorRouterError)
      -> PiConnectorResponse
    {
      let code: String
      if case .permissionDenied = error {
        code = "PERMISSION_DENIED"
      } else {
        code = "ROUTER_ERROR"
      }
      return PiConnectorResponse(
        requestID: request.requestID,
        error: PiConnectorErrorPayload(code: code, message: error.localizedDescription)
      )
    }

    private func auditInbound(
      request: PiConnectorRequest,
      artifactIDs: [String],
      dataTypes: [ContextArtifactKind]
    ) {
      _ = appState.recordAgentAudit(
        AgentAuditEvent(
          action: .inboundRead,
          caller: "pi-connector",
          connectorID: "pi",
          jobID: nil,
          traceID: request.requestID,
          artifactIDs: artifactIDs,
          dataTypes: dataTypes,
          outcomeCode: request.method.rawValue))
    }
  }
#endif
