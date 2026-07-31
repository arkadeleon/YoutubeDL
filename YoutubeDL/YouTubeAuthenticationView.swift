//
//  YouTubeAuthenticationView.swift
//  YoutubeDL
//

import SwiftUI
import WebKit

struct YouTubeAuthenticationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppModel

    @StateObject private var session = Session()

    @State private var isSaving = false
    @State private var isShowingError = false
    @State private var errorMessage = ""

    var body: some View {
        WebView(webView: session.webView)
            .navigationTitle("YouTube Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Cookies") {
                        saveCookies()
                    }
                    .disabled(isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("Saving cookies…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("Unable to save cookies", isPresented: $isShowingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
    }

    private func saveCookies() {
        Task {
            isSaving = true
            defer {
                isSaving = false
            }

            let cookies = await session.cookies()
            do {
                try app.saveYouTubeCookies(cookies)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isShowingError = true
            }
        }
    }
}

private extension YouTubeAuthenticationView {
    @MainActor
    final class Session: ObservableObject {
        let webView: WKWebView

        init() {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            webView = WKWebView(frame: .zero, configuration: configuration)
            webView.load(URLRequest(url: URL(string: "https://www.youtube.com/account")!))
        }

        func cookies() async -> [HTTPCookie] {
            await withCheckedContinuation { continuation in
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    continuation.resume(returning: cookies)
                }
            }
        }
    }

    struct WebView: UIViewRepresentable {
        let webView: WKWebView

        func makeUIView(context: Context) -> WKWebView {
            webView
        }

        func updateUIView(_ webView: WKWebView, context: Context) {
        }
    }
}
