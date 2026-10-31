#!/bin/zsh
# Builds TailscaleKit.xcframework from a pinned libtailscale commit into Vendor/TailscaleKit.
# Needs Go (brew install go). The framework is large and not committed.
set -euo pipefail
# On a fresh clone there is nothing for the clean-up below to match.
setopt null_glob

LIBTAILSCALE_COMMIT=d1dc45d
ROOT=${0:A:h:h}
WORK=${LIBTAILSCALE_DIR:-$ROOT/.build/libtailscale}

if [[ ! -d $WORK/.git ]]; then
    git clone https://github.com/tailscale/libtailscale "$WORK"
fi
git -C "$WORK" fetch --quiet origin
git -C "$WORK" checkout --quiet "$LIBTAILSCALE_COMMIT"

cp "$ROOT/scripts/libtailscale/duoremote_nologs.go" "$WORK/"
# Neither make nor xcodebuild notice the added file, so build from clean.
rm -rf "$WORK"/libtailscale*.a "$WORK"/libtailscale*.h "$WORK/swift/build"
make -C "$WORK/swift" ios-fat

rm -rf "$ROOT/Vendor/TailscaleKit/TailscaleKit.xcframework"
cp -R "$WORK/swift/build/Build/Products/Release-iphonefat/TailscaleKit.xcframework" "$ROOT/Vendor/TailscaleKit/"
echo "TailscaleKit.xcframework → Vendor/TailscaleKit"
