import XCTest
import UIKit

@testable import Runner

final class RunnerTests: XCTestCase {
  private func keyboardTestView(frame: CGRect) throws -> UIView {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    let window = try XCTUnwrap(scene?.windows.first(where: { $0.isKeyWindow }))
    let view = UIView(frame: frame)
    window.addSubview(view)
    return view
  }

  func testKeyboardTargetUsesFlutterViewCoordinatesAndNativeTiming() throws {
    let view = try keyboardTestView(frame: CGRect(x: 0, y: 44, width: 390, height: 800))
    defer { view.removeFromSuperview() }
    let screen = try XCTUnwrap(view.window?.screen)
    let end = view.convert(CGRect(x: 0, y: 500, width: 390, height: 300), to: screen.coordinateSpace)
    let notification = Notification(name: UIResponder.keyboardWillChangeFrameNotification,
      userInfo: [
        UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: end),
        UIResponder.keyboardAnimationDurationUserInfoKey: 0.4,
        UIResponder.keyboardAnimationCurveUserInfoKey: 3,
      ])
    let payload = keyboardTransitionPayload(notification, in: view)
    XCTAssertEqual(payload?["bottomInset"] as? Double, 300)
    XCTAssertEqual((payload?["frame"] as? [String: Double])?["y"], 500)
    XCTAssertEqual(payload?["duration"] as? Double, 0.4)
    XCTAssertEqual(payload?["curve"] as? Int, 3)
  }

  func testHiddenAndFloatingKeyboardTargetsDoNotConsumeBottomSpace() throws {
    let view = try keyboardTestView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    defer { view.removeFromSuperview() }
    let screen = try XCTUnwrap(view.window?.screen)
    for frame in [CGRect(x: 0, y: 844, width: 390, height: 300), CGRect(x: 80, y: 400, width: 240, height: 200)] {
      let end = view.convert(frame, to: screen.coordinateSpace)
      let notification = Notification(name: UIResponder.keyboardWillChangeFrameNotification,
        userInfo: [UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: end)])
      XCTAssertEqual(keyboardTransitionPayload(notification, in: view)?["bottomInset"] as? Double, 0)
    }
  }

  func testKeyboardTimingResolvesUIKitCurves() throws {
    let view = try keyboardTestView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    defer { view.removeFromSuperview() }
    let screen = try XCTUnwrap(view.window?.screen)
    let end = view.convert(CGRect(x: 0, y: 544, width: 390, height: 300), to: screen.coordinateSpace)
    for curve in [3, 7] {
      let notification = Notification(name: UIResponder.keyboardWillChangeFrameNotification,
        userInfo: [
          UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: end),
          UIResponder.keyboardAnimationDurationUserInfoKey: 0.4,
          UIResponder.keyboardAnimationCurveUserInfoKey: curve,
        ])
      let payload = keyboardTransitionPayload(notification, in: view)
      XCTAssertNotNil(payload?["spring"] ?? payload?["controlPoints"])
    }
  }

  func testPushTokenUsesAPNsHexEncoding() {
    XCTAssertEqual(pushTokenHex(Data([0x00, 0x0f, 0xa0, 0xff])), "000fa0ff")
  }

  func testDiscourseURLComesFromNotificationPayload() {
    let url = "https://meta.discourse.org/t/native-push/42/3"

    XCTAssertEqual(discourseUrl(in: ["discourse_url": url]), url)
    XCTAssertNil(discourseUrl(in: ["discourse_url": 42]))
    XCTAssertNil(
      discourseUrl(in: ["discourse_url": String(repeating: "x", count: 2049)])
    )
  }
}
