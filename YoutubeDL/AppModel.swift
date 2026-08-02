//
//  AppModel.swift
//  YoutubeDL
//
//  Copyright (c) 2021 Changbeom Ahn
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation
import PythonSupport
import YoutubeDL
import Combine
import UIKit
import AVFoundation
import Photos
import PythonKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

typealias TimeRange = Range<TimeInterval>

enum DownloadState: Equatable {
    case idle
    case extracting
    case downloading
    case converting
    case saving
    case completed(URL)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .extracting, .downloading, .converting, .saving:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }
}

struct DownloadProgress: Equatable {
    var fileName: String?
    var completedUnitCount: Int64?
    var totalUnitCount: Int64?
    var throughput: Int?
    var estimatedTimeRemaining: TimeInterval?

    static let empty = DownloadProgress()

    var fractionCompleted: Double? {
        guard let completedUnitCount,
              let totalUnitCount,
              completedUnitCount >= 0,
              totalUnitCount > 0 else {
            return nil
        }

        return min(max(Double(completedUnitCount) / Double(totalUnitCount), 0), 1)
    }
}

struct YtDlpDownloadResult: Equatable {
    var outputFilePath: String?
    var errorMessage: String?
}

struct DownloadedFile: Identifiable {
    let url: URL
    let byteCount: Int64

    var id: URL {
        url
    }

    var name: String {
        url.lastPathComponent
    }

    var iconName: String {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return "doc"
        }

        if type.conforms(to: .movie) {
            return "film"
        }
        if type.conforms(to: .audio) {
            return "waveform"
        }
        if type.conforms(to: .image) {
            return "photo"
        }
        return "doc"
    }
}

@MainActor
class AppModel: ObservableObject {
    @Published var url: URL?

    @Published var youtubeDL = YoutubeDL()

    @Published var downloads: [DownloadedFile] = []

    @Published var downloadState: DownloadState = .idle

    @Published var downloadProgress: DownloadProgress = .empty

    private var progress = Progress()

    @Published var hasYouTubeCookies = YouTubeCookieStore.hasStoredCookies

    lazy var subscriptions = Set<AnyCancellable>()

    init() {
        youtubeDL.downloadsDirectory = try! documentsDirectory()

        $url
            .compactMap { $0 }
            .sink { [weak self] url in
                Task { [weak self] in
                    await self?.startDownload(url: url)
                }
            }
            .store(in: &subscriptions)

        do {
            try refreshDownloads()
        } catch {
            // FIXME: ...
            print(#function, error)
        }
    }

    func startDownload(url: URL) async {
        guard !downloadState.isBusy else {
            return
        }

        print(#function, url)
        downloadProgress = .empty
        downloadState = .extracting

        do {
            let outputURL = try await download(url: url)

            downloadState = .saving
            try await export(url: outputURL)

            do {
                try refreshDownloads()
            } catch {
                print(#function, "unable to refresh downloads", error)
            }

            downloadProgress = .empty
            downloadState = .completed(outputURL)
            notify(body: String(localized: "Download complete"))
        } catch YoutubeDLError.canceled {
            print(#function, "canceled")
            downloadProgress = .empty
            downloadState = .idle
        } catch is CancellationError {
            print(#function, "canceled")
            downloadProgress = .empty
            downloadState = .idle
        } catch PythonError.exception(let exception, traceback: _) {
            print(#function, exception)
            downloadProgress = .empty
            downloadState = .failed(exception.description)
        } catch {
            print(#function, error)
            downloadProgress = .empty
            downloadState = .failed(error.localizedDescription)
        }
    }

    func refreshDownloads() throws {
        let fileManager = FileManager.default
        let documents = try documentsDirectory()
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey,
        ]

        let urls = try fileManager.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        var files: [(file: DownloadedFile, modificationDate: Date?)] = []
        for url in urls {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else {
                continue
            }

            let file = DownloadedFile(
                url: url,
                byteCount: Int64(values.fileSize ?? 0)
            )
            files.append((file, values.contentModificationDate))
        }

        downloads = files
            .sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
            .map(\.file)
    }

    func delete(_ file: DownloadedFile) throws {
        try FileManager.default.removeItem(at: file.url)
        try refreshDownloads()
    }

    func loadThumbnail(for file: DownloadedFile, size: CGSize, scale: CGFloat) async -> UIImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: file.url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )

        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            guard !Task.isCancelled else {
                return nil
            }
            return representation.uiImage
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }
    }

    func loadDuration(for file: DownloadedFile) async -> String? {
        guard let type = UTType(filenameExtension: file.url.pathExtension),
              type.conforms(to: .movie) else {
            return nil
        }

        do {
            let duration = try await AVURLAsset(url: file.url).load(.duration)
            try Task.checkCancellation()

            let seconds = duration.seconds
            guard seconds.isFinite, seconds > 0 else { return nil }

            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
            formatter.unitsStyle = .positional
            formatter.zeroFormattingBehavior = .pad
            return formatter.string(from: seconds)
        } catch {
            return nil
        }
    }

    func documentsDirectory() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    }

    func cancelDownload() {

    }

    func download(url: URL) async throws -> URL {
        progress = Progress()
        progress.localizedDescription = NSLocalizedString("Extracting info", comment: "progress description")

        var argv: [String] = [
            "-f", "bestvideo[vcodec!^=vp9][vcodec!^=av01]+bestaudio/bestvideo+bestaudio/best",
            "--recode-video", "mov",
            "--postprocessor-args", "VideoConvertor+ffmpeg:-c:v h264 -c:a aac",
            "-o", "%(title).200B.%(ext)s", // https://github.com/yt-dlp/yt-dlp/issues/1136#issuecomment-932077195
            "--no-check-certificates",
        ]
        if let cookieFileURL = YouTubeCookieStore.existingFileURL {
            argv.append(contentsOf: ["--cookies", cookieFileURL.path])
        }
        argv.append(url.absoluteString)
        print(#function, argv)
        let (events, eventContinuation) = AsyncStream.makeStream(of: YtDlpEvent.self)
        async let downloadResult = consumeYtDlpEvents(events)

        try await yt_dlp(argv: argv, events: eventContinuation)

        let result = await downloadResult
        if let errorMessage = result.errorMessage {
            throw NSError(domain: "App", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
        guard let outputFilePath = result.outputFilePath else {
            throw NSError(domain: "App", code: 2, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "The downloader did not return an output file.")
            ])
        }

        return URL(fileURLWithPath: outputFilePath)
            .deletingPathExtension()
            .appendingPathExtension("mov")
    }

    func consumeYtDlpEvents(_ events: AsyncStream<YtDlpEvent>) async -> YtDlpDownloadResult {
        var result = YtDlpDownloadResult()
        var transcodeStartTime: TimeInterval?

        for await event in events {
            switch event {
            case .downloadProgress(let progress):
                if let outputFilePath = progress.outputFilePath {
                    result.outputFilePath = outputFilePath
                }
                updateDownloadProgress(progress)

            case .log(let level, let message):
                print(#function, level, message)
                if level == "error" || message.hasSuffix("has already been downloaded") {
                    result.errorMessage = message
                }

            case .transcodeStarted:
                transcodeStartTime = ProcessInfo.processInfo.systemUptime
                beginTranscodeProgress()

            case .transcodeProgress(let fractionCompleted):
                if transcodeStartTime == nil {
                    transcodeStartTime = ProcessInfo.processInfo.systemUptime
                    beginTranscodeProgress()
                }
                updateTranscodeProgress(
                    fractionCompleted,
                    startTime: transcodeStartTime ?? ProcessInfo.processInfo.systemUptime
                )
            }
        }

        return result
    }

    private func updateDownloadProgress(_ update: YtDlpDownloadProgress) {
        progress.localizedDescription = nil

        switch update.status {
        case "downloading":
            downloadState = .downloading
            progress.kind = .file
            progress.fileOperationKind = .downloading
            let fileName = update.temporaryFilePath
                .map { URL(fileURLWithPath: $0).lastPathComponent }
            if #available(iOS 16.0, *), let temporaryFilePath = update.temporaryFilePath {
                progress.fileURL = URL(filePath: temporaryFilePath)
            }
            progress.completedUnitCount = update.downloadedBytes ?? -1
            progress.totalUnitCount = update.totalBytes ?? -1
            progress.throughput = update.throughput
            progress.estimatedTimeRemaining = update.estimatedTimeRemaining
            downloadProgress = DownloadProgress(
                fileName: fileName,
                completedUnitCount: progress.completedUnitCount,
                totalUnitCount: progress.totalUnitCount,
                throughput: progress.throughput,
                estimatedTimeRemaining: progress.estimatedTimeRemaining
            )

        case "finished":
            print(#function, update.outputFilePath ?? "no filename")

        default:
            print(#function, update)
        }
    }

    private func beginTranscodeProgress() {
        downloadState = .converting
        progress.kind = nil
        progress.localizedDescription = NSLocalizedString("Transcoding...", comment: "Progress description")
        progress.completedUnitCount = 0
        progress.totalUnitCount = 100
        progress.estimatedTimeRemaining = nil
        downloadProgress = DownloadProgress(
            completedUnitCount: 0,
            totalUnitCount: 100
        )
    }

    private func updateTranscodeProgress(_ progressValue: Double, startTime: TimeInterval) {
        print(#function, "transcode:", progressValue)

        let fractionCompleted = min(max(progressValue, 0), 1)
        let elapsed = ProcessInfo.processInfo.systemUptime - startTime
        let estimatedTimeRemaining: TimeInterval?
        if fractionCompleted > 0, elapsed > 0 {
            let estimate = (1 - fractionCompleted) / (fractionCompleted / elapsed)
            estimatedTimeRemaining = estimate.isFinite && estimate >= 0 ? estimate : nil
        } else {
            estimatedTimeRemaining = nil
        }

        downloadState = .converting
        progress.completedUnitCount = Int64(fractionCompleted * 100)
        progress.estimatedTimeRemaining = estimatedTimeRemaining
        downloadProgress = DownloadProgress(
            completedUnitCount: progress.completedUnitCount,
            totalUnitCount: progress.totalUnitCount,
            estimatedTimeRemaining: estimatedTimeRemaining
        )
    }

    func saveYouTubeCookies(_ cookies: [HTTPCookie]) throws {
        try YouTubeCookieStore.save(cookies: cookies)
        hasYouTubeCookies = true
    }

    func removeYouTubeCookies() throws {
        try YouTubeCookieStore.removeCookies()
        hasYouTubeCookies = false
    }

    func transcode(videoURL: URL, transcodedURL: URL, timeRange: TimeRange?, bitRate: Double?) async throws {
        progress.kind = nil
        progress.localizedDescription = NSLocalizedString("Transcoding...", comment: "Progress description")
        progress.totalUnitCount = 100

        let t0 = ProcessInfo.processInfo.systemUptime

        let transcoder = Transcoder { progress in
            print(#function, "transcode:", progress)
            let elapsed = ProcessInfo.processInfo.systemUptime - t0
            let speed = progress / elapsed
            let ETA = (1 - progress) / speed

            guard ETA.isFinite else { return }

            self.progress.completedUnitCount = Int64(progress * 100)
            self.progress.estimatedTimeRemaining = ETA
        }

        let _: Int = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try transcoder.transcode(from: videoURL, to: transcodedURL, timeRange: timeRange, bitRate: bitRate)
                    continuation.resume(returning: 0)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func mux(video videoURL: URL, audio audioURL: URL, out outputURL: URL, timeRange: TimeRange?) async throws -> Bool {
        let t0 = ProcessInfo.processInfo.systemUptime

        let videoAsset = AVAsset(url: videoURL)
        let audioAsset = AVAsset(url: audioURL)

        guard let videoAssetTrack = videoAsset.tracks(withMediaType: .video).first,
              let audioAssetTrack = audioAsset.tracks(withMediaType: .audio).first else {
            print(#function,
                  videoAsset.tracks(withMediaType: .video),
                  audioAsset.tracks(withMediaType: .audio))
            return false
        }

        let composition = AVMutableComposition()
        let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        do {
            try videoCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: videoAssetTrack.timeRange.duration), of: videoAssetTrack, at: .zero)
            let range: CMTimeRange
            if let timeRange = timeRange {
                range = CMTimeRange(start: CMTime(seconds: timeRange.lowerBound, preferredTimescale: 1),
                                    end: CMTime(seconds: timeRange.upperBound, preferredTimescale: 1))
            } else {
                range = CMTimeRange(start: .zero, duration: audioAssetTrack.timeRange.duration)
            }
            try audioCompositionTrack?.insertTimeRange(range, of: audioAssetTrack, at: .zero)
            print(#function, videoAssetTrack.timeRange, range)
        }
        catch {
            print(#function, error)
            return false
        }

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            print(#function, "unable to init export session")
            return false
        }

        removeItem(at: outputURL)

        session.outputURL = outputURL
        session.outputFileType = .mp4
        print(#function, "merging...")

        DispatchQueue.main.async {
            let progress = self.progress
            progress.kind = nil
            progress.localizedDescription = NSLocalizedString("Merging...", comment: "Progress description")
            progress.localizedAdditionalDescription = nil
            progress.totalUnitCount = 0
            progress.completedUnitCount = 0
            progress.estimatedTimeRemaining = nil
        }

        Task {
            while session.status != .completed {
                print(#function, session.progress)
                progress.localizedDescription = "\(Int(session.progress * 100))%"
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                print(#function, "finished merge", session.status.rawValue)
                print(#function, "took", self.youtubeDL.downloader.dateComponentsFormatter.string(from: ProcessInfo.processInfo.systemUptime - t0) ?? "?")
                if session.status == .completed {
                    if !self.youtubeDL.keepIntermediates {
                        removeItem(at: videoURL)
                        removeItem(at: audioURL)
                    }
                } else {
                    print(#function, session.error ?? "no error?")
                }

                continuation.resume(with: Result {
                    if let error = session.error { throw error }
                    return true
                })
            }
        }
    }

    func export(url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    func share() {

    }
}
