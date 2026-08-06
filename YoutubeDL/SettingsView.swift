//
//  SettingsView.swift
//  YoutubeDL
//

import SwiftUI
import YoutubeDL

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel

    @Binding var isIdleTimerDisabled: Bool

    @State private var version: String?
    @State private var isLoadingVersion = false
    @State private var isUpdating = false
    @State private var updateRequest = 0
    @State private var isShowingYouTubeSignIn = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var isShowingAlert = false

    var body: some View {
        List {
            Toggle("Keep Screen On", isOn: $isIdleTimerDisabled)

            Section("yt-dlp") {
                HStack {
                    Text("Version")

                    Spacer()

                    if isLoadingVersion {
                        ProgressView()
                    } else if let version {
                        Text(version)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(app.downloadState.isBusy ? "Available after the download" : "Unavailable")
                            .foregroundStyle(.secondary)
                    }
                }

                Button(action: requestUpdate) {
                    if isUpdating {
                        HStack {
                            ProgressView()
                            Text("Updating...")
                        }
                    } else {
                        Text("Update to Latest Version")
                    }
                }
                .disabled(isLoadingVersion || isUpdating || app.downloadState.isBusy)
            }

            Section("YouTube Authentication") {
                Button {
                    isShowingYouTubeSignIn = true
                } label: {
                    Label("Sign In and Save YouTube Cookies", systemImage: "person.crop.circle.badge.checkmark")
                }

                if app.hasYouTubeCookies {
                    Button {
                        removeCookies()
                    } label: {
                        Label("Remove YouTube Cookies", systemImage: "trash.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .task(id: app.downloadState.isBusy) {
            await loadVersion()
        }
        .task(id: updateRequest) {
            guard updateRequest > 0 else {
                return
            }
            await updateYtDlp()
        }
        .sheet(isPresented: $isShowingYouTubeSignIn) {
            NavigationView {
                YouTubeAuthenticationView()
            }
            .environmentObject(app)
        }
        .alert(alertTitle, isPresented: $isShowingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func requestUpdate() {
        updateRequest += 1
    }

    /// Reading the version loads the Python module, and the interpreter cannot be
    /// used from two threads at once, so reuse the loaded version and wait for the
    /// download to finish before loading it.
    private func loadVersion() async {
        if let loadedVersion = app.youtubeDL.version {
            version = loadedVersion
            return
        }
        guard !app.downloadState.isBusy else {
            return
        }

        isLoadingVersion = true
        defer {
            isLoadingVersion = false
        }

        do {
            version = try await app.youtubeDL.loadVersion()
        } catch is CancellationError {
            return
        } catch {
            version = nil
        }
    }

    private func updateYtDlp() async {
        isUpdating = true
        defer {
            isUpdating = false
        }

        do {
            try await YoutubeDL.downloadPythonModule()
            alertTitle = "yt-dlp"
            alertMessage = String(
                localized: "yt-dlp was updated. Restart the app to use the latest version."
            )
            isShowingAlert = true
        } catch is CancellationError {
            return
        } catch {
            alertTitle = "yt-dlp"
            alertMessage = String(
                format: String(localized: "Could not update yt-dlp: %@"),
                error.localizedDescription
            )
            isShowingAlert = true
        }
    }

    private func removeCookies() {
        do {
            try app.removeYouTubeCookies()
        } catch {
            alertTitle = "Cookie operation failed"
            alertMessage = error.localizedDescription
            isShowingAlert = true
        }
    }
}
