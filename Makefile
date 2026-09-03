SHELL := /bin/zsh

APP_NAME := Woice
BUILD_DIR := .build/release
DEV_APP_NAME := Woice (Dev)
APP_BUNDLE := build/$(DEV_APP_NAME).app
DIRECT_XCODE_APP := .build/xcode-direct-derived/Build/Products/Release-Direct/$(DEV_APP_NAME).app
DEV_INSTALL_APP := /Applications/$(DEV_APP_NAME).app

.PHONY: docs-check harness-check appicon-check release-manifest-check model-package-check model-catalog-check local-app-cleanup-check release-verify-remote store-capability-check connectors-check mcp-check project xcode-project xcode-list xcode-build-direct xcode-build-store build test package package-core package-offline package-store package-dmg-core package-dmg-offline release-adhoc release-developer-id model-catalog model-benchmark-fixture model-benchmark model-benchmark-strict model-benchmark-qwen model-benchmark-qwen-strict model-benchmark-qwen-only-strict model-benchmark-qwen-reference-fixture model-benchmark-qwen-official-reference material-benchmark-fixture material-benchmark install format lint acceptance-core acceptance-whisperkit acceptance-meeting acceptance-meeting-transcription acceptance-settings acceptance-material acceptance-recovery acceptance-catalog acceptance-interruption acceptance-offline-model acceptance-local-provider acceptance-agent-outbound acceptance-agent-inbound acceptance-agent-external-inbound acceptance-workspace-sidebar acceptance-media-import-transcription acceptance-media-import-desktop acceptance-permission-continuity acceptance-stable-upgrade acceptance-launch-window acceptance-accessibility-runtime verify verify-core verify-offline verify-app-store archive-app-store acceptance-app-store-sandbox acceptance-app-store-clean-user

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
	@test -f scripts/check_appicon_source.sh
	@test -x scripts/check_appicon_source.sh
	@test -f scripts/release_developer_id.sh
	@test -x scripts/release_developer_id.sh
	@test -f scripts/release_artifact_manifest.py
	@test -x scripts/release_artifact_manifest.py
	@test -f scripts/test_release_artifact_manifest.py
	@test -f scripts/test_package_distribution.py
	@test -f scripts/test_generate_model_catalog.py
	@test -f scripts/cleanup_local_apps.py
	@test -x scripts/cleanup_local_apps.py
	@test -f scripts/test_cleanup_local_apps.py
	@test -f specs/2026-08-31-dev-store-app-naming-and-cleanup.md
	@test -f Resources/Woice.entitlements
	@test -f Resources/Woice-Store.entitlements
	@test -f Resources/PrivacyInfo.xcprivacy
	@test -f Resources/DistributionManifest.json
	@test -f Resources/SBOM.json
	@test -f assets/app-store/README.md
	@test -f assets/app-store/privacy-policy-draft.md
	@test -f assets/app-store/app-privacy-draft.md
	@test -f assets/app-store/apple-submission-reference.md
	@test -f App/WoiceApp/README.md
	@test -f scripts/verify_app_store.py
	@test -x scripts/verify_app_store.py
	@test -f scripts/verify_xcode_store_bundle.py
	@test -f scripts/test_verify_xcode_store_bundle.py
	@test -f scripts/archive_app_store.sh
	@test -x scripts/archive_app_store.sh
	@test -f project.yml
	@test -f Woice.xcodeproj/project.pbxproj
	@test -f scripts/acceptance_app_store_clean_user.sh
	@test -x scripts/acceptance_app_store_clean_user.sh
	@test -f specs/2026-08-24-technical-development-closure.md
	@test -f specs/2026-08-24-mas-capability-slice.md
	@test -f specs/2026-08-24-mas-release-gates.md
	@test -f specs/2026-08-24-microphone-capture-readiness.md
	@test -f doc/plan/2026-08-24-current-technical-development-closure.md
	@test -f scripts/acceptance_agent_external_inbound.mjs
	@test -x scripts/acceptance_workspace_sidebar.sh
	@test -x scripts/acceptance_media_import.sh
	@test -x scripts/acceptance_permission_continuity.sh
	@test -x scripts/acceptance_stable_upgrade.sh
	@test -x scripts/acceptance_launch_window.sh
	@test -f scripts/run_model_benchmark.sh
	@test -x scripts/fetch_qwen_reference_fixtures.sh
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
	@test -x scripts/create_material_benchmark_fixtures.sh
	@test -f Tests/WoiceAppTests/MaterialBenchmarkTests.swift
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

appicon-check: docs-check harness-check
	@./scripts/check_appicon_source.sh

release-manifest-check: docs-check harness-check
	@python3 scripts/test_release_artifact_manifest.py

model-package-check: docs-check harness-check
	@python3 scripts/test_package_distribution.py

model-catalog-check: docs-check harness-check
	@python3 scripts/test_generate_model_catalog.py

local-app-cleanup-check: docs-check harness-check
	@python3 scripts/test_cleanup_local_apps.py

release-verify-remote: docs-check harness-check release-manifest-check
	@test -n "$(WOICE_LOCAL_RELEASE_MANIFEST)" || { echo "WOICE_LOCAL_RELEASE_MANIFEST 未设置；不会伪造远程发行读回。"; exit 1; }
	@test -n "$(WOICE_RELEASE_MANIFEST_URL)" || { echo "WOICE_RELEASE_MANIFEST_URL 未设置；不会伪造远程发行读回。"; exit 1; }
	@set -euo pipefail; \
		manifest_verify_cmd=(python3 scripts/release_artifact_manifest.py verify \
			--local-manifest "$(WOICE_LOCAL_RELEASE_MANIFEST)" \
			--remote-manifest-url "$(WOICE_RELEASE_MANIFEST_URL)"); \
		if [[ -n "$(WOICE_REMOTE_EVIDENCE_OUTPUT)" ]]; then \
			manifest_verify_cmd+=(--output "$(WOICE_REMOTE_EVIDENCE_OUTPUT)"); \
		fi; \
		"$${manifest_verify_cmd[@]}"

store-capability-check: docs-check harness-check
	@WOICE_DISTRIBUTION=app-store swift test --no-parallel

connectors-check:
	@npm test --prefix Connectors/PiWoice
	@$(MAKE) mcp-check

mcp-check:
	@npm test --prefix Connectors/McpWoice

project:
	@test -f Package.swift || { echo "Package.swift 尚未创建；先完成 M0-00"; exit 1; }
	@echo "project: SwiftPM package ready"

xcode-project:
	@command -v xcodegen >/dev/null || { echo "xcodegen 未安装；无法从 project.yml 生成正式 Xcode 工程。"; exit 1; }
	@xcodegen generate --spec project.yml

xcode-list: xcode-project
	@xcodebuild -list -project Woice.xcodeproj

xcode-build-direct: xcode-project
	@xcodebuild -quiet -project Woice.xcodeproj -scheme Woice-Store -configuration Release-Direct -sdk macosx -derivedDataPath .build/xcode-direct-derived ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -skipPackagePluginValidation build

xcode-build-store: xcode-project
	@xcodebuild -project Woice.xcodeproj -scheme Woice-Store -configuration Release-AppStore -sdk macosx -derivedDataPath .build/xcode-derived CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -skipPackagePluginValidation build
	@python3 scripts/verify_xcode_store_bundle.py --app .build/xcode-derived/Build/Products/Release-AppStore/Woice.app

build: project
	@swift build -c release

test: project
	@swift test --no-parallel

package: xcode-build-direct
	@python3 scripts/cleanup_local_apps.py --build-dir build
	@python3 scripts/package_distribution.py --flavor dev --binary "$(DIRECT_XCODE_APP)/Contents/MacOS/Woice" --mlx-bundle "$(DIRECT_XCODE_APP)/Contents/Resources/mlx-swift_Cmlx.bundle" --info-plist Resources/Info.plist --output "$(APP_BUNDLE)"

package-core: xcode-build-direct
	@python3 scripts/package_distribution.py --flavor core --binary "$(DIRECT_XCODE_APP)/Contents/MacOS/Woice" --mlx-bundle "$(DIRECT_XCODE_APP)/Contents/Resources/mlx-swift_Cmlx.bundle" --info-plist Resources/Info.plist --output build/Woice-Core.app

package-offline: xcode-build-direct
	@test -n "$(WOICE_OFFLINE_MODEL_ROOT)" || { echo "WOICE_OFFLINE_MODEL_ROOT 未设置；请显式提供已验证模型目录。"; exit 1; }
	@python3 scripts/package_distribution.py --flavor offline --binary "$(DIRECT_XCODE_APP)/Contents/MacOS/Woice" --mlx-bundle "$(DIRECT_XCODE_APP)/Contents/Resources/mlx-swift_Cmlx.bundle" --info-plist Resources/Info.plist --model-root "$(WOICE_OFFLINE_MODEL_ROOT)" --output build/Woice-Offline.app

package-store: xcode-build-store appicon-check model-package-check
	@set -euo pipefail; \
		package_args=( \
			--flavor store \
			--binary .build/xcode-derived/Build/Products/Release-AppStore/Woice.app/Contents/MacOS/Woice \
			--mlx-bundle .build/xcode-derived/Build/Products/Release-AppStore/Woice.app/Contents/Resources/mlx-swift_Cmlx.bundle \
			--info-plist Resources/Info.plist \
			--output build/Woice-Store.app \
			--entitlements Resources/Woice-Store.entitlements \
			--privacy-manifest Resources/PrivacyInfo.xcprivacy \
		); \
		WOICE_CODESIGN_IDENTITY=- python3 scripts/package_distribution.py "$${package_args[@]}"

package-dmg-core: package-core
	@python3 scripts/package_dmg.py --app build/Woice-Core.app --output build/Woice-Core.dmg --volume-name Woice-Core

package-dmg-offline: package-offline
	@python3 scripts/package_dmg.py --app build/Woice-Offline.app --output build/Woice-Offline.dmg --volume-name Woice-Offline

release-adhoc: docs-check harness-check xcode-build-direct
	@test -n "$(WOICE_OFFLINE_MODEL_ROOT)" || { echo "WOICE_OFFLINE_MODEL_ROOT 未设置；不会伪造 Offline 预发布包。"; exit 1; }
	@WOICE_CODESIGN_IDENTITY=- python3 scripts/package_distribution.py --flavor core --binary "$(DIRECT_XCODE_APP)/Contents/MacOS/Woice" --mlx-bundle "$(DIRECT_XCODE_APP)/Contents/Resources/mlx-swift_Cmlx.bundle" --info-plist Resources/Info.plist --output build/Woice-Core.app
	@WOICE_CODESIGN_IDENTITY=- python3 scripts/package_distribution.py --flavor offline --binary "$(DIRECT_XCODE_APP)/Contents/MacOS/Woice" --mlx-bundle "$(DIRECT_XCODE_APP)/Contents/Resources/mlx-swift_Cmlx.bundle" --info-plist Resources/Info.plist --model-root "$(WOICE_OFFLINE_MODEL_ROOT)" --output build/Woice-Offline.app
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

release-developer-id: docs-check harness-check appicon-check release-manifest-check
	@./scripts/release_developer_id.sh

model-catalog: docs-check harness-check
	@test -n "$(WOICE_MODEL_ROOT)" || { echo "WOICE_MODEL_ROOT 未设置；不会生成生产模型 Catalog。"; exit 1; }
	@test -n "$(WOICE_CATALOG_PRIVATE_KEY)" || { echo "WOICE_CATALOG_PRIVATE_KEY 未设置；不会生成签名模型 Catalog。"; exit 1; }
	@test -n "$(WOICE_CATALOG_VERSION)" || { echo "WOICE_CATALOG_VERSION 未设置；不会生成版本不明的模型 Catalog。"; exit 1; }
	@python3 scripts/generate_model_catalog.py \
		--model-root "$(WOICE_MODEL_ROOT)" \
		--output Resources/ModelCatalog/model-catalog.json \
		--private-key "$(WOICE_CATALOG_PRIVATE_KEY)" \
		--catalog-version "$(WOICE_CATALOG_VERSION)"

verify-app-store: docs-check harness-check appicon-check package-store
	@python3 scripts/verify_app_store.py --app build/Woice-Store.app

archive-app-store: docs-check harness-check xcode-project
	@./scripts/archive_app_store.sh

acceptance-app-store-sandbox: verify-app-store
	@codesign --verify --deep --strict build/Woice-Store.app
	@python3 scripts/verify_app_store.py --app build/Woice-Store.app
	@echo "acceptance-app-store-sandbox: passed (local signed bundle and entitlement checks; no TCC/TestFlight claim)"

acceptance-app-store-clean-user: docs-check harness-check
	@./scripts/acceptance_app_store_clean_user.sh

model-benchmark: docs-check harness-check
	@test -n "$(WOICE_BENCHMARK_AUDIO_DIR)" || { echo "WOICE_BENCHMARK_AUDIO_DIR 尚未设置；不会伪造模型基准。"; exit 1; }
	@./scripts/run_model_benchmark.sh "$(WOICE_BENCHMARK_AUDIO_DIR)" "$(WOICE_BENCHMARK_OUTPUT)"

model-benchmark-fixture: docs-check harness-check
	@test -n "$(WOICE_BENCHMARK_AUDIO_DIR)" || { echo "WOICE_BENCHMARK_AUDIO_DIR 尚未设置；请显式提供 Fixture 输出目录。"; exit 1; }
	@./scripts/create_model_benchmark_fixtures.sh "$(WOICE_BENCHMARK_AUDIO_DIR)" "$${WOICE_BENCHMARK_MIN_DURATION_SECONDS:-300}"

material-benchmark-fixture: docs-check harness-check
	@test -n "$(WOICE_MATERIAL_BENCHMARK_DIR)" || { echo "WOICE_MATERIAL_BENCHMARK_DIR 尚未设置；请显式提供 Fixture 输出目录。"; exit 1; }
	@./scripts/create_material_benchmark_fixtures.sh "$(WOICE_MATERIAL_BENCHMARK_DIR)"

material-benchmark: docs-check harness-check
	@test -n "$(WOICE_MATERIAL_BENCHMARK_DIR)" || { echo "WOICE_MATERIAL_BENCHMARK_DIR 未设置；不会伪造素材基准。"; exit 1; }
	@set -euo pipefail; \
	output_path="$${WOICE_MATERIAL_BENCHMARK_OUTPUT:-build/material-benchmark.json}"; \
	WOICE_RUN_MATERIAL_BENCHMARK=1 \
	WOICE_MATERIAL_BENCHMARK_DIR="$(WOICE_MATERIAL_BENCHMARK_DIR)" \
	WOICE_MATERIAL_BENCHMARK_OUTPUT="$$output_path" \
	WOICE_ENFORCE_MATERIAL_BENCHMARK="$${WOICE_ENFORCE_MATERIAL_BENCHMARK:-0}" \
	swift test --no-parallel --filter materialBenchmarkProducesReport

model-benchmark-strict: docs-check harness-check
	@test -n "$(WOICE_BENCHMARK_AUDIO_DIR)" || { echo "WOICE_BENCHMARK_AUDIO_DIR 尚未设置；不会伪造完整模型基准。"; exit 1; }
	@WOICE_ENFORCE_MODEL_BENCHMARK=1 WOICE_BENCHMARK_MIN_DURATION_SECONDS="$${WOICE_BENCHMARK_MIN_DURATION_SECONDS:-300}" ./scripts/run_model_benchmark.sh --strict "$(WOICE_BENCHMARK_AUDIO_DIR)" "$(WOICE_BENCHMARK_OUTPUT)"

model-benchmark-qwen: docs-check harness-check xcode-build-store
	@test -n "$(WOICE_BENCHMARK_AUDIO_DIR)" || { echo "WOICE_BENCHMARK_AUDIO_DIR 尚未设置；不会伪造 Qwen 模型基准。"; exit 1; }
	@WOICE_BENCHMARK_INCLUDE_QWEN=1 ./scripts/run_model_benchmark.sh "$(WOICE_BENCHMARK_AUDIO_DIR)" "$(WOICE_BENCHMARK_OUTPUT)"

model-benchmark-qwen-strict: docs-check harness-check xcode-build-store
	@test -n "$(WOICE_BENCHMARK_AUDIO_DIR)" || { echo "WOICE_BENCHMARK_AUDIO_DIR 尚未设置；不会伪造完整 Qwen 模型基准。"; exit 1; }
	@WOICE_BENCHMARK_INCLUDE_QWEN=1 WOICE_ENFORCE_MODEL_BENCHMARK=1 WOICE_BENCHMARK_MIN_DURATION_SECONDS="$${WOICE_BENCHMARK_MIN_DURATION_SECONDS:-300}" ./scripts/run_model_benchmark.sh --strict "$(WOICE_BENCHMARK_AUDIO_DIR)" "$(WOICE_BENCHMARK_OUTPUT)"

model-benchmark-qwen-only-strict: docs-check harness-check xcode-build-store
	@test -n "$(WOICE_BENCHMARK_AUDIO_DIR)" || { echo "WOICE_BENCHMARK_AUDIO_DIR 尚未设置；不会伪造 Qwen-only 模型基准。"; exit 1; }
	@WOICE_BENCHMARK_INCLUDE_QWEN=1 WOICE_BENCHMARK_MODEL_PACK_IDS=com.woice.qwen3.asr.0.6b.4bit WOICE_ENFORCE_MODEL_BENCHMARK=1 WOICE_BENCHMARK_MIN_DURATION_SECONDS="$${WOICE_BENCHMARK_MIN_DURATION_SECONDS:-300}" ./scripts/run_model_benchmark.sh --strict "$(WOICE_BENCHMARK_AUDIO_DIR)" "$(WOICE_BENCHMARK_OUTPUT)"

model-benchmark-qwen-reference-fixture: docs-check harness-check
	@test -n "$(WOICE_BENCHMARK_AUDIO_DIR)" || { echo "WOICE_BENCHMARK_AUDIO_DIR 尚未设置；不会写入官方参考夹具。"; exit 1; }
	@./scripts/fetch_qwen_reference_fixtures.sh "$(WOICE_BENCHMARK_AUDIO_DIR)"

model-benchmark-qwen-official-reference: model-benchmark-qwen-reference-fixture xcode-build-store
	@test -n "$(WOICE_BENCHMARK_OUTPUT)" || { echo "WOICE_BENCHMARK_OUTPUT 尚未设置；不会丢弃官方参考报告。"; exit 1; }
	@WOICE_BENCHMARK_INCLUDE_QWEN=1 WOICE_BENCHMARK_MODEL_PACK_IDS=com.woice.qwen3.asr.0.6b.4bit ./scripts/run_model_benchmark.sh "$(WOICE_BENCHMARK_AUDIO_DIR)" "$(WOICE_BENCHMARK_OUTPUT)"

install: xcode-build-direct
	@test -n "$(WOICE_LOCAL_SIGNING_IDENTITY)" || { echo "WOICE_LOCAL_SIGNING_IDENTITY 未设置；拒绝安装 ad hoc Dev App。"; exit 1; }
	@pkill -f '^/Applications/Woice [(]Dev[)]\.app/Contents/MacOS/Woice($$| )' 2>/dev/null || true
	@python3 scripts/cleanup_local_apps.py --build-dir build
	@WOICE_CODESIGN_IDENTITY="$(WOICE_LOCAL_SIGNING_IDENTITY)" python3 scripts/package_distribution.py --flavor dev --binary "$(DIRECT_XCODE_APP)/Contents/MacOS/Woice" --mlx-bundle "$(DIRECT_XCODE_APP)/Contents/Resources/mlx-swift_Cmlx.bundle" --info-plist Resources/Info.plist --output "$(APP_BUNDLE)"
	@python3 scripts/cleanup_local_apps.py --prepare-install
	@ditto "$(APP_BUNDLE)" "$(DEV_INSTALL_APP)"
	@python3 scripts/cleanup_local_apps.py \
		--build-dir build \
		--derived-products-dir .build/xcode-direct-derived/Build/Products \
		--derived-products-dir .build/xcode-derived/Build/Products
	@echo "install: $(DEV_INSTALL_APP)"

format:
	@swift format --in-place --recursive Sources Tests

lint:
	@swift format lint --recursive Sources Tests

acceptance-core: docs-check harness-check
	@WOICE_REQUIRE_MIC_AUDIO=1 swift test --no-parallel --filter microphoneInputCheckReportsCapturedFrames
	@WOICE_RUN_APPSTATE_CAPTURE=1 swift test --no-parallel --filter appStateTerminationFinalizesRecordingAndRetainsJournal
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
	@swift test --no-parallel --filter recordingProcessSIGKILLRecoversCommittedChunks
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

verify: docs-check harness-check appicon-check release-manifest-check model-package-check model-catalog-check local-app-cleanup-check connectors-check lint test package

verify-core: docs-check harness-check package-dmg-core
	@codesign --verify --deep --strict build/Woice-Core.app
	@hdiutil verify build/Woice-Core.dmg >/dev/null
	@echo "verify-core: passed"

verify-offline: docs-check harness-check package-dmg-offline
	@codesign --verify --deep --strict build/Woice-Offline.app
	@hdiutil verify build/Woice-Offline.dmg >/dev/null
	@echo "verify-offline: passed"
