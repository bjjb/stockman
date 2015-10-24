#!/usr/bin/env sh
s=stockman
tmux has-session -t $s
if [ $? != 0 ]
then
  tmux new-session -d -s $s -n edit
  tmux send-keys -t $s:edit "vim ." C-m
  tmux split-window -t $s:edit -d -l 2
  tmux send-keys -t $s:edit.2 "node_modules/.bin/cake watch" C-m
  tmux new-window -t $s -d -n server
  tmux send-keys -t $s:server "npm start" C-m
fi
tmux attach-session -t $s
