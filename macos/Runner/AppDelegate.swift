import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return false
  }
  
  override func applicationShouldHandleReopen(
      _ sender: NSApplication,
      hasVisibleWindows flag: Bool
    ) -> Bool {

      // If no window is visible, reopen Flutter window
      if !flag {
        for window in sender.windows {
          window.makeKeyAndOrderFront(self)
        }
      }

      return true
    }
}
