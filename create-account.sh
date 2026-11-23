#!/bin/bash
# Creates a macOS app that opens Claude Desktop with ANOTHER account,
# with its own name and icon colour, so both can run side by side.
#
# Usage:    ./create-account.sh "Name" [colour]
# Examples: ./create-account.sh "Claude Work"                 # colour picked for you
#           ./create-account.sh "Claude Work" yellow          # a named colour
#           ./create-account.sh "Claude Work" "#7C3AED"       # any hex colour
#
# Colour (optional): yellow green blue purple pink red teal | #RRGGBB | #RGB
#                    If omitted, a colour is generated from the name (same name = same colour).
# Env (optional):    DEST=/some/folder   where to put the app   (default: ~/Applications)
#                    PROFILE=Some-Folder  session folder name    (default: derived from the name)
#
# Idempotent: running it again rebuilds the app and keeps the session.
set -euo pipefail

# --- helpers: the name becomes a folder name (dashes) and an identifier (no dashes) ---
to_profile() { printf '%s' "$1" | tr -s ' ' '-' | tr -cd 'A-Za-z0-9._-'; }   # "Claude Work" -> Claude-Work
to_slug()    { printf '%s' "$1" | tr -cd 'A-Za-z0-9' | tr 'A-Z' 'a-z'; }     # "Claude Work" -> claudework

NAME="${1:?Missing name. Usage: $0 \"Name\" [colour]}"
SLUG="$(to_slug "$NAME")"
PROFILE="${PROFILE:-$(to_profile "$NAME")}"
DEST="${DEST:-$HOME/Applications}"
SRC="/Applications/Claude.app"

[ -n "$SLUG" ] && [ -n "$PROFILE" ] || { echo "The name needs at least one letter or number."; exit 1; }
# The main Claude app stores its session in "Claude": never share it.
case "$PROFILE" in Claude|Claude-3p) echo "Pick a different name: the profile '$PROFILE' belongs to the main Claude app."; exit 1 ;; esac

# --- colour: named, hex, or generated from the name ---
COLOUR_IN="${2:-}"
case "$(echo "$COLOUR_IN" | tr 'A-Z' 'a-z')" in
  "")     # hue 55..334: stays clear of the original orange (~15) so accounts are easy to tell apart
          HUE=$(( 55 + $(printf '%s' "$NAME" | cksum | cut -d' ' -f1) % 280 )); COLOUR="hue:$HUE"; SHOWN="generated from the name (hue $HUE)" ;;
  yellow) COLOUR=F4B000 ;; green) COLOUR=2FB344 ;; blue) COLOUR=1FA6D8 ;; purple) COLOUR=8B5CF6 ;;
  pink)   COLOUR=EC4899 ;; red)   COLOUR=E5483A ;; teal) COLOUR=14B8A6 ;;
  *)      HEX="${COLOUR_IN#\#}"
          [[ "$HEX" =~ ^[0-9A-Fa-f]{3}$ ]] && HEX="${HEX:0:1}${HEX:0:1}${HEX:1:1}${HEX:1:1}${HEX:2:1}${HEX:2:1}"
          [[ "$HEX" =~ ^[0-9A-Fa-f]{6}$ ]] || { echo "Invalid colour '$COLOUR_IN'. Use a name (yellow, green, blue, purple, pink, red, teal) or hex like #7C3AED."; exit 1; }
          COLOUR="$HEX" ;;
esac
[ -n "${SHOWN:-}" ] || SHOWN="${COLOUR_IN:-$COLOUR}"

[ -d "$SRC" ] || { echo "Cannot find $SRC"; exit 1; }
command -v swiftc >/dev/null && command -v clang >/dev/null || { echo "Missing Xcode Command Line Tools: xcode-select --install"; exit 1; }

A="$DEST/$NAME.app"                      # launcher (what you open)
E="$A/Contents/Resources/$NAME.app"      # copy of Claude with its own identity
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

pkill -f "$A" 2>/dev/null || true; sleep 1

echo "1/5 Icon ($SHOWN)..."
iconutil -c iconset "$SRC/Contents/Resources/electron.icns" -o "$W/set.iconset"
cat > "$W/recolor.swift" <<'SWIFT'
import AppKit

// usage: recolor <iconset-dir> <RRGGBB | hue:DEGREES>
// Recolours the orange background of the Claude icon to a target colour.
// The white star, glow and shadow are left alone (they have almost no saturation).

func toHSV(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, v: Double) {
  let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
  var h = 0.0
  if d > 0 {
    if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
    else if mx == g { h = (b - r) / d + 2 }
    else { h = (r - g) / d + 4 }
    h /= 6
    if h < 0 { h += 1 }
  }
  return (h, mx == 0 ? 0 : d / mx, mx)
}

func toRGB(_ h: Double, _ s: Double, _ v: Double) -> (r: Double, g: Double, b: Double) {
  let c = v * s
  let hp = (h - floor(h)) * 6
  let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
  let m = v - c
  var p: (Double, Double, Double)
  switch Int(hp) {
  case 0: p = (c, x, 0)
  case 1: p = (x, c, 0)
  case 2: p = (0, c, x)
  case 3: p = (0, x, c)
  case 4: p = (x, 0, c)
  default: p = (c, 0, x)
  }
  return (p.0 + m, p.1 + m, p.2 + m)
}

func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
  let t = min(max((x - a) / (b - a), 0), 1)
  return t * t * (3 - 2 * t)
}

func pixels(of file: String) -> (data: [UInt8], w: Int, h: Int) {
  let img = NSImage(contentsOfFile: file)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
  let w = img.width, h = img.height
  var data = [UInt8](repeating: 0, count: w * h * 4)
  let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
  return (data, w, h)
}

let dir = CommandLine.arguments[1]
let spec = CommandLine.arguments[2]
let files = try! FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".png") }

// Target colour
var th = 0.0, ts = 0.8, tv = 0.92
if spec.hasPrefix("hue:") {
  th = Double(spec.dropFirst(4))! / 360
} else {
  let n = Int(spec, radix: 16)!
  (th, ts, tv) = toHSV(Double((n >> 16) & 255) / 255, Double((n >> 8) & 255) / 255, Double(n & 255) / 255)
}

// Base colour of the original background, measured from the biggest icon.
let biggest = files.max { pixels(of: dir + "/" + $0).w < pixels(of: dir + "/" + $1).w }!
let ref = pixels(of: dir + "/" + biggest)
var sx = 0.0, sy = 0.0, ss = 0.0, sv = 0.0, cnt = 0.0
for i in stride(from: 0, to: ref.data.count, by: 4) where ref.data[i + 3] > 250 {
  let (h, s, v) = toHSV(Double(ref.data[i]) / 255, Double(ref.data[i + 1]) / 255, Double(ref.data[i + 2]) / 255)
  if s > 0.4 && v > 0.5 { sx += cos(h * 2 * .pi); sy += sin(h * 2 * .pi); ss += s; sv += v; cnt += 1 }
}
let bh = (atan2(sy, sx) / (2 * .pi) + 1).truncatingRemainder(dividingBy: 1)
let bs = ss / cnt, bv = sv / cnt

for f in files {
  let path = dir + "/" + f
  var (data, w, h) = pixels(of: path)
  for i in stride(from: 0, to: data.count, by: 4) {
    let a = Double(data[i + 3]) / 255
    if a == 0 { continue }
    let r = Double(data[i]) / 255 / a, g = Double(data[i + 1]) / 255 / a, b = Double(data[i + 2]) / 255 / a
    let (ph, ps, pv) = toHSV(min(r, 1), min(g, 1), min(b, 1))
    let weight = smoothstep(0.15, 0.40, ps)
    if weight == 0 { continue }
    let nh = th + (ph - bh)                     // keep the original hue variation (grain)
    let ns = min(1, ps * ts / bs)
    let nv = min(1, pv * tv / bv)
    let n = toRGB(nh, ns, nv)
    let out = (r + (n.r - r) * weight, g + (n.g - g) * weight, b + (n.b - b) * weight)
    data[i] = UInt8(max(0, min(255, out.0 * a * 255)))
    data[i + 1] = UInt8(max(0, min(255, out.1 * a * 255)))
    data[i + 2] = UInt8(max(0, min(255, out.2 * a * 255)))
  }
  let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
SWIFT
swiftc -O -o "$W/recolor" "$W/recolor.swift" && "$W/recolor" "$W/set.iconset" "$COLOUR"
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
Session (login) is stored in: ~/Library/Application Support/$PROFILE

How to open it later, even if it is not in the Dock:
  - Spotlight:  Cmd+Space, type "$NAME"
  - Finder:     Go > Go to Folder... > $DEST
  - Terminal:   open "$A"
Tip: to keep it in the Dock, open it, then right-click its Dock icon > Options > Keep in Dock.
First time only: sign in with email + code (not Google). See the README.
DONE
