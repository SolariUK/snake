#!/bin/bash
#
# Centipede game
#
# v2.2 - Used Claude to improve some fragility and fix some undiscovered bugs.
#
# - Replaced the background sleep+SIGALRM movement timer with a simple
#   `read -t` timeout loop: single-threaded, no orphaned subshells, and not
#   dependent on signal-delivery timing during a blocking read (which varies
#   across bash builds/terminals)
# - Added a trap to always restore the terminal (echo, cursor, colours) on
#   exit, even on Ctrl-C or an unexpected error
# - Fixed a bug where quitting referenced an undefined $COLS variable
# - Modernized deprecated $[ ] arithmetic to $(( ))
# - Added a terminal size check so the game refuses to start somewhere the
#   board won't fit, instead of drawing off-screen
# - tput setaf 9 (used as a "reset to default colour") isn't guaranteed to
#   exist in every terminfo entry; using tput sgr0 instead, which is the
#   portable way to reset attributes/colours
#
# Original Author: Mark M - ^Sol
#
# Functions

cleanup() {
   # Always restore the terminal, however we exit
   tput cnorm    # restore cursor
   tput sgr0     # reset colours/attributes
   stty echo
}
trap cleanup EXIT INT TERM

drawborder() {
   tput setaf 6
   tput cup "$FIRSTROW" "$FIRSTCOL"
   x=$FIRSTCOL
   while [ "$x" -le "$LASTCOL" ]; do
      printf %b "$WALLCHAR"
      x=$(( x + 1 ))
   done

   x=$FIRSTROW
   while [ "$x" -le "$LASTROW" ]; do
      tput cup "$x" "$FIRSTCOL"; printf %b "$WALLCHAR"
      tput cup "$x" "$LASTCOL"; printf %b "$WALLCHAR"
      x=$(( x + 1 ))
   done

   tput cup "$LASTROW" "$FIRSTCOL"
   x=$FIRSTCOL
   while [ "$x" -le "$LASTCOL" ]; do
      printf %b "$WALLCHAR"
      x=$(( x + 1 ))
   done
   tput sgr0
}

apple() {
   APPLEX=$(( (RANDOM % (AREAMAXX - AREAMINX + 1)) + AREAMINX ))
   APPLEY=$(( (RANDOM % (AREAMAXY - AREAMINY + 1)) + AREAMINY ))
}

drawapple() {
   # Check we haven't picked an occupied space. This could theoretically hunt
   # many times if a stupidly high score is reached but won't really worry 
   # about it for now.
   LASTEL=$(( ${#LASTPOSX[@]} - 1 ))
   x=0
   apple
   while [ "$x" -le "$LASTEL" ]; do
      if [ "$APPLEX" = "${LASTPOSX[$x]}" ] && [ "$APPLEY" = "${LASTPOSY[$x]}" ]; then
         # Invalid coords... in use, try again
         x=0
         apple
      else
         x=$(( x + 1 ))
      fi
   done
   tput setaf 1
   tput cup "$APPLEY" "$APPLEX"
   printf %b "$APPLECHAR"
   tput sgr0
}

growsnake() {
   # Pad out the arrays with oldest position 3 times to make snake bigger
   LASTPOSX=( "${LASTPOSX[0]}" "${LASTPOSX[0]}" "${LASTPOSX[0]}" "${LASTPOSX[@]}" )
   LASTPOSY=( "${LASTPOSY[0]}" "${LASTPOSY[0]}" "${LASTPOSY[0]}" "${LASTPOSY[@]}" )
   drawapple
}

move() {
   case "$DIRECTION" in
      u) POSY=$(( POSY - 1 ));;
      d) POSY=$(( POSY + 1 ));;
      l) POSX=$(( POSX - 1 ));;
      r) POSX=$(( POSX + 1 ));;
   esac

   # Collision detection - walls
   if [ "$POSX" -le "$FIRSTCOL" ] || [ "$POSX" -ge "$LASTCOL" ] ||
      [ "$POSY" -le "$FIRSTROW" ] || [ "$POSY" -ge "$LASTROW" ]; then
      tput cup $(( LASTROW + 1 )) 0
      echo " GAME OVER! You hit a wall!"
      gameover
   fi

   # Collision detection - self
   LASTEL=$(( ${#LASTPOSX[@]} - 1 ))
   x=1 # start at 1: element 0 is the tail end, about to be erased below
   while [ "$x" -le "$LASTEL" ]; do
      if [ "$POSX" = "${LASTPOSX[$x]}" ] && [ "$POSY" = "${LASTPOSY[$x]}" ]; then
         tput cup $(( LASTROW + 1 )) 0
         echo " GAME OVER! YOU ATE YOURSELF!"
         gameover
      fi
      x=$(( x + 1 ))
   done

   # clear the oldest position on screen
   tput cup "${LASTPOSY[0]}" "${LASTPOSX[0]}"
   printf " "

   # truncate position history by 1 (drop oldest, append new)
   LASTPOSX=( "${LASTPOSX[@]:1}" "$POSX" )
   LASTPOSY=( "${LASTPOSY[@]:1}" "$POSY" )

   tput cup 2 30
   printf "SCORE: %d " "$SCORE"

   # plot new position
   tput setaf 2
   tput cup "$POSY" "$POSX"
   printf %b "$SNAKECHAR"
   tput sgr0

   # Check if we hit an apple
   if [ "$POSX" -eq "$APPLEX" ] && [ "$POSY" -eq "$APPLEY" ]; then
      growsnake
      updatescore 10
   fi
}

updatescore() {
   SCORE=$(( SCORE + $1 ))
   tput cup 2 30
   printf "SCORE: %d " "$SCORE"
}

randomchar() {
   [ $# -eq 0 ] && return 1
   n=$(( (RANDOM % $#) + 1 ))
   eval DIRECTION=\${$n}
}

gameover() {
   sleep "$DELAY"
   tput cup "$ROWS" 0
   exit 0
   # cleanup() runs automatically via the EXIT trap
}

###########################END OF FUNCS##########################

# Normal boring ASCII Chars (portable across terminals/locales)
SNAKECHAR="@"                           # Character to use for snake
WALLCHAR="X"                            # Character to use for wall
APPLECHAR="o"                           # Character to use for apples

SNAKESIZE=3                             # Initial Size of array aka snake
DELAY=0.1                               # Timer delay for move function
FIRSTROW=3                              # First row of game area
FIRSTCOL=1                              # First col of game area
LASTCOL=40                              # Last col of game area
LASTROW=20                              # Last row of game area
AREAMAXX=$(( LASTCOL - 1 ))             # Furthest right play area X
AREAMINX=$(( FIRSTCOL + 1 ))            # Furthest left play area X
AREAMAXY=$(( LASTROW - 1 ))             # Lowest play area Y
AREAMINY=$(( FIRSTROW + 1 ))            # Highest play area Y
ROWS=$(tput lines)                      # Rows in terminal
COLS=$(tput cols)                       # Columns in terminal

# Make sure the terminal is actually big enough for the board before
# we clear the screen and start drawing off the edge of it.
if [ "$ROWS" -le $(( LASTROW + 2 )) ] || [ "$COLS" -le $(( LASTCOL + 1 )) ]; then
   echo "Your terminal is too small for this game."
   echo "Need at least $(( LASTCOL + 1 )) columns x $(( LASTROW + 2 )) rows,"
   echo "but this terminal is only ${COLS}x${ROWS}."
   exit 1
fi

ORIGINX=$(( LASTCOL / 2 ))              # Start point X
ORIGINY=$(( LASTROW / 2 ))              # Start point Y
POSX=$ORIGINX
POSY=$ORIGINY

# Pad out arrays with the starting position, SNAKESIZE times
LASTPOSX=()
LASTPOSY=()
i=0
while [ "$i" -lt "$SNAKESIZE" ]; do
   LASTPOSX+=( "$POSX" )
   LASTPOSY+=( "$POSY" )
   i=$(( i + 1 ))
done

SCORE=0

clear
echo "
Keys:

 W - UP
 S - DOWN
 A - LEFT
 D - RIGHT
 X - QUIT

If characters do not display properly, consider changing
SNAKECHAR, APPLECHAR and WALLCHAR variables in script.
Characters supported depend upon your terminal setup.

Press Return to continue
"

stty -echo
tput civis
read -r RTN
tput setab 0   # black background (modern replacement for old `setb`)
tput bold
clear
drawborder
updatescore 0

# Draw the first apple (drawapple avoids the snake's starting squares)
drawapple

# Pick a random starting direction
DIRECTIONS=( u d l r )
randomchar "${DIRECTIONS[@]}"

# Main loop: wait up to $DELAY seconds for a keypress, then move regardless.
# This replaces the old background `sleep && kill -ALRM` timer - it's
# single-threaded, leaves no orphaned processes behind, and doesn't depend
# on signal delivery racing a blocking read.
while :
do
   if read -rs -n 1 -t "$DELAY" key; then
      case "$key" in
         w) DIRECTION="u";;
         s) DIRECTION="d";;
         a) DIRECTION="l";;
         d) DIRECTION="r";;
         x)
            tput cup "$ROWS" 0
            echo "Quitting..."
            printf "Bye Bye!\n"
            exit 0
            ;;
      esac
   fi
   move
done
