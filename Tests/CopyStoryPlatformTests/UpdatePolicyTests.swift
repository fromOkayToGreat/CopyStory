import Foundation
import Testing
@testable import CopyStory

struct UpdatePolicyTests {
    private let asset = URL(string: "https://github.com/fromOkayToGreat/CopyStory/releases/download/v0.4.0/CopyStory-0.4.0.zip")!
    private let signature = Data(repeating: 1, count: 64).base64EncodedString()

    private var configuration: [String: Any] {
        ["CFBundleIdentifier": "com.copystory.app", "CFBundleVersion": "4",
         "SUFeedURL": UpdatePolicy.feedURL, "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString(),
         "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true,
         "SUSignedFeedFailureExpirationInterval": 0.0, "SUEnableAutomaticChecks": false,
         "SUAutomaticallyUpdate": false, "SUEnableSystemProfiling": false, "SUEnableJavaScript": false]
    }

    @Test func releaseConfigurationAndNewerCandidateAreAccepted() throws {
        #expect(try UpdatePolicy.validateConfiguration(info: configuration, bundleURL: URL(fileURLWithPath: "/Applications/CopyStory.app"), demo: false, testing: false) == "4")
        try UpdatePolicy.validateCandidate(currentBuild: "4", candidateBuild: "5", assetURL: asset, signature: signature)
        try UpdatePolicy.validateCandidate(currentBuild: "9", candidateBuild: "10", assetURL: asset, signature: signature)
    }

    @Test(arguments: ["", "0", "04", "-1", "+4", "4.0", " 4", "4\n", "4beta", "４", "18446744073709551616"])
    func rejectsNoncanonicalAndOverflowBuildNumbers(build: String) {
        #expect(UpdatePolicy.buildNumber(build) == nil)
        #expect(throws: UpdatePolicy.Rejection.invalidBuild) {
            try UpdatePolicy.validateCandidate(currentBuild: "4", candidateBuild: build, assetURL: asset, signature: signature)
        }
    }

    @Test(arguments: ["1", "3", "4"])
    func refusesDowngradeAndEqualVersion(build: String) {
        #expect(throws: UpdatePolicy.Rejection.notNewer) {
            try UpdatePolicy.validateCandidate(currentBuild: "4", candidateBuild: build, assetURL: asset, signature: signature)
        }
    }

    @Test(arguments: [
        "http://github.com/fromOkayToGreat/CopyStory/releases/download/v0.4.0/CopyStory.zip",
        "https://github.com.evil.test/fromOkayToGreat/CopyStory/releases/download/v0.4.0/CopyStory.zip",
        "https://github.com@evil.test/fromOkayToGreat/CopyStory/releases/download/v0.4.0/CopyStory.zip",
        "https://user@github.com/fromOkayToGreat/CopyStory/releases/download/v0.4.0/CopyStory.zip",
        "https://github.com:443/fromOkayToGreat/CopyStory/releases/download/v0.4.0/CopyStory.zip",
        "https://github.com/other/CopyStory/releases/download/v0.4.0/CopyStory.zip",
        "https://github.com/fromOkayToGreat/Other/releases/download/v0.4.0/CopyStory.zip",
        "https://github.com/fromOkayToGreat/CopyStory/releases/latest/download/CopyStory.zip",
        "https://github.com/fromOkayToGreat/CopyStory/releases/download/v0.4.0/CopyStory.zip?redirect=x",
        "https://github.com/fromOkayToGreat/CopyStory/releases/download/v0.4.0/CopyStory.zip#x",
        "https://github.com/fromOkayToGreat/CopyStory/releases/download/v0.4.0/CopyStory.pkg",
        "https://github.com/fromOkayToGreat/CopyStory/releases/download/v0.4.0/CopyStory.zip/extra",
        "https://github.com/fromOkayToGreat/CopyStory/releases/download/%2E%2E/CopyStory.zip",
        "file:///tmp/CopyStory.zip"
    ])
    func rejectsUntrustedOrUnsupportedAsset(value: String) throws {
        let url = try #require(URL(string: value))
        #expect(throws: UpdatePolicy.Rejection.invalidAsset) {
            try UpdatePolicy.validateCandidate(currentBuild: "4", candidateBuild: "5", assetURL: url, signature: signature)
        }
    }

    @Test func requiresArchiveSignatureAndDownloadURL() {
        for invalid in [nil, "", "not base64", Data(repeating: 1, count: 63).base64EncodedString()] as [String?] {
            #expect(throws: UpdatePolicy.Rejection.missingSignature) {
                try UpdatePolicy.validateCandidate(currentBuild: "4", candidateBuild: "5", assetURL: asset, signature: invalid)
            }
        }
        #expect(throws: UpdatePolicy.Rejection.invalidAsset) {
            try UpdatePolicy.validateCandidate(currentBuild: "4", candidateBuild: "5", assetURL: nil, signature: signature)
        }
    }

    @Test func deltaRequiresSamePolicyAndDedicatedArchiveType() throws {
        let delta = asset.deletingPathExtension().appendingPathExtension("delta")
        try UpdatePolicy.validateCandidate(currentBuild: "4", candidateBuild: "5", assetURL: delta, signature: signature, delta: true)
        #expect(throws: UpdatePolicy.Rejection.invalidAsset) {
            try UpdatePolicy.validateCandidate(currentBuild: "4", candidateBuild: "5", assetURL: delta, signature: signature)
        }
    }

    @Test func missingAnySecuritySettingDisablesUpdater() {
        for key in configuration.keys {
            var info = configuration
            info.removeValue(forKey: key)
            #expect(throws: UpdatePolicy.Rejection.invalidConfiguration) {
                try UpdatePolicy.validateConfiguration(info: info, bundleURL: URL(fileURLWithPath: "/Applications/CopyStory.app"), demo: false, testing: false)
            }
        }
    }

    @Test func rejectsUnsafeDefaultsAndUnsignedConfiguration() {
        let unsafe: [String: Any] = ["SUFeedURL": "https://evil.test/appcast.xml", "SUPublicEDKey": "SET_ME",
            "SURequireSignedFeed": false, "SUVerifyUpdateBeforeExtraction": false,
            "SUSignedFeedFailureExpirationInterval": 1728000.0, "SUEnableAutomaticChecks": true,
            "SUAutomaticallyUpdate": true, "SUEnableSystemProfiling": true, "SUEnableJavaScript": true]
        for (key, value) in unsafe {
            var info = configuration
            info[key] = value
            #expect(throws: UpdatePolicy.Rejection.invalidConfiguration) {
                try UpdatePolicy.validateConfiguration(info: info, bundleURL: URL(fileURLWithPath: "/Applications/CopyStory.app"), demo: false, testing: false)
            }
        }
    }

    @Test func previewTestsAndUnbundledRunsNeverEnableUpdates() {
        for (path, demo, testing) in [("/tmp/CopyStory.app", true, false), ("/tmp/CopyStory.app", false, true), ("/tmp/CopyStory", false, false)] {
            #expect(throws: UpdatePolicy.Rejection.disabledEnvironment) {
                try UpdatePolicy.validateConfiguration(info: configuration, bundleURL: URL(fileURLWithPath: path), demo: demo, testing: testing)
            }
        }
    }

    @Test func developmentPackageNeverEnablesUpdaterButSupportsStrictRuntimeSmoke() throws {
        let bundleURL = URL(fileURLWithPath: "/tmp/CopyStory.app")
        var development = configuration
        development["CopyStoryDevelopmentBuild"] = true
        #expect(throws: UpdatePolicy.Rejection.developmentBuild) {
            try UpdatePolicy.validateConfiguration(info: development, bundleURL: bundleURL, demo: false, testing: false)
        }
        #expect(try UpdatePolicy.validateRuntimeConfiguration(info: development, bundleURL: bundleURL))
        #expect(try !UpdatePolicy.validateRuntimeConfiguration(info: configuration, bundleURL: bundleURL))
        development["SURequireSignedFeed"] = false
        #expect(throws: UpdatePolicy.Rejection.invalidConfiguration) {
            try UpdatePolicy.validateRuntimeConfiguration(info: development, bundleURL: bundleURL)
        }
    }

    @MainActor
    @Test func disabledServiceDoesNotStartAnUpdater() {
        let service = UpdateService(demo: true, testing: true)
        #expect(!service.isAvailable)
        #expect(!service.canCheckForUpdates)
        service.setAutomaticallyChecks(true)
        service.setAutomaticallyDownloads(true)
        service.checkForUpdates()
        #expect(!service.automaticallyChecks)
        #expect(!service.automaticallyDownloads)
    }
}
