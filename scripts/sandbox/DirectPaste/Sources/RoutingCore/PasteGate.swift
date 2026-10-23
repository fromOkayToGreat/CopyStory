// Pure policy: unit tests never open stores, access pasteboards or post events.
public struct PasteGate {
    public enum Outcome: String, Equatable {
        case dispatch, consumed, cancelled, expired, clipboardChanged
        case permissionDenied, destinationUnavailable, appChanged, modifiersHeld
    }
    private var destination: Int32?
    private var openedAt: Double = 0
    private var used = true
    private var invalidated = false
    private var ownWrite: Int?
    public private(set) var generation = 0
    public let ownPID: Int32
    public var canBegin: Bool { !used }
    public init(ownPID: Int32) { self.ownPID = ownPID }

    public mutating func open(destination: Int32?, now: Double) {
        generation += 1
        self.destination = destination == ownPID ? nil : destination
        openedAt = now; used = false; invalidated = false; ownWrite = nil
    }
    public mutating func invalidate() { invalidated = true }
    public mutating func applicationActivated(_ pid: Int32) {
        if pid != destination { invalidate() }
    }
    // Claims one deliberate selection; repeated actions cannot rewrite/retry it.
    public mutating func begin(writeCount: Int) -> Int? {
        guard !used else { return nil }
        used = true; ownWrite = writeCount
        return generation
    }
    public mutating func consume(token: Int, now: Double, frontmost: Int32?,
                                 destinationAlive: Bool, currentWrite: Int,
                                 permission: Bool, modifiersReleased: Bool) -> Outcome {
        guard token == generation, let expectedWrite = ownWrite else { return .consumed }
        ownWrite = nil // Even failed dispatch is consumed; no implicit retry.
        guard !invalidated else { return .cancelled }
        guard now - openedAt < 30, now >= openedAt else { return .expired }
        guard currentWrite == expectedWrite else { return .clipboardChanged }
        guard let destination, destinationAlive else { return .destinationUnavailable }
        guard frontmost == destination else { return .appChanged }
        guard permission else { return .permissionDenied }
        guard modifiersReleased else { return .modifiersHeld }
        return .dispatch
    }
}
