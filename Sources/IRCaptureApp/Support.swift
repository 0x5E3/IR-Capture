#if os(macOS)
import AppKit
import Foundation
import IRCaptureCore

/// Product constants. Lowell decides the name and the support address (readiness plan, section 9);
/// change them here and in scripts/make_app.sh (APP_NAME).
enum Product {
    static let name = "IR Capture"
    /// Placeholder until Lowell picks the support address.
    static let supportEmail = "support@swellamps.com"
    static let website = URL(string: "https://swellamps.com")!
    /// Until P1.7 (a real version check) this opens the download page.
    static let updatesPage = URL(string: "https://github.com/0x5E3/IR-Capture/releases/latest")!

    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? IRCaptureVersion }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev" }
    static var channel: String { Bundle.main.infoDictionary?["IRCaptureChannel"] as? String ?? "development" }
    /// "1.0.0 (build 14)" plus " pre-release" for builds that aren't a tagged release.
    static var fullVersion: String { "\(version) (build \(build))" + (channel == "release" ? "" : " pre-release") }
    static var macOS: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

/// A plain-text log in ~/Library/Logs/IR Capture/, for support: device names, rates, CoreAudio errors, timings.
enum Log {
    private static let queue = DispatchQueue(label: "ircapture.log")
    static let folder = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Logs").appendingPathComponent(Product.name)
    static let file = folder.appendingPathComponent("\(Product.name).log")
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    static func write(_ line: String) {
        let text = "\(stamp.string(from: Date()))  \(line)\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            if let a = try? fm.attributesOfItem(atPath: file.path), let size = a[.size] as? Int, size > 2_000_000 {
                let old = folder.appendingPathComponent("\(Product.name).previous.log")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: file, to: old)
            }
            if let h = try? FileHandle(forWritingTo: file) {
                h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
            } else {
                try? Data(text.utf8).write(to: file)
            }
        }
    }

    static func reveal() {
        write("log opened from the Help menu")
        queue.async {
            DispatchQueue.main.async {
                if FileManager.default.fileExists(atPath: file.path) { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                else { NSWorkspace.shared.open(folder) }
            }
        }
    }
}

enum Support {
    /// Opens a mail draft to support with the details support needs, and attaches the log and the latest report.
    @MainActor
    static func contact(interface: String?, latestReport: URL?) {
        Log.write("contact support: \(Product.fullVersion), \(Product.macOS), interface \(interface ?? "none")")
        let subject = "\(Product.name) \(Product.version) support"
        let body = """
        What happened (and what you expected):


        ——
        \(Product.name) \(Product.fullVersion)
        \(Product.macOS) · \(ProcessInfo.processInfo.machineHardwareName)
        Interface: \(interface ?? "none selected")
        The log and the latest report.json are attached if your mail app allows it.
        """
        var items: [Any] = [body]
        if FileManager.default.fileExists(atPath: Log.file.path) { items.append(Log.file) }
        if let r = latestReport, FileManager.default.fileExists(atPath: r.path) { items.append(r) }
        if let s = NSSharingService(named: .composeEmail), s.canPerform(withItems: items) {
            s.recipients = [Product.supportEmail]
            s.subject = subject
            s.perform(withItems: items)
            return
        }
        // No mail app set up: fall back to a mailto: link and show the files to attach by hand.
        var c = URLComponents()
        c.scheme = "mailto"; c.path = Product.supportEmail
        c.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        if let u = c.url { NSWorkspace.shared.open(u) }
        let files = items.compactMap { $0 as? URL }
        if !files.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(files) }
    }

    @MainActor
    static func showAbout() {
        let credits = NSMutableAttributedString()
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        credits.append(NSAttributedString(string: "Guitar cab impulse responses and NAM amp captures, recorded through your own interface.\n\n", attributes: small))
        credits.append(NSAttributedString(string: "Method: exponential sine sweeps (Farina), averaged, with harmonic distortion windowed out. With a reference tap each IR is the speaker-terminal voltage to microphone response.\n\n", attributes: small))
        credits.append(NSAttributedString(string: "Support: \(Product.supportEmail)\n", attributes: small))
        var link = small; link[.link] = Product.website
        credits.append(NSAttributedString(string: "swellamps.com", attributes: link))
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: Product.name,
            .applicationVersion: Product.version + (Product.channel == "release" ? "" : " pre-release"),
            .version: "build \(Product.build)",
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© Swell Amplification LLC",
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension ProcessInfo {
    /// "arm64" or "x86_64" — useful to support, since Intel Macs behave differently.
    var machineHardwareName: String {
        var u = utsname()
        uname(&u)
        return withUnsafePointer(to: &u.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
    }
}
#endif
