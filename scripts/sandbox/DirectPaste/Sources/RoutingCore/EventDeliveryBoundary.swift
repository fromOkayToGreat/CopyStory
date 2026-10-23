// One final validation followed by two process-directed events. Injected
// closures make the real ordering testable without posting keyboard events.
// This deliberately does NOT claim atomicity between validation and delivery.
public enum EventDeliveryBoundary {
    public enum Event: Equatable { case down, up }
    @discardableResult
    public static func deliver(validate: () -> Bool, post: (Event) -> Void) -> Bool {
        guard validate() else { return false }
        post(.down)
        post(.up)
        return true
    }
}
