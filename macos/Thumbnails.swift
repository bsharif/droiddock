// Photo thumbnails for the file list.
//
// A JPEG keeps a small preview in its first bytes, so we read only 64 KB of it.
// Other image types (PNG screenshots, HEIC, WebP, GIF) are read whole when small.
// Results are kept in memory and on disk (~/Library/Caches/DroidDock/thumbs).
import AppKit
import CryptoKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Lets only `n` tasks run at once.
actor Gate {
    private var free: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(_ n: Int) { free = n }
    func enter() async {
        if free > 0 { free -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func leave() {
        if waiters.isEmpty { free += 1 } else { waiters.removeFirst().resume() }
    }
}

final class ThumbCache: @unchecked Sendable {
    static let shared = ThumbCache()

    private static let jpeg: Set<String> = ["jpg", "jpeg"]
    private static let whole: Set<String> = ["png", "heic", "heif", "webp", "gif", "bmp", "tif", "tiff"]
    private static let maxWhole: UInt64 = 8_000_000
    private static let pixels = 96

    private let mem = NSCache<NSString, NSImage>()
    private let gate = Gate(4)
    private let dir: URL

    private init() {
        dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DroidDock/thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        mem.countLimit = 2000
    }

    static func canThumb(_ item: FileItem) -> Bool {
        guard !item.dir, item.size > 0 else { return false }
        if jpeg.contains(item.ext) { return true }
        return whole.contains(item.ext) && item.size <= maxWhole
    }

    private func key(_ item: FileItem) -> String {
        let raw = "\(item.path)|\(item.size)|\(item.mtime)"
        return SHA256.hash(data: Data(raw.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Memory only, so it is quick enough to call while drawing a row.
    func cached(_ item: FileItem) -> NSImage? { mem.object(forKey: key(item) as NSString) }

    func thumbnail(for item: FileItem, serial: String) async -> NSImage? {
        let k = key(item)
        if let img = mem.object(forKey: k as NSString) { return img }
        let file = dir.appendingPathComponent(k + ".png")
        if let img = NSImage(contentsOf: file) {
            mem.setObject(img, forKey: k as NSString)
            return img
        }
        await gate.enter()
        if Task.isCancelled { await gate.leave(); return nil } // row scrolled away
        let cg = await make(item, serial: serial)
        await gate.leave()
        guard let cg else { return nil }
        save(cg, to: file)
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        mem.setObject(img, forKey: k as NSString)
        return img
    }

    private func make(_ item: FileItem, serial: String) async -> CGImage? {
        if Self.jpeg.contains(item.ext) {
            if let data = await fetch(serial, item.path, bytes: 65_536),
               let cg = Self.thumb(data, decodeIfNoPreview: false) {
                return cg
            }
            // No built-in preview: decode the whole photo if it is not too large.
            guard item.size <= Self.maxWhole else { return nil }
        }
        guard let data = await fetch(serial, item.path, bytes: 0) else { return nil }
        return Self.thumb(data, decodeIfNoPreview: true)
    }

    private func fetch(_ serial: String, _ path: String, bytes: Int) async -> Data? {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pt-thumb-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard (try? await Engine.call(["head", serial, path, String(bytes), tmp.path], as: OK.self)) != nil else { return nil }
        return try? Data(contentsOf: tmp)
    }

    private static func thumb(_ data: Data, decodeIfNoPreview: Bool) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: decodeIfNoPreview,
            kCGImageSourceCreateThumbnailWithTransform: true, // respect photo rotation
            kCGImageSourceThumbnailMaxPixelSize: pixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    private func save(_ cg: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
    }
}

/// The icon in the Name column: a photo preview when there is one, else the Finder icon.
struct FileIcon: View {
    let item: FileItem
    let serial: String?
    @AppStorage("showThumbnails") private var showThumbnails = true
    @State private var thumb: NSImage?

    private var size: CGFloat { showThumbnails ? 32 : 16 }

    var body: some View {
        Group {
            if showThumbnails, let thumb {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))
            } else {
                Image(nsImage: Icons.icon(for: item))
                    .resizable()
                    .frame(width: size, height: size)
            }
        }
        // Runs only while the row is on screen; SwiftUI cancels it when the row scrolls away.
        .task(id: "\(item.id)|\(serial ?? "")|\(showThumbnails)") {
            thumb = ThumbCache.shared.cached(item)
            guard showThumbnails, thumb == nil, let serial, ThumbCache.canThumb(item) else { return }
            thumb = await ThumbCache.shared.thumbnail(for: item, serial: serial)
        }
    }
}
