import Foundation
import UIKit
import os

/// Every strap event, kept on the phone so a real sync can be debugged after
/// the fact. Each line goes to a file the Log tab shares, and to the unified
/// log (Console.app, subsystem `aloft`, category `strap`) while a cable is in.
///
/// Raw packets carry heart rate, so their bytes go to the file only. The file
/// leaves the phone only when the user shares it. Never commit one.
@MainActor
final class StrapTrace {
    static let fileName = "strap-trace.log"
    private static let maxBytes = 4 << 20

    let url: URL
    private let logger = Logger(subsystem: "aloft", category: "strap")
    private let timestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private var handle: FileHandle?
    private var size = 0

    init(directory: URL) {
        url = directory.appending(path: Self.fileName)
        open()
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))"
        write("session start · Aloft \(version) · \(Self.deviceModel) · iOS \(UIDevice.current.systemVersion)")
    }

    /// The current file and the one rotated out before it, oldest first.
    var files: [URL] {
        [rotatedURL, url].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Appends one line. `bytes` are written to the file as hex and kept out
    /// of the unified log.
    func write(_ message: String, bytes: [UInt8]? = nil) {
        logger.log("\(message, privacy: .public)\(bytes.map { " [\($0.count) bytes]" } ?? "", privacy: .public)")
        var line = "\(Date.now.formatted(timestamp)) \(message)"
        if let bytes { line += " \(bytes.count)B \(bytes.map { String(format: "%02x", $0) }.joined())" }
        append(Data((line + "\n").utf8))
    }

    private var rotatedURL: URL { url.deletingPathExtension().appendingPathExtension("1.log") }

    private func open() {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) {
            // Bluetooth keeps working with the phone locked, so the file must too.
            fm.createFile(atPath: url.path, contents: nil, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        handle = try? FileHandle(forWritingTo: url)
        size = Int((try? handle?.seekToEnd()) ?? 0)
    }

    private func append(_ data: Data) {
        if size + data.count > Self.maxBytes { rotate() }
        guard let handle else { return }
        do {
            try handle.write(contentsOf: data)
            size += data.count
        } catch {
            logger.error("trace write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        let fm = FileManager.default
        try? fm.removeItem(at: rotatedURL)
        try? fm.moveItem(at: url, to: rotatedURL)
        open()
    }

    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
