import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // The shell wants room for rail + sidebar + content + details panel, so the
    // 800x600 Flutter default opens narrower than the layout was designed for.
    self.setContentSize(NSSize(width: 1280, height: 860))
    self.contentMinSize = NSSize(width: 380, height: 480)
    self.center()

    // No title bar: the shell draws its own chrome and runs the full height of
    // the window. The traffic lights stay, floating over the strip the shell
    // reserves across the top (see ShellTitleBar).
    self.styleMask.insert(.fullSizeContentView)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    // Dragging the title bar is how a window is normally moved, so without one
    // the background has to take over.
    self.isMovableByWindowBackground = true

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
