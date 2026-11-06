# Réglages dmgbuild pour la fenêtre d'installation du .dmg.
# Appelé par scripts/package.sh avec -D app=… -D guide=… -D background=… -D icon=…
import os.path

app = defines["app"]
guide = defines["guide"]

format = "UDZO"
filesystem = "HFS+"
files = [app, guide]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]  # icône du volume monté

background = defines["background"]
window_rect = ((200, 140), (660, 468))  # 440 de contenu + barre de titre
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 88
text_size = 12
icon_locations = {
    os.path.basename(app): (165, 190),
    "Applications": (495, 190),
    os.path.basename(guide): (585, 352),
}
