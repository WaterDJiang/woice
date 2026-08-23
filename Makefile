SHELL := /bin/zsh

APP_NAME := Woice
BUILD_DIR := .build/release
APP_BUNDLE := build/Woice.app

.PHONY: docs-check harness-check connectors-check mcp-check project build test package package-core package-offline package-dmg-core package-dmg-offline release-adhoc model-benchmark-fixture model-benchmark model-benchmark-strict install format lint acceptance-core acceptance-whisperkit acceptance-meeting acceptance-meeting-transcription acceptance-settings acceptance-material acceptance-recovery acceptance-catalog acceptance-interruption acceptance-offline-model acceptance-local-provider acceptance-agent-outbound acceptance-agent-inbound acceptance-agent-external-inbound acceptance-workspace-sidebar acceptance-media-import-transcription acceptance-media-import-desktop acceptance-permission-continuity acceptance-stable-upgrade acceptance-launch-window acceptance-accessibility-runtime verify verify-core verify-offline

docs-check:
	@test -f doc/INDEX.md
	@test -f doc/spec/INDEX.md
	@test -f doc/plan/INDEX.md
	@test -f doc/log/INDEX.md
	@test -f doc/design/INDEX.md
	@test -f doc/plan/2026-08-22-m0-mvp.md
	@test -f doc/plan/2026-08-22-current-roadmap-and-plan-transition.md
	@test -f doc/plan/2026-08-22-model-integration.md
	@test -f doc/plan/2026-08-22-voice-context-agent-integration.md
	@test -f doc/spec/2026-08-22-product-research-and-design-draft.md
	@test -f doc/spec/2026-08-22-voice-context-source-positioning.md
	@test -f doc/spec/2026-08-22-settings-menu-experience.md
	@test -f doc/spec/2026-08-22-model-download-status-display.md
	@test -f doc/spec/2026-08-22-independent-tts-and-background-transcription.md
	@test -f doc/spec/2026-08-22-dual-edition-model-integration.md
	@test -f doc/spec/2026-08-22-local-asr-model-closed-loop.md
	@test -f doc/design/2026-08-22-model-onboarding-provider-architecture.md
	@test -f doc/design/2026-08-22-argmax-oss-whisperkit-dependency.md
	@test -f doc/design/2026-08-22-voice-context-agent-collaboration.md
	@test -f scripts/package_distribution.py
	@test -f scripts/package_dmg.py
	@test -f scripts/acceptance_agent_external_inbound.mjs
	@test -x scripts/acceptance_workspace_sidebar.sh
	@test -x scripts/acceptance_media_import.sh
	@test -x scripts/acceptance_permission_continuity.sh
	@test -x scripts/acceptance_stable_upgrade.sh
	@test -x scripts/acceptance_launch_window.sh
	@test -f scripts/run_model_benchmark.sh
	@test -f Resources/NOTICES.md
	@test -f doc/spec/2026-08-22-recording-ui-fix.md
	@test -f doc/spec/2026-08-22-recording-audio-monitoring-fix.md
	@test -f doc/spec/2026-08-22-m2-audio-review-transcription.md
	@test -f doc/spec/2026-08-22-m2-system-audio-dual-track.md
	@test -f doc/spec/2026-08-22-m2-system-audio-capture.md
	@test -f doc/spec/2026-08-22-m2-vad-segmentation-foundation.md
	@test -f doc/spec/2026-08-22-m2-transcription-timestamps.md
	@test -f doc/spec/2026-08-22-m2-structured-note-sections.md
	@test -f doc/spec/2026-08-22-m2-processing-recovery.md
	@test -f doc/spec/2026-08-22-m2-sqlite-job-lease.md
	@test -f doc/spec/2026-08-22-m2-accessibility-paste.md
	@test -f doc/spec/2026-08-22-m2-tts.md
	@test -f doc/spec/2026-08-22-m2-provider-sdk.md
	@test -f doc/spec/2026-08-22-m2-pi-connector.md
	@test -f doc/spec/2026-08-22-m2-provider-runtime.md
	@test -f doc/spec/2026-08-22-m2-segment-transcription.md
	@test -f doc/spec/2026-08-22-m2-local-rpc-provider-trust.md
	@test -f doc/spec/2026-08-22-m2-pi-extension.md
	@test -f doc/spec/2026-08-22-m2-live-transcription.md
	@test -f doc/spec/2026-08-22-local-asr-http-acceptance.md
	@test -f doc/spec/2026-08-22-global-recording-shortcut.md
	@test -f doc/spec/2026-08-22-configurable-recording-shortcut.md
	@test -f doc/spec/2026-08-22-settings-key-field-ux.md
	@test -f doc/spec/2026-08-22-settings-draft-isolation.md
	@test -f doc/spec/2026-08-22-asr-provider-health-check.md
	@test -f doc/spec/2026-08-22-microphone-input-check.md
	@test -f doc/spec/2026-08-22-transcript-display-and-brand-assets.md
	@test -f doc/spec/2026-08-22-menubar-popover-optimization.md
	@test -f doc/spec/2026-08-22-app-icon-bundle-packaging.md
	@test -f doc/spec/2026-08-22-unified-workspace.md
	@test -f doc/spec/2026-08-22-logo-white-background.md
	@test -f doc/spec/2026-08-22-button-feedback-ux.md
	@test -f doc/spec/2026-08-22-system-audio-and-button-visual-audit.md
	@test -f doc/spec/2026-08-22-menubar-status-mark-clarity.md
	@test -f doc/spec/2026-08-22-system-audio-permission-reliability.md
	@test -f doc/spec/2026-08-22-system-audio-source-observability.md
	@test -f doc/spec/2026-08-22-core-acceptance-harness.md
	@test -f specs/2026-08-23-upgrade-plan-completion-slice.md
	@test -f specs/2026-08-23-catalog-transport-and-key-rotation.md
	@test -f specs/2026-08-23-catalog-model-download-orchestration.md
	@test -f specs/2026-08-23-model-benchmark-matrix.md
	@test -f specs/2026-08-23-background-transcription-durability.md
	@test -f specs/2026-08-23-processing-configuration-snapshot.md
	@test -f specs/2026-08-23-local-asr-service-presets.md
	@test -f specs/2026-08-23-meeting-transcription-acceptance.md
	@test -f specs/2026-08-23-keychain-state-diagnostics.md
	@test -f specs/2026-08-23-keychain-lazy-read.md
	@test -f specs/2026-08-23-language-picker-ux.md
	@test -f specs/2026-08-23-transcript-artifact-lineage.md
	@test -f specs/2026-08-23-model-benchmark-fixture-generator.md
	@test -f specs/2026-08-23-default-model-freeze.md
	@test -f specs/2026-08-23-agent-readonly-search-pagination.md
	@test -f specs/2026-08-23-agent-context-package-contract.md
	@test -f specs/2026-08-23-agent-job-ui-status.md
	@test -f specs/2026-08-23-agent-dispatch-and-results.md
	@test -f specs/2026-08-24-public-github-adhoc-release-preparation.md
	@test -f specs/2026-08-23-media-import-continuity.md
	@test -f specs/2026-08-23-launch-window-continuity.md
	@test -f scripts/acceptance_agent_inbound.mjs
	@test -f Connectors/McpWoice/src/index.mjs
	@test -f Connectors/McpWoice/test/server.test.mjs
	@test -x scripts/create_model_benchmark_fixtures.sh
	@test -f doc/benchmarks/2026-08-23-whisperkit-300s-matrix.md
	@rg -q '唯一跨计划状态源' doc/plan/INDEX.md
	@rg -q '旧 M3 生态.*已停止' doc/plan/INDEX.md
	@rg -q '^> 替代：' doc/plan/2026-08-22-model-integration.md
	@rg -q '^> 停止：' doc/plan/2026-08-22-model-integration.md
	@rg -q '^> 替代：' doc/plan/2026-08-22-voice-context-agent-integration.md
	@rg -q '^> 停止：' doc/plan/2026-08-22-voice-context-agent-integration.md
	@echo "docs-check: ok"

harness-check:
	@test -f AGENTS.md
	@test -f CLAUDE.md
	@rg -q '当前路线图.*current-roadmap-and-plan-transition.md' AGENTS.md
	@test $$(wc -l < AGENTS.md) -lt 200
	@test $$(wc -l < CLAUDE.md) -lt 200
	@! head -n 1 AGENTS.md | rg -q '^---$$'
	@! rg -q '@import|<!--' AGENTS.md
	@test $$(( $$(rg -o '```' AGENTS.md | wc -l) % 2 )) -eq 0
	@test $$(( $$(rg -o '```' CLAUDE.md | wc -l) % 2 )) -eq 0
	@echo "harness-check: ok"

connectors-check:
	@npm test --prefix Connectors/PiWoice
	@$(MAKE) mcp-check

mcp-check:
	@npm test --prefix Connectors/McpWoice

project:
	@test -f Package.swift || { echo "Package.swift 尚未创建；先完成 M0-00"; exit 1; }
	@echo "project: SwiftPM package ready"

build: project
	@swift build -c release

test: project
	@swift test --no-parallel

package: build
	@python3 scripts/package_distribution.py --flavor core --binary "$(BUILD_DIR)/Woice" --info-plist Resources/Info.plist --output "$(APP_BUNDLE)"

package-core: build
	@python3 scripts/package_distribution.py --flavor core --binary "$(BUILD_DIR)/Woice" --info-plist Resources/Info.plist --output build/Woice-Core.app

package-offline: build
	@test -n "$(WOICE_OFFLINE_MODEL_ROOT)" || { echo "WOICE_OFFLINE_MODEL_ROOT 未设置；请显式提供已验证模型目录。"; exit 1; }
	@python3 scripts/package_distribution.py --flavor offline --binary "$(BUILD_DIR)/Woice" --info-plist Resources/Info.plist --model-root "$(WOICE_OFFLINE_MODEL_ROOT)" --output build/Woice-Offline.app

package-dmg-core: package-core
	@python3 scripts/package_dmg.py --app build/Woice-Core.app --output build/Woice-Core.dmg --volume-name Woice-Core

package-dmg-offline: package-offline
	@python3 scripts/package_dmg.py --app build/Woice-Offline.app --output build/Woice-Offline.dmg --volume-name Woice-Offline

release-adhoc: docs-check harness-check build
	@test -n "$(WOICE_OFFLINE_MODEL_ROOT)" || { echo "WOICE_OFFLINE_MODEL_ROOT 未设置；不会伪造 Offline 预发布包。"; exit 1; }
	@WOICE_CODESIGN_IDENTITY=- python3 scripts/package_distribution.py --flavor core --binary "$(BUILD_DIR)/Woice" --info-plist Resources/Info.plist --output build/Woice-Core.app
	@WOICE_CODESIGN_IDENTITY=- python3 scripts/package_distribution.py --flavor offline --binary "$(BUILD_DIR)/Woice" --info-plist Resources/Info.plist --model-root "$(WOICE_OFFLINE_MODEL_ROOT)" --output build/Woice-Offline.app
	@python3 scripts/package_dmg.py --app build/Woice-Core.app --output build/Woice-Core.dmg --volume-name Woice-Core
	@python3 scripts/package_dmg.py --app build/Woice-Offline.app --output build/Woice-Offline.dmg --volume-name Woice-Offline
	@set -euo pipefail; \
		version=$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist); \
		build_version=$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist); \
		release_path="release/$${version}-$${build_version}-arm64-adhoc"; \
		mkdir -p "$$release_path"; \
		ditto build/Woice-Core.dmg "$$release_path/Woice-Core-$${version}-$${build_version}-arm64.dmg"; \
		ditto build/Woice-Offline.dmg "$$release_path/Woice-Offline-$${version}-$${build_version}-arm64.dmg"; \
		codesign --verify --deep --strict build/Woice-Core.app; \
		codesign --verify --deep --strict build/Woice-Offline.app; \
		hdiutil verify "$$release_path/Woice-Core-$${version}-$${build_version}-arm64.dmg" >/dev/null; \
		hdiutil verify "$$release_path/Woice-Offline-$${version}-$${build_version}-arm64.dmg" >/dev/null; \
		test "$$(lipo -archs build/Woice-Core.app/Contents/MacOS/Woice)" = "arm64"; \
		test "$$(lipo -archs build/Woice-Offline.app/Contents/MacOS/Woice)" = "arm64"; \
		(cd "$$release_path" && shasum -a 256 *.dmg > SHA256SUMS.txt); \
		echo "release-adhoc: $$release_path"

model-benchmark: docs-check harness-check
	@test -n "$(WOICE_BENCHMARK_AUDIO_DIR)" || { echo "WOICE_BENCHMARK_AUDIO_DIR 尚未设置；不会伪造模型基准。"; exit 1; }
	@./scripts/run_model_benchmark.sh "$(WOICE_BENCHMARK_AUDIO_DIR)" "$(WOICE_BENCHMARK_OUTPUT)"

model-benchmark-fixture: docs-check harness-check
	@test -n "$(WOICE_BENCHMARK_AUDIO_DIR)" || { echo "WOICE_BENCHMARK_AUDIO_DIR 尚未设置；请显式提供 Fixture 输出目录。"; exit 1; }
	@./scripts/create_model_benchmark_fixtures.sh "$(WOICE_BENCHMARK_AUDIO_DIR)" "$${WOICE_BENCHMARK_MIN_DURATION_SECONDS:-300}"

model-benchmark-strict: docs-check harness-check
	@test -n "$(WOICE_BENCHMARK_AUDIO_DIR)" || { echo "WOICE_BENCHMARK_AUDIO_DIR 尚未设置；不会伪造完整模型基准。"; exit 1; }
	@WOICE_ENFORCE_MODEL_BENCHMARK=1 WOICE_BENCHMARK_MIN_DURATION_SECONDS="$${WOICE_BENCHMARK_MIN_DURATION_SECONDS:-300}" ./scripts/run_model_benchmark.sh --strict "$(WOICE_BENCHMARK_AUDIO_DIR)" "$(WOICE_BENCHMARK_OUTPUT)"

install: package
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@ditto "$(APP_BUNDLE)" "/Applications/Woice.app"
	@echo "install: /Applications/Woice.app"

format:
	@swift format --in-place --recursive Sources Tests

lint:
	@swift format lint --recursive Sources Tests

acceptance-core: docs-check harness-check
	@WOICE_REQUIRE_MIC_AUDIO=1 swift test --no-parallel --filter microphoneInputCheckReportsCapturedFrames
	@WOICE_RUN_APPSTATE_LOOPBACK=1 swift test --no-parallel --filter appStateRecordingTranscribesWithRealLoopbackHTTP
	@WOICE_RUN_APPSTATE_TRANSCRIPTION=1 swift test --no-parallel --filter appStateRecordingTranscribesWithCustomASR
	@swift test --no-parallel --filter localASRClosedLoopPersistsTranscriptAndModelSnapshot
	@WOICE_RUN_APPSTATE_LOCAL_ASR=1 swift test --no-parallel --filter realMicrophoneRoutesToLocalASRWithoutExternalEndpoint
	@swift test --no-parallel --filter transcriptionClientHealthCheckUsesRealLoopbackHTTP
	@swift test --no-parallel --filter audioPlaybackPreparesWAVMetadata
	@echo "acceptance-core: passed (real mic + local/custom ASR + API health check + timestamps + duration + playback metadata)"

acceptance-whisperkit: docs-check harness-check
	@WOICE_RUN_REAL_WHISPERKIT=1 WOICE_INSTALL_REAL_WHISPERKIT=1 swift test --no-parallel --filter realWhisperKitModelPackDownloadsAndTranscribes
	@WOICE_RUN_INSTALLED_WHISPERKIT=1 WOICE_REQUIRE_MIC_AUDIO=1 swift test --no-parallel --filter installedWhisperKitRecordsAndTranscribes
	@echo "acceptance-whisperkit: passed (pinned model download/install + real microphone -> WhisperKit transcript)"

acceptance-meeting: docs-check harness-check
	@./scripts/acceptance_meeting.sh
	@echo "acceptance-meeting: passed (real system sound + dual-track meetingMix)"

acceptance-meeting-transcription: docs-check harness-check
	@swift test --no-parallel --filter meetingTranscriptionModesUseExpectedRequestCounts
	@echo "acceptance-meeting-transcription: passed (both raw tracks transcribed + deterministic merged transcript)"

acceptance-settings: docs-check harness-check
	@swift test --no-parallel --filter 'settingsSaveScopesKeychainAccessToChangedAPIKeys|appStateDefersKeychainReadAndPreservesRuntimeSecret|settingsSectionSaveIgnoresUncommittedOtherSection|settingsFilesSectionSaveIsIndependent|keychainStatusDiagnostics'
	@echo "acceptance-settings: passed (independent section saves + Keychain scope)"

acceptance-material: docs-check harness-check
	@swift test --no-parallel --filter recordingSearchUsesSharedProjection
	@swift test --no-parallel --filter openingMissingMaterialFailsClosed
	@swift test --no-parallel --filter piRouterReadsMaterialProjectionWithoutStartingWork
	@swift test --no-parallel --filter recordingMaterialStatusProjectsDurableFacts
	@echo "acceptance-material: passed (search + external open fail-closed + read-only material projection)"

acceptance-recovery: docs-check harness-check
	@swift test --no-parallel --filter interruptedRecordingJournalRecoversAudio
	@swift test --no-parallel --filter invalidInterruptedRecordingJournalFailsClosed
	@swift test --no-parallel --filter sqliteLegacyImportIsNotRepeated
	@swift test --no-parallel --filter sqliteJobLeaseIsDurable
	@echo "acceptance-recovery: passed (Journal/restart + SQLite recovery contracts; real crash/sleep matrix remains explicit)"

acceptance-interruption: docs-check harness-check
	@WOICE_RUN_RECORDING_INTERRUPTION=1 WOICE_REQUIRE_MIC_AUDIO=1 swift test --no-parallel --filter realRecordingStopsOnAudioConfigurationChange
	@echo "acceptance-interruption: passed (real mic configuration change -> safe stop -> durable audio/transcript)"

acceptance-offline-model: docs-check harness-check
	@test -n "$(WOICE_OFFLINE_MODEL_ROOT)" || { echo "WOICE_OFFLINE_MODEL_ROOT 未设置；不会伪造 Offline 模型验收。"; exit 1; }
	@swift test --no-parallel --filter bundledModelPackIsDiscoverableAndRoutable
	@$(MAKE) verify-offline WOICE_OFFLINE_MODEL_ROOT="$(WOICE_OFFLINE_MODEL_ROOT)"
	@echo "acceptance-offline-model: passed (bundled inventory/routing + Offline DMG verification)"

acceptance-local-provider: docs-check harness-check
	@swift test --no-parallel --filter localASRClosedLoopPersistsTranscriptAndModelSnapshot
	@swift test --no-parallel --filter missingASRProviderPersistsWaitingForModel
	@echo "acceptance-local-provider: passed (local ASR route, snapshot and no-provider fail-closed)"

acceptance-agent-outbound: docs-check harness-check
	@swift test --no-parallel --filter AgentDispatchTests
	@if [[ "$$WOICE_RUN_REAL_AGENT" == "1" ]]; then \
		WOICE_RUN_REAL_AGENT=1 swift test --no-parallel --filter realAgentCLIsDispatchAndCollectArtifacts; \
		echo "acceptance-agent-outbound: fixture and real CLI smoke passed"; \
	else \
		echo "acceptance-agent-outbound: passed (fixture dispatch/result/audit); real CLI smoke remains opt-in with WOICE_RUN_REAL_AGENT=1"; \
	fi

acceptance-agent-inbound: docs-check harness-check connectors-check
	@swift test --no-parallel --filter PiConnectorRouterTests
	@swift test --no-parallel --filter PiConnectorServerTests
	@if [[ "$$WOICE_RUN_REAL_INBOUND" == "1" ]]; then \
		node scripts/acceptance_agent_inbound.mjs; \
		echo "acceptance-agent-inbound: contract and real local MCP smoke passed"; \
	else \
		echo "acceptance-agent-inbound: passed (RPC/MCP read-only contract); real local MCP smoke remains opt-in with WOICE_RUN_REAL_INBOUND=1"; \
	fi

acceptance-agent-external-inbound: docs-check harness-check
	@if [[ "$$WOICE_RUN_EXTERNAL_AGENT_INBOUND" == "1" ]]; then \
		node scripts/acceptance_agent_external_inbound.mjs; \
	else \
		echo "acceptance-agent-external-inbound: synthetic external Agent smoke remains opt-in with WOICE_RUN_EXTERNAL_AGENT_INBOUND=1"; \
	fi

acceptance-workspace-sidebar: docs-check harness-check
	@./scripts/acceptance_workspace_sidebar.sh

acceptance-media-import-transcription: docs-check harness-check
	@./scripts/acceptance_media_import.sh

acceptance-media-import-desktop: docs-check harness-check
	@./scripts/acceptance_media_import_desktop.sh

acceptance-permission-continuity: docs-check harness-check
	@./scripts/acceptance_permission_continuity.sh

acceptance-stable-upgrade: docs-check harness-check
	@./scripts/acceptance_stable_upgrade.sh

acceptance-launch-window: docs-check harness-check
	@./scripts/acceptance_launch_window.sh

acceptance-accessibility-runtime: docs-check harness-check
	@./scripts/acceptance_accessibility_runtime.sh

acceptance-catalog: docs-check harness-check
	@swift test --no-parallel --filter signedModelCatalogVerifiesAndFailsClosed
	@swift test --no-parallel --filter modelCatalogRejectsInvalidTrustInputs
	@swift test --no-parallel --filter modelCatalogStorePersistsTrustedSnapshotAndRejectsRollback
	@swift test --no-parallel --filter modelCatalogKeyRotationPersistsAndRevokesPreviousKey
	@swift test --no-parallel --filter ModelCatalogTransportTests
	@swift test --no-parallel --filter ModelCatalogDownloadTests
	@echo "acceptance-catalog: passed (signature, trust root, rollback, rotation, bounded transport and multi-file download contracts)"

verify: docs-check harness-check connectors-check lint test package

verify-core: docs-check harness-check package-dmg-core
	@codesign --verify --deep --strict build/Woice-Core.app
	@hdiutil verify build/Woice-Core.dmg >/dev/null
	@echo "verify-core: passed"

verify-offline: docs-check harness-check package-dmg-offline
	@codesign --verify --deep --strict build/Woice-Offline.app
	@hdiutil verify build/Woice-Offline.dmg >/dev/null
	@echo "verify-offline: passed"
