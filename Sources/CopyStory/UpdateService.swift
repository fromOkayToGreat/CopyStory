import AppKit
import Combine
#if !APP_STORE
import Sparkle
#endif

/// Product policy supplements Sparkle's signature verification and installer.
/// No network, archive extraction, replacement, or cryptography is implemented here.
enum UpdatePolicy {
    static let sourceURL = URL(string: "https://github.com/fromOkayToGreat/CopyStory")!
    static let feedURL = "https://github.com/fromOkayToGreat/CopyStory/releases/latest/download/appcast.xml"

    enum Rejection: Error, LocalizedError, Equatable {
        case disabledEnvironment, developmentBuild, invalidConfiguration, invalidBuild, notNewer, invalidAsset, missingSignature

        var errorDescription: String? {
            switch self {
            case .disabledEnvironment: return "Updates are disabled in preview, test, and unpackaged development builds."
            case .developmentBuild: return "Updates are disabled in this development build. A signed public release is required."
            case .invalidConfiguration: return "Updates are unavailable because this build has no valid signed update configuration."
            case .invalidBuild: return "The update has an invalid build number."
            case .notNewer: return "The update is not newer than the installed build."
            case .invalidAsset: return "The update is not a supported CopyStory release asset."
            case .missingSignature: return "The update does not include a valid EdDSA signature."
            }
        }
    }

    static func buildNumber(_ value: String) -> UInt64? {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              value.first != "0", let number = UInt64(value), number > 0 else { return nil }
        return number
    }

    static func validateConfiguration(info: [String: Any], bundleURL: URL, demo: Bool, testing: Bool) throws -> String {
        guard !demo, !testing, bundleURL.pathExtension == "app" else { throw Rejection.disabledEnvironment }
        if info["CopyStoryDevelopmentBuild"] as? Bool == true { throw Rejection.developmentBuild }
        guard info["CFBundleIdentifier"] as? String == "com.copystory.app",
              info["SUFeedURL"] as? String == feedURL,
              let key = info["SUPublicEDKey"] as? String, Data(base64Encoded: key)?.count == 32,
              info["SURequireSignedFeed"] as? Bool == true,
              info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
              info["SUSignedFeedFailureExpirationInterval"] as? Double == 0,
              info["SUEnableAutomaticChecks"] as? Bool == false,
              info["SUAutomaticallyUpdate"] as? Bool == false,
              info["SUEnableSystemProfiling"] as? Bool == false,
              info["SUEnableJavaScript"] as? Bool == false,
              let build = info["CFBundleVersion"] as? String, buildNumber(build) != nil
        else { throw Rejection.invalidConfiguration }
        return build
    }

    /// A development package may load Sparkle for a packaging smoke test while
    /// its actual updater remains disabled. All other release settings must pass.
    static func validateRuntimeConfiguration(info: [String: Any], bundleURL: URL) throws -> Bool {
        let development = info["CopyStoryDevelopmentBuild"] as? Bool == true
        if development {
            do {
                _ = try validateConfiguration(info: info, bundleURL: bundleURL, demo: false, testing: false)
                throw Rejection.invalidConfiguration
            } catch Rejection.developmentBuild {
                // Confirm the actual initialization path rejects this package.
            }
            var releaseConfiguration = info
            releaseConfiguration.removeValue(forKey: "CopyStoryDevelopmentBuild")
            _ = try validateConfiguration(info: releaseConfiguration, bundleURL: bundleURL, demo: false, testing: false)
        } else {
            _ = try validateConfiguration(info: info, bundleURL: bundleURL, demo: false, testing: false)
        }
        return development
    }

    /// Only explicitly versioned assets under the project's release path.
    /// GitHub may redirect their transport to its CDN; signed bytes remain mandatory.
    static func isReleaseAsset(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host == "github.com",
              components.port == nil, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              !components.percentEncodedPath.contains("%") else { return false }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 7, parts[0].isEmpty, parts[1] == "fromOkayToGreat", parts[2] == "CopyStory",
              parts[3] == "releases", parts[4] == "download" else { return false }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return [parts[5], parts[6]].allSatisfy { part in
            !part.isEmpty && part != "." && part != ".." && part.unicodeScalars.allSatisfy(safe.contains)
        }
    }

    static func validateCandidate(currentBuild: String, candidateBuild: String, assetURL: URL?, signature: String?, delta: Bool = false) throws {
        guard let current = buildNumber(currentBuild), let candidate = buildNumber(candidateBuild) else { throw Rejection.invalidBuild }
        guard candidate > current else { throw Rejection.notNewer }
        guard let assetURL, isReleaseAsset(assetURL),
              (delta ? ["delta"] : ["zip", "dmg"]).contains(assetURL.pathExtension.lowercased()) else { throw Rejection.invalidAsset }
        // This is only a structural requirement. Sparkle verifies the actual signature
        // against the embedded public key before extracting the downloaded archive.
        guard let signature, Data(base64Encoded: signature)?.count == 64 else { throw Rejection.missingSignature }
    }
}

#if !APP_STORE
@MainActor
final class UpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecks = false
    @Published private(set) var automaticallyDownloads = false
    @Published private(set) var unavailableReason: String?
    private var controller: SPUStandardUpdaterController?
    private var currentBuild = ""
    private var subscriptions = Set<AnyCancellable>()

    var isAvailable: Bool { controller != nil && unavailableReason == nil }

    /// Packaging smoke test: no preferences, updater, AppKit application, or
    /// history store is created. Touch a Sparkle class to verify dynamic loading.
    static func verifyPackagedRuntime(bundle: Bundle = .main) throws -> String {
        let development = try UpdatePolicy.validateRuntimeConfiguration(info: bundle.infoDictionary ?? [:], bundleURL: bundle.bundleURL)
        _ = NSStringFromClass(SPUStandardUpdaterController.self)
        return development ? "CopyStory development runtime verified; updater is disabled. This is not a public distribution build." :
            "CopyStory packaged runtime and signed update configuration verified."
    }

    init(bundle: Bundle = .main, demo: Bool, testing: Bool = UpdateService.isTesting) {
        super.init()
        do {
            currentBuild = try UpdatePolicy.validateConfiguration(info: bundle.infoDictionary ?? [:], bundleURL: bundle.bundleURL, demo: demo, testing: testing)
            let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
            self.controller = controller
            let updater = controller.updater
            // This is a privacy policy, including for preferences carried over from
            // an earlier version; the delegate additionally suppresses all profile keys.
            updater.sendsSystemProfile = false
            updater.publisher(for: \.canCheckForUpdates).sink { [weak self] in self?.canCheckForUpdates = $0 }.store(in: &subscriptions)
            updater.publisher(for: \.automaticallyChecksForUpdates).sink { [weak self] in self?.automaticallyChecks = $0 }.store(in: &subscriptions)
            updater.publisher(for: \.automaticallyDownloadsUpdates).sink { [weak self] in self?.automaticallyDownloads = $0 }.store(in: &subscriptions)
            try updater.start()
        } catch {
            unavailableReason = error.localizedDescription
            controller = nil
            subscriptions.removeAll()
            canCheckForUpdates = false
            automaticallyChecks = false
            automaticallyDownloads = false
        }
    }

    nonisolated static var isTesting: Bool {
        let process = ProcessInfo.processInfo
        return process.environment["XCTestConfigurationFilePath"] != nil ||
            process.environment["XCTestBundlePath"] != nil ||
            process.arguments.contains(where: { $0.hasSuffix(".xctest") || $0.contains("swift-testing") })
    }

    @objc func checkForUpdates(_ sender: Any? = nil) {
        guard canCheckForUpdates else { return }
        controller?.checkForUpdates(sender)
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        guard let updater = controller?.updater else { return }
        if !enabled { updater.automaticallyDownloadsUpdates = false }
        updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyDownloads(_ enabled: Bool) {
        guard let updater = controller?.updater, !enabled || updater.automaticallyChecksForUpdates else { return }
        updater.automaticallyDownloadsUpdates = enabled
    }

    // Never accept a persisted alternate feed. Forks must change and review the
    // source policy and replace the public key when configuring their own releases.
    func feedURLString(for updater: SPUUpdater) -> String? { UpdatePolicy.feedURL }
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        try validate(item)
        // Sparkle may select a delta or fall back to a full archive. Require the
        // same source and signatures for every advertised path.
        for delta in item.deltaUpdates?.values ?? [:].values { try validate(delta) }
    }

    private func validate(_ item: SUAppcastItem) throws {
        let enclosure = item.propertiesDictionary["enclosure"] as? [String: Any]
        try UpdatePolicy.validateCandidate(currentBuild: currentBuild, candidateBuild: item.versionString,
                                           assetURL: item.fileURL, signature: enclosure?["sparkle:edSignature"] as? String,
                                           delta: item.isDeltaUpdate)
    }

    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate item: SUAppcastItem) -> Bool {
        guard let url = item.releaseNotesURL else { return false }
        return UpdatePolicy.isReleaseAsset(url)
    }
}

#else
/// No updater framework, controller, network requests or preferences in store builds.
@MainActor
final class UpdateService: NSObject, ObservableObject {
    let canCheckForUpdates = false
    let automaticallyChecks = false
    let automaticallyDownloads = false
    let isAvailable = false
    let unavailableReason: String? = "Updates are managed by the App Store."
    init(demo: Bool, testing: Bool = false) { super.init() }
    func checkForUpdates() {}
    func setAutomaticallyChecks(_ enabled: Bool) {}
    func setAutomaticallyDownloads(_ enabled: Bool) {}
    static func verifyPackagedRuntime(bundle: Bundle = .main) throws -> String {
        guard bundle.object(forInfoDictionaryKey: "CopyStorySandboxFeasibility") as? Bool == true,
              bundle.bundleIdentifier == "com.copystory.sandbox-feasibility",
              !(bundle.infoDictionary ?? [:]).keys.contains(where: { $0.hasPrefix("SU") }) else {
            throw UpdatePolicy.Rejection.invalidConfiguration
        }
        return "CopyStory sandbox feasibility runtime verified; no in-app updater. Not a submission build."
    }
}
#endif
