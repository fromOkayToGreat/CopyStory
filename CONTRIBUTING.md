# Contributing

CopyStory is a native Swift/AppKit/SwiftUI app for macOS 26+. Start with the
[README](README.md) and [privacy boundaries](docs/PRIVACY.md). Small, focused
pull requests with a clear reproduction and observed results are welcome.

## Local development

1. Clone the repository and install Xcode or Command Line Tools with a macOS
   26+ SDK and Swift 6. SwiftPM resolves the exact dependency in Package.swift.
2. Run `./scripts/test-development.sh` and the build-only command in README.
   The historical full suite includes native clipboard/shortcut cases; do not
   run it as an unattended offline check.
3. Run the packaging and release-policy checks described in
   [RELEASING.md](docs/RELEASING.md) when changing distribution or updates.

Use synthetic data, named pasteboards, temporary history roots, and isolated
UserDefaults suites. Never write a test that deletes or corrupts a contributor's
normal history, changes Accessibility or login settings, or posts real paste
events unattended. Runtime permission and login checks belong in a controlled
test account under the [manual plan](docs/MANUAL_TESTING.md).

Preserve pins, stored data, preference keys, and the clear-history capture-order
invariant. Storage migrations require an explicit recovery design and tests
for interruption and unsupported versions. An update must not weaken signature
checks, download arbitrary executable URLs, or silently reset opt-in choices.

Describe what changed, why, relevant tests, and remaining manual checks in the
pull request. Do not paste real clipboard data, credentials, private paths,
production databases, or signing material into commits, logs, screenshots, or
issues. Report vulnerabilities using [SECURITY.md](SECURITY.md).

Dependency upgrades require upstream release/security review, lockfile updates,
license notices, and package/update validation. Contributions are provided under
the repository's [MIT license](LICENSE); retain third-party notices.
