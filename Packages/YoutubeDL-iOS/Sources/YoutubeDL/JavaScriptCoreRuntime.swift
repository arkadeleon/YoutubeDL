//
//  JavaScriptCoreRuntime.swift
//  YoutubeDL
//

import Foundation
import JavaScriptCore

/// Runs standalone scripts in JavaScriptCore, standing in for the external
/// JavaScript runtimes (Deno, Node, Bun, QuickJS) that yt-dlp shells out to but
/// that cannot exist on iOS.
///
/// The contract mirrors those runtimes: a script is fed in, whatever it writes
/// to `console.log` is handed back as its output.
public final class JavaScriptCoreRuntime {
    public enum Error: LocalizedError {
        case contextUnavailable
        case exception(String)

        public var errorDescription: String? {
            switch self {
            case .contextUnavailable:
                return "Unable to create a JavaScript context."
            case .exception(let message):
                return message
            }
        }
    }

    public static let shared = JavaScriptCoreRuntime()

    /// The solver parses the whole YouTube player with a recursive descent parser.
    /// The default 512 KB of a background thread is enough for the players seen so
    /// far, but the depth is YouTube's to change, and the reservation costs nothing.
    static let stackSize = 32 << 20

    private init() {}

    /// Evaluates `script` and returns everything it logged to `console.log`.
    ///
    /// The script runs on a dedicated thread with an enlarged stack, in a fresh
    /// virtual machine so that the memory taken by the player script is released
    /// as soon as it finishes.
    public func evaluate(_ script: String) throws -> String {
        var result: Result<String, Swift.Error> = .failure(Error.contextUnavailable)

        let semaphore = DispatchSemaphore(value: 0)
        let thread = Thread {
            result = Result { try Self.evaluateOnCurrentThread(script) }
            semaphore.signal()
        }
        thread.name = "JavaScriptCoreRuntime"
        thread.stackSize = Self.stackSize
        // The caller blocks on this thread, so keep it off a lower priority.
        thread.qualityOfService = Thread.current.qualityOfService
        thread.start()
        semaphore.wait()

        return try result.get()
    }

    private static func evaluateOnCurrentThread(_ script: String) throws -> String {
        guard let context = JSContext(virtualMachine: JSVirtualMachine()) else {
            throw Error.contextUnavailable
        }

        let output = Output()

        var exception: String?
        context.exceptionHandler = { _, value in
            exception = value.map(describe) ?? "unknown JavaScript exception"
        }

        install(console: output, in: context)

        context.evaluateScript(script)

        if let exception {
            throw Error.exception(exception)
        }
        return output.stdout
    }

    /// JavaScriptCore has no `console`, so provide the parts the solver uses.
    private static func install(console output: Output, in context: JSContext) {
        context.evaluateScript("globalThis.console = {};")
        guard let console = context.objectForKeyedSubscript("console") else { return }

        let log: @convention(block) () -> Void = {
            output.stdout += joinCurrentArguments() + "\n"
        }
        let diagnostic: @convention(block) () -> Void = {
            print("console:", joinCurrentArguments())
        }

        console.setObject(log, forKeyedSubscript: "log" as NSString)
        for name in ["debug", "info", "warn", "error", "trace"] {
            console.setObject(diagnostic, forKeyedSubscript: name as NSString)
        }
    }

    private static func joinCurrentArguments() -> String {
        (JSContext.currentArguments() as? [JSValue] ?? [])
            .map { $0.toString() ?? "" }
            .joined(separator: " ")
    }

    private static func describe(_ exception: JSValue) -> String {
        let message = exception.toString() ?? "unknown JavaScript exception"
        guard let stack = exception.objectForKeyedSubscript("stack"),
              !stack.isUndefined, let stack = stack.toString(), !stack.isEmpty else {
            return message
        }
        return "\(message)\n\(stack)"
    }

    /// Boxes the captured output so the `console` blocks can append to it.
    private final class Output {
        var stdout = ""
    }
}
