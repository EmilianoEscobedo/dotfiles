# ooooo                   o8o                                                  .o8              
# `888'                   `"'                                                 "888              
#  888          .oooo.   oooo  ooo. .oo.    .oooooooo  .oooo.   oooo d8b  .oooo888              
#  888         `P  )88b  `888  `888P"Y88b  888' `88b  `P  )88b  `888""8P d88' `888              
#  888          .oP"888   888   888   888  888   888   .oP"888   888     888   888              
#  888       o d8(  888   888   888   888  `88bod8P'  d8(  888   888     888   888              
# o888ooooood8 `Y888""8o o888o o888o o888o `8oooooo.  `Y888""8o d888b    `Y8bod88P"             
#                                          d"     YD                                            
#                                          "Y88888P'                                            
                                                                                                                                  
                                                          
                                                                                              
#   .oooooo.          .    o8o  oooo                   .oooooo.                          .o88o. 
#  d8P'  `Y8b       .o8    `"'  `888                  d8P'  `Y8b                         888 `" 
# 888      888    .o888oo oooo   888   .ooooo.       888           .ooooo.  ooo. .oo.   o888oo  
# 888      888      888   `888   888  d88' `88b      888          d88' `88b `888P"Y88b   888    
# 888      888      888    888   888  888ooo888      888          888   888  888   888   888    
# `88b    d88b      888 .  888   888  888    .o      `88b    ooo  888   888  888   888   888    
#  `Y8bood8P'Ybd'   "888" o888o o888o `Y8bod8P'       `Y8bood8P'  `Y8bod8P' o888o o888o o888o   
                                                                                                                                                     
                                                                                                                                        
import os
import subprocess
from libqtile import hook

from libqtile import bar, layout, widget
from libqtile.config import Click, Drag, Group, Key, Match, Screen
from libqtile.lazy import lazy
from libqtile.utils import guess_terminal

####################
# General settings #
####################

auto_fullscreen = True
focus_on_window_activation = "smart"
reconfigure_screens = True
auto_minimize = False
wl_input_rules = None
wmname = "LG3D"
mod = "mod4"
terminal = guess_terminal()

taskbarColor ="#282a36"
taskbarSize = 40
defaultFont = "Hack Nerd Font Mono"

####################
# Shortcuts config #
####################

keys = [

    # Focus window 
    Key([mod], "h", lazy.layout.left(), desc="Move focus to left"),
    Key([mod], "l", lazy.layout.right(), desc="Move focus to right"),
    Key([mod], "j", lazy.layout.down(), desc="Move focus down"),
    Key([mod], "k", lazy.layout.up(), desc="Move focus up"),
    Key([mod], "space", lazy.layout.next(), desc="Move window focus to other window"),

    # Move window
    Key([mod, "shift"], "h", lazy.layout.shuffle_left(), desc="Move window to the left"),
    Key([mod, "shift"], "l", lazy.layout.shuffle_right(), desc="Move window to the right"),
    Key([mod, "shift"], "j", lazy.layout.shuffle_down(), desc="Move window down"),
    Key([mod, "shift"], "k", lazy.layout.shuffle_up(), desc="Move window up"),

    # Grow window 
    Key([mod, "control"], "h", lazy.layout.grow_left(), desc="Grow window to the left"),
    Key([mod, "control"], "l", lazy.layout.grow_right(), desc="Grow window to the right"),
    Key([mod, "control"], "j", lazy.layout.grow_down(), desc="Grow window down"),
    Key([mod, "control"], "k", lazy.layout.grow_up(), desc="Grow window up"),
    Key([mod], "n", lazy.layout.normalize(), desc="Reset all window sizes"),
    Key([mod, "shift"], "Return", lazy.layout.toggle_split(), desc="Toggle between split and unsplit sides of stack"),
    Key(["control", "shift"], "f", lazy.window.toggle_fullscreen(), desc="Toggle fullscreen for focused window"),
    
    # Custom bindings
    Key([mod], 'm', lazy.spawn("rofi -show drun"), desc="Show menu"),
    Key([mod], "Return", lazy.spawn("alacritty"), desc="Launch terminal"),
    Key([mod], 'f', lazy.spawn("firefox"), desc="Launch firefox"),
    Key([mod], 'd', lazy.spawn("discord"), desc="Launch discord"),
    Key([mod], 'p', lazy.spawn("flameshot gui"), desc="Launch flameshot"),
    Key([mod], 's', lazy.spawn("pavucontrol -t 3"), desc="Launch sound control"),
    Key([mod], 'c', lazy.spawn("calc.sh"), desc="Launch calculator"),
    Key([mod], 'i', lazy.spawn("/opt/intellij-idea-ultimate-edition/bin/idea.sh", shell=True), desc="Launch IntelliJ"),
    Key([mod, "shift"], 'Return', lazy.spawn("/home/laingard/shellScripts/changeLayout.sh", shell=True), desc="Change layout"),
    Key([mod], 'period', lazy.next_screen(), desc='Next monitor'),

    # Etc
    Key([mod], "Tab", lazy.next_layout(), desc="Toggle between layouts"),
    Key([mod], "w", lazy.window.kill(), desc="Kill focused window"),
    Key([mod, "control"], "r", lazy.reload_config(), desc="Reload the config"),
    Key([mod, "control"], "q", lazy.shutdown(), desc="Shutdown Qtile"),
    Key([mod], "r", lazy.spawncmd(), desc="Spawn a command using a prompt widget"),
    Key([mod], "b", lazy.window.toggle_floating()),
]

#########################
# Default groups config #
#########################

groups = [Group(i) for i in [
    '','','','','',''
    ]]

for i, group in enumerate(groups):
    nDesktop = str(i + 1)
    keys.extend(
        [
            Key([mod], nDesktop, lazy.group[group.name].toscreen(),
                desc="Switch to group {}".format(group.name)),
            Key([mod, "shift"], nDesktop, lazy.window.togroup(group.name, switch_group=True),
                desc="Switch to & move focused window to group {}".format(group.name)),
        ]
    )

#######################################
# Create dynamic groups functionality #
#######################################

def create_new_group(qtile):
    current_group = qtile.current_group.name
    
    base_name = current_group.split(' ')[0]
    suffix = 1
    
    subscript_map = {
        1: '₁',
        2: '₂',
        3: '₃',
        4: '₄',
        5: '₅',
        6: '₆',
        7: '₇',
        8: '₈',
        9: '₉',
        0: '₀'
    }

    while f"{base_name} {''.join(subscript_map[int(digit)] for digit in str(suffix))}" in [group.name for group in qtile.groups]:
        suffix += 1
        
    new_group_name = f"{base_name} {''.join(subscript_map[int(digit)] for digit in str(suffix))}"
    current_index = qtile.groups.index(qtile.current_group)
    qtile.add_group(new_group_name)
    qtile.groups.insert(current_index + 1, qtile.groups.pop(-1))
    qtile.groups_map[new_group_name].toscreen()
    

def delete_current_group(qtile):
    if len(qtile.groups) > 1:  
        group_name = qtile.current_group.name
        qtile.delete_group(group_name)

keys.extend([
    Key(["control"], "space", lazy.function(create_new_group), desc="Create new group"),
    Key(["control"], "backspace", lazy.function(delete_current_group), desc="Delete current group"),
])

keys.extend([
    Key(["control"], "period", lazy.screen.next_group(), desc="Move to the next group"),
    Key(["control"], "comma", lazy.screen.prev_group(), desc="Move to the previous group")
])

keys.extend([
    Key(["control", "shift"], "period", lazy.function(lambda qtile: qtile.current_window.togroup(qtile.current_group.get_next_group().name, switch_group=True)),
        desc="Move focused window to the next group"),
    Key(["control", "shift"], "comma", lazy.function(lambda qtile: qtile.current_window.togroup(qtile.current_group.get_previous_group().name, switch_group=True)),
    desc="Move focused window to the previous group")
])

#########################################
# Check available updates functionality #
#########################################

def get_updates():
    try:
        pacman_updates = int(subprocess.check_output(["checkupdates | wc -l"], shell=True))
        aur_updates = int(subprocess.check_output(["yay -Qu | wc -l"], shell=True))
        updates = pacman_updates + aur_updates
    except subprocess.CalledProcessError:
        updates = "Error"
    return f"{updates}"


##################
# Layouts config #
##################

layouts = [
    layout.Columns(border_focus="#13dde8", border_width=3, margin=4),
    layout.Max(border_focus="#13dde8", border_width=3, margin=4),
    layout.Bsp(border_focus="#13dde8", border_width=3, margin=4),
    layout.Matrix(border_focus="#13dde8", border_width=3, margin=4)
    # layout.Stack(num_stacks=2),
    # layout.MonadTall(),
    # layout.MonadWide(),
    # layout.RatioTile(),
    # layout.Tile(),
    # layout.TreeTab(),
    # layout.VerticalTile(),
    # layout.Zoomy(),
]

##############
# Bar config #
##############

extension_defaults = widget_defaults.copy()

widget_defaults = dict(
    font= defaultFont,
    fontsize=14,
    padding=3,
)

def separator():
    return widget.Sep(
        linewidth = 0,
        padding = 6,
    )

def pipe():
    return widget.TextBox(
        "|",
        padding = 10
    )



screens = [
    Screen(
        top=bar.Bar(
            [
                # Groups
                widget.GroupBox(
                    disable_drag = True,
                    borderwidth = 2,
                    highlight_method='line',
                    inactive = "#5c5b5b",
                    this_current_screen_border = "#bd93f9",
                    fontsize=35,
                    padding=5
                    ),
                separator(),
                
                # Arch logo
                widget.Image(margin=5, filename='/home/laingard/Images/archlogo.png'),
                
                # Window focus title
                widget.WindowTabs(
                    padding=20,
                    foreground = "#bd93f9",
                    max_chars = 50,
                    ),
                
                # Systray
                widget.Systray(
                    padding = 10,
                    icon_size = 21
                    ),
                separator(),
                
                #Clock
                pipe(),
                widget.Clock(format="%d-%m-%Y %a %I:%M %p"),
                
                # Available updates
                pipe(),
                widget.TextBox(
                    "",
                    fontsize=23
                ),
                widget.GenPollText(
                    func=get_updates,
                    update_interval=600,
                ),
                
                # Current layout
                pipe(),
                widget.TextBox(
                    "",
                    fontsize=23),
                widget.CurrentLayout(),
                separator()
            ],
            taskbarSize,
            background = taskbarColor,
        ),
    ),
    Screen()
]

#######################################
# Drag floating layouts functionality #
#######################################

mouse = [
    Drag([mod], "Button1", lazy.window.set_position_floating(), start=lazy.window.get_position()),
    Drag([mod], "Button3", lazy.window.set_size_floating(), start=lazy.window.get_size()),
    Click([mod], "Button2", lazy.window.bring_to_front()),
]

dgroups_key_binder = None
dgroups_app_rules = [] 
follow_mouse_focus = False
bring_front_click = False
cursor_warp = False
floating_layout = layout.Floating(
    float_rules=[
        *layout.Floating.default_float_rules,
        Match(wm_class="confirmreset"),  # gitk
        Match(wm_class="makebranch"),  # gitk
        Match(wm_class="maketag"),  # gitk
        Match(wm_class="ssh-askpass"),  # ssh-askpass
        Match(title="branchdialog"),  # gitk
        Match(title="pinentry"),  # GPG key password entry
    ]
)

###################
# Startup scripts #
###################

@hook.subscribe.startup_once
def autostart():
    home = os.path.expanduser('~')
    subprocess.Popen([home + '/.config/qtile/autostart.sh'])

@hook.subscribe.startup_complete
def poststart():
    home = os.path.expanduser('~')
    subprocess.Popen([home + '/home/laingard/shellScripts/sensorScreen.sh'])
