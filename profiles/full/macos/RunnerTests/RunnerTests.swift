import Cocoa
import UserNotifications
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

  func testNotificationDelegateIsInstalledBeforeLaunchFinishes() {
    let center = UNUserNotificationCenter.current()
    let previousDelegate = center.delegate
    let appDelegate = AppDelegate()
    defer { center.delegate = previousDelegate }
    center.delegate = nil

    appDelegate.applicationWillFinishLaunching(
      Notification(name: NSApplication.willFinishLaunchingNotification)
    )

    XCTAssertTrue(center.delegate === appDelegate)
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

  func testLaunchScreenCentersBareLogoOnItsFullWindowGradient() {
    let logo = NSImage(size: NSSize(width: 32, height: 32))
    let launchScreen = LaunchScreenView(logo: logo)
    launchScreen.frame = NSRect(x: 0, y: 0, width: 800, height: 600)

    launchScreen.layoutSubtreeIfNeeded()

    XCTAssertTrue(launchScreen.logoView.image === logo)
    XCTAssertEqual(launchScreen.logoView.imageScaling, .scaleProportionallyUpOrDown)
    XCTAssertEqual(launchScreen.logoView.frame.size, NSSize(width: 192, height: 192))
    XCTAssertEqual(launchScreen.logoView.frame.midX, launchScreen.bounds.midX)
    XCTAssertEqual(launchScreen.logoView.frame.midY, launchScreen.bounds.midY)
    XCTAssertEqual(launchScreen.gradientLayer.frame, launchScreen.bounds)
    XCTAssertEqual(launchScreen.gradientLayer.colors?.count, 2)
  }
}

private final class RecordingWindow: NSWindow {
  var didZoom = false

  override func zoom(_ sender: Any?) {
    didZoom = true
  }
}
