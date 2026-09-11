//
//  FormatSelectionView.swift
//  YoutubeDL
//

import SwiftUI
import YoutubeDL

struct FormatSelectionView: View {
    var request: FormatSelectionRequest
    var onCancel: () -> Void
    var onConfirm: (MediaFormat?, MediaFormat?) -> Void

    @State private var selectedVideoID: String?
    @State private var selectedAudioID: String?

    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.info.title)
                            .font(.headline)

                        if let durationText {
                            Text(durationText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !videoFormats.isEmpty {
                    Section("Video") {
                        ForEach(videoFormats) { format in
                            FormatRow(
                                title: videoTitle(of: format),
                                subtitle: videoSubtitle(of: format),
                                isSelected: format.id == selectedVideoID
                            ) {
                                selectedVideoID = format.id
                            }
                        }
                    }
                }

                Section {
                    if selectedVideo?.hasAudio == true {
                        Text("Included in the selected video format")
                            .foregroundStyle(.secondary)
                    } else if audioFormats.isEmpty {
                        Text("This video has no separate audio format")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(audioFormats) { format in
                            FormatRow(
                                title: audioTitle(of: format),
                                subtitle: audioSubtitle(of: format),
                                isSelected: format.id == selectedAudioID
                            ) {
                                selectedAudioID = format.id
                            }
                        }
                    }
                } header: {
                    Text("Audio")
                } footer: {
                    Text("Downloads are re-encoded to H.264 video and AAC audio in a .mov file. Formats that are not already H.264 take longer to process.")
                }
            }
            .navigationTitle("Choose Quality")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Download") {
                        onConfirm(selectedVideo, selectedAudio)
                    }
                    .disabled(selectedVideo == nil && selectedAudio == nil)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var videoFormats: [MediaFormat] {
        request.info.videoFormats
    }

    private var audioFormats: [MediaFormat] {
        request.info.audioFormats
    }

    private var selectedVideo: MediaFormat? {
        videoFormats.first { $0.id == selectedVideoID }
    }

    private var selectedAudio: MediaFormat? {
        audioFormats.first { $0.id == selectedAudioID }
    }

    private var durationText: String? {
        guard let duration = request.info.duration, duration > 0 else {
            return nil
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration)
    }

    init(
        request: FormatSelectionRequest,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (MediaFormat?, MediaFormat?) -> Void
    ) {
        self.request = request
        self.onCancel = onCancel
        self.onConfirm = onConfirm

        // The lists are ordered best first, so the defaults are what
        // `bestvideo+bestaudio` would have picked.
        _selectedVideoID = State(initialValue: request.info.videoFormats.first?.id)
        _selectedAudioID = State(initialValue: request.info.audioFormats.first?.id)
    }

    private func videoTitle(of format: MediaFormat) -> String {
        guard let height = format.height else {
            return format.note ?? format.ext.uppercased()
        }

        // Only high frame rates are worth calling out, the way yt-dlp does it.
        guard let fps = format.fps, fps >= 50 else {
            return "\(height)p"
        }
        return "\(height)p\(Int(fps.rounded()))"
    }

    private func videoSubtitle(of format: MediaFormat) -> String {
        var parts = [format.ext.uppercased()]

        if let videoCodec = format.videoCodec {
            parts.append(codecName(videoCodec))
        }

        if let dynamicRange = format.dynamicRange, dynamicRange != "SDR" {
            parts.append(dynamicRange)
        }

        if let bitRate = format.videoBitRate ?? format.totalBitRate {
            parts.append(bitRateText(kilobitsPerSecond: bitRate))
        }

        if let fileSize = format.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
        }

        if format.hasAudio {
            parts.append(String(localized: "with audio"))
        }

        return parts.joined(separator: " • ")
    }

    private func audioTitle(of format: MediaFormat) -> String {
        guard let bitRate = format.audioBitRate ?? format.totalBitRate else {
            return format.note ?? format.ext.uppercased()
        }
        return bitRateText(kilobitsPerSecond: bitRate)
    }

    private func audioSubtitle(of format: MediaFormat) -> String {
        var parts = [format.ext.uppercased()]

        if let audioCodec = format.audioCodec {
            parts.append(codecName(audioCodec))
        }

        if let sampleRate = format.sampleRate {
            parts.append(String(
                format: String(localized: "%g kHz"),
                Double(sampleRate) / 1000
            ))
        }

        if let fileSize = format.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
        }

        return parts.joined(separator: " • ")
    }

    private func bitRateText(kilobitsPerSecond: Double) -> String {
        guard kilobitsPerSecond >= 1000 else {
            return String(
                format: String(localized: "%ld kbps"),
                Int(kilobitsPerSecond.rounded())
            )
        }
        return String(
            format: String(localized: "%.1f Mbps"),
            kilobitsPerSecond / 1000
        )
    }

    /// Codecs come as RFC 6381 strings such as `avc1.640028`, which say more
    /// than a format list needs to.
    private func codecName(_ codec: String) -> String {
        let name = codec.split(separator: ".").first.map(String.init) ?? codec

        switch name.lowercased() {
        case "avc1", "avc3", "h264":
            return "H.264"
        case "hvc1", "hev1", "h265":
            return "HEVC"
        case "av01":
            return "AV1"
        case "vp09", "vp9":
            return "VP9"
        case "vp08", "vp8":
            return "VP8"
        case "mp4a":
            return "AAC"
        case "opus":
            return "Opus"
        case "vorbis":
            return "Vorbis"
        case "mp3":
            return "MP3"
        case "ac-3", "ec-3":
            return "Dolby Digital"
        default:
            return name.uppercased()
        }
    }
}

private struct FormatRow: View {
    var title: String
    var subtitle: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
