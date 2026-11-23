#!/bin/bash
# Creates a macOS app that opens Claude Desktop with ANOTHER account,
# with its own name and icon colour, so both can run side by side.
#
# Usage:   ./create-account.sh "Display name" [profile-folder] [colour]
# Example: ./create-account.sh "Claude Work" Claude-Work yellow
#
# Colour:  yellow (default) | green | blue | purple | pink | ANGLE:EXPOSURE (radians, e.g. 1.8:0.3)
# Env:     DEST=/some/folder  where to put the app (default: ~/Applications)
#
# Idempotent: running it again rebuilds the app and keeps the profile (and its login).
set -euo pipefail

NAME="${1:?Missing display name. Usage: $0 \"Display name\" [profile-folder] [colour]}"
SLUG="$(echo "$NAME" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')"
PROFILE="${2:-$(echo "$NAME" | tr ' ' '-')}"
COLOUR="${3:-yellow}"
DEST="${DEST:-$HOME/Applications}"
SRC="/Applications/Claude.app"

case "$COLOUR" in
  yellow) ANG=0.55; EV=0.75 ;;
  green)  ANG=1.83; EV=0.30 ;;
  blue)   ANG=3.49; EV=0.30 ;;
  purple) ANG=4.45; EV=0.30 ;;
  pink)   ANG=5.50; EV=0.30 ;;
  *:*)    ANG="${COLOUR%%:*}"; EV="${COLOUR##*:}" ;;
  *) echo "Invalid colour: $COLOUR"; exit 1 ;;
esac

[ -d "$SRC" ] || { echo "Cannot find $SRC"; exit 1; }
command -v swiftc >/dev/null && command -v clang >/dev/null || { echo "Missing Xcode Command Line Tools: xcode-select --install"; exit 1; }

A="$DEST/$NAME.app"                      # launcher (what you open)
E="$A/Contents/Resources/$NAME.app"      # copy of Claude with its own identity
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

pkill -f "$A" 2>/dev/null || true; sleep 1

echo "1/5 Icon ($COLOUR)..."
iconutil -c iconset "$SRC/Contents/Resources/electron.icns" -o "$W/set.iconset"
cat > "$W/hue.swift" <<'SWIFT'
import CoreImage
import AppKit
let dir = CommandLine.arguments[1]
let ang = Double(CommandLine.arguments[2])!
let ev = Double(CommandLine.arguments[3])!
let ctx = CIContext()
for f in try! FileManager.default.contentsOfDirectory(atPath: dir) where f.hasSuffix(".png") {
  let u = URL(fileURLWithPath: dir + "/" + f)
  let h = CIFilter(name: "CIHueAdjust")!
  h.setValue(CIImage(contentsOf: u)!, forKey: kCIInputImageKey); h.setValue(ang, forKey: kCIInputAngleKey)
  let e = CIFilter(name: "CIExposureAdjust")!
  e.setValue(h.outputImage!, forKey: kCIInputImageKey); e.setValue(ev, forKey: kCIInputEVKey)
  try! ctx.writePNGRepresentation(of: e.outputImage!, to: u, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
}
SWIFT
swiftc -o "$W/hue" "$W/hue.swift" && "$W/hue" "$W/set.iconset" "$ANG" "$EV"
iconutil -c icns "$W/set.iconset" -o "$W/icon.icns"

echo "2/5 Launcher..."
cat > "$W/l.applescript" <<APPLE
set p to POSIX path of (path to me) & "Contents/Resources/$NAME.app"
do shell script "open -n " & quoted form of p
APPLE
mkdir -p "$DEST"; rm -rf "$A"
osacompile -o "$A" "$W/l.applescript"
cp "$W/icon.icns" "$A/Contents/Resources/applet.icns"
plutil -replace CFBundleName -string "$NAME" "$A/Contents/Info.plist"
# Without a bundle identifier the app does not show up in the Apps view / Launchpad.
plutil -insert CFBundleIdentifier -string "local.multiaccount.$SLUG" "$A/Contents/Info.plist" 2>/dev/null \
  || plutil -replace CFBundleIdentifier -string "local.multiaccount.$SLUG" "$A/Contents/Info.plist"
plutil -insert LSApplicationCategoryType -string "public.app-category.productivity" "$A/Contents/Info.plist" 2>/dev/null || true

echo "3/5 Copy of Claude (about 656 MB)..."
cp -R "$SRC" "$E"
cp "$W/icon.icns" "$E/Contents/Resources/electron.icns"
plutil -remove CFBundleIconName "$E/Contents/Info.plist"          # otherwise the Dock keeps the original icon (Assets.car)
plutil -replace CFBundleIdentifier -string "com.anthropic.claudefordesktop.$SLUG" "$E/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "$NAME" "$E/Contents/Info.plist" 2>/dev/null \
  || plutil -insert CFBundleDisplayName -string "$NAME" "$E/Contents/Info.plist"
# CFBundleName stays "Claude": Electron looks up its helper apps by that name

echo "4/5 Pinning the profile '$PROFILE' on every launch..."
cat > "$W/w.c" <<'C'
#include <mach-o/dyld.h>
#include <libgen.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
  char p[PATH_MAX]; uint32_t n = sizeof p;
  if (_NSGetExecutablePath(p, &n) != 0) return 1;
  char real[PATH_MAX]; if (!realpath(p, real)) return 1;
  char bin[PATH_MAX]; snprintf(bin, sizeof bin, "%s/Claude-bin", dirname(real));
  const char *h = getenv("HOME"); if (!h) return 1;
  char ud[PATH_MAX]; snprintf(ud, sizeof ud, "--user-data-dir=%s/Library/Application Support/%s", h, PROFILE);
  char **a = malloc(sizeof(char*) * (argc + 3));
  int k = 0; a[k++] = bin; a[k++] = ud;
  for (int i = 1; i < argc; i++) a[k++] = argv[i];
  a[k] = NULL; execv(bin, a); return 1;
}
C
mv "$E/Contents/MacOS/Claude" "$E/Contents/MacOS/Claude-bin"
clang -O1 -DPROFILE="\"$PROFILE\"" -o "$E/Contents/MacOS/Claude" "$W/w.c"

echo "5/5 Signing and refreshing..."
codesign --force --deep --sign - "$E" 2>&1 | tail -1
codesign --force --deep --sign - "$A" 2>&1 | tail -1
codesign --verify --deep "$A" && echo "signature ok"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREG" -f "$A" 2>/dev/null || true
touch "$E" "$A"; killall Dock || true

cat <<DONE

Done: $A
Profile (login lives here): ~/Library/Application Support/$PROFILE

How to open it later, even if it is not in the Dock:
  - Spotlight:  Cmd+Space, type "$NAME"
  - Finder:     Go > Go to Folder... > $DEST
  - Terminal:   open "$A"
Tip: to keep it in the Dock, open it, then right-click its Dock icon > Options > Keep in Dock.
First time only: sign in with email + code (not Google). See the README.
DONE
