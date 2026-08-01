#!/bin/sh
# Cross-compiles CPython for iOS. Run from the package root, then build.sh to
# turn the result into the XCFrameworks this package ships.
set -e

# Pinned so a rebuild reproduces the shipped binaries. Upstream kivy-ios carries
# the Python 3.11 recipe; the kewlbear fork this package used to build from is a
# toolchain generation behind and stuck on 3.10.
KIVY_IOS_REF=892c4b72ee4eb3537310b0694d5fb73cb6a18d53

git clone https://github.com/kivy/kivy-ios.git
cd kivy-ios
git checkout $KIVY_IOS_REF

# kivy-ios pulls in sh 1.14.3, which does not run on recent Python versions.
python3.11 -m venv venv
. venv/bin/activate

pip install -e .
pip install "cython<3"

# arm64 only: the x86_64 simulator slice would serve Intel Macs alone.
python toolchain.py build python3 \
	--platform iphoneos-arm64 \
	--platform iphonesimulator-arm64
