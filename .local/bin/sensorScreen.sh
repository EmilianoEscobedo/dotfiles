#!/bin/bash

sleep 1

xdotool key Super_L+5
sleep 0.2

xdotool key Super_L+period
sleep 0.2

alacritty -e btop -p 1 &
sleep 0.5

xdotool key Super_L+period
sleep 0.2
xdotool key Super_L+1
