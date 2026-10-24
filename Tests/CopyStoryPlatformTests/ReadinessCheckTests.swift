import Testing
@testable import CopyStory

struct ReadinessCheckTests {
    @Test func independentSignalsAndNextRefreshArePreservedAndBounded() {
        var check = ReadinessCheck()
        var reads = 0
        check.begin(now: 10, lastRefresh: 8, sequence: 4, displayed: false, optIn: false) {
            reads += 1
            return .init(axTrusted: true, postEventAccess: false)
        }
        #expect(check.status == .waiting)
        #expect(check.initial?.signals.axTrusted == true)
        #expect(check.initial?.displayedReady == false)
        #expect(check.initial?.refreshAge == 2)
        check.refreshed(now: 11, sequence: 5, displayed: true, optIn: false) {
            reads += 1
            return .init(axTrusted: false, postEventAccess: false)
        }
        #expect(check.status == .complete)
        #expect(check.next?.displayedReady == true)
        #expect(check.next?.signals.postEventAccess == false)
        #expect(check.next?.refreshSequence == 5 && check.next?.refreshAge == 0)
        for sequence in 6...100 {
            check.refreshed(now: 12, sequence: UInt64(sequence), displayed: false, optIn: true) {
                reads += 1; return .init(axTrusted: true, postEventAccess: true)
            }
        }
        #expect(reads == 2 && check.next?.directPasteOptIn == false)
    }

    @Test func staleDelayedWrongSequenceAndBackwardTimeNeverReadAgain() {
        for (now, sequence) in [(15.01, UInt64(5)), (11, 4), (11, 6), (9, 5)] {
            var check = ReadinessCheck()
            var reads = 0
            check.begin(now: 10, lastRefresh: 1, sequence: 4, displayed: false, optIn: true) {
                reads += 1; return .init(axTrusted: false, postEventAccess: true)
            }
            #expect(check.initial?.refreshAge == 9)
            check.refreshed(now: now, sequence: sequence, displayed: true, optIn: true) {
                reads += 1; return .init(axTrusted: true, postEventAccess: true)
            }
            #expect(check.status == .stale && check.next == nil && reads == 1)
        }
    }

    @Test func repeatedClickReplacesSamplesAndDismissalOrTimeoutStopsReads() {
        var check = ReadinessCheck()
        var reads = 0
        let read = { reads += 1; return ReadinessCheck.Signals(axTrusted: true, postEventAccess: true) }
        check.begin(now: 10, lastRefresh: 9, sequence: 0, displayed: false, optIn: false, read: read)
        check.begin(now: 11, lastRefresh: 10, sequence: 1, displayed: true, optIn: true, read: read)
        #expect(check.initial?.refreshSequence == 1 && check.next == nil)
        check.expire()
        check.refreshed(now: 12, sequence: 2, displayed: true, optIn: true, read: read)
        #expect(check.status == .stale && reads == 2)
        check.dismiss()
        check.refreshed(now: 12, sequence: 2, displayed: true, optIn: true, read: read)
        #expect(check.status == .idle && check.initial == nil && check.next == nil && reads == 2)
        check.begin(now: 20, lastRefresh: 20, sequence: 3, displayed: true, optIn: true, read: read)
        check.refreshed(now: 25, sequence: 4, displayed: true, optIn: true, read: read)
        check.expire()
        #expect(check.status == .complete && reads == 4)
    }
}
