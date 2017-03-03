"
" neovim-fuzzy
"
" Author:       Alexis Sellier <http://cloudhead.io>
" Version:      0.2
"
if exists("g:loaded_fuzzy") || &cp || !has('nvim')
    finish
endif
let g:loaded_fuzzy = 1

if !exists("g:fuzzy_opencmd")
    let g:fuzzy_opencmd = 'edit'
endif

if !exists("g:fuzzy_rootcmds")
    let g:fuzzy_rootcmds = [
                \ 'git rev-parse --show-toplevel',
                \ 'svn info . | grep -F "Working Copy Root Path:"',
                \ 'hg root'
                \ ]
endif

let s:fuzzy_job_id = 0
let s:fuzzy_prev_window = -1
let s:fuzzy_prev_window_height = -1
let s:fuzzy_bufnr = -1
let s:fuzzy_source = {'name': 'abstract'}

" Only suppot unix-like path: /this/is/dir
function! s:strip(str)
    let path = substitute(a:str, '\n*$', '', 'g')
    return matchstr(path, '/\p\{-}\ \?$')
endfunction

function! s:fuzzy_getroot()
    for cmd in g:fuzzy_rootcmds
        let result = system(cmd)
        if v:shell_error == 0
            return s:strip(result)
        endif
    endfor
    return "."
endfunction

function! s:fuzzy_err_noexec()
    throw "Fuzzy: no search executable was found. " .
                \ "Please make sure either '" .  s:ag.path .
                \ "' or '" . s:rg.path . "' are in your path"
endfunction

" Methods to be replaced by an actual implementation.
function! s:fuzzy_source.find(il) dict
    call s:fuzzy_err_noexec()
endfunction

function! s:fuzzy_source.find_contents() dict
    call s:fuzzy_err_noexec()
endfunction

function! s:fuzzy_open_dir(root) abort
    let root = empty(a:root) ? s:fuzzy_getroot() : a:root
    exe 'lcd' root
    " If the list include opened buffer, return here
    " Otherwise, rem this return
    return []

    " Get open buffers.
    let bufs = filter(range(1, bufnr('$')),
                \ 'buflisted(v:val) && bufnr("%") != v:val && bufnr("#") != v:val')
    let bufs = map(bufs, 'expand(bufname(v:val))')
    call reverse(bufs)

    " Add the '#' buffer at the head of the list.
    if bufnr('#') > 0 && bufnr('%') != bufnr('#')
        call insert(bufs, expand(bufname('#')))
    endif

    " Save a list of files the find command should ignore.
    let ignorelist = !empty(bufname('%')) ? bufs + [expand(bufname('%'))] : bufs
    return bufs + ignorelist
endfunction

"
" local from file-list and tags
"
let s:local = { 'name': 'local', 'path': '' }
if !exists('g:fuzzy_file_list')
    let g:fuzzy_file_list = ['cscope.files']
endif
for i in g:fuzzy_file_list
    if filereadable(i)
        let s:local.path = i
        break
    endif
endfor

" @root is a file name
function! s:local.find(root, ignorelist) dict
    return empty(a:root) ?
           \  systemlist('cat '. s:local.path)
           \  : systemlist("grep '". a:root. "' ". s:local.path. "| grep -v '". expand('%'). "'")
endfunction

function! s:local.find_contents(query) dict
    return ["local not support content search."]
endfunction

function! s:local.find_symbol(type, query) dict
    let query= empty(a:query) ? '.' : a:query
    let tagfile = ''
    if !exists('g:fuzzy_file_tag')
        let g:fuzzy_file_tag = ["tagx", ".tagx"]
    endif
    for i in g:fuzzy_file_tag
        if filereadable(i)
            let tagfile = i
            break
        endif
    endfor
    if empty(tagfile)
        throw "tagx file not exist!"
    endif

    " 1 symbol, 0 function
    return a:type == 1 ?
           \  (systemlist("awk '($2 != \"function\" && $1~/"
           \             . query. "/) {$1=$2=\"\"; print $0}' ". tagfile))
           \  : (systemlist("awk '($2 == \"function\" && $1~/"
           \             . query. "/) {$1=$2=\"\"; print $0}' ". tagfile))
endfunction

"
" ag (the silver searcher)
"
let s:ag = { 'name': 'ag', 'path': 'ag' }

function! s:ag.find(root, ignorelist) dict
    return systemlist(s:ag.path . " -l --silent --nocolor -g ''")
endfunction

function! s:ag.find_contents(query) dict
    let query = empty(a:query) ? '^(?=.)' : a:query
    return systemlist(s:ag.path . " --noheading --nogroup --nocolor -S " . shellescape(query) . " .")
endfunction

function! s:ag.find_symbol(type, query) dict
    return s:ag.find_contents(a:query)
endfunction
"
" rg (ripgrep)
"
let s:rg = { 'name': 'rg', 'path': 'rg' }

function! s:rg.find(root, ignorelist) dict
    let path = '.'
    let ignorelist += a:ignorelist
    let ignores = []
    for str in ignorelist
        call add(ignores, printf("-g '!%s'", str))
    endfor
    return systemlist(s:rg.path . " --color never --files --fixed-strings " . join(ignores, ' ') . ' ' . path . ' 2>/dev/null')
endfunction

function! s:rg.find_contents(query) dict
    let query = empty(a:query) ? '.' : shellescape(a:query)
    return systemlist(s:rg.path . " -n --no-heading --color never -S " . query . " . 2>/dev/null")
endfunction

function! s:rg.find_symbol(type, query) dict
    return s:rg.find_contents(a:query)
endfunction

" Set the finder based on available binaries.
function! s:fuzzy_init()
    let cdir = fnamemodify('.', ':p:h')
    if cdir ==# $HOME || cdir ==# '/'
        echomsg "Fuzzy refuse working for cwd=". cdir
        return 0
    endif
    if len(split(cdir, '/')) < 3
        let ans = input("Fuzzy on ". cdir. " ? ", "Yes|No")
        if ans !=# 'Yes'
            return 0
        endif
    endif

    if !empty(s:local.path)
        let s:fuzzy_source = s:local
    elseif executable(s:rg.path)
        let s:fuzzy_source = s:rg
    elseif executable(s:ag.path)
        let s:fuzzy_source = s:ag
    else
        echomsg "Fuzzy cann't find fuzzy-instance."
        return 0
    endif
    return 1
endfunction

command! -nargs=? FuzzyGrep   call s:fuzzy_grep(<q-args>)
command! -nargs=? FuzzyFunc   call s:fuzzy_symbol(0, <q-args>)
command! -nargs=? FuzzySymb   call s:fuzzy_symbol(1, <q-args>)
command! -nargs=? FuzzyOpen   call s:fuzzy_open(<q-args>)
command!          FuzzyKill   call s:fuzzy_kill()

autocmd FileType fuzzy tnoremap <buffer> <Esc> <C-\><C-n>:FuzzyKill<CR>

function! s:fuzzy_kill()
    echo
    call jobstop(s:fuzzy_job_id)
endfunction

function! s:fuzzy_grep(str) abort
    if s:fuzzy_init() == 0
        return
    endif

    let contents = []
    try
        let contents = s:fuzzy_source.find_contents(a:str)
    catch
        echoerr v:exception
        return
    endtry
    if empty(contents)
        return
    endif

    let opts = { 'lines': 12, 'statusfmt': 'FuzzyGrep %s (%d '. s:fuzzy_source.name. ')', 'root': '.' }

    function! opts.handler(result) abort
        let parts = split(join(a:result), ':')
        let name = parts[0]
        let lnum = parts[1]
        let text = parts[2] " Not used.

        return { 'name': name, 'lnum': lnum }
    endfunction

    return s:fuzzy(contents, opts)
endfunction

function! s:fuzzy_symbol(type, str) abort
    if s:fuzzy_init() == 0
        return
    endif
    if s:fuzzy_source.name !=# 'local'
        if a:type == 0
            echomsg "Fuzzy '". s:fuzzy_source.name. "' cann't implemate function."
            return
        endif
    endif

    let contents = []
    try
        let contents = s:fuzzy_source.find_symbol(a:type, a:str)
    catch
        echoerr v:exception
        return
    endtry
    if empty(contents)
        return
    endif

    if s:fuzzy_source.name ==# 'local'
        let opts = { 'lines': 12,
                    \ 'statusfmt': (a:type == 0 ? 'fzyFunction' : 'fzySymbol'). ' %s (%d '. s:fuzzy_source.name. ')',
                    \ 'root': '.' }

        function! opts.handler(result) abort
            let parts = split(join(a:result), ' ')
            let name = parts[1]
            let lnum = parts[0]
            let text = join(parts[2:]) " Not used.

            return { 'name': name, 'lnum': lnum, 'text': text }
        endfunction
    else
        let opts = { 'lines': 12, 'statusfmt': 'FuzzyGrep %s (%d '. s:fuzzy_source.name. ')', 'root': '.' }

        function! opts.handler(result) abort
            let parts = split(join(a:result), ':')
            let name = parts[0]
            let lnum = parts[1]
            let text = parts[2] " Not used.

            return { 'name': name, 'lnum': lnum }
        endfunction
    endif

    return s:fuzzy(contents, opts)
endfunction


function! s:fuzzy_open_file(root, file, lnum) abort
    let ffile = isdirectory(a:root) ?
                \  (a:root[-1:] == '/' ?
                \    (a:root . expand(fnameescape(a:file)))
                \    : (a:root. '/'. expand(fnameescape(a:file))))
                \  : expand(fnameescape(a:file))

    if !filereadable(ffile)
        echomsg 'Fuzzy openfile fail: ' ffile
        return
    endif
    silent execute g:fuzzy_opencmd ffile
    if !empty(a:lnum)
        silent execute a:lnum
        normal! zz
    endif
endfunction


function! s:fuzzy_open(root) abort
    if s:fuzzy_init() == 0
        return
    endif
    let root = '.'
    let result = []
    try
        let root = empty(a:root) ? s:fuzzy_getroot() : a:root
        if root !=# '.' && isdirectory(root)
            exe 'lcd' root
        endif

        let result = s:fuzzy_source.find(a:root, [])
        let result_len = len(result)
        if result_len == 0
            let result = []
        elseif result_len == 1
            call s:fuzzy_open_file('', join(result), '')
            let result = []
        endif
    catch
        echoerr v:exception
    finally
        if root !=# '.' && isdirectory(root)
            lcd -
        endif
    endtry

    if empty(result)
        return
    endif
    " multiple result feed to fuzzy
    let opts = { 'lines': 12, 'statusfmt': 'FuzzyOpen %s (%d '. s:fuzzy_source.name. ')', 'root': root }
    function! opts.handler(result)
        return { 'name': join(a:result) }
    endfunction

    return s:fuzzy(result, opts)
endfunction

function! s:fuzzy(choices, opts) abort
    let inputs = tempname()
    let outputs = tempname()

    if !executable('fzy')
        echoerr "Fuzzy: the executable 'fzy' was not found, https://github.com/jhawthorn/fzy"
        return
    endif

    " Clear the command line.
    echo

    call writefile(a:choices, inputs)

    let command = "fzy -l " . a:opts.lines . " > " . outputs . " < " . inputs
    let opts = { 'outputs': outputs, 'handler': a:opts.handler, 'root': a:opts.root }

    function! opts.on_exit(id, code, _event) abort
        " NOTE: The order of these operations is important: Doing the delete first
        " would leave an empty buffer in netrw. Doing the resize first would break
        " the height of other splits below it.
        call win_gotoid(s:fuzzy_prev_window)
        exe 'silent' 'bdelete!' s:fuzzy_bufnr
        exe 'resize' s:fuzzy_prev_window_height

        if a:code != 0 || !filereadable(self.outputs)
            return
        endif

        let result = readfile(self.outputs)
        if !empty(result)
            let file = self.handler(result)
            let lnum = ''
            if has_key(file, 'lnum')
                let lnum = file.lnum
            endif
            call s:fuzzy_open_file(self.root, file.name, lnum)
        endif
    endfunction

    let s:fuzzy_prev_window = win_getid()
    let s:fuzzy_prev_window_height = winheight('%')

    if bufnr(s:fuzzy_bufnr) > 0
        exe 'keepalt' 'below' a:opts.lines . 'sp' bufname(s:fuzzy_bufnr)
    else
        exe 'keepalt' 'below' a:opts.lines . 'new'
        let s:fuzzy_job_id = termopen(command, opts)
        let b:fuzzy_status = printf(
                    \ a:opts.statusfmt,
                    \ fnamemodify(opts.root, ':~:.'),
                    \ len(a:choices))
        setlocal statusline=%{b:fuzzy_status}
    endif
    let s:fuzzy_bufnr = bufnr('%')
    set filetype=fuzzy
    startinsert
endfunction

