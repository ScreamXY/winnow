import UIKit
import WebKit

// New windows, camera and microphone requests, JavaScript dialogs, and messages from the page script.

extension BrowserController: WKUIDelegate {
    /// Links that open a new window (target=_blank, window.open).
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else {
            return nil
        }
        switch RoutePolicy.decide(url, settings: settings, userTappedLink: true) {
        case .allow:
            load(url)
        case .redirect(let target):
            redirect(to: target)
        case .openExternally(let target):
            openOutside(target)
        case .block:
            break
        }
        return nil
    }

    func webView(
        _ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
        initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType
    ) async -> WKPermissionDecision {
        .prompt
    }

    func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in continuation.resume() })
            showDialog(alert)
        }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(
                UIAlertAction(title: "Cancel", style: .cancel) { _ in continuation.resume(returning: false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in continuation.resume(returning: true) })
            showDialog(alert)
        }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
        initiatedByFrame frame: WKFrameInfo
    ) async -> String? {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in continuation.resume(returning: nil) })
            alert.addAction(
                UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
                    continuation.resume(returning: alert?.textFields?.first?.text ?? "")
                })
            showDialog(alert)
        }
    }
}

// MARK: - Messages from the page script

extension BrowserController {
    func received(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else {
            return
        }
        if type == "layoutChanged" {
            refreshLayout()
        }
        log.debug("Page script: \(type, privacy: .public) \(String(describing: message["route"]), privacy: .public)")
    }
}

/// WKUserContentController keeps a strong reference to its handlers. This proxy avoids a retain cycle.
final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var owner: BrowserController?

    init(owner: BrowserController) {
        self.owner = owner
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            owner?.received(message.body)
        }
    }
}
