#!/bin/bash
# Explicit offline suite. Never selects GUI, named/general clipboard, login or
# global-shortcut suites; all request effects and stores are synthetic/injected.
set -euo pipefail
COPYSTORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$COPYSTORY_ROOT"
export COPYSTORY_APP_STORE=1 COPYSTORY_SHIPPING_RECONSTRUCTION=1
swift test --disable-xctest --filter 'MainPanelDesignTests|ShortcutTests|ProductionConfigurationTests|ReadinessCheckTests|DevelopmentConfigurationTests|NativeSourceIntegrationTests|ConsolidatedPanelActivationTests|HistoryInvocationPathTests|HistoryRequestPathTests|LibraryRecordingPathTests|HistoryRequestSimulationTests|NativeLifecycleEffectsTests|HistoryStoreTests|LibraryStoreTests|PromptTemplateTests|AutomaticPasteDisabledTests|legacyPasteEntryHasNoWriteAdmissionOrCloseEffects' "$@"
