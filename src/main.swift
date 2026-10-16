import Cocoa
import WebKit

// MARK: - Persistent storage (~/Library/Application Support/CourseS)

final class Store {
    let dir: URL
    let file: URL
    let snapDir: URL
    private let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("CourseS", isDirectory: true)
        file = dir.appendingPathComponent("courses.json")
        snapDir = dir.appendingPathComponent("Snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: snapDir, withIntermediateDirectories: true)
    }

    private func courseCount(_ data: Data) -> (courses: Int, trash: Int)? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let courses = obj["courses"] as? [Any] else { return nil }
        return (courses.count, (obj["trash"] as? [Any])?.count ?? 0)
    }

    private func snapshots() -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: snapDir, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Main file first; if it is missing or corrupt, fall back to the newest valid snapshot.
    func load() -> String? {
        for url in [file] + snapshots() {
            if let d = try? Data(contentsOf: url), courseCount(d) != nil,
               let s = String(data: d, encoding: .utf8) { return s }
        }
        return nil
    }

    func save(_ json: String) {
        guard let data = json.data(using: .utf8), let new = courseCount(data) else { return }
        // Safety net: never let an empty state silently replace real data.
        if new.courses + new.trash == 0, let old = try? Data(contentsOf: file),
           let oldCount = courseCount(old), oldCount.courses > 0 {
            NSLog("CourseS: refused to overwrite \(oldCount.courses) courses with empty data")
            return
        }
        do { try data.write(to: file, options: .atomic) } catch { NSLog("CourseS: save failed: \(error)") }
        // One rolling snapshot per day, last 30 days kept.
        let snap = snapDir.appendingPathComponent("courses-\(dayFormat.string(from: Date())).json")
        try? data.write(to: snap, options: .atomic)
        for old in snapshots().dropFirst(30) { try? FileManager.default.removeItem(at: old) }
    }
}

// MARK: - Menu bar panel

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var statusItem: NSStatusItem!
    var panel: Panel!
    var webView: WKWebView!
    let store = Store()
    var contentSize = NSSize(width: 440, height: 320)
    var pinned = false
    var outsideClickMonitor: Any?
    var didFlush = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let img = NSImage(systemSymbolName: "books.vertical.fill", accessibilityDescription: "CourseS")
            img?.isTemplate = true
            button.image = img
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let ucc = WKUserContentController()
        ucc.add(self, name: "save")
        ucc.add(self, name: "panel")
        let config = WKWebViewConfiguration()
        config.userContentController = ucc
        webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false

        panel = Panel(contentRect: NSRect(origin: .zero, size: contentSize),
                      styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let fx = NSVisualEffectView()
        fx.material = .popover
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.maskImage = Self.roundedMask(radius: 18)
        panel.contentView = fx
        fx.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: fx.topAnchor),
            webView.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
        ])

        loadPage()
    }

    static func roundedMask(radius: CGFloat) -> NSImage {
        let d = radius * 2 + 1
        let img = NSImage(size: NSSize(width: d, height: d), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        img.resizingMode = .stretch
        return img
    }

    /// Injects the latest saved data from disk, then loads the UI.
    func loadPage() {
        let ucc = webView.configuration.userContentController
        ucc.removeAllUserScripts()
        let initial = store.load() ?? "null"
        ucc.addUserScript(WKUserScript(source: "window.__INITIAL_DATA__ = \(initial);",
                                       injectionTime: .atDocumentStart, forMainFrameOnly: true))
        guard let html = Bundle.main.url(forResource: "index", withExtension: "html") else { return }
        webView.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
    }

    // MARK: Show / hide

    @objc func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let data = menu.addItem(withTitle: "Show Saved Data in Finder", action: #selector(showData(_:)), keyEquivalent: "")
            data.target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit CourseS", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            sender.performClick(nil)   // pops the menu
            statusItem.menu = nil
            return
        }
        panel.isVisible ? hidePanel() : showPanel()
    }

    var anchor: (screen: NSScreen, rect: NSRect)? {
        guard let button = statusItem.button, let win = button.window else { return nil }
        let rect = win.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = win.screen ?? NSScreen.main ?? NSScreen.screens[0]
        return (screen, rect)
    }

    /// Frame hanging just below the menu bar icon, kept fully on screen.
    func panelFrame() -> NSRect {
        guard let (screen, r) = anchor else { return panel.frame }
        let vf = screen.visibleFrame
        let top = r.minY - 6
        let w = min(contentSize.width, vf.width - 16)
        let h = min(contentSize.height, top - vf.minY - 10)
        var x = r.midX - w / 2
        x = max(vf.minX + 8, min(x, vf.maxX - 8 - w))
        return NSRect(x: x, y: top - h, width: w, height: h)
    }

    func showPanel() {
        if let (screen, r) = anchor {
            let vf = screen.visibleFrame
            let maxH = r.minY - 6 - vf.minY - 10
            webView.evaluateJavaScript("window.onShow && window.onShow(\(Int(vf.width - 16)), \(Int(maxH)))", completionHandler: nil)
        }
        let end = panelFrame()
        panel.setFrame(end.offsetBy(dx: 0, dy: 8), display: false)
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(end, display: true)
        }
        statusItem.button?.highlight(true)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.pinned else { return }
            self.hidePanel()
        }
    }

    func hidePanel() {
        guard panel.isVisible else { return }
        webView.evaluateJavaScript("window.flushSave && window.flushSave()", completionHandler: nil)
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
        statusItem.button?.highlight(false)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
            self?.panel.alphaValue = 1
        })
    }

    // MARK: Bridge

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "save":
            if let s = message.body as? String { store.save(s) }
        case "panel":
            guard let body = message.body as? [String: Any] else { return }
            if let w = body["w"] as? Double, let h = body["h"] as? Double {
                contentSize = NSSize(width: ceil(w), height: ceil(h))
                if panel.isVisible { panel.setFrame(panelFrame(), display: true, animate: false) }
            }
            if let p = body["pinned"] as? Bool { pinned = p }
            if let cmd = body["cmd"] as? String {
                if cmd == "close" { hidePanel() }
                if cmd == "quit" { NSApp.terminate(nil) }
            }
        default: break
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, url.isFileURL { decisionHandler(.allow); return }
        if let url = action.request.url { NSWorkspace.shared.open(url) }
        decisionHandler(.cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loadPage() // re-reads fresh data from disk
    }

    // Flush any pending edit before quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if didFlush || webView == nil { return .terminateNow }
        webView.evaluateJavaScript("window.flushSave ? window.flushSave() : null") { [weak self] result, _ in
            if let s = result as? String { self?.store.save(s) }
            self?.didFlush = true
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    @objc func showData(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting([store.file])
    }

    /// Never shown (menu bar app), but routes ⌘C / ⌘V / ⌘Z / ⌘A to the text fields.
    func buildMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit CourseS", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = appMenu

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only — no Dock icon, no window
app.run()
