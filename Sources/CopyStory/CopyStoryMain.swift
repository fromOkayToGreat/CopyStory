import AppKit
import SwiftUI
import Carbon
import CopyStoryCore

@main
struct CopyStoryMain {
    @MainActor static func main() {
        guard NativeIntegrationGates.appLaunchEnabled else {
            fputs("Source-only integration: app launch is disabled.\n", stderr)
            exit(EXIT_FAILURE)
        }
        #if COPYSTORY_DEVELOPMENT || COPYSTORY_PRODUCTION
        // Refuse mismatched/unpackaged development identities before NSApplication,
        // stores, clipboard, preferences or other startup effects are constructed.
        do { _ = try UpdateService.verifyPackagedRuntime() }
        catch {
            fputs("Invalid CopyStory package. Use the matching configuration and build script.\n", stderr)
            exit(EXIT_FAILURE)
        }
        #endif
        #if SHIPPING_RECONSTRUCTION && !COPYSTORY_DEVELOPMENT
        fputs("Compile-only reconstruction: launch disabled pending adapter and runtime review.\n", stderr)
        exit(EXIT_FAILURE)
        #else
        if ProcessInfo.processInfo.arguments.contains("--verify-package-runtime") {
            do {
                print(try UpdateService.verifyPackagedRuntime())
            } catch {
                fputs("CopyStory runtime verification failed: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
            return
        }
        #if APP_STORE && !COPYSTORY_DEVELOPMENT && !COPYSTORY_PRODUCTION
        if ProcessInfo.processInfo.arguments.contains("--sandbox-probe") {
            _ = NSApplication.shared
            Task { @MainActor in
                do { try await SandboxProbe.run(); exit(EXIT_SUCCESS) }
                catch { fputs("Sandbox probe failed: \(error)\n", stderr); exit(EXIT_FAILURE) }
            }
            NSApp.run()
            return
        }
        // This first-stage feasibility bundle must never start real capture/login.
        guard ProcessInfo.processInfo.arguments.contains("--demo") else {
            fputs("Feasibility builds require --demo or --sandbox-probe.\n", stderr)
            exit(EXIT_FAILURE)
        }
        #endif
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
        #endif
    }
}

