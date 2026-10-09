#!/bin/sh
# Rebuilds the six theme app icons from the Figma SVGs (node 331:539).
# Quick Look renders the SVG (WebKit, so masks and clip paths survive);
# flatten.swift drops the alpha channel, which iOS rejects in an icon.
set -e
cd "$(dirname "$0")/../.."
R=build/icon-render; mkdir -p "$R"
A=JUI/Resources/Assets.xcassets
for pair in cream:F7C82D mint:61E7C1 sky:65BFFF coral:FF985E lilac:C18FFF orchid:FF87E5; do
  t=${pair%%:*}; bg=${pair##*:}
  # The design draws a rounded tile; iOS wants a full square and rounds it
  # itself. The original SVG goes in unedited, nested inside a square of its
  # own background colour, so the corners come out in the tile's colour.
  # (Quick Look renders onto white, so filling the corners afterwards can't
  # work — there is no transparency left by then.)
  { echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"360\" height=\"360\" viewBox=\"0 0 360 360\">"
    echo "<rect width=\"360\" height=\"360\" fill=\"#$bg\"/>"
    cat "Art/AppIcons/$t.svg"
    echo "</svg>"; } > "$R/$t.svg"
  qlmanage -t -s 1024 -o "$R" "$R/$t.svg" >/dev/null 2>&1
  if [ "$t" = cream ]; then set_name=AppIcon; else set_name=AppIcon-$t; fi
  mkdir -p "$A/$set_name.appiconset"
  rm -f "$A/$set_name.appiconset"/*.png
  swift Art/AppIcons/flatten.swift "$R/$t.svg.png" "$A/$set_name.appiconset/$set_name.png" "$bg"
  cat > "$A/$set_name.appiconset/Contents.json" <<JSON
{
  "images" : [
    { "filename" : "$set_name.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
  echo "$set_name <- $t ($bg)"
done
