import XCTest
import LayoutPilotCore

final class ModifierGestureTests: XCTestCase {
    func testDoubleCancelsDelayedSingle() {
        var gesture = ModifierGesture()
        XCTAssertEqual(gesture.modifier(keyCode: 56, isDown: true, time: 0), [])
        XCTAssertEqual(gesture.modifier(keyCode: 56, isDown: false, time: 0.1), [])
        XCTAssertEqual(gesture.advance(time: 0.3), [])
        XCTAssertEqual(gesture.modifier(keyCode: 56, isDown: true, time: 0.31), [])
        XCTAssertEqual(gesture.modifier(keyCode: 56, isDown: false, time: 0.35), [.correctText])
        XCTAssertEqual(gesture.advance(time: 1), [])
    }
    func testInclusiveDoubleBoundary() {
        var gesture = ModifierGesture()
        _ = gesture.modifier(keyCode: 56, isDown: true, time: 0.9)
        _ = gesture.modifier(keyCode: 56, isDown: false, time: 1)
        _ = gesture.modifier(keyCode: 56, isDown: true, time: 1.1)
        XCTAssertEqual(gesture.modifier(keyCode: 56, isDown: false, time: 1.32), [.correctText])
    }
    func testChordInvalidatesBothReleases() {
        var gesture = ModifierGesture(bothShiftPause: true)
        _ = gesture.modifier(keyCode: 56, isDown: true, time: 0)
        XCTAssertEqual(gesture.modifier(keyCode: 60, isDown: true, time: 0.05), [.toggleAutomatic])
        XCTAssertEqual(gesture.modifier(keyCode: 56, isDown: false, time: 0.1), [])
        XCTAssertEqual(gesture.modifier(keyCode: 60, isDown: false, time: 0.15), [])
        XCTAssertEqual(gesture.advance(time: 1), [])
    }
    func testTypingAndResetCancelGestures() {
        var gesture = ModifierGesture(optionTap: true)
        _ = gesture.modifier(keyCode: 58, isDown: true, time: 0)
        gesture.keyUsed()
        XCTAssertEqual(gesture.modifier(keyCode: 58, isDown: false, time: 0.1), [])
        _ = gesture.modifier(keyCode: 56, isDown: true, time: 1)
        _ = gesture.modifier(keyCode: 56, isDown: false, time: 1.1)
        gesture.reset()
        XCTAssertEqual(gesture.advance(time: 2), [])
    }
}
