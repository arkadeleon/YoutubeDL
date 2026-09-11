//
//  MediaInfo.swift
//

import Foundation
import PythonKit

/// One downloadable stream of a video, as reported by yt-dlp.
///
/// This is a lenient counterpart of ``Format``: it keeps only what a format
/// picker needs to show, and anything yt-dlp leaves out stays `nil` instead of
/// failing the whole list.
public struct MediaFormat: Identifiable, Hashable, Sendable {
    /// yt-dlp's `format_id`, i.e. what to pass back to `-f`.
    public let id: String

    public let ext: String
    public let note: String?
    public let width: Int?
    public let height: Int?
    public let fps: Double?
    /// Bit rate of the whole stream, in kbps.
    public let totalBitRate: Double?
    /// Bit rate of the video track, in kbps.
    public let videoBitRate: Double?
    /// Bit rate of the audio track, in kbps.
    public let audioBitRate: Double?
    /// Audio sample rate, in Hz.
    public let sampleRate: Int?
    public let fileSize: Int64?
    public let videoCodec: String?
    public let audioCodec: String?
    public let dynamicRange: String?

    public var hasVideo: Bool { videoCodec != nil }

    public var hasAudio: Bool { audioCodec != nil }
}

extension MediaFormat {
    init?(pythonObject: PythonObject) {
        func string(_ key: String) -> String? {
            pythonObject.checking[key].flatMap(String.init)
        }

        func int(_ key: String) -> Int? {
            pythonObject.checking[key].flatMap(Int.init)
        }

        func double(_ key: String) -> Double? {
            pythonObject.checking[key].flatMap(Double.init)
        }

        /// yt-dlp spells a missing track as `"none"` instead of omitting the codec.
        func codec(_ key: String) -> String? {
            guard let codec = string(key), codec != "none" else { return nil }
            return codec
        }

        guard let id = string("format_id"), let ext = string("ext") else {
            return nil
        }

        self.init(
            id: id,
            ext: ext,
            note: string("format_note"),
            width: int("width"),
            height: int("height"),
            fps: double("fps"),
            totalBitRate: double("tbr"),
            videoBitRate: double("vbr"),
            audioBitRate: double("abr"),
            sampleRate: int("asr"),
            fileSize: (double("filesize") ?? double("filesize_approx")).map(Int64.init),
            videoCodec: codec("vcodec"),
            audioCodec: codec("acodec"),
            dynamicRange: string("dynamic_range")
        )
    }
}

/// What ``yt_dlp_extractInfo(argv:log:)`` found out about a URL without
/// downloading anything.
public struct MediaInfo: Sendable {
    public let id: String?
    public let title: String
    public let duration: TimeInterval?

    /// Every format that carries a video or an audio track, in yt-dlp's own
    /// order: worst first.
    public let formats: [MediaFormat]

    /// Formats carrying a video track, best first.
    public var videoFormats: [MediaFormat] {
        Array(formats.filter(\.hasVideo).reversed())
    }

    /// Audio-only formats, best first.
    public var audioFormats: [MediaFormat] {
        Array(formats.filter { $0.hasAudio && !$0.hasVideo }.reversed())
    }
}

extension MediaInfo {
    init?(pythonObject: PythonObject) {
        // A playlist URL resolves to entries rather than to a single video.
        var object = pythonObject
        if let entries = object.checking["entries"].flatMap({ Array<PythonObject>($0) }),
           let first = entries.first {
            object = first
        }

        guard let title = object.checking["title"].flatMap(String.init) else {
            return nil
        }

        let formats = object.checking["formats"].flatMap { Array<PythonObject>($0) } ?? []

        self.init(
            id: object.checking["id"].flatMap(String.init),
            title: title,
            duration: object.checking["duration"].flatMap(Double.init),
            formats: formats
                .compactMap(MediaFormat.init(pythonObject:))
                .filter { $0.hasVideo || $0.hasAudio }
        )
    }
}

/// Resolve a URL into the formats it offers, without downloading anything.
///
/// Takes the same arguments as ``yt_dlp(argv:progress:log:makeTranscodeProgressBlock:events:)``
/// so that options which affect extraction — cookies above all — can be passed
/// the same way. Any `-f` in `argv` is ignored: every format is returned, and
/// picking one is the caller's job.
/// - Parameters:
///   - argv: yt-dlp command line arguments, ending with the URL to extract.
///   - log: closure called for each yt-dlp log message.
/// - Returns: the extracted media information.
public func yt_dlp_extractInfo(
    argv: [String],
    log: ((String, String) -> Void)? = nil
) async throws -> MediaInfo {
    let context = Context()
    let yt_dlp = try await YtDlp(context: context)

    let (ydl_opts, all_urls) = try yt_dlp.parseOptions(args: argv)

    if let log {
        ydl_opts["logger"] = makeLogger(name: "ExtractInfoLogger", log)
    }

    guard let url = Array<PythonObject>(all_urls)?.first else {
        throw YoutubeDLError.noMediaInfo
    }

    let ydl = yt_dlp.makeYoutubeDL(ydlOpts: ydl_opts)

    let info = try ydl.extract_info.throwing.dynamicallyCall(
        withKeywordArguments: ["": url, "download": false])

    guard let mediaInfo = MediaInfo(pythonObject: info) else {
        throw YoutubeDLError.noMediaInfo
    }

    return mediaInfo
}
