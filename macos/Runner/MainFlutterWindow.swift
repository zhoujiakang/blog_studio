import Cocoa
import FlutterMacOS
import WebKit
import Security

class MainFlutterWindow: NSWindow, NSDraggingDestination {
  private var dropChannel: FlutterMethodChannel?
  private var dropRectangle: NSRect?
  private weak var dragWebView: WKWebView?
  private var editorDragTypes: [NSPasteboard.PasteboardType] = []

  private var credentialChannel: FlutterMethodChannel?
  private var lifecycleChannel: FlutterMethodChannel?
  private var editorFocusChannel: FlutterMethodChannel?

  private weak var previousEditorResponder: NSResponder?

  private func isEditorResponder(_ responder: NSResponder?, web: WKWebView) -> Bool {
    var view = responder as? NSView
    while let current = view {
      if current === web { return true }
      view = current.superview
    }
    return false
  }

  private func releaseEditorKeyboard() -> Bool {
    guard let web = editorWebView(in: contentView),
          isEditorResponder(firstResponder, web: web) else {
      // Flutter may already have activated an input field. Do not overwrite it.
      return true
    }
    if let previous = previousEditorResponder, previous.acceptsFirstResponder,
       let view = previous as? NSView, view.window === self,
       !isEditorResponder(previous, web: web), makeFirstResponder(previous) {
      return !isEditorResponder(firstResponder, web: web)
    }
    if let flutterView = contentViewController?.view, flutterView.acceptsFirstResponder {
      _ = makeFirstResponder(flutterView)
    } else {
      _ = makeFirstResponder(nil)
    }
    return !isEditorResponder(firstResponder, web: web)
  }

  private func editorWebView(in view: NSView?) -> WKWebView? {
    guard let view = view, !view.isHidden else { return nil }
    if let web = view as? WKWebView { return web }
    for child in view.subviews {
      if let web = editorWebView(in: child) { return web }
    }
    return nil
  }

  private func focusEditor() -> Bool {
    guard let web = editorWebView(in: contentView), web.acceptsFirstResponder else { return false }
    if !isEditorResponder(firstResponder, web: web) {
      previousEditorResponder = firstResponder
      _ = makeFirstResponder(web)
    }
    return firstResponder === web
  }

  // DOM focus alone does not route AppKit keyboard events to the platform view.
  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown, event.modifierFlags.contains(.command),
       event.charactersIgnoringModifiers?.lowercased() == "v",
       let web = editorWebView(in: contentView), firstResponder === web,
       NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil) {
      editorFocusChannel?.invokeMethod("pasteImage", arguments: nil)
      return
    }
    if event.type == .leftMouseDown, let web = editorWebView(in: contentView) {
      var hit = contentView?.hitTest(contentView!.convert(event.locationInWindow, from: nil))
      var editorHit = false
      while let view = hit {
        if view === web { editorHit = true; break }
        hit = view.superview
      }
      if editorHit {
        _ = focusEditor()
      } else {
        _ = releaseEditorKeyboard()
      }
    }
    super.sendEvent(event)
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    credentialChannel = FlutterMethodChannel(
      name: "inkjian/credentials",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    credentialChannel?.setMethodCallHandler { call, result in
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "inkjian.github.authorization",
        kSecAttrAccount as String: "github"
      ]
      func failure(_ status: OSStatus) {
        result(FlutterError(code: "keychain", message: "无法访问系统钥匙串", details: Int(status)))
      }
      switch call.method {
      case "read":
        var readQuery = query
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &item)
        if status == errSecItemNotFound { result(nil) }
        else if status == errSecSuccess, let data = item as? Data {
          result(String(data: data, encoding: .utf8))
        } else { failure(status) }
      case "write":
        guard let value = call.arguments as? String, let data = value.data(using: .utf8) else {
          result(FlutterError(code: "arguments", message: "凭证格式无效", details: nil)); return
        }
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
          var addQuery = query
          addQuery[kSecValueData as String] = data
          addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
          status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        if status == errSecSuccess { result(nil) } else { failure(status) }
      case "delete":
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { result(nil) }
        else { failure(status) }
      default: result(FlutterMethodNotImplemented)
      }
    }

    editorFocusChannel = FlutterMethodChannel(
      name: "blog_studio/editor_focus",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    editorFocusChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(false); return }
      switch call.method {
      case "focus": result(self.focusEditor())
      case "blur": result(self.releaseEditorKeyboard())
      case "state":
        let web = self.editorWebView(in: self.contentView)
        var centerHit = web.flatMap { view in
          self.contentView?.hitTest(self.contentView!.convert(
            NSPoint(x: view.bounds.midX, y: view.bounds.midY), from: view))
        }
        var pointerReachesEditor = false
        while let view = centerHit {
          if view === web { pointerReachesEditor = true; break }
          centerHit = view.superview
        }
        result([
          "editorFocused": web.map { self.isEditorResponder(self.firstResponder, web: $0) } ?? false,
          "firstResponder": self.firstResponder.map { String(describing: type(of: $0)) } ?? "none",
          "keyWindow": self.isKeyWindow,
          "pointerReachesEditor": pointerReachesEditor
        ])
      default: result(FlutterMethodNotImplemented)
      }
    }

    lifecycleChannel = FlutterMethodChannel(
      name: "blog_studio/lifecycle",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    lifecycleChannel?.setMethodCallHandler { call, result in
      guard call.method == "quit" else { result(FlutterMethodNotImplemented); return }
      (NSApp.delegate as? AppDelegate)?.terminationApproved = true
      result(nil)
      DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    dropChannel = FlutterMethodChannel(
      name: "inkjian/file_drops",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    dropChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      guard call.method == "target" else { result(FlutterMethodNotImplemented); return }
      if let web = self.dragWebView {
        web.registerForDraggedTypes(self.editorDragTypes)
      }
      self.dragWebView = nil
      if let values = call.arguments as? [String: Double],
         let left = values["left"], let top = values["top"],
         let width = values["width"], let height = values["height"] {
        self.dropRectangle = NSRect(x: left,
          y: (self.contentView?.bounds.height ?? 0) - top - height,
          width: width, height: height)
        self.registerForDraggedTypes([.fileURL])
        if let web = self.editorWebView(in: self.contentView) {
          self.dragWebView = web
          self.editorDragTypes = web.registeredDraggedTypes
          web.unregisterDraggedTypes()
        }
      } else {
        self.dropRectangle = nil
        self.unregisterDraggedTypes()
      }
      result(nil)
    }

    super.awakeFromNib()
  }

  private func imagePaths(_ sender: NSDraggingInfo) -> [String] {
    let urls = sender.draggingPasteboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    return urls.filter {
      ["png", "jpg", "jpeg", "gif", "webp"].contains($0.pathExtension.lowercased())
        && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }.map { $0.path }
  }

  private func acceptsDrop(_ sender: NSDraggingInfo) -> Bool {
    dropRectangle?.contains(sender.draggingLocation) == true && !imagePaths(sender).isEmpty
  }

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    return draggingUpdated(sender)
  }

  func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    let accepted = acceptsDrop(sender)
    dropChannel?.invokeMethod("event", arguments: ["hovering": accepted])
    return accepted ? .copy : []
  }

  func draggingExited(_ sender: NSDraggingInfo?) {
    dropChannel?.invokeMethod("event", arguments: ["hovering": false])
  }

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard acceptsDrop(sender) else { return false }
    dropChannel?.invokeMethod("event", arguments: ["paths": imagePaths(sender)])
    return true
  }
}
