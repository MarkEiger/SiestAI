// SleepLockMenu — menu-bar view of sleeplockd. Polls the daemon socket every 2 s.
// Icon: moon = sleep allowed, cup = sleep disabled by N running turns.
import AppKit
import Foundation

let sockPath = (ProcessInfo.processInfo.environment["SLEEPLOCK_DIR"] ?? NSString("~/.cache/sleeplock").expandingTildeInPath) + "/sock"

func query(_ obj: [String: Any]) -> [String: Any]? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let cpath = sockPath.utf8CString
    guard cpath.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
    withUnsafeMutablePointer(to: &addr.sun_path) { p in
        p.withMemoryRebound(to: CChar.self, capacity: cpath.count) { dst in
            cpath.withUnsafeBufferPointer { src in _ = memcpy(dst, src.baseAddress, src.count) }
        }
    }
    let rc = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard rc == 0 else { return nil }
    var tv = timeval(tv_sec: 2, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    guard let body = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
    let out = [UInt8](body) + [10]
    _ = out.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
    var resp = [UInt8](), buf = [UInt8](repeating: 0, count: 8192)
    while true {
        let n = read(fd, &buf, buf.count)
        if n <= 0 { break }
        resp.append(contentsOf: buf[0..<n])
        if resp.last == 10 { break }
    }
    return (try? JSONSerialization.jsonObject(with: Data(resp))) as? [String: Any]
}

final class App: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    var timer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        item.menu = menu
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func icon(_ name: String, _ desc: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: desc)
        img?.isTemplate = true
        return img
    }

    func refresh() {
        menu.removeAllItems()
        guard let st = query(["cmd": "status"]) else {
            item.button?.image = icon("exclamationmark.triangle", "sleeplockd unreachable")
            item.button?.title = ""
            menu.addItem(withTitle: "sleeplockd not running", action: nil, keyEquivalent: "")
            addFooter(); return
        }
        let holders = (st["holders"] as? [String: [String: Any]]) ?? [:]
        let now = (st["now"] as? Double) ?? Date().timeIntervalSince1970
        let disabled = (st["sleep_disabled"] as? Int) == 1
        item.button?.image = icon(disabled ? "cup.and.saucer.fill" : "moon.zzz", disabled ? "sleep disabled" : "sleep allowed")
        item.button?.title = holders.isEmpty ? "" : " \(holders.count)"

        let head = NSMenuItem(title: disabled ? "Sleep disabled — \(holders.count) running turn\(holders.count == 1 ? "" : "s")"
                                             : "Sleep allowed — nothing running", action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        if !holders.isEmpty { menu.addItem(.separator()) }
        for (sid, h) in holders.sorted(by: { (($0.value["since"] as? Double) ?? 0) < (($1.value["since"] as? Double) ?? 0) }) {
            let tool = (h["tool"] as? String) ?? "?"
            let cwd = ((h["cwd"] as? String) ?? "").replacingOccurrences(of: NSHomeDirectory(), with: "~")
            let pid = (h["pid"] as? Int) ?? 0
            let mins = Int((now - ((h["since"] as? Double) ?? now)) / 60)
            let alive = (h["alive"] as? Bool) ?? true
            let line = NSMenuItem(title: "\(tool)  \(cwd.isEmpty ? "?" : cwd)  ·  \(mins)m  ·  pid \(pid)\(alive ? "" : "  (dead)")",
                                  action: #selector(releaseOne(_:)), keyEquivalent: "")
            line.representedObject = sid
            line.target = self
            line.toolTip = "session \(sid) — click: show its terminal · ⌥-click: release"
            menu.addItem(line)
        }
        addFooter()
    }

    func addFooter() {
        menu.addItem(.separator())
        let rel = menu.addItem(withTitle: "Release all (allow sleep now)", action: #selector(releaseAll), keyEquivalent: "")
        rel.target = self
        let q = menu.addItem(withTitle: "Quit SleepLock Menu", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        q.target = NSApp
    }

    @objc func releaseOne(_ sender: NSMenuItem) {
        guard let sid = sender.representedObject as? String else { return }
        if NSEvent.modifierFlags.contains(.option) { _ = query(["cmd": "release", "session": sid]); refresh(); return }
        let p = Process(); p.executableURL = URL(fileURLWithPath: NSString("~/.local/bin/sleeplock").expandingTildeInPath); p.arguments = ["focus", sid]
        try? p.run()
    }
    @objc func releaseAll() { _ = query(["cmd": "release-all"]); refresh() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
