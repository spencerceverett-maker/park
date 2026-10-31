# dmgbuild settings for Park's disk image. Used by scripts/release.sh:
#   dmgbuild -s scripts/dmg-settings.py -D app=build/release/Park.app -D background=build/dmg/background.tiff \
#            -D icon=Resources/AppIcon.icns Park build/release/Park.dmg
# dmgbuild writes Finder's window layout (.DS_Store) directly, so no Finder scripting is needed.
# Window size and icon positions come from layout.json, written next to the background by
# scripts/dmg-quiet.swift, so the art and Finder's layout always match.
import json
import os.path

app = defines["app"]
app_name = os.path.basename(app)

format = "UDZO"
compression_level = 9
filesystem = "HFS+"
size = None

files = [app]
symlinks = {"Applications": "/Applications"}
badge_icon = None
icon = defines["icon"]          # the volume's icon in Finder and on the desktop

background = defines["background"]
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0

layout_path = os.path.join(os.path.dirname(defines["background"]), "layout.json")
layout = json.load(open(layout_path)) if os.path.exists(layout_path) else {
    "window": [640, 400], "icon_size": 112, "text_size": 13, "app": [180, 212], "applications": [460, 212],
}

# Window content area from the layout, placed roughly centered on a laptop screen.
window_rect = ((360, 220), tuple(layout["window"]))
default_view = "icon-view"
show_icon_preview = False
arrange_by = None
icon_size = layout["icon_size"]
text_size = layout["text_size"]
label_pos = "bottom"
icon_locations = {
    app_name: tuple(layout["app"]),
    "Applications": tuple(layout["applications"]),
}
