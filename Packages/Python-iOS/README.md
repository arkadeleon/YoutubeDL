# Python-iOS

This swift package enables you to use python modules in your iOS apps.

Vendored from https://github.com/kewlbear/Python-iOS and consumed by path, so
the XCFrameworks in `Frameworks/` are checked in rather than downloaded.

## Installation

```
.package(path: "../Python-iOS")
```

## Usage

```
import PythonSupport

PythonSupport.initialize()
```

## Building

Ships CPython 3.11.6, cross-compiled from upstream https://github.com/kivy/kivy-ios
for arm64 device and simulator. To rebuild, from the package root:

```
sh Scripts/toolchain.sh
sh Scripts/build.sh
```

3.11 is as far as the current sources go: `PythonSupport` builds its importer on
the `imp` module, removed in 3.12, and `LinkPython` calls `PySys_SetArgv` and
`PyEval_InitThreads`, removed in 3.13.

## License

MIT
