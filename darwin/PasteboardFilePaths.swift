#if os(macOS)
import AppKit

/// Paths of the files copied onto `pasteboard`, in pasteboard order.
///
/// Any URL on the pasteboard coerces to NSURL, including the `public.url` a
/// browser writes for a copied link. Read without `.urlReadingFileURLsOnly`,
/// `https://host/Users/me/secret` yields `/Users/me/secret`, and pasting that
/// link would upload the local file it happens to name. With the option AppKit
/// returns only `public.file-url` items: what Finder writes for copied files,
/// and never a web link, whatever its scheme.
func pasteboardFilePaths(_ pasteboard: NSPasteboard) -> [String] {
  let urls = pasteboard.readObjects(
    forClasses: [NSURL.self],
    options: [.urlReadingFileURLsOnly: true]
  ) ?? []
  return urls.compactMap { object in
    guard let url = object as? NSURL, url.isFileURL else { return nil }
    return url.path
  }
}
#endif
