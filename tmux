#!/usr/bin/env sh
s=stockman
tmux has-session -t $s
if [ $? != 0 ]
then
  tmux new-session -d -s $s -n edit
  tmux send-keys -t $s:edit "vim ." C-m
  tmux split-window -d -l 10
  tmux send-keys -t $s:edit.2 "node_modules/.bin/cake server" C-m
fi
tmux attach-session -t $s
