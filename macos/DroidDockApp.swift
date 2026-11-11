// App entry, menu commands, and the Settings window.
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // For screenshots and tests only: DROIDDOCK_APPEARANCE=dark|light forces the look.
        switch ProcessInfo.processInfo.environment["DROIDDOCK_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }
}

@main
struct DroidDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared
    @AppStorage("showThumbnails") private var showThumbnails = true

    var body: some Scene {
        Window("DroidDock", id: "main") {
            ContentView().environmentObject(model)
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Send to Phone…") { model.showImporter = true }
                    .keyboardShortcut("o")
                    .disabled(model.current == nil)
                Button("Copy to Mac") { model.copyToMac() }
                    .keyboardShortcut("d")
                    .disabled(model.selection.isEmpty)
                Divider()
                Button("Show Mac Folder in Finder") { model.revealSaveFolder() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Toggle("Show Photo Thumbnails", isOn: $showThumbnails)
                    .keyboardShortcut("t", modifiers: [.command, .option])
                Divider()
            }
            CommandMenu("Go") {
                Button("Back") { model.goBack() }.keyboardShortcut("[").disabled(!model.canGoBack)
                Button("Forward") { model.goForward() }.keyboardShortcut("]").disabled(!model.canGoForward)
                Button("Enclosing Folder") { model.goUp() }.keyboardShortcut(.upArrow).disabled(!model.canGoUp)
                Divider()
                ForEach(Array(Place.all.enumerated()), id: \.offset) { i, place in
                    Button(place.title) { model.go(place.path) }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [.command, .option])
                }
            }
            CommandMenu("Phone") {
                Button("Choose Phone…") { model.showPhones = true }.keyboardShortcut("k")
                Button("Refresh") { Task { await model.load() } }.keyboardShortcut("r")
            }
        }

        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @AppStorage(Defaults.saveDir) private var saveDir = ""
    @AppStorage(Defaults.pickerAtStart) private var pickerAtStart = true
    @AppStorage("showThumbnails") private var showThumbnails = true

    var body: some View {
        Form {
            LabeledContent("Save copied files to:") {
                HStack {
                    Text(Defaults.saveURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("Choose…") { choose() }
                }
            }
            Toggle("Show the phone list when the app opens", isOn: $pickerAtStart)
            Toggle("Show photo thumbnails", isOn: $showThumbnails)
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = Defaults.saveURL
        if panel.runModal() == .OK, let url = panel.url { saveDir = url.path }
    }
}
