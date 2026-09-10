import AppKit

@main @MainActor enum WindowFixture {
    static func main() {
        let app = NSApplication.shared
        let parent = getppid()
        app.setActivationPolicy(.accessory)
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let screen = NSScreen.screens.first!
        let top = screen.frame.maxY
        let window = NSWindow(contentRect: NSRect(x: screen.visibleFrame.minX + 180, y: screen.visibleFrame.minY + 180, width: 260, height: 140),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.title = "Ruller Attach test"; window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        if #available(macOS 14.0, *) { window.collectionBehavior.insert(.canJoinAllApplications) }
        window.orderFrontRegardless()
        var last = ""
        let timer = Timer(timeInterval: 0.03, repeats: true) { _ in
            MainActor.assumeIsolated {
                if getppid() != parent { app.terminate(nil); return }
                guard let command = try? String(contentsOf: folder.appendingPathComponent("command"), encoding: .utf8), command != last else { return }
                last = command
                switch command {
                case "move": window.setFrameOrigin(NSPoint(x: window.frame.minX + 40, y: window.frame.minY + 30))
                case "hide": window.orderOut(nil)
                case "show": window.orderFrontRegardless()
                case "front": app.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
                case "float": window.level = .floating; window.orderFrontRegardless()
                case "normal": window.level = .normal; window.orderFrontRegardless()
                case "pass-through": window.ignoresMouseEvents = true
                case "capture-mouse": window.ignoresMouseEvents = false
                case "close": window.close()
                case "quit": app.terminate(nil)
                default:
                    let values = command.split(separator: " ")
                    if values.count == 3, values[0] == "position", let x = Double(values[1]), let y = Double(values[2]) {
                        window.setFrameOrigin(NSPoint(x: x, y: top - y - window.frame.height))
                        window.orderFrontRegardless()
                    }
                }
                let state: [String: Any] = ["command": command, "id": window.windowNumber,
                    "x": window.frame.minX, "y": top - window.frame.maxY]
                try! JSONSerialization.data(withJSONObject: state).write(to: folder.appendingPathComponent("state"), options: .atomic)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        app.run()
    }
}
