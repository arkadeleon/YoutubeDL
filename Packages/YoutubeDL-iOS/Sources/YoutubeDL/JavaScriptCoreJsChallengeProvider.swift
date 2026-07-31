//
//  JavaScriptCoreJsChallengeProvider.swift
//  YoutubeDL
//

import Foundation
import PythonKit
import PythonSupport

/// yt-dlp needs a JavaScript runtime to solve YouTube's `n` and `sig` challenges,
/// and without one it drops every real format, leaving only storyboard images.
/// It looks for Deno, Node, Bun or QuickJS, none of which can exist on iOS, so
/// register a challenge provider that runs the solver in JavaScriptCore instead.
///
/// Everything but the actual evaluation is already handled by yt-dlp's
/// `EJSBaseJCP`, which loads the solver script and speaks its JSON protocol.
/// See https://github.com/yt-dlp/yt-dlp/wiki/EJS
func registerJavaScriptCoreJsChallengeProvider() {
    guard javaScriptCoreEvaluate == nil else { return }

    // Held for the lifetime of the process: yt-dlp calls it on every download.
    javaScriptCoreEvaluate = PythonFunction { args in
        guard let script = String(args[0]) else {
            throw JavaScriptCoreRuntime.Error.exception("Expected the script as a string.")
        }
        return try JavaScriptCoreRuntime.shared.evaluate(script)
    }
    .pythonObject

    let main = Python.import("__main__")
    main._javascript_core_evaluate = javaScriptCoreEvaluate!

    runSimpleString(providerSource)
}

private var javaScriptCoreEvaluate: PythonObject?

private let providerSource = """
    import os


    def _install_javascript_core_provider():
        from yt_dlp.extractor.youtube.jsc._builtin.ejs import EJSBaseJCP
        from yt_dlp.extractor.youtube.jsc.provider import (
            JsChallengeProviderError,
            register_preference,
            register_provider,
        )
        from yt_dlp.extractor.youtube.pot._provider import BuiltinIEContentProvider

        @register_provider
        class JavaScriptCoreJCP(EJSBaseJCP, BuiltinIEContentProvider):
            # The provider name and key are the class name without the suffix.
            JS_RUNTIME_NAME = 'JavaScriptCore'

            # Parsing the player script again on every download is by far the most
            # expensive part on a phone, so keep the preprocessed one around.
            _ENABLE_PREPROCESSED_PLAYER_CACHE = True

            # Each cached player costs a few megabytes and yt-dlp never rotates
            # them, so keep only the handful of variants currently being served.
            _PLAYER_CACHE_LIMIT = 3

            def is_available(self):
                # JavaScriptCore is part of the system; there is no runtime to look up.
                return self._available

            def _run_js_runtime(self, stdin, /):
                try:
                    return _javascript_core_evaluate(stdin)
                except Exception as error:
                    raise JsChallengeProviderError(str(error)) from error

            def _real_bulk_solve(self, /, requests):
                yield from super()._real_bulk_solve(requests)
                self._prune_player_cache()

            def _prune_player_cache(self):
                try:
                    directory = os.path.join(
                        self.ie.cache._get_root_dir(), self._CACHE_SECTION)
                    # Anything not named after a player is a solver script.
                    players = [
                        os.path.join(directory, name)
                        for name in os.listdir(directory)
                        if name.startswith('player')
                    ]
                    for path in sorted(players, key=os.path.getmtime)[:-self._PLAYER_CACHE_LIMIT]:
                        os.remove(path)
                except Exception as error:
                    self.logger.debug(f'Unable to prune the player cache: {error}')

        @register_preference(JavaScriptCoreJCP)
        def preference(provider, requests):
            return 1000


    try:
        _install_javascript_core_provider()
    except Exception as error:
        print('Unable to register the JavaScriptCore JS challenge provider:', error)
    """
