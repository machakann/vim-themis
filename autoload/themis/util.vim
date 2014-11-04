" themis: Utility functions.
" Version: 1.3
" Author : thinca <thinca+vim@gmail.com>
" License: zlib License

let s:save_cpo = &cpo
set cpo&vim

function! themis#util#callstacklines(throwpoint, ...)
  let infos = call('themis#util#callstack', [a:throwpoint] + a:000)
  return map(infos, 'themis#util#funcinfo_format(v:val)')
endfunction

function! themis#util#callstack(throwpoint, ...)
  let this_stacks = themis#util#parse_callstack(expand('<sfile>'))[: -2]
  let throwpoint_stacks = themis#util#parse_callstack(a:throwpoint)
  let start = a:0 ? len(this_stacks) + a:1 : 0
  if len(throwpoint_stacks) <= start ||
  \  this_stacks[0] != throwpoint_stacks[0]
    let start = 0
  endif
  let error_stack = throwpoint_stacks[start :]
  return map(error_stack, 'themis#util#funcinfo(v:val)')
endfunction

function! themis#util#parse_callstack(callstack)
  let callstack_line = matchstr(a:callstack, '^\%(function\s\+\)\?\zs.*')
  if callstack_line =~# ',.*\d'
    let pat = '^\(.\+\),.\{-}\(\d\+\)'
    let [callstack_line, line] = matchlist(callstack_line, pat)[1 : 2]
  else
    let line = 0
  endif
  let stack_info = split(callstack_line, '\.\.')
  call map(stack_info, '{"function": v:val, "line": 0}')
  let stack_info[-1].line = line - 0
  return stack_info
endfunction

function! themis#util#funcinfo_format(funcinfo)
  if !a:funcinfo.exists
    return printf('function %s()  This function is already deleted.',
    \             a:funcinfo.funcname)
  endif

  if a:funcinfo.signature ==# ''
    " This is a file.
    return printf('%s Line:%d', a:funcinfo.filename, a:funcinfo.line)
  endif
  let result = a:funcinfo.signature
  if a:funcinfo.line
    let result .= '  Line:' . a:funcinfo.line
  endif
  return result . '  (' . a:funcinfo.filename . ')'
endfunction

function! themis#util#funcinfo(stack)
  let f = a:stack.function
  let line = a:stack.line
  if themis#util#is_funcname(f)
    let data = themis#util#funcdata(f)
    let data.line = line
    return data
  elseif filereadable(f)
    return {
    \   'exists': 1,
    \   'funcname': f,
    \   'signature': '',
    \   'filename': f,
    \   'line': line,
    \ }
  else
    return {}
  endif
endfunction

function! themis#util#funcdata(func)
  let func = type(a:func) == type(function('type')) ?
  \          themis#util#funcname(a:func) : a:func
  let fname = func =~# '^\d\+' ? '{' . func . '}' : func
  if !exists('*' . fname)
    return {
    \   'exists': 0,
    \   'funcname': func,
    \ }
  endif
  redir => body
  silent execute 'verbose function' fname
  redir END
  let lines = split(body, "\n")
  let signature = matchstr(lines[0], '^\s*\zs.*')
  let file = matchstr(lines[1], '^\s*Last set from\s*\zs.*$')
  let file = substitute(file, '[/\\]\+', '/', 'g')
  let arguments = split(matchstr(signature, '(\zs.*\ze)'), '\s*,\s*')
  let has_extra_arguments = get(arguments, -1, '') ==# '...'
  let arity = len(arguments) - (has_extra_arguments ? 1 : 0)
  return {
  \   'exists': 1,
  \   'filename': file,
  \   'funcname': func,
  \   'signature': signature,
  \   'arguments': arguments,
  \   'arity': arity,
  \   'has_extra_arguments': has_extra_arguments,
  \   'is_dict': signature =~# ').*dict',
  \   'is_abort': signature =~# ').*abort',
  \   'has_range': signature =~# ').*range',
  \   'body': lines[2 : -2],
  \ }
endfunction

function! themis#util#funcline(target, lnum)
  if themis#util#is_funcname(a:target)
    let data = themis#util#funcdata(a:target)
    " XXX: More improve speed
    for line in data.body
      if line =~# '^' . a:lnum
        let num_width = a:lnum < 1000 ? 3 : len(a:lnum)
        return line[num_width :]
      endif
    endfor
  elseif filereadable(a:target)
    let lines = readfile(a:target, '', a:lnum)
    return empty(lines) ? '' : lines[-1]
  endif
  return ''
endfunction

function! themis#util#error_info(stacktrace)
  let tracelines = map(copy(a:stacktrace), 'themis#util#funcinfo_format(v:val)')
  let tail = a:stacktrace[-1]
  if has_key(tail, 'funcname')
    let line_str = themis#util#funcline(tail.funcname, tail.line)
    let error_line = printf('%d: %s', tail.line, line_str)
    let tracelines += [error_line]
  endif
  return join(tracelines, "\n")
endfunction

function! themis#util#is_funcname(name)
  return a:name =~# '\v^%(\d+|%(\u|g:\u|s:|\<SNR\>\d+_)\w+|\h\w*%(#\w+)+)$'
endfunction

function! themis#util#funcname(funcref)
  return matchstr(string(a:funcref), '^function(''\zs.*\ze'')$')
endfunction

function! themis#util#get_full_title(obj, ...)
  let obj = a:obj
  let titles = a:0 ? a:1 : []
  call insert(titles, obj.get_title())
  while has_key(obj, 'parent')
    let obj = obj.parent
    call insert(titles, obj.get_title())
  endwhile
  return join(filter(titles, 'v:val !=# ""'), ' ')
endfunction

function! themis#util#sortuniq(list)
  call sort(a:list)
  let i = len(a:list) - 1
  while 0 < i
    if a:list[i] == a:list[i - 1]
      call remove(a:list, i)
    endif
    let i -= 1
  endwhile
  return a:list
endfunction

function! themis#util#find_files(paths, filename)
  let todir =  'isdirectory(v:val) ? v:val : fnamemodify(v:val, ":h")'
  let dirs = map(copy(a:paths), todir)
  let mod = ':p:gs?\\\+?/?:s?/$??'
  call map(dirs, 'fnamemodify(v:val, mod)')
  let files = findfile(a:filename, join(map(dirs, 'v:val . ";"'), ','), -1)
  return themis#util#sortuniq(files)
endfunction


let &cpo = s:save_cpo
unlet s:save_cpo
