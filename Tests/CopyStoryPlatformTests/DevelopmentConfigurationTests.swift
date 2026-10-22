import Foundation
import Testing
@testable import CopyStory

struct DevelopmentConfigurationTests {
    @Test func separateStoreAndPackageIdentityAreRequired() {
        let support = URL(fileURLWithPath: "/synthetic/Application Support", isDirectory: true)
        #expect(DevelopmentConfiguration.storeDirectory(applicationSupport: support, development: true).lastPathComponent == "CopyStory Development")
        #expect(DevelopmentConfiguration.storeDirectory(applicationSupport: support, development: false).lastPathComponent == "CopyStory")
        let valid: [String: Any] = ["CFBundleIdentifier": "com.copystory.development",
            "CopyStoryDevelopmentBuild": true, "CopyStorySourceRevision": String(repeating: "a", count: 40),
            "CopyStorySourceDirty": "clean", "CopyStoryBuildConfiguration": "Debug"]
        #expect(DevelopmentConfiguration.validates(info: valid))
        for (key, value): (String, Any) in [
            ("CFBundleIdentifier", "com.copystory.app"), ("CopyStoryDevelopmentBuild", false),
            ("CopyStorySourceRevision", "$(COPYSTORY_SOURCE_REVISION)"), ("CopyStorySourceDirty", "unknown"),
            ("CopyStoryBuildConfiguration", "Release"), ("SUFeedURL", "https://example.invalid"),
            ("CopyStoryNativeSourceOnly", true), ("CopyStorySandboxFeasibility", true)] {
            var info = valid; info[key] = value
            #expect(!DevelopmentConfiguration.validates(info: info))
        }
    }
}
