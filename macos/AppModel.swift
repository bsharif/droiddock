// App state: phones, the open folder, selection, and transfers.
import AppKit
import SwiftUI

struct Place: Identifiable, Hashable {
    let title: String
    let symbol: String
    let path: String
    var id: String { path }

    static let all: [Place] = [
        Place(title: "Camera", symbol: "camera", path: "/sdcard/DCIM/Camera"),
        Place(title: "Screenshots", symbol: "camera.viewfinder", path: "/sdcard/Pictures/Screenshots"),
        Place(title: "Pictures", symbol: "photo.on.rectangle", path: "/sdcard/Pictures"),
        Place(title: "Downloads", symbol: "arrow.down.circle", path: "/sdcard/Download"),
        Place(title: "Documents", symbol: "doc", path: "/sdcard/Documents"),
        Place(title: "Movies", symbol: "film", path: "/sdcard/Movies"),
        Place(title: "Music", symbol: "music.note", path: "/sdcard/Music"),
        Place(title: "Internal Storage", symbol: "internaldrive", path: "/sdcard"),
    ]
}

enum Defaults {
    static let saveDir = "saveDir"
    static let lastSerial = "lastSerial"
    static let pickerAtStart = "pickerAtStart"
    static var saveURL: URL {
        if let p = UserDefaults.standard.string(forKey: saveDir), !p.isEmpty { return URL(fileURLWithPath: p) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/DroidDock")
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // Phones
    @Published var devices: [Device] = []
    @Published var recent: [String] = []
    @Published var services: [Service] = []
    @Published var searchingWiFi = false
    @Published var selectedSerial: String?
    @Published var showPhones = false
    @Published var phoneBusy: String?

    // Files
    @Published var path = "/sdcard/DCIM/Camera"
    @Published var items: [FileItem] = []
    @Published var loading = false
    @Published var loadError: String?
    @Published var selection = Set<FileItem.ID>()
    @Published var search = ""
    @Published var sortOrder = [KeyPathComparator(\FileItem.mtime, order: .reverse)]
    private var back: [String] = []
    private var forward: [String] = []

    // Transfers
    @Published var transfer: String?
    @Published var lastResult: String?
    @Published var alert: String?
    @Published var showImporter = false
    @Published var dropTargeted = false

    private var poller: Timer?
    private var started = false

    var current: Device? { devices.first { $0.serial == selectedSerial && $0.ready } }
    var readyDevices: [Device] { devices.filter(\.ready) }
    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }
    var canGoUp: Bool { path != "/sdcard" && path.count > 1 }
    var folderName: String { path == "/sdcard" ? "Internal Storage" : (path as NSString).lastPathComponent }

    var visibleItems: [FileItem] {
        let f = search.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return f.filter(\.dir).sorted(using: sortOrder) + f.filter { !$0.dir }.sorted(using: sortOrder)
    }

    var selectedItems: [FileItem] { items.filter { selection.contains($0.id) } }

    // MARK: start

    func start() {
        guard !started else { return }
        started = true
        if UserDefaults.standard.object(forKey: Defaults.pickerAtStart) == nil {
            UserDefaults.standard.set(true, forKey: Defaults.pickerAtStart)
        }
        selectedSerial = UserDefaults.standard.string(forKey: Defaults.lastSerial)
        Task {
            await refreshDevices() // this also starts the folder load when it finds a phone
            if UserDefaults.standard.bool(forKey: Defaults.pickerAtStart) || current == nil { showPhones = true }
        }
        poller = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            Task { @MainActor in await AppModel.shared.refreshDevices() }
        }
    }

    // MARK: phones

    func refreshDevices() async {
        guard let list = try? await Engine.call(["devices"], as: DeviceList.self) else { return }
        let had = current?.serial
        devices = list.devices
        recent = list.recent
        if current == nil { autoSelect() }
        // Load the folder in the background, so the caller (for example the startup picker)
        // does not wait for a large folder to finish.
        if current?.serial != had, current != nil { Task { await self.load() } }
    }

    /// Keep the chosen phone; else the last one used; else a USB phone; else any ready phone.
    private func autoSelect() {
        let last = UserDefaults.standard.string(forKey: Defaults.lastSerial)
        let pick = readyDevices.first { $0.serial == last }
            ?? readyDevices.first { !$0.wifi }
            ?? readyDevices.first
        if let pick { selectedSerial = pick.serial }
    }

    func use(_ d: Device) {
        selectedSerial = d.serial
        UserDefaults.standard.set(d.serial, forKey: Defaults.lastSerial)
        Task { await load() }
    }

    func searchWiFi() async {
        searchingWiFi = true
        services = (try? await Engine.call(["mdns"], as: ServiceList.self))?.items ?? []
        searchingWiFi = false
    }

    private func phoneTask(_ label: String, _ work: @escaping () async throws -> Void) {
        phoneBusy = label
        Task {
            do { try await work() } catch { alert = error.localizedDescription }
            phoneBusy = nil
            await refreshDevices()
            await searchWiFi()
        }
    }

    func connect(_ addr: String) {
        let a = addr.trimmingCharacters(in: .whitespaces)
        guard !a.isEmpty else { return }
        phoneTask("Connecting to \(a)…") {
            _ = try await Engine.call(["connect", a], as: OK.self)
            await self.refreshDevices()
            if let d = self.devices.first(where: { $0.serial == a && $0.ready }) { self.use(d) }
        }
    }

    func pair(_ addr: String, _ code: String) {
        phoneTask("Pairing…") {
            _ = try await Engine.call(["pair", addr.trimmingCharacters(in: .whitespaces), code.trimmingCharacters(in: .whitespaces)], as: OK.self)
            try? await Task.sleep(for: .seconds(2))
        }
    }

    func disconnect(_ d: Device) {
        phoneTask("Disconnecting…") { _ = try await Engine.call(["disconnect", d.serial], as: OK.self) }
    }

    func forget(_ addr: String) {
        phoneTask("") { _ = try await Engine.call(["forget", addr], as: OK.self) }
    }

    func wifiOff(_ d: Device) {
        phoneTask("Turning off unencrypted Wi-Fi…") {
            _ = try await Engine.call(["wifi-off", d.serial], as: OK.self)
            if self.selectedSerial == d.serial { self.selectedSerial = nil }
        }
    }

    func switchToWiFi(_ d: Device) {
        phoneTask("Switching to Wi-Fi…") {
            struct R: Decodable { let serial: String }
            let r = try await Engine.call(["usb-to-wifi", d.serial], as: R.self)
            await self.refreshDevices()
            if let w = self.devices.first(where: { $0.serial == r.serial }) { self.use(w) }
        }
    }

    // MARK: folders

    func go(_ p: String, record: Bool = true) {
        if record, p != path { back.append(path); forward.removeAll() }
        path = p
        selection = []
        search = ""
        Task { await load() }
    }

    func goBack() { guard let p = back.popLast() else { return }; forward.append(path); go(p, record: false) }
    func goForward() { guard let p = forward.popLast() else { return }; back.append(path); go(p, record: false) }
    func goUp() { if canGoUp { go((path as NSString).deletingLastPathComponent) } }

    private var loadToken = 0

    func load() async {
        guard let dev = current else { items = []; loadError = nil; loading = false; return }
        let p = path
        loadToken += 1
        let token = loadToken
        loading = true
        // Only the newest load may change the list or the spinner.
        defer { if token == loadToken { loading = false } }
        do {
            let list = try await Engine.call(["ls", dev.serial, p], as: FileList.self)
            guard token == loadToken else { return }
            items = list.items
            loadError = nil
            selection = selection.filter { id in items.contains { $0.id == id } }
        } catch {
            guard token == loadToken else { return }
            items = []
            loadError = error.localizedDescription
        }
    }

    func open(_ ids: Set<FileItem.ID>) {
        let chosen = items.filter { ids.contains($0.id) }
        if chosen.count == 1, let one = chosen.first, one.dir { go(one.path); return }
        copyToMac(chosen, openAfter: true)
    }

    // MARK: transfers

    func copyToMac(_ chosen: [FileItem]? = nil, openAfter: Bool = false) {
        let list = chosen ?? selectedItems
        guard let dev = current, !list.isEmpty, transfer == nil else { return }
        let dest = Defaults.saveURL
        transfer = "Copying \(list.count == 1 ? list[0].name : "\(list.count) items") to the Mac…"
        Task {
            do {
                let r = try await Engine.call(["pull", dev.serial, dest.path] + list.map(\.path), as: TransferResult.self)
                lastResult = r.failed.isEmpty
                    ? "Copied \(r.done.count) item\(r.done.count == 1 ? "" : "s") to \(dest.lastPathComponent)"
                    : "Copied \(r.done.count). \(r.failed.count) failed."
                if !r.failed.isEmpty { alert = r.failed.map { "\($0.path): \($0.msg)" }.joined(separator: "\n") }
                if openAfter {
                    for item in list where !item.dir && r.failed.allSatisfy({ $0.path != item.path }) {
                        NSWorkspace.shared.open(dest.appendingPathComponent(item.name))
                    }
                }
            } catch { alert = error.localizedDescription }
            transfer = nil
        }
    }

    func send(_ urls: [URL]) {
        guard let dev = current, !urls.isEmpty, transfer == nil else { return }
        let dest = path
        transfer = "Sending \(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items") to the phone…"
        Task {
            let scoped = urls.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { scoped.forEach { if $0.1 { $0.0.stopAccessingSecurityScopedResource() } } }
            do {
                let r = try await Engine.call(["push", dev.serial, dest] + urls.map(\.path), as: TransferResult.self)
                lastResult = r.failed.isEmpty
                    ? "Sent \(r.done.count) item\(r.done.count == 1 ? "" : "s") to \((dest as NSString).lastPathComponent)"
                    : "Sent \(r.done.count). \(r.failed.count) failed."
                if !r.failed.isEmpty { alert = r.failed.map { "\($0.path): \($0.msg)" }.joined(separator: "\n") }
            } catch { alert = error.localizedDescription }
            transfer = nil
            if path == dest { await load() }
        }
    }

    func revealSaveFolder() {
        let url = Defaults.saveURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}
