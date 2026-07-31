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
    @State private var isLoadingVersion = true
    @State private var isUpdating = false
    @State private var updateRequest = 0
    @State private var alertMessage = ""
    @State private var isShowingAlert = false

    var body: some View {
        List {
            Toggle("Keep screen turned on", isOn: $isIdleTimerDisabled)

            Section("yt-dlp") {
                HStack {
                    Text("Version")

                    Spacer()

                    if isLoadingVersion {
                        ProgressView()
                    } else {
                        Text(version ?? "Unavailable")
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
                .disabled(isLoadingVersion || isUpdating)
            }
        }
        .task {
            await loadVersion()
        }
        .task(id: updateRequest) {
            guard updateRequest > 0 else {
                return
            }
            await updateYtDlp()
        }
        .alert("yt-dlp", isPresented: $isShowingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func requestUpdate() {
        updateRequest += 1
    }

    private func loadVersion() async {
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
            alertMessage = String(
                localized: "yt-dlp was updated. Restart the app to use the latest version."
            )
            isShowingAlert = true
        } catch is CancellationError {
            return
        } catch {
            alertMessage = String(
                format: String(localized: "Could not update yt-dlp: %@"),
                error.localizedDescription
            )
            isShowingAlert = true
        }
    }
}
