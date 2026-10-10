import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var terminationApproved = false
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if terminationApproved { return .terminateNow }
    if let window = sender.windows.first(where: { $0.isVisible }) {
      window.performClose(nil)
      return .terminateCancel
    }
    return .terminateNow
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
