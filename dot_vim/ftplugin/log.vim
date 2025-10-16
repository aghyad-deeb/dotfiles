" ~/.vim/ftplugin/log.vim
" Only run once per buffer
if exists("b:log_rainbow_loaded")
  finish
endif
let b:log_rainbow_loaded = 1

" Number of distinct colors to cycle through (choose 6 or so)
let s:levels = 6

" Define highlight groups (link to common groups so theme controls color)
" Use highlight default so colorschemes can override if they define these links.
for i in range(1, s:levels)
  execute 'highlight default link RainbowParen' . i . ' Delimiter'
endfor

" When colorscheme changes, re-link (use a set of varied groups to better blend with themes)
augroup LogRainbowColorLinks
  autocmd!
  autocmd ColorScheme * call s:SetupRainbowLinks()
augroup END

function! s:SetupRainbowLinks() abort
  " Link each RainbowParenN to a different conventional group so themes give variety.
  " You can tweak which groups to link to (Delimiter, Identifier, Statement, Type, Special, Constant, etc.)
  let groups = ['Delimiter', 'Identifier', 'Statement', 'Type', 'Special', 'Constant']
  for i in range(1, s:levels)
    let gname = groups[(i - 1) % len(groups)]
    execute 'highlight default link RainbowParen' . i . ' ' . gname
  endfor
endfunction

" storage for match IDs per window-line (dictionary: line -> list of match-ids)
let b:log_rainbow_matches = {}

" Helper: clear matches for a given line number
function! s:ClearLineMatches(lnum) abort
  if has_key(b:log_rainbow_matches, a:lnum)
    for id in b:log_rainbow_matches[a:lnum]
      call matchdelete(id)
    endfor
    call remove(b:log_rainbow_matches, a:lnum)
  endif
endfunction

" Main: scan visible window lines and add matches per bracket with nesting color
function! s:UpdateVisibleRainbow() abort
  " visible window start / end (works for current window)
  let top = line('w0')
  let bot = line('w$')

  " Safety limit: don't scan gigantic ranges
  if bot - top > 1000
    let bot = top + 1000
  endif

  for lnum in range(top, bot)
    " clear previous matches for this line
    call s:ClearLineMatches(lnum)

    let text = getline(lnum)
    if empty(text)
      continue
    endif

    let stack = []
    let matches = []

    " iterate chars; use byte index for columns
    let i = 0
    while i < strlen(text)
      let ch = text[i]
      if ch ==# '(' || ch ==# '[' || ch ==# '{'
        call add(stack, ch)
        let lvl = len(stack)
        let grp = 'RainbowParen' . ((lvl - 1) % s:levels + 1)
        " add match position: [ [lnum, col] ] where col is 1-based
        call add(matches, [lnum, i + 1, 1, grp])
      elseif ch ==# ')' || ch ==# ']' || ch ==# '}'
        " closing bracket: use current stack depth if available (this gives symmetric coloring)
        if !empty(stack)
          let lvl = len(stack)
          call remove(stack, -1)
        else
          let lvl = 1
        endif
        let grp = 'RainbowParen' . ((lvl - 1) % s:levels + 1)
        call add(matches, [lnum, i + 1, 1, grp])
      endif
      let i += 1
    endwhile

    " convert matches into actual matchaddpos() calls and store ids
    if !empty(matches)
      let ids = []
      for m in matches
        " m is [lnum, col, length, group]
        let pos = [[m[0], m[1]]]
        " call matchaddpos with the group's name by building a pattern: use matchaddpos with group name indirectly:
        " matchaddpos() only takes a highlight group name for the pattern name, so use matchaddpos(group, pos)
        " Note: matchaddpos() signature is matchaddpos({group}, {pos}, {priority})
        let id = matchaddpos(m[3], [ [m[0], m[1]] ])
        call add(ids, id)
      endfor
      let b:log_rainbow_matches[lnum] = ids
    endif
  endfor
endfunction

" Update on events that change display or buffer
augroup LogRainbowAutocmds
  autocmd!
  autocmd CursorMoved,CursorMovedI,TextChanged,TextChangedI,InsertLeave,WinScrolled * call s:UpdateVisibleRainbow()
  " update once when buffer is loaded
  autocmd BufWinEnter,FileType log * call s:UpdateVisibleRainbow()
augroup END

" initial link setup and initial run
call s:SetupRainbowLinks()
call s:UpdateVisibleRainbow()

