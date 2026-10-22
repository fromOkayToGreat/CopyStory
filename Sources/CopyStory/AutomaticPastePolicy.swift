// Engineering build only. No runtime opt-in or permission grant can enable it.
enum AutomaticPastePolicy {
    static let enabled = false
    static let unavailableReason = "Automatic paste is disabled in this reconstruction. Nothing was copied or sent. Use the explicit Copy action if needed."
    static func request(write: () throws -> Void, admit: () -> Void, close: () -> Void) -> String {
        // Intentionally call none of these actions. No clipboard write/admission,
        // dismissal or event can precede the independently reviewed adapter.
        unavailableReason
    }
}
