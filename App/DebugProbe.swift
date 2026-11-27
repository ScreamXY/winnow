#if DEBUG
    import UIKit
    import WebKit

    /// Debug builds only. Lets a developer check the filters against the real site from a Mac,
    /// with Apple's `devicectl` and no other tools:
    ///
    /// 1. Copy a script to the app's `Documents/probe/request.js`
    ///    (`xcrun devicectl device copy to --domain-type appDataContainer
    ///    --domain-identifier com.screamxy.winnow …`). The script runs in Winnow's script world as
    ///    the body of an async function, so it can `return` a value.
    ///    `request-strip.js` runs in the stories strip instead.
    /// 2. Copy back `Documents/probe/response.json`. It holds the value (or the error) and the
    ///    native scroll state, including the last flick mode decisions.
    ///
    /// An empty file `Documents/probe/snapshot.request` asks for `Documents/probe/snapshot.png`.
    /// The app must be open on the device. Scripts should return structure, not people's content.
    @MainActor
    final class DebugProbe {
        private weak var webView: WKWebView?
        private weak var strip: WKWebView?
        private let nativeState: () -> [String: Any]
        private let folder = URL.documentsDirectory.appending(path: "probe", directoryHint: .isDirectory)
        private var timer: Timer?

        init(webView: WKWebView, strip: WKWebView?, nativeState: @escaping () -> [String: Any]) {
            self.webView = webView
            self.strip = strip
            self.nativeState = nativeState
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.poll()
                }
            }
        }

        isolated deinit {
            timer?.invalidate()
        }

        private func poll() {
            var isFolder: ObjCBool = false
            if !FileManager.default.fileExists(atPath: folder.path(), isDirectory: &isFolder) || !isFolder.boolValue {
                try? FileManager.default.removeItem(at: folder)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            let request = folder.appending(path: "request.js")
            if let script = try? String(contentsOf: request, encoding: .utf8) {
                try? FileManager.default.removeItem(at: request)
                run(script, in: webView)
            }
            let stripRequest = folder.appending(path: "request-strip.js")
            if let script = try? String(contentsOf: stripRequest, encoding: .utf8) {
                try? FileManager.default.removeItem(at: stripRequest)
                run(script, in: strip)
            }
            let snapshot = folder.appending(path: "snapshot.request")
            if FileManager.default.fileExists(atPath: snapshot.path()) {
                try? FileManager.default.removeItem(at: snapshot)
                takeSnapshot()
            }
        }

        private func run(_ script: String, in target: WKWebView?) {
            target?.callAsyncJavaScript(script, arguments: [:], in: nil, in: .defaultClient) { [weak self] result in
                guard let self else {
                    return
                }
                var payload = nativeState()
                payload["time"] = Date.now.formatted(.iso8601)
                switch result {
                case .success(let value):
                    payload["value"] = Self.jsonSafe(value)
                case .failure(let error):
                    payload["error"] = String(describing: error)
                }
                write(payload)
            }
        }

        private func takeSnapshot() {
            webView?.takeSnapshot(with: nil) { [folder] image, _ in
                if let data = image?.pngData() {
                    try? data.write(to: folder.appending(path: "snapshot.png"))
                }
            }
        }

        private func write(_ payload: [String: Any]) {
            let safe = Self.jsonSafe(payload)
            guard JSONSerialization.isValidJSONObject(safe),
                let data = try? JSONSerialization.data(withJSONObject: safe, options: [.prettyPrinted, .sortedKeys])
            else {
                return
            }
            try? data.write(to: folder.appending(path: "response.json"))
        }

        private static func jsonSafe(_ value: Any?) -> Any {
            switch value {
            case nil:
                return NSNull()
            case let dictionary as [String: Any]:
                return dictionary.mapValues { jsonSafe($0) }
            case let array as [Any]:
                return array.map { jsonSafe($0) }
            case let text as String:
                return text
            case let number as NSNumber:
                return number
            case let number as Double:
                return number
            case let number as Int:
                return number
            case let flag as Bool:
                return flag
            default:
                return String(describing: value)
            }
        }
    }
#endif
