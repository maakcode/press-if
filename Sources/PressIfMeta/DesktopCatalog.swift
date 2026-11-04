import AppKit
import PressIfCore

@MainActor
final class DesktopCatalog {
    private(set) var apps: [AppIdentity] = []
    private var locations: [String: URL] = [:]

    func refresh() {
        var identities: [String: AppIdentity] = [:]
        let roots = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        for root in roots {
            let url = URL(fileURLWithPath: root)
            guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let appURL as URL in files {
                guard appURL.pathExtension.lowercased() == "app", let bundle = Bundle(url: appURL), let id = bundle.bundleIdentifier else { continue }
                let diskName = appURL.deletingPathExtension().lastPathComponent
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? diskName
                let aliases = Array(Set([diskName, name] + Self.localizedAliases[id, default: []])).sorted()
                identities[id] = AppIdentity(bundleID: id, name: name, aliases: aliases)
                locations[id] = appURL
            }
        }
        for running in NSWorkspace.shared.runningApplications {
            guard let id = running.bundleIdentifier, let url = running.bundleURL, let name = running.localizedName, identities[id] == nil else { continue }
            identities[id] = AppIdentity(bundleID: id, name: name, aliases: [url.deletingPathExtension().lastPathComponent])
            locations[id] = url
        }
        apps = identities.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func title(for id: String?) -> String {
        guard let id else { return "app" }
        if let name = Self.displayNames[id] { return name }
        if let name = apps.first(where: { $0.bundleID == id })?.name { return name }
        guard let location = locations[id] ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return "app" }
        let bundle = Bundle(url: location)
        return bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? location.deletingPathExtension().lastPathComponent
    }

    func icon(for id: String?) -> NSImage? {
        guard let id, let location = locations[id] ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: location.path)
    }

    func activate(_ id: String) async throws -> NSRunningApplication {
        guard let location = locations[id] else { throw PressError.message("Could not find the installed app. Preview again.") }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let application = try await NSWorkspace.shared.openApplication(at: location, configuration: configuration)
        application.activate()
        for _ in 0..<30 {
            try Task.checkCancellation()
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier {
                try await Task.sleep(for: .milliseconds(500))
                return application
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw PressError.message("Could not bring \(title(for: id)) to the front.")
    }

    private static let displayNames = [
        "com.apple.clock": "Clock",
        "com.apple.calculator": "Calculator",
        "com.apple.Safari": "Safari",
        "com.apple.Notes": "Notes",
        "com.apple.TextEdit": "TextEdit",
        "com.apple.iCal": "Calendar",
        "com.google.Chrome": "Chrome",
        "com.apple.Preview": "Preview"
    ]

    private static let localizedAliases: [String: [String]] = [
        "com.apple.clock": ["시계", "Clock", "시계.app"],
        "com.apple.calculator": ["계산기"],
        "com.apple.Safari": ["사파리"],
        "com.apple.Notes": ["메모"],
        "com.apple.TextEdit": ["텍스트 편집기"],
        "com.apple.iCal": ["캘린더", "달력"],
        "com.google.Chrome": ["크롬"],
        "com.apple.Preview": ["미리보기"]
    ]
}
