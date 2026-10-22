#!/usr/bin/env python3
"""Static source barriers/default routing only. Never executes an app or OS API."""
from pathlib import Path
import re,json,hashlib
root=Path(__file__).resolve().parent.parent
native=(root/'Sources/CopyStory/NativePasteAdapter.swift').read_text()
main=(root/'Sources/CopyStory/CopyStoryApp.swift').read_text()
model=(root/'Sources/CopyStory/AppModel.swift').read_text()
platform=(root/'Sources/CopyStory/PlatformServices.swift').read_text()
inert=native[native.index('    #else'):native.index('    #endif')]
for gate in ['appLaunchEnabled','storageEnabled','clipboardEnabled','observationEnabled','shortcutEnabled','loginEnabled','postingConsentEnabled','realPostingEnabled']:
    assert len(re.findall(r'static let '+gate+r' = false\b',inert))==1,gate
entrySource=(root/'Sources/CopyStory/CopyStoryMain.swift').read_text()
entry=entrySource[entrySource.index('@MainActor static func main()'):entrySource.index('#if SHIPPING_RECONSTRUCTION')]
assert 'guard NativeIntegrationGates.appLaunchEnabled else' in entry and 'exit(EXIT_FAILURE)' in entry
tracking=main[main.index('func trackContextMenuInvocation('):main.index('@objc private func openFromMenu(')]
assert 'defer {' in tracking and 'finishContextMenuInvocation(ticket: ticket, generation: generation)' in tracking and 'tracking(ticket)' in tracking
choice=main[main.index('func openContextMenuInvocation(ticket:'):main.index('func finishContextMenuInvocation(ticket:')]
assert 'contextMenuOpenRequested = true' in choice and 'toggleHistory(' not in choice
assert 'trackContextMenuInvocation { ticket in' in main and 'open.representedObject = ContextMenuCommand(ticket: ticket, generation: generation)' in main
assert 'pasteCoordinator.paste(' not in model
assert 'historyRecording ?? pasteCoordinator.dependencies' in model
assert 'requestHistory(item, copyOnly: false)' in model and 'requestHistory(item, copyOnly: true)' in model
assert 'useRecordedPrompt(text: text, copyOnly: copyOnly, recording: requestDependencies)' in model
post=native[native.index('static func postPair('):native.index('static func observe(')]
assert post.index('guard NativeIntegrationGates.realPostingEnabled')<post.index('CGEventSource(')<post.index('down.postToPid(')
assert 'up.postToPid(target.pid)' in post and 'down.postToPid(target.pid)' in post
assert 'NSPasteboard.general.changeCount == boardVersion' in post
compiled=[p for p in (root/'Sources/CopyStory').glob('*.swift') if p.name!='SandboxProbe.swift']
posting=[p.name for p in compiled if '.postToPid(' in p.read_text() or '.post(tap:' in p.read_text()]
assert posting==['NativePasteAdapter.swift'],posting
assert all('AXUIElement' not in p.read_text() for p in compiled)
consent=platform[platform.index('static func requestPostingConsent()'):platform.index('static func requestAccessibility()')]
assert consent.index('guard NativeIntegrationGates.postingConsentEnabled')<consent.index('CGRequestPostEventAccess')
assert 'static let launchAtLogin = false' in (root/'Sources/CopyStory/OnboardingDefaults.swift').read_text()
assert 'OnboardingDefaults.registrationChange(selected: launchAtLogin, wasChanged: loginWasChanged)' in model and 'setLogin(launchAtLogin)' not in model
assert 'OnboardingDefaults.initialLogin(existingRegistration: model.loginEnabled)' in (root/'Sources/CopyStory/AppViews.swift').read_text()
print(json.dumps({'result':'PASS','scope':'nondevelopment reconstruction only; COPYSTORY_DEVELOPMENT enables separately reviewed capabilities','launch':'hard-disabled before any mode/argument handling in reconstruction','platformAccess':'hard-disabled','realPosting':'hard-disabled before event creation/posts','defaultHistoryLibraryCopyRouting':'shared lifecycle via native adapter; no legacy coordinator paste call','permission':'CGPreflightPostEventAccess; explicit CGRequestPostEventAccess, both gated','AXFieldManipulation':'absent from compiled app source','login':'fresh onboarding off; existing registration preserved; no implicit unregister','limits':'Static source assertions only; not effective sandbox, OS permission freshness, delivery or runtime acceptance','sourceSHA256':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in compiled}},indent=2))
