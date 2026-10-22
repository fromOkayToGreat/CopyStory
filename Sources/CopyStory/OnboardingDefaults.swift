// Fresh onboarding UI only. Does not register/unregister login, write saved
// preferences, or change an existing user’s ServiceManagement registration.
enum OnboardingDefaults {
    static let launchAtLogin = false
    static func registrationChange(selected: Bool, wasChanged: Bool) -> Bool? {
        // An untouched fresh default is no registration action. A user's
        // explicit change (including off) retains its ordinary meaning.
        wasChanged ? selected : (selected ? true : nil)
    }
    static func initialLogin(existingRegistration: Bool) -> Bool { existingRegistration || launchAtLogin }
}
