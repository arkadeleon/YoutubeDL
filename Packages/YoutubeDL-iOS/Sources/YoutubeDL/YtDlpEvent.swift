//
//  YtDlpEvent.swift
//

import Foundation
import PythonKit

public struct YtDlpDownloadProgress: Equatable, Sendable {
    public let status: String
    public let temporaryFilePath: String?
    public let outputFilePath: String?
    public let downloadedBytes: Int64?
    public let totalBytes: Int64?
    public let throughput: Int?
    public let estimatedTimeRemaining: TimeInterval?

    public init(
        status: String,
        temporaryFilePath: String? = nil,
        outputFilePath: String? = nil,
        downloadedBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        throughput: Int? = nil,
        estimatedTimeRemaining: TimeInterval? = nil
    ) {
        self.status = status
        self.temporaryFilePath = temporaryFilePath
        self.outputFilePath = outputFilePath
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.throughput = throughput
        self.estimatedTimeRemaining = estimatedTimeRemaining
    }

    init?(dictionary: [String: PythonObject]) {
        guard let status = dictionary["status"].flatMap(String.init) else {
            return nil
        }

        self.init(
            status: status,
            temporaryFilePath: dictionary["tmpfilename"].flatMap(String.init),
            outputFilePath: dictionary["info_dict"].flatMap { String($0["_filename"]) },
            downloadedBytes: dictionary["downloaded_bytes"].flatMap(Int64.init),
            totalBytes: (dictionary["total_bytes"] ?? dictionary["total_bytes_estimate"])
                .flatMap(Double.init)
                .map(Int64.init),
            throughput: dictionary["speed"].flatMap(Int.init),
            estimatedTimeRemaining: dictionary["eta"].flatMap(TimeInterval.init)
        )
    }
}

public enum YtDlpEvent: Equatable, Sendable {
    case downloadProgress(YtDlpDownloadProgress)
    case log(level: String, message: String)
    case transcodeStarted
    case transcodeProgress(Double)
}
