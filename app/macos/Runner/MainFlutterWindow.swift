import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var folderAccess: PapyrusFolderAccess?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    folderAccess = PapyrusFolderAccess(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

// Read-only access to user-selected directories. Bookmarks never leave this device.
private final class PapyrusFolderAccess: NSObject {
    private let queue = DispatchQueue(label: "papyrus.folder-access")
    private let defaults = UserDefaults.standard
    private var cursors: [String: FolderCursor] = [:]
    private var watched: [String: URL] = [:]

    init(messenger: FlutterBinaryMessenger) {
        super.init()
        let channel = FlutterMethodChannel(name: "papyrus/folders", binaryMessenger: messenger)
        channel.setMethodCallHandler { [self] call, result in
            if call.method == "pick" {
                pick(result)
                return
            }
            let arguments = call.arguments as? [String: Any] ?? [:]
            queue.async { [self] in
                do {
                    let value = try perform(call.method, arguments)
                    DispatchQueue.main.async { result(value) }
                } catch {
                    let failure = error as NSError
                    let access = failure.domain == "PapyrusFolderAccess" || failure.code == NSFileReadNoPermissionError
                    DispatchQueue.main.async {
                        result(FlutterError(code: access ? "access" : "unavailable",
                            message: access ? "Reconnect this folder to allow access." : "Source file unavailable offline or folder disconnected. \(error.localizedDescription)", details: nil))
                    }
                }
            }
        }
    }

    private func bookmarkKey(_ key: String) -> String { "papyrus.folder-grant.\(key)" }

    private func resolve(_ key: String) throws -> URL {
        guard let data = defaults.data(forKey: bookmarkKey(key)) else {
            throw NSError(domain: "PapyrusFolderAccess", code: 1)
        }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)
        guard !stale else { throw NSError(domain: "PapyrusFolderAccess", code: 1) }
        return url
    }

    private func access<T>(_ key: String, _ operation: (URL) throws -> T) throws -> T {
        let url = try resolve(key)
        guard url.startAccessingSecurityScopedResource() else { throw NSError(domain: "PapyrusFolderAccess", code: 1) }
        defer { url.stopAccessingSecurityScopedResource() }
        return try operation(url)
    }

    private func source(_ root: URL, _ key: String) throws -> URL {
        let url = root.appendingPathComponent(key).standardizedFileURL
        let resolved = url.resolvingSymlinksInPath()
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard resolved.path.hasPrefix(directoryPrefix(root.resolvingSymlinksInPath())),
            values.isSymbolicLink != true, values.isRegularFile == true else {
            throw NSError(domain: "PapyrusFolderAccess", code: 1)
        }
        return url
    }

    private func directoryPrefix(_ root: URL) -> String {
        root.path.hasSuffix("/") ? root.path : root.path + "/"
    }

    private func metadata(_ url: URL, root: URL) throws -> [String: Any] {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return ["key": String(url.path.dropFirst(directoryPrefix(root).count)), "name": url.lastPathComponent,
            "size": values.fileSize ?? -1, "modified": Int64((values.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000)]
    }

    private func perform(_ method: String, _ arguments: [String: Any]) throws -> Any? {
        let key = arguments["grant"] as? String ?? ""
        switch method {
        case "watch":
            let root = try resolve(key)
            guard root.startAccessingSecurityScopedResource() else { throw NSError(domain: "PapyrusFolderAccess", code: 1) }
            watched.removeValue(forKey: key)?.stopAccessingSecurityScopedResource()
            watched[key] = root
            return root.path
        case "unwatch": watched.removeValue(forKey: key)?.stopAccessingSecurityScopedResource(); return nil
        case "restore": return try access(key) { FileManager.default.fileExists(atPath: $0.path) }
        case "start":
            let root = try resolve(key)
            guard root.startAccessingSecurityScopedResource() else { throw NSError(domain: "PapyrusFolderAccess", code: 1) }
            let failures = FolderFailures()
            let prefix = directoryPrefix(root)
            guard FileManager.default.fileExists(atPath: root.path),
                let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles], errorHandler: { url, error in
                        failures.entries.append(["key": String(url.path.dropFirst(prefix.count)),
                            "name": url.lastPathComponent, "size": 0, "modified": 0, "error": error.localizedDescription])
                        return true
                    }) else {
                root.stopAccessingSecurityScopedResource()
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
            }
            let cursor = UUID().uuidString
            cursors[cursor] = FolderCursor(root: root, enumerator: enumerator,
                recursive: arguments["recursive"] as? Bool ?? true, failures: failures)
            return cursor
        case "next":
            guard let cursor = cursors[arguments["cursor"] as? String ?? ""] else { return [] }
            var batch: [[String: Any]] = []
            while batch.count < 128, let url = cursor.enumerator.nextObject() as? URL {
                do {
                    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
                    let name = url.lastPathComponent
                    if name.hasPrefix(".") || name.hasPrefix("~") || values.isSymbolicLink == true ||
                        name.range(of: "\\.(tmp|part|partial|crdownload|download)$", options: [.regularExpression, .caseInsensitive]) != nil {
                        cursor.enumerator.skipDescendants()
                        continue
                    }
                    if values.isDirectory == true {
                        if !cursor.recursive { cursor.enumerator.skipDescendants() }
                    } else if values.isRegularFile == true {
                        batch.append(try metadata(url, root: cursor.root))
                    }
                } catch {
                    batch.append(["key": String(url.path.dropFirst(directoryPrefix(cursor.root).count)), "name": url.lastPathComponent,
                        "size": 0, "modified": 0, "error": error.localizedDescription])
                }
            }
            batch.append(contentsOf: cursor.failures.entries)
            cursor.failures.entries.removeAll()
            return batch
        case "close": cursors.removeValue(forKey: arguments["cursor"] as? String ?? "")?.close(); return nil
        case "stat": return try access(key) { root in try metadata(source(root, arguments["key"] as? String ?? ""), root: root) }
        case "read":
            return try access(key) { root in
                let url = try source(root, arguments["key"] as? String ?? "")
                var coordinationError: NSError?
                var readResult: Result<Data, Error>?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
                    readResult = Result { try Data(contentsOf: coordinated) }
                }
                if let error = coordinationError { throw error }
                guard let readResult = readResult else { throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError) }
                return FlutterStandardTypedData(bytes: try readResult.get())
            }
        case "release": defaults.removeObject(forKey: bookmarkKey(key)); return nil
        default: throw NSError(domain: "PapyrusFolderAccess", code: 2)
        }
    }

    private func selected(_ url: URL?, result: @escaping FlutterResult) {
        guard let url = url else { result(nil); return }
        do {
            guard url.startAccessingSecurityScopedResource() else { throw NSError(domain: "PapyrusFolderAccess", code: 1) }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            let key = UUID().uuidString
            defaults.set(data, forKey: bookmarkKey(key))
            result(["key": key, "identity": url.standardizedFileURL.path, "name": url.lastPathComponent,
                "location": url.path, "persistent": true])
        } catch {
            result(FlutterError(code: "access", message: "Could not save access to this folder.", details: nil))
        }
    }

    private func pick(_ result: @escaping FlutterResult) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose folder"
        panel.begin { [self] response in selected(response == .OK ? panel.url : nil, result: result) }
    }

    private final class FolderFailures {
        var entries: [[String: Any]] = []
    }

    private final class FolderCursor {
        let root: URL
        let enumerator: FileManager.DirectoryEnumerator
        let recursive: Bool
        let failures: FolderFailures
        private var closed = false
        init(root: URL, enumerator: FileManager.DirectoryEnumerator, recursive: Bool, failures: FolderFailures) {
            self.root = root; self.enumerator = enumerator; self.recursive = recursive
            self.failures = failures
        }
        func close() {
            if !closed { root.stopAccessingSecurityScopedResource(); closed = true }
        }
        deinit { close() }
    }
}
