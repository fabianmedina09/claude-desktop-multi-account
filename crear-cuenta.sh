#!/bin/bash
# Crea una app de macOS que abre Claude Desktop con OTRA cuenta, con nombre e icono propios.
# Uso:    ./crear-cuenta.sh "Nombre visible" [carpeta-de-perfil] [color]
# Ejemplo: ./crear-cuenta.sh "Claude Trabajo" Claude-Trabajo amarillo
# Color:  amarillo (por defecto) | verde | azul | morado | rosa | ANGULO:EXPOSICION (radianes, p. ej. 1.8:0.3)
# Es idempotente: volver a correrlo reconstruye la app y conserva el perfil (y su sesión).
set -euo pipefail

NOMBRE="${1:?Falta el nombre visible. Uso: $0 \"Nombre\" [perfil] [color]}"
SLUG="$(echo "$NOMBRE" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')"
PERFIL="${2:-$(echo "$NOMBRE" | tr ' ' '-')}"
COLOR="${3:-amarillo}"
DESTINO="${DESTINO:-$HOME/Applications}"
ORIGEN="/Applications/Claude.app"

case "$COLOR" in
  amarillo) ANG=0.55; EV=0.75 ;;
  verde)    ANG=1.83; EV=0.30 ;;
  azul)     ANG=3.49; EV=0.30 ;;
  morado)   ANG=4.45; EV=0.30 ;;
  rosa)     ANG=5.50; EV=0.30 ;;
  *:*)      ANG="${COLOR%%:*}"; EV="${COLOR##*:}" ;;
  *) echo "Color no válido: $COLOR"; exit 1 ;;
esac

[ -d "$ORIGEN" ] || { echo "No encuentro $ORIGEN"; exit 1; }
command -v swiftc >/dev/null && command -v clang >/dev/null || { echo "Faltan las Xcode Command Line Tools: xcode-select --install"; exit 1; }

A="$DESTINO/$NOMBRE.app"                      # lanzador (lo que se abre)
E="$A/Contents/Resources/$NOMBRE.app"         # copia de Claude con identidad propia
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

pkill -f "$A" 2>/dev/null || true; sleep 1

echo "1/5 Icono ($COLOR)…"
iconutil -c iconset "$ORIGEN/Contents/Resources/electron.icns" -o "$W/set.iconset"
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
iconutil -c icns "$W/set.iconset" -o "$W/icono.icns"

echo "2/5 Lanzador…"
cat > "$W/l.applescript" <<APPLE
set p to POSIX path of (path to me) & "Contents/Resources/$NOMBRE.app"
do shell script "open -n " & quoted form of p
APPLE
mkdir -p "$DESTINO"; rm -rf "$A"
osacompile -o "$A" "$W/l.applescript"
cp "$W/icono.icns" "$A/Contents/Resources/applet.icns"
plutil -replace CFBundleName -string "$NOMBRE" "$A/Contents/Info.plist"

echo "3/5 Copia de Claude (656 MB aprox.)…"
cp -R "$ORIGEN" "$E"
cp "$W/icono.icns" "$E/Contents/Resources/electron.icns"
plutil -remove CFBundleIconName "$E/Contents/Info.plist"          # si no, el Dock usa el icono original (Assets.car)
plutil -replace CFBundleIdentifier -string "com.anthropic.claudefordesktop.$SLUG" "$E/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "$NOMBRE" "$E/Contents/Info.plist" 2>/dev/null \
  || plutil -insert CFBundleDisplayName -string "$NOMBRE" "$E/Contents/Info.plist"
# CFBundleName se queda en "Claude": Electron busca sus helpers con ese nombre

echo "4/5 Fijar el perfil '$PERFIL' en cada arranque…"
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
  char ud[PATH_MAX]; snprintf(ud, sizeof ud, "--user-data-dir=%s/Library/Application Support/%s", h, PERFIL);
  char **a = malloc(sizeof(char*) * (argc + 3));
  int k = 0; a[k++] = bin; a[k++] = ud;
  for (int i = 1; i < argc; i++) a[k++] = argv[i];
  a[k] = NULL; execv(bin, a); return 1;
}
C
mv "$E/Contents/MacOS/Claude" "$E/Contents/MacOS/Claude-bin"
clang -O1 -DPERFIL="\"$PERFIL\"" -o "$E/Contents/MacOS/Claude" "$W/w.c"

echo "5/5 Firmar y refrescar…"
codesign --force --deep --sign - "$E" 2>&1 | tail -1
codesign --force --deep --sign - "$A" 2>&1 | tail -1
codesign --verify --deep "$A" && echo "firma ok"
touch "$E" "$A"; killall Dock || true
echo "Listo: $A  (perfil: ~/Library/Application Support/$PERFIL)"
