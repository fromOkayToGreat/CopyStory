import AppKit
import Testing
@testable import CopyStory

struct MainPanelDesignTests {
    @Test func preferredPanelIsTallerApprovedSize() {
        let frame = MainPanelDesign.frame(in: NSRect(x: 0, y: 0, width: 1440, height: 900))
        #expect(frame.size == NSSize(width: 540, height: 716))
    }
    @Test func clampingIncludesPlacementOffsetAndScreenOrigin() {
        for screen in [NSRect(x: 0, y: 24, width: 1024, height: 680),
                       NSRect(x: -800, y: -500, width: 460, height: 560),
                       NSRect(x: 100, y: 100, width: 300, height: 400)] {
            let frame = MainPanelDesign.frame(in: screen)
            #expect(screen.contains(frame))
            #expect(frame.width <= 540 && frame.height <= 716)
            #expect(frame.minX >= screen.minX + 15 && frame.maxX <= screen.maxX - 15)
            #expect(frame.minY >= screen.minY + 18 && frame.maxY <= screen.maxY - 18)
        }
    }
}
