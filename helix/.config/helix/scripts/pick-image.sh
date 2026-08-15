#!/bin/bash
FILE=$(find /home/rotimi/Documents/research/images -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.svg" \) \
  | fzf --prompt="Image: ")

[ -n "$FILE" ] && echo "![]($FILE)" | xclip -selection clipboard
