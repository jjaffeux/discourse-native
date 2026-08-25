import Cocoa
import FlutterMacOS
import XCTest
@testable import Discourse

class RunnerTests: XCTestCase {
  func testLaunchActivatesAndPresentsMainWindow() {
    let application = TestApplication()
    let window = TestWindow()

    activateMainWindow(application: application, window: window)

    XCTAssertTrue(application.ignoredOtherApps)
    XCTAssertTrue(window.becameKeyAndVisible)
  }

  func testLaunchStillActivatesWithoutAConnectedWindow() {
    let application = TestApplication()

    activateMainWindow(application: application, window: nil)

    XCTAssertTrue(application.ignoredOtherApps)
  }
}

private final class TestApplication: ApplicationActivating {
  private(set) var ignoredOtherApps = false

  func activate(ignoringOtherApps flag: Bool) {
    ignoredOtherApps = flag
  }
}

private final class TestWindow: MainWindowPresenting {
  private(set) var becameKeyAndVisible = false

  func makeKeyAndOrderFront(_ sender: Any?) {
    becameKeyAndVisible = true
  }
}
