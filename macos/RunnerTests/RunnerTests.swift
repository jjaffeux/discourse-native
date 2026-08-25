import Cocoa
import XCTest
@testable import Discourse

class RunnerTests: XCTestCase {
  func testContentViewCannotConsumeClicksAsWindowDrags() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .resizable],
      backing: .buffered,
      defer: false
    )
    window.isMovableByWindowBackground = true

    disableContentViewWindowDragging(window)

    XCTAssertFalse(window.isMovableByWindowBackground)
  }
}
