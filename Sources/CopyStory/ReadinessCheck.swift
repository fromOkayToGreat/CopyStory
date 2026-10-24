#if !COPYSTORY_PRODUCTION
import Foundation
#if COPYSTORY_DEVELOPMENT
import ApplicationServices
import Darwin
import CoreGraphics
#endif

/// Two in-memory samples only. The injected readers make offline tests inert.
struct ReadinessCheck {
    struct Signals: Equatable {
        let axTrusted: Bool
        let postEventAccess: Bool
    }
    struct Sample: Equatable {
        let signals: Signals
        let displayedReady: Bool
        let refreshSequence: UInt64
        let refreshAge: TimeInterval
        let directPasteOptIn: Bool
    }
    enum Status: String { case idle, waiting, complete, stale }
    static let maximumWait: TimeInterval = 5
    private(set) var status: Status = .idle
    private(set) var initial: Sample?
    private(set) var next: Sample?
    private var startedAt: TimeInterval = 0
    private var expectedSequence: UInt64 = 0

    mutating func begin(now: TimeInterval, lastRefresh: TimeInterval, sequence: UInt64,
                        displayed: Bool, optIn: Bool, read: () -> Signals) {
        initial = Sample(signals: read(), displayedReady: displayed, refreshSequence: sequence,
                         refreshAge: max(0, now - lastRefresh), directPasteOptIn: optIn)
        next = nil
        startedAt = now
        expectedSequence = sequence &+ 1
        status = .waiting
    }

    mutating func refreshed(now: TimeInterval, sequence: UInt64, displayed: Bool,
                            optIn: Bool, read: () -> Signals) {
        guard status == .waiting else { return }
        guard now >= startedAt, now - startedAt <= Self.maximumWait,
              sequence == expectedSequence else { status = .stale; return }
        next = Sample(signals: read(), displayedReady: displayed, refreshSequence: sequence,
                      refreshAge: 0, directPasteOptIn: optIn)
        status = .complete
    }

    mutating func expire() { if status == .waiting { status = .stale } }
    mutating func dismiss() { self = Self() }
}

#if COPYSTORY_DEVELOPMENT
extension ReadinessCheck {
    static func nativeSignals() -> Signals {
        Signals(axTrusted: AXIsProcessTrusted(), postEventAccess: CGPreflightPostEventAccess())
    }

    /// Own bundle metadata only; never emits the actual filesystem path.
    static func identity(bundle: Bundle = .main) -> String {
        let info = bundle.infoDictionary ?? [:]
        // The sandbox home may be the container; use this user's account home.
        let home = getpwuid(getuid()).map { URL(fileURLWithPath: String(cString: $0.pointee.pw_dir)) }
        let canonical = home?.appendingPathComponent("Applications/CopyStory Development.app").standardizedFileURL
        return "PID: \(ProcessInfo.processInfo.processIdentifier)\nBundle: \(bundle.bundleIdentifier ?? "unknown")\nVersion/build: \(info["CFBundleShortVersionString"] as? String ?? "unknown") / \(info["CFBundleVersion"] as? String ?? "unknown")\nRevision: \(info["CopyStorySourceRevision"] as? String ?? "unknown")\nCanonical path match: \(bundle.bundleURL.standardizedFileURL == canonical)\nCompile gates: development=\(DevelopmentConfiguration.enabled), consent=\(NativeIntegrationGates.postingConsentEnabled), posting=\(NativeIntegrationGates.realPostingEnabled)"
    }

    static func describe(_ sample: Sample) -> String {
        "AX trusted: \(sample.signals.axTrusted) · Event preflight: \(sample.signals.postEventAccess)\nDisplayed ready: \(sample.displayedReady) · Direct Paste opt-in: \(sample.directPasteOptIn)\nDisplay refresh: #\(sample.refreshSequence) · age \(String(format: "%.2f", sample.refreshAge))s"
    }
}
#endif

#endif
