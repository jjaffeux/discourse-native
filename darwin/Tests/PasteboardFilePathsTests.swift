#if os(macOS)
import AppKit
import XCTest
@testable import DiscourseNativeSupport

final class PasteboardFilePathsTests: XCTestCase {
  private var pasteboard: NSPasteboard!

  override func setUp() {
    super.setUp()
    pasteboard = NSPasteboard(
      name: NSPasteboard.Name("org.discourse.native.tests.\(UUID().uuidString)")
    )
    pasteboard.clearContents()
  }

  override func tearDown() {
    pasteboard.releaseGlobally()
    pasteboard = nil
    super.tearDown()
  }

  func testCopiedWebLinkNamesNoFile() {
    // What Safari's Copy Link and the address bar write.
    let link = "https://attacker.example/private/etc/hosts"
    pasteboard.setString(link, forType: .URL)
    pasteboard.setString(link, forType: .string)

    XCTAssertEqual(pasteboardFilePaths(pasteboard), [])
  }

  func testCopiedFileSchemeLinkNamesNoFile() {
    pasteboard.setString("file:///private/etc/hosts", forType: .URL)

    XCTAssertEqual(pasteboardFilePaths(pasteboard), [])
  }

  func testTextThatLooksLikeAPathNamesNoFile() {
    pasteboard.setString("/private/etc/hosts", forType: .string)

    XCTAssertEqual(pasteboardFilePaths(pasteboard), [])
  }

  func testCopiedFilesYieldTheirPathsInOrder() {
    // Finder writes one item per copied file, each with its name as text.
    let items = ["/private/etc/services", "/private/etc/hosts"].map { path in
      let item = NSPasteboardItem()
      item.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
      item.setString((path as NSString).lastPathComponent, forType: .string)
      return item
    }
    XCTAssertTrue(pasteboard.writeObjects(items))

    XCTAssertEqual(
      pasteboardFilePaths(pasteboard),
      ["/private/etc/services", "/private/etc/hosts"]
    )
  }

  func testFileReferenceURLYieldsItsPath() throws {
    let reference = try XCTUnwrap(
      (URL(fileURLWithPath: "/private/etc/hosts") as NSURL).fileReferenceURL()
    )
    XCTAssertTrue(pasteboard.writeObjects([reference as NSURL]))

    XCTAssertEqual(pasteboardFilePaths(pasteboard), ["/private/etc/hosts"])
  }
}
#endif
