import SwiftUI
import AppKit

@main
struct PressIfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Press If", id: "main") {
            MainView(model: model)
                .environment(\.locale, PressLocale.english)
                .onAppear { delegate.connect(model) }
        }
        .defaultSize(width: 1120, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") { model.newRequest(); openWindow(id: "main") }
                    .keyboardShortcut("n")
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.showSettings = true; openWindow(id: "main") }
                    .keyboardShortcut(",")
            }
        }
        MenuBarExtra("Press If", systemImage: model.runningID == nil ? "cursorarrow.rays" : "stop.circle.fill") {
            Button("Open Press If") { openWindow(id: "main"); NSApp.activate() }
            if model.pendingCount > 0 { Text("\(model.pendingCount) scheduled") }
            if model.runningID != nil || model.pendingCount > 0 || model.interpreting {
                Divider()
                Button("Stop All") { model.stopAll() }
            }
            Divider()
            Button("Quit Press If") { model.stopAll(); NSApp.terminate(nil) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private var hotkeys: GlobalHotkeys?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
    }

    func connect(_ model: AppModel) {
        self.model = model
        guard hotkeys == nil else { return }
        let keys = GlobalHotkeys()
        keys.onOpen = { [weak model] in
            Task { @MainActor in
                model?.newRequest()
                NSApp.activate()
                NSApp.windows.first(where: { $0.title == "Press If" })?.makeKeyAndOrderFront(nil)
            }
        }
        keys.onStop = { [weak model] in Task { @MainActor in model?.stopAll() } }
        hotkeys = keys
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.stopAll(reason: "Scheduled tasks paused when the app quit.")
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
