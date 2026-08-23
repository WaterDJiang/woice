#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
swift test --no-parallel --filter 'SystemAudioCapabilityTests|TextInsertionServiceTests|SettingsDraftTests'
rg -q '复制原文' Sources/WoiceApp/RecordingDetailView.swift
rg -q '自动粘贴' Sources/WoiceApp/SettingsView.swift
rg -q 'needsReauthorization' Sources/WoiceApp/SystemAudioCapabilityService.swift
echo "acceptance-permission-continuity: code contract passed; stable-signature/TCC upgrade journey remains user-run"
