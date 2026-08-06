//
//  JavaScriptCoreRuntime.swift
//

import Foundation
import JavaScriptCore

/// Runs scripts in JavaScriptCore, in place of the external JavaScript runtimes
/// (Deno, Node, Bun, QuickJS) that yt-dlp runs but iOS cannot.
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

    /// The solver parses the whole YouTube player with a recursive parser. The
    /// default 512 KB stack fits the players seen so far, but YouTube can make
    /// them deeper at any time, and reserving more costs nothing.
    static let stackSize = 32 << 20

    private init() {}

    /// Runs `script` and returns everything it wrote to `console.log`.
    ///
    /// Each call gets its own thread with a bigger stack and a new virtual
    /// machine, so the memory the player script uses is freed as soon as it
    /// finishes.
    public func evaluate(_ script: String) throws -> String {
        var result: Result<String, Swift.Error> = .failure(Error.contextUnavailable)

        let semaphore = DispatchSemaphore(value: 0)
        let thread = Thread {
            result = Result { try Self.evaluateOnCurrentThread(script) }
            semaphore.signal()
        }
        thread.name = "JavaScriptCoreRuntime"
        thread.stackSize = Self.stackSize
        // The caller waits for this thread, so do not give it a lower priority.
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

    /// JavaScriptCore has no `console`, so add the parts the solver uses.
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

    /// A reference type so the `console` blocks can append to the output.
    private final class Output {
        var stdout = ""
    }
}
