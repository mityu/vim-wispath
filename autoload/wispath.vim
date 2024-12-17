vim9script

final NON_ESCAPED = '\v%(%(\_^|[^\\])%(\\\\)*)@<='
def IsInCmdwin(): bool
  return getcmdwintype() !=# '' && getcmdtype() ==# ''
enddef

def NullExecuter()
enddef
var Executer: func(): void = NullExecuter
def EvalInAlterWin(F: func): any
  var retval: any
  Executer = () => {
    retval = F()
  }
  try
    win_execute(bufwinid('#'), 'call Executer()')
  finally
    Executer = NullExecuter
  endtry
  return retval
enddef

def ExtractTargetPath(line: string): string
  if trim(line) ==# ''
    return ''
  endif
  # TODO: Refer to 'isfname'?
  return split(line, NON_ESCAPED .. '[[:space:]"''=(&]')[-1]
enddef

final PatternFilenameModifiers = NON_ESCAPED .. '%(%(\%|#\d?)\C%(:%([p8~.htreS]|<%(s|gs)>(.)%(.{-}\1){2}))*|#%(#|\<\d))'
def ExpandEnviron(src: string, in_cmdline: bool): string
  if strlen(src) == 0
    return ''
  endif

  var dest = src
  var env = environ()
  dest = substitute(dest, NON_ESCAPED .. '\$[_[:alpha:]]%(\a|\d|-|_)*', (m) => get(env, m[0][1 :], ''), 'g')
  if in_cmdline
    # Expand filename-modifiers
    dest = substitute(dest, PatternFilenameModifiers, (m) => {
      if IsInCmdwin()
        return EvalInAlterWin(function('expand', [m[0]]))
      else
        return expand(m[0])
      endif
    }, 'g')
  endif
  if src[0] ==# '~' && !has('patch-8.2.3550')
    dest = expand('~') .. dest[1 :]
  endif
  return dest
enddef


export def Complete()
  if mode() !=# 'i'
    return
  endif
  var target_path = getline('.')->strpart(0, col('.') - 1)->ExtractTargetPath()
  var is_in_cmdline = getcmdtype() !=# '' || getcmdwintype() !=# ''
  var c = wispath#GetCompletion(target_path, col('.'), is_in_cmdline)
  if empty(c)
    return
  endif
  call('complete', c)
enddef

export def GetCompletion(target_path: string, cursor_col: number, in_cmdline: bool): list<any>
  var completions: list<string>
  if IsInCmdwin()
    completions = EvalInAlterWin(function('getcompletion', [target_path, 'file']))
  else
    completions = getcompletion(target_path, 'file')
  endif
  if empty(completions)
    return []
  endif

  var truncate_len: number
  var truncate_len_buffer: number
  if target_path ==# fnamemodify(target_path, ':t')
    truncate_len = 0
    truncate_len_buffer = 0
  else
    var dir_buffer = fnamemodify(target_path, ':h')  # Directory path as is on buffer.
    var dir = ExpandEnviron(dir_buffer, in_cmdline)  # Expanded directory path.
    while true
      if stridx(completions[0], dir) == 0
        # Additinonal truncation length for path separator.
        const addition = fnamemodify(dir, ':t') ==# '' ? 0 : 1

        truncate_len = strchars(dir) + addition
        truncate_len_buffer = strlen(dir_buffer) + addition
        break
      elseif fnamemodify(dir_buffer, ':t') ==# dir_buffer
        truncate_len = 0
        truncate_len_buffer = 0
        break
      endif

      dir = fnamemodify(dir, ':h')
      dir_buffer = fnamemodify(dir_buffer, ':h')
    endwhile
  endif


  var dirs: list<dict<string>>
  var files: list<dict<string>>
  for path in completions
    var c = path[truncate_len :]
    if fnamemodify(path, ':t') ==# ''
      dirs->add({word: c, menu: '[dir]'})
    else
      files->add({word: c, menu: '[file]'})
    endif
  endfor

  var startcol = cursor_col - strlen(target_path) + truncate_len_buffer

  return [startcol, dirs + files]
enddef

# For testing
export def InternalFuncs_(): dict<func>
  return {
    EvalInAlterWin: funcref('EvalInAlterWin'),
    ExtractTargetPath: funcref('ExtractTargetPath'),
    ExpandEnviron: funcref('ExpandEnviron'),
  }
enddef
