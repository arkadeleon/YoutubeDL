#!/bin/sh
# Packages the kivy-ios build output into the XCFrameworks and the standard
# library this package ships. Run from the package root, after toolchain.sh.
set -e

VERSION=3.11
DIST=${DIST:-kivy-ios/dist}
STAGE=`mktemp -d`

# kivy-ios caches its lipo step, so a simulator archive can keep an x86_64 slice
# from an earlier build even when it is no longer selected. Reduce to arm64 so
# every XCFramework ends up with the same architectures.
thin() {
	if [ "`lipo -archs $1`" = "arm64" ]
	then
		cp $1 $2
	else
		lipo -thin arm64 $1 -output $2
	fi
}

# $1 XCFramework name, $2 static library name, rest passed through per slice.
package() {
	name=$1
	library=$2
	shift 2

	for sdk in iphoneos iphonesimulator
	do
		mkdir -p $STAGE/$sdk
		thin $DIST/lib/$sdk/$library.a $STAGE/$sdk/$library.a
	done

	rm -rf Frameworks/$name.xcframework
	xcodebuild -create-xcframework -output Frameworks/$name.xcframework \
		-library $STAGE/iphoneos/$library.a "$@" \
		-library $STAGE/iphonesimulator/$library.a "$@"
}

mkdir -p Frameworks

# The binary target is named libpython3 regardless of the Python version, so
# bumping VERSION does not touch Package.swift. Headers ride along with it so
# consumers can compile against the C API.
package libpython3 libpython$VERSION -headers $DIST/root/python3/include/python$VERSION
package libssl libssl
package libcrypto libcrypto
package libffi libffi

rm -rf Sources/PythonSupport/lib
cp -R $DIST/root/python3/lib Sources/PythonSupport/lib
