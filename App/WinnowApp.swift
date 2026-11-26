import SwiftUI
import WebKit

@main
struct WinnowApp: App {
    var body: some Scene {
        WindowGroup {
            BrowserScreen()
        }
    }
}

/// One window with Instagram. Each window has its own web view; the login is shared.
struct BrowserScreen: View {
    @State private var browser = BrowserController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color(uiColor: browser.pageBackground).ignoresSafeArea()
            // Instagram's web page does not leave room for the status bar (Safari does that), so
            // the page starts below it. At the bottom, Instagram already adds room for the home bar.
            WebViewHost(webView: browser.webView)
                .ignoresSafeArea(edges: .bottom)
            if browser.isLoadingFirstPage {
                ProgressView()
                    .controlSize(.large)
            }
            if let message = browser.loadError {
                LoadErrorView(message: message, retry: browser.retry)
            }
        }
        .onAppear { browser.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                browser.appBecameActive()
            }
        }
    }
}

private struct LoadErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Instagram did not load", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .background(Color(uiColor: .systemBackground))
    }
}

private struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
