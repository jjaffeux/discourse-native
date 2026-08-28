import XCTest

@testable import Runner

final class RunnerTests: XCTestCase {
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
