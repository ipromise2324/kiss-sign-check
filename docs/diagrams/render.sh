#!/bin/sh
# Renders each diagram source in this folder to its PNG in docs/ with headless Chrome:
#   sh docs/diagrams/render.sh
# Set CHROME to the Chrome binary when it is not at the macOS default path.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
chrome=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}

render() {
  src="$here/$1"
  out="$here/../$2"
  url="file://$src${3:-}"
  width=$(sed -n 's/.*name="render-width" content="\([0-9]*\)".*/\1/p' "$src")
  profile=$(mktemp -d)
  flags="--headless=new --disable-gpu --hide-scrollbars --no-first-run --no-default-browser-check --disable-extensions --virtual-time-budget=3000 --user-data-dir=$profile"
  height=$("$chrome" $flags --window-size="$width,1000" --dump-dom "$url" 2>/dev/null | sed -n 's/.*data-height="\([0-9]*\)".*/\1/p')
  [ -n "$height" ] || { echo "could not measure $1" >&2; rm -rf "$profile"; exit 1; }
  # Headless Chrome paints a strip of the page's top into the last pixels of the window, so render taller and keep the top.
  "$chrome" $flags --force-device-scale-factor=2 --window-size="$width,$((height + 40))" --screenshot="$out" "$url" 2>/dev/null
  sips --cropOffset 0 0 -c $((height * 2)) $((width * 2)) "$out" --out "$out" >/dev/null
  rm -rf "$profile"
  echo "$2: ${width}x${height} CSS px at 2x"
}



render overview.html readme/overview.png
render overview.html readme/overview-dark.png "?dark"
