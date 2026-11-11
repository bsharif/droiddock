// Sheet to choose, connect, pair, and disconnect phones.
import SwiftUI

struct PhonesSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var addr = ""
    @State private var pairAddr = ""
    @State private var pairCode = ""
    @FocusState private var codeFocused: Bool
    @State private var confirmUnencrypted: Device?

    private var connectedNames: String { model.devices.map(\.serial).joined(separator: " ") }
    private var wifiFound: [Service] {
        model.services.filter { s in
            s.kind == "pair" || !(model.devices.contains { $0.serial == s.addr } || connectedNames.contains(s.name))
        }
    }
    private var recentShown: [String] { model.recent.filter { a in !model.devices.contains { $0.serial == a } } }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if model.devices.isEmpty {
                        Text("No phone connected yet.").foregroundStyle(.secondary)
                    }
                    ForEach(model.devices) { d in deviceRow(d) }
                } header: {
                    Text("Connected")
                } footer: {
                    Text("Connect with a USB cable, or over Wi-Fi when the Mac and the phone use the same network. A phone hotspot works with no internet.")
                }

                Section {
                    if model.searchingWiFi && model.services.isEmpty {
                        HStack { ProgressView().controlSize(.small); Text("Searching…").foregroundStyle(.secondary) }
                    } else if wifiFound.isEmpty {
                        Text("No phone found.").foregroundStyle(.secondary)
                    }
                    ForEach(wifiFound) { s in
                        HStack {
                            Image(systemName: s.kind == "pair" ? "lock.open" : "wifi").frame(width: 20)
                            VStack(alignment: .leading) {
                                Text(s.kind == "pair" ? "Phone ready to pair" : s.shortName)
                                Text(s.addr).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if s.kind == "pair" {
                                Button("Pair…") { pairAddr = s.addr; codeFocused = true }
                            } else {
                                Button("Connect") { model.connect(s.addr) }
                            }
                        }
                    }
                } header: {
                    Text("Found on This Wi-Fi")
                } footer: {
                    Text("Recommended for Wi-Fi: Wireless debugging is encrypted. On the phone: Settings › System › Developer options › Wireless debugging. Turn it on, and pair one time below. The phone then shows here.")
                }

                if !recentShown.isEmpty {
                    Section("Recent") {
                        ForEach(recentShown, id: \.self) { a in
                            HStack {
                                Image(systemName: "clock").frame(width: 20)
                                Text(a)
                                Spacer()
                                Button("Forget") { model.forget(a) }
                                Button("Connect") { model.connect(a) }
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        TextField("Address", text: $addr, prompt: Text("192.168.1.20:5555"))
                            .labelsHidden()
                            .onSubmit { model.connect(addr) }
                        Button("Connect") { model.connect(addr) }.disabled(addr.isEmpty)
                    }
                } header: {
                    Text("Connect by Address")
                } footer: {
                    Text("Use the IP address and port from the Wireless debugging screen.")
                }

                Section {
                    HStack {
                        TextField("Pairing address", text: $pairAddr, prompt: Text("192.168.1.20:37011"))
                            .labelsHidden()
                        TextField("Code", text: $pairCode, prompt: Text("Code"))
                            .labelsHidden()
                            .frame(width: 90)
                            .focused($codeFocused)
                            .onSubmit { model.pair(pairAddr, pairCode); pairCode = "" }
                        Button("Pair") { model.pair(pairAddr, pairCode); pairCode = "" }
                            .disabled(pairAddr.isEmpty || pairCode.isEmpty)
                    }
                } header: {
                    Text("Pair a New Phone")
                } footer: {
                    Text("On the phone: Wireless debugging › Pair device with pairing code. You pair one time only.")
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let b = model.phoneBusy, !b.isEmpty {
                    ProgressView().controlSize(.small)
                    Text(b).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.refreshDevices(); await model.searchWiFi() }
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.current == nil && !model.readyDevices.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 560, height: 620)
        .task { await model.refreshDevices(); await model.searchWiFi() }
        .confirmationDialog(
            "Use unencrypted Wi-Fi?",
            isPresented: Binding(get: { confirmUnencrypted != nil }, set: { if !$0 { confirmUnencrypted = nil } }),
            presenting: confirmUnencrypted
        ) { d in
            Button("Use Unencrypted Wi-Fi") { model.switchToWiFi(d) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This uses classic adb on port 5555. It does not encrypt your files. Another device on the same network can capture them. Use it only on a network you own, such as your phone's hotspot. For other networks, use the cable or Wireless debugging. Port 5555 stays open until you click Turn Off or restart the phone.")
        }
    }

    @ViewBuilder private func deviceRow(_ d: Device) -> some View {
        let inUse = d.ready && d.serial == model.selectedSerial
        HStack {
            Image(systemName: d.symbol).frame(width: 20).foregroundStyle(d.ready ? .primary : .secondary)
            VStack(alignment: .leading) {
                HStack(spacing: 6) {
                    Text(d.model)
                    Text(d.link)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .foregroundStyle(d.secure ? Color.primary : Color.orange)
                        .background(d.secure ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.orange.opacity(0.18)), in: Capsule())
                }
                Text(d.stateText).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if d.ready && !d.wifi {
                Menu("Wi-Fi") {
                    Button("Use Unencrypted Wi-Fi (Port 5555)…") { confirmUnencrypted = d }
                } primaryAction: { confirmUnencrypted = d }
                    .fixedSize()
                    .help("Classic adb over Wi-Fi on port 5555. Not encrypted. For encrypted Wi-Fi, use Wireless debugging.")
            }
            if d.wifi && !d.secure {
                Button("Turn Off") { model.wifiOff(d) }
                    .help("Close port 5555 on the phone. adb goes back to USB only.")
            } else if d.wifi {
                Button("Disconnect") { model.disconnect(d) }
            }
            if inUse {
                Label("In Use", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon).foregroundStyle(.green)
            } else if d.ready {
                Button("Use") { model.use(d) }.buttonStyle(.borderedProminent)
            }
        }
    }
}
