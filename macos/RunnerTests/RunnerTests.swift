import Cocoa
import XCTest
@testable import Discourse

class RunnerTests: XCTestCase {
  func testPushTokenUsesAPNsHexEncoding() {
    XCTAssertEqual(pushTokenHex(Data([0x00, 0x0f, 0xa5, 0xff])), "000fa5ff")
  }

  func testDiscourseURLComesFromNotificationPayload() {
    let url = "https://meta.discourse.org/t/native-push/42/3"

    XCTAssertEqual(discourseUrl(in: ["discourse_url": url]), url)
    XCTAssertNil(discourseUrl(in: ["discourse_url": 42]))
    XCTAssertNil(
      discourseUrl(in: ["discourse_url": String(repeating: "x", count: 2049)])
    )
  }

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

  func testWindowZoomUsesAppKitZoomBehavior() {
    let window = RecordingWindow()

    toggleWindowZoom(window)

    XCTAssertTrue(window.didZoom)
  }
}

private final class RecordingWindow: NSWindow {
  var didZoom = false

  override func zoom(_ sender: Any?) {
    didZoom = true
  }
}
