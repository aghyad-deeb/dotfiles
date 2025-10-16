" ~/.vim/syntax/log.vim
" basic filetype name
if exists("b:current_syntax")
  finish
endif
let b:current_syntax = "log"

" keep any other syntax you want here (keywords, errors, etc.)
" We'll use a ftplugin to do rainbow bracket highlighting dynamically.

