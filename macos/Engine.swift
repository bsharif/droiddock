// Calls the Rust engine (droiddock-engine) and decodes its JSON.
import AppKit
import Foundation
import UniformTypeIdentifiers

struct Device: Identifiable, Hashable, Decodable {
    let serial: String
    let state: String
    let model: String
    let wifi: Bool
    /// false only for classic Wi-Fi adb (port 5555), which is not encrypted.
    let secure: Bool
    var id: String { serial }
    var ready: Bool { state == "device" }
    var link: String { wifi ? (secure ? "Wi-Fi" : "Wi-Fi, unencrypted") : "USB" }
    var symbol: String { wifi ? (secure ? "wifi" : "wifi.exclamationmark") : "cable.connector" }
    var stateText: String {
        switch state {
        case "device": return serial
        case "unauthorized": return "Unlock the phone and tap Allow"
        case "offline": return "Offline. Reconnect it."
        default: return state
        }
    }
}

struct DeviceList: Decodable {
    let devices: [Device]
    let recent: [String]
}

struct Service: Identifiable, Decodable, Hashable {
    let name: String
    let kind: String
    let addr: String
    var id: String { kind + addr }
    /// "adb-R5CX12345-a1b2c3" → "R5CX12345"
    var shortName: String {
        var n = name
        if n.hasPrefix("adb-") { n.removeFirst(4) }
        if let dash = n.lastIndex(of: "-") { n = String(n[..<dash]) }
        return n
    }
}

struct ServiceList: Decodable { let items: [Service] }

struct FileItem: Identifiable, Hashable, Decodable {
    let name: String
    let path: String
    let dir: Bool
    let size: UInt64
    let mtime: Int
    var id: String { path }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(mtime)) }
    var ext: String { (name as NSString).pathExtension.lowercased() }
    var kind: String {
        if dir { return "Folder" }
        return UTType(filenameExtension: ext)?.localizedDescription?.capitalizedFirst ?? "Document"
    }
}

struct FileList: Decodable { let items: [FileItem] }

struct TransferResult: Decodable {
    struct Entry: Decodable { let path: String; let msg: String }
    let done: [Entry]
    let failed: [Entry]
}

struct OK: Decodable {}

private struct EngineErrorBody: Decodable { let error: String }

struct EngineError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

enum Engine {
    static let url: URL = {
        if let p = ProcessInfo.processInfo.environment["DROIDDOCK_ENGINE"] { return URL(fileURLWithPath: p) }
        if let u = Bundle.main.url(forAuxiliaryExecutable: "droiddock-engine") { return u }
        return URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent().appendingPathComponent("droiddock-engine")
    }()

    /// Run one engine command off the main thread and decode the result.
    static func call<T: Decodable>(_ args: [String], as: T.Type = T.self) async throws -> T {
        try await Task.detached(priority: .userInitiated) {
            let p = Process()
            p.executableURL = url
            p.arguments = args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch {
                throw EngineError(message: "Could not start the engine: \(error.localizedDescription)")
            }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                let msg = (try? JSONDecoder().decode(EngineErrorBody.self, from: data))?.error
                throw EngineError(message: msg ?? "The engine stopped with code \(p.terminationStatus).")
            }
            do { return try JSONDecoder().decode(T.self, from: data) } catch {
                throw EngineError(message: "Unexpected reply from the engine.")
            }
        }.value
    }
}

/// Finder icons, cached by file extension.
@MainActor
enum Icons {
    private static var cache: [String: NSImage] = [:]
    static func icon(for item: FileItem) -> NSImage {
        let key = item.dir ? "/folder" : item.ext
        if let i = cache[key] { return i }
        let type: UTType = item.dir ? .folder : (UTType(filenameExtension: item.ext) ?? .data)
        let i = NSWorkspace.shared.icon(for: type)
        cache[key] = i
        return i
    }
}
