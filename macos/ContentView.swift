// The main window: sidebar of phone places, Finder-style file table, toolbar, status bar.
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    private var sidebarSelection: Binding<String?> {
        Binding(
            get: { Place.all.contains { $0.path == model.path } ? model.path : nil },
            set: { if let p = $0 { model.go(p) } }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section("Phone") {
                    ForEach(Place.all) { place in
                        Label(place.title, systemImage: place.symbol).tag(place.path)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 280)
        } detail: {
            FileTable()
                .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar() }
        }
        .navigationTitle(model.folderName)
        .navigationSubtitle(model.current.map { "\($0.model) · \($0.link)" } ?? "No phone")
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search this folder")
        .toolbar { Toolbar() }
        .sheet(isPresented: $model.showPhones) { PhonesSheet().environmentObject(model) }
        .fileImporter(isPresented: $model.showImporter, allowedContentTypes: [.item, .folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.send(urls) }
        }
        .alert("DroidDock", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.alert ?? "") }
        .onAppear { model.start() }
        .frame(minWidth: 760, minHeight: 440)
    }
}

struct Toolbar: ToolbarContent {
    @EnvironmentObject var model: AppModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            ControlGroup {
                Button { model.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                    .disabled(!model.canGoBack)
                Button { model.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                    .disabled(!model.canGoForward)
            }
            .controlGroupStyle(.navigation)
        }
        ToolbarItem {
            Menu {
                ForEach(model.readyDevices) { d in
                    Button { model.use(d) } label: {
                        if d.serial == model.selectedSerial {
                            Label("\(d.model) (\(d.link))", systemImage: "checkmark")
                        } else {
                            Text("\(d.model) (\(d.link))")
                        }
                    }
                }
                if !model.readyDevices.isEmpty { Divider() }
                Button("Phones…") { model.showPhones = true }
            } label: {
                Label(model.current?.model ?? "Choose Phone", systemImage: model.current?.symbol ?? "iphone.slash")
                    .labelStyle(.titleAndIcon)
            }
            .help("Choose the phone")
        }
        ToolbarItemGroup {
            Button { Task { await model.load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .help("Refresh this folder")
            Button { model.showImporter = true } label: { Label("Send to Phone", systemImage: "square.and.arrow.up") }
                .help("Send files from the Mac to this phone folder")
                .disabled(model.current == nil || model.transfer != nil)
            Button { model.copyToMac() } label: { Label("Copy to Mac", systemImage: "square.and.arrow.down") }
                .help("Copy the selected items to the Mac")
                .disabled(model.selection.isEmpty || model.transfer != nil)
        }
    }
}

struct FileTable: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Table(model.visibleItems, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Name", value: \.name) { item in
                HStack(spacing: 8) {
                    FileIcon(item: item, serial: model.current?.serial)
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                }
            }
            .width(min: 200, ideal: 340)
            TableColumn("Date Modified", value: \.mtime) { item in
                Text(item.date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                    .foregroundStyle(.secondary)
            }
            .width(min: 130, ideal: 170)
            TableColumn("Size", value: \.size) { item in
                Text(item.dir ? "--" : ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))
                    .foregroundStyle(.secondary).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 80)
            TableColumn("Kind", value: \.kind) { item in
                Text(item.kind).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 80, ideal: 120)
        }
        .contextMenu(forSelectionType: FileItem.ID.self) { ids in
            let chosen = model.items.filter { ids.contains($0.id) }
            if chosen.count == 1, let one = chosen.first, one.dir {
                Button("Open") { model.go(one.path) }
                Divider()
            }
            Button("Copy to Mac") { model.copyToMac(chosen) }.disabled(chosen.isEmpty)
            if chosen.contains(where: { !$0.dir }) {
                Button("Copy to Mac and Open") { model.copyToMac(chosen, openAfter: true) }
            }
        } primaryAction: { ids in
            model.open(ids)
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.send(urls)
            return true
        } isTargeted: { model.dropTargeted = $0 }
        .overlay { overlay }
        .overlay {
            if model.dropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.08))
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder private var overlay: some View {
        if model.current == nil {
            ContentUnavailableView {
                Label("No Phone", systemImage: "iphone.slash")
            } description: {
                Text("Connect your phone with a USB cable, or connect over Wi-Fi.")
            } actions: {
                Button("Choose Phone…") { model.showPhones = true }
            }
        } else if let e = model.loadError {
            ContentUnavailableView("Cannot Open Folder", systemImage: "exclamationmark.triangle", description: Text(e))
        } else if model.loading && model.items.isEmpty {
            ProgressView("Loading…")
        } else if model.visibleItems.isEmpty {
            if model.search.isEmpty {
                ContentUnavailableView("Empty Folder", systemImage: "folder",
                                       description: Text("Drag files here to send them to the phone."))
            } else {
                ContentUnavailableView.search(text: model.search)
            }
        }
    }
}

struct StatusBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            if let d = model.current, !d.secure {
                Label("Unencrypted Wi-Fi", systemImage: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                    .help("This connection uses classic adb on port 5555 and is not encrypted. Open the phone list to turn it off.")
                Divider().frame(height: 14)
            }
            if let t = model.transfer {
                ProgressView().controlSize(.small)
                Text(t).lineLimit(1)
            } else if let r = model.lastResult {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(r).lineLimit(1)
                Button("Show in Finder") { model.revealSaveFolder() }
                    .buttonStyle(.link)
            }
            Spacer()
            if model.loading && !model.items.isEmpty { ProgressView().controlSize(.small) }
            Text(countText).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var countText: String {
        let n = model.visibleItems.count
        let s = model.selection.count
        let items = "\(n) item\(n == 1 ? "" : "s")"
        return s > 0 ? "\(s) of \(items) selected" : items
    }
}
