#!/bin/sh

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

# Btop on sensors screen
sensorScreen.sh&
