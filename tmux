#!/usr/bin/env sh

name="stockman"
serve="npm start"
watch="node_modules/.bin/cake watch"
serve="npm start"

tmux has-session -t $name
if [ $? != 0 ]
then
  tmux new-session -d -s "$name" -n edit
  tmux send-keys -t "$name:edit" "vim ." C-m
  tmux split-window -t "$name:edit" -d -l 2
  tmux send-keys -t "$name:edit.2" "$watch" C-m
  tmux new-window -t "$name" -d -n server
  tmux send-keys -t "$name:server" "$serve" C-m
fi
tmux attach-session -t "$name"
