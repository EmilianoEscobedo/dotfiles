#!/bin/sh

# Update systemd/D-Bus environment for portals
dbus-update-activation-environment --systemd DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP=qtile
systemctl --user import-environment DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP
systemctl --user restart xdg-desktop-portal-gtk
systemctl --user restart xdg-desktop-portal

# System icons
udiskie -t &
nm-applet &
volumeicon &

# Nitrogen wallpapers
nitrogen --restore &

# Picom
picom --experimental-backends --backend glx --xrender-sync-fence&

# Xrandr 144hz & rotate sensors screen
xrandr --output DisplayPort-2 --mode 2560x1440 --rate 143.91&
xrandr --output HDMI-A-0 --rotate inverted&

# Sensor screen setup
~/shellScripts/sensorScreen.sh &
