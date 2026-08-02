//
//  DownloadView.swift
//  YoutubeDL
//

import SwiftUI

struct DownloadView: View {
    @EnvironmentObject private var app: AppModel

    @State private var urlString = ""
    @FocusState private var isURLFieldFocused: Bool

    @State private var alertMessage: String?
    @State private var isShowingAlert = false

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Enter URL", text: $urlString)
                        .focused($isURLFieldFocused)
                        .onSubmit(submitURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .disabled(app.downloadState.isBusy)

                    if !urlString.isEmpty && !app.downloadState.isBusy {
                        Button("Clear URL", systemImage: "xmark.circle.fill", action: clearURL)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }

                    Button("Paste URL", systemImage: "doc.on.clipboard", action: pasteURL)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(app.downloadState.isBusy)
                }

                Button("Download", action: submitURL)
                    .disabled(downloadURL == nil || app.downloadState.isBusy)
            }

            if app.downloadState != .idle {
                Section {
                    DownloadStatusView(
                        state: app.downloadState,
                        progress: app.downloadProgress
                    )
                }
            }
        }
        .onChange(of: app.url) { newValue in
            guard let url = newValue else { return }
            urlString = url.absoluteString
        }
        .alert(isPresented: $isShowingAlert) {
            Alert(title: Text(alertMessage ?? "no message?"))
        }
    }

    private var downloadURL: URL? {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    private func pasteURL() {
        let pasteBoard = UIPasteboard.general
        guard let url = pasteBoard.url ?? pasteBoard.string.flatMap(URL.init(string:)) else {
            alert(message: "Nothing to paste")
            return
        }
        urlString = url.absoluteString
    }

    private func clearURL() {
        urlString = ""
        isURLFieldFocused = true
    }

    private func submitURL() {
        isURLFieldFocused = false

        guard let url = downloadURL else {
            alert(message: "Invalid URL")
            return
        }
        app.url = url
    }

    private func alert(message: String) {
        alertMessage = message
        isShowingAlert = true
    }
}

private struct DownloadStatusView: View {
    var state: DownloadState
    var progress: DownloadProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayTitle)
                .font(.headline)
                .lineLimit(2)

            if state.isBusy {
                if let fractionCompleted = progress.fractionCompleted {
                    HStack {
                        ProgressView(value: fractionCompleted)

                        Text(fractionCompleted, format: .percent.precision(.fractionLength(0)))
                            .font(.footnote)
                            .monospacedDigit()
                    }
                } else {
                    ProgressView()
                }

                if let progressDescription {
                    Text(progressDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                switch state {
                case .completed(let url):
                    Text(url.lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                case .failed(let message):
                    Text(message)
                        .foregroundStyle(.secondary)
                default:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayTitle: String {
        if case .downloading = state,
           let fileName = progress.fileName {
            return String(
                format: String(localized: "Downloading %@"),
                fileName
            )
        }
        return title
    }

    private var title: String {
        switch state {
        case .idle:
            return String(localized: "Ready")
        case .extracting:
            return String(localized: "Extracting information…")
        case .downloading:
            return String(localized: "Downloading…")
        case .transcoding:
            return String(localized: "Transcoding…")
        case .completed:
            return String(localized: "Download complete")
        case .failed:
            return String(localized: "Download failed")
        }
    }

    private var progressDescription: String? {
        var parts: [String] = []

        if case .downloading = state,
           let completedUnitCount = progress.completedUnitCount,
           let totalUnitCount = progress.totalUnitCount,
           completedUnitCount >= 0,
           totalUnitCount > 0 {
            let completed = ByteCountFormatter.string(fromByteCount: completedUnitCount, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: totalUnitCount, countStyle: .file)
            parts.append(String(format: String(localized: "%@ of %@"), completed, total))
        }

        if case .downloading = state,
           let throughput = progress.throughput,
           throughput > 0 {
            let speed = ByteCountFormatter.string(fromByteCount: Int64(throughput), countStyle: .file)
            parts.append(String(format: String(localized: "%@/s"), speed))
        }

        if let estimatedTimeRemaining = progress.estimatedTimeRemaining,
           estimatedTimeRemaining.isFinite,
           estimatedTimeRemaining >= 0,
           let duration = durationFormatter.string(from: estimatedTimeRemaining) {
            parts.append(String(format: String(localized: "%@ remaining"), duration))
        }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private var durationFormatter: DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }
}
