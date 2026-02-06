// FFmpeg-iOS: Swift package to use FFmpeg in your iOS apps
// Copyright (C) 2023  Changbeom Ahn
//
// This library is free software; you can redistribute it and/or
// modify it under the terms of the GNU Lesser General Public
// License as published by the Free Software Foundation; either
// version 2.1 of the License, or (at your option) any later version.
//
// This library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public
// License along with this library; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

import Foundation
//import ffmpeg
import Hook

public func ffmpeg(_ args: String...) -> Int {
    ffmpeg(args)
}

public func ffmpeg(_ args: [String]) -> Int {
    run(tool: HookFFmpeg, args: args)
}

public func ffprobe(_ args: String...) -> Int {
    ffprobe(args)
}

public func ffprobe(_ args: [String]) -> Int {
    run(tool: HookFFprobe, args: args)
}

public func ffmpegCapture(_ args: [String]) -> (Int, String?, String?) {
    runCapture(tool: HookFFmpegCapture, args: args)
}

public func ffprobeCapture(_ args: [String]) -> (Int, String?, String?) {
    runCapture(tool: HookFFprobeCapture, args: args)
}

func run(tool: (Int32, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32, args: [String]) -> Int {
    withArgv(args: args) { argv in
        Int(tool(Int32(args.count), &argv))
    }
}

func runCapture(tool: (Int32, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
                       UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
                       UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32,
                args: [String]) -> (Int, String?, String?) {
    withArgv(args: args) { argv in
        var capturedStdout: UnsafeMutablePointer<CChar>?
        var capturedStderr: UnsafeMutablePointer<CChar>?
        let ret = Int(tool(Int32(args.count), &argv, &capturedStdout, &capturedStderr))
        defer {
            if let capturedStdout {
                HookFreeCString(capturedStdout)
            }
            if let capturedStderr {
                HookFreeCString(capturedStderr)
            }
        }
        let stdout = capturedStdout.flatMap { String(validatingUTF8: $0) }
        let stderr = capturedStderr.flatMap { String(validatingUTF8: $0) }
        return (ret, stdout, stderr)
    }
}

func withArgv<T>(args: [String], _ body: (inout [UnsafeMutablePointer<CChar>?]) -> T) -> T {
    var argv = args.map { strdup($0) }
    defer {
        for pointer in argv {
            free(pointer)
        }
    }
    return body(&argv)
}
