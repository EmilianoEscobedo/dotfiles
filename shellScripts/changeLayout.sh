 #!/bin/bash

actual=$(xkb-switch)

if [ "$actual" = us ];
then 
    setxkbmap latam
else 
    setxkbmap us
fi
