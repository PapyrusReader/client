import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var folderAccess: PapyrusFolderAccess?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PapyrusFolders") {
      folderAccess = PapyrusFolderAccess(messenger: registrar.messenger(), presenter: window?.rootViewController)
    }
  }
}

// Read-only access to user-selected directories. Bookmarks never leave this device.
private final class PapyrusFolderAccess: NSObject {
    private let queue = DispatchQueue(label: "papyrus.folder-access")
    private let defaults = UserDefaults.standard
    private var cursors: [String: FolderCursor] = [:]
    private var pickerResult: FlutterResult?
    private weak var presenter: UIViewController?

    init(messenger: FlutterBinaryMessenger, presenter: UIViewController?) {
        super.init()
        self.presenter = presenter
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
        let url = try URL(resolvingBookmarkData: data, options: [.withoutUI], bookmarkDataIsStale: &stale)
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
            let data = try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
            let key = UUID().uuidString
            defaults.set(data, forKey: bookmarkKey(key))
            result(["key": key, "identity": url.standardizedFileURL.path, "name": url.lastPathComponent,
                "location": url.path, "persistent": true])
        } catch {
            result(FlutterError(code: "access", message: "Could not save access to this folder.", details: nil))
        }
    }

    private func pick(_ result: @escaping FlutterResult) {
        let activePresenter = presenter ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController
        guard pickerResult == nil, let presenter = activePresenter else {
            result(FlutterError(code: "busy", message: "A folder picker is already open.", details: nil)); return
        }
        pickerResult = result
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = self
        presenter.present(picker, animated: true)
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

extension PapyrusFolderAccess: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let result = pickerResult else { return }
        pickerResult = nil
        selected(urls.first, result: result)
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pickerResult?(nil)
        pickerResult = nil
    }
}
