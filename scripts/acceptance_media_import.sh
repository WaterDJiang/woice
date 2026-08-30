#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
swift test --no-parallel --filter MediaImportTests
rg -q 'MediaImportSheet' Sources/WoiceApp/WorkspaceView.swift
rg -q 'fileImporter' Sources/WoiceApp/MediaImportSheet.swift
rg -F -q '@Environment(\.dismiss)' Sources/WoiceApp/MediaImportSheet.swift
rg -q 'onDismiss: handleMediaImportDismissal' Sources/WoiceApp/WorkspaceView.swift
rg -q 'MediaImportSheetDismissalDestination' Sources/WoiceApp/MediaImportSheet.swift
rg -q '关闭并后台继续' Sources/WoiceApp/MediaImportSheet.swift
rg -q 'prepareTranscriptionAudio' Sources/WoiceApp/AudioPreparationService.swift
rg -q 'AudioChunkingService' Sources/WoiceApp/AppState.swift
rg -q 'defaultMaximumUploadBytes' Sources/WoiceApp/AudioChunkingService.swift
rg -q '损坏的媒体导入失败且不会留下半成品' Tests/WoiceAppTests/MediaImportTests.swift
rg -q '损坏视频报告音轨读取失败而不是原始文件保存失败' Tests/WoiceAppTests/MediaImportTests.swift
rg -q 'WOICE_MEDIA_IMPORT_EXPECT_FAILURE' scripts/acceptance_media_import_desktop.sh
rg -q '视频音轨；文件可能损坏或格式不受支持' Sources/WoiceApp/MediaImportService.swift
echo "acceptance-media-import-transcription: contract passed; real audio/video desktop journey remains required"
