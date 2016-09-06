let s:CORE_URL_PREFIX = "http://rawgit.com/nodejs/node/"
let s:CORE_MODULES = ["_debugger", "_http_agent", "_http_client",
	\ "_http_common", "_http_incoming", "_http_outgoing", "_http_server",
	\ "_linklist", "_stream_duplex", "_stream_passthrough", "_stream_readable",
	\ "_stream_transform", "_stream_writable", "_tls_legacy", "_tls_wrap",
	\ "assert", "buffer", "child_process", "cluster", "console", "constants",
	\ "crypto", "dgram", "dns", "domain", "events", "freelist", "fs", "http",
	\ "https", "module", "net", "node", "os", "path", "punycode", "querystring",
	\ "readline", "repl", "smalloc", "stream", "string_decoder", "sys",
	\ "timers", "tls", "tty", "url", "util", "vm", "zlib"]

if !exists("g:js_suffixes")
  let g:js_suffixes = ["js", "json", "coffee", "es6", "es", "jsx", "yml", "css", "less", "md"]
endif

if !exists("g:graft_node_find_variable")
  let g:graft_node_find_variable = 1
endif

function graft#node#load()
  let file = ""
  if graft#node#lineContainsRequire() || graft#node#lineContainsImport()
    let req = graft#node#extractRequiredFilename()
    let file = graft#node#resolveRequiredFile(req)
  endif

  if empty(file) && g:graft_node_find_variable
    let [ var, prop ] = graft#node#getVariableUnderCursor()
    let line = graft#node#findVariableDefinition(var)
    if line != 0
      let req = graft#node#extractRequiredFilenameFrom(getline(line))
      let Callback = graft#createCallback("graft#node#highlightVariableProperty", [prop])
      let file = [ graft#node#resolveRequiredFile(req), Callback ]
    endif
  endif

  return file
endfunction

function graft#node#lineContainsRequire()
  return graft#lineMatches("require")
endfunction

function graft#node#lineContainsImport()
  return graft#lineMatches("import")
endfunction

function graft#node#extractRequiredFilename()
  return graft#node#extractRequiredFilenameFrom(getline('.'))
endfunction

function graft#node#extractRequiredFilenameFrom(line)
  let required = matchlist(a:line, "require[( ]['\"]\\([^'\"]\\+\\)['\"])\\?")
  let imported = matchlist(a:line, "import\\s\\([a-zA-Z0-9_$ s{}-]\\+\\sfrom\\s\\)\\?['\"]\\([^'\"]\\+\\)['\"]")
  let lessimport = matchlist(a:line, "@import \"\\([^\"]\\+\\)\";")

  if len(required) > 1
    return required[1]
  elseif len(imported) > 1
    return empty(imported[2]) ? imported[1] : imported[2]
  elseif len(lessimport)
    return lessimport[1]
  endif
endfunction

function graft#node#resolveRequiredFile(req)
  if !empty(a:req)
    let filename = graft#node#resolveViaRequire(a:req)
    echom filename
    if empty(filename) || !graft#hasPathSeparator(filename)
      let filename = graft#resolveRelativeToCurrentFile(a:req)
      return graft#node#nodeRequireTree(filename, a:req)
    else
      return filename
    endif
  endif
endfunction

" Load a path via node's require.resolve
function graft#node#resolveViaRequire(module)
  let module = a:module
  if module =~ "^\\./\\?$"
    let module = expand("%:h")
  elseif module =~ "^[./]\\+$"
    let module = fnamemodify(module, ":p")
  endif
  " Don't try to require.resolve a built-in module, as that just
  " returns the module name, which we'd then have to look for later
  if !graft#node#isCoreModule(module)
    silent return system("node -e \"
      \ try {
      \   var resolved = require.resolve('" . module . "');
      \   process.stdout.write(resolved);
      \ } catch (e) {
      \   process.stdout.write('')
      \ }\"")
  endif

  return ""
endfunction

function graft#node#isCoreModule(module)
  return index(s:CORE_MODULES, split(a:module, "/")[0]) != -1
endfunction

function graft#node#nodeRequireTree(path, ...)
  let path = a:path
  " If this is already a full path, use that
  if graft#hasExtension(path)
    return path
  endif

  " Trim an end slash so we don't have to worry about
  " ending up with double slashes in paths
  let path = graft#trimTrailingSlash(path)

  " Get any files that match with any extension
  let matched = graft#node#tryNodeExtensions(path)

  " If we found one, end here
  if !empty(matched)
    return matched
  endif

  " If not, see if this path is a directory, and try
  " index files inside that
  if isdirectory(path)
    let matched = graft#node#tryNodeExtensions(path . "/index")
    if !empty(matched)
      return matched
    else
      return ""
    endif
  endif

  if a:0 > 0
    let orig = a:1
    " If the original file has a dot at the beginning and we haven't
    " foudn it yet, it's a local file that hasn't been created
    if graft#isRelativeFilepath(orig)
      " If the directory exists, add the js extension now
      if isdirectory(fnamemodify(path, ":h"))
        return graft#addExtension(path, "js")

      " If the directory doesn't exist but create missing dirs
      " is turned on, create the missing directories, and then
      " add the js extension
      elseif g:graft_create_missing_dirs
        call graft#createMissingDirs(path)
        return graft#addExtension(path, "js")

      " If the directories don't exist and we're not autocreating
      " them, do nothing here and don't keep processing.
      else
        return ""
      endif

    " Check if we're on a built-in module
    elseif graft#node#isCoreModule(orig)
      return s:CORE_URL_PREFIX . graft#node#getVersion() . "/lib/" . orig . ".js"
    endif
  endif
endfunction

function graft#node#tryNodeExtensions(path)
  let matches = glob(a:path . "\.{" . join(g:js_suffixes, ",") . "}", 0, 1)
  if len(matches) > 0
    for ext in g:js_suffixes
      let maybeMatch = match(matches, "\." . ext . "$")
      if maybeMatch > -1
        return matches[maybeMatch]
      endif
    endfor
    
    return matches[0]
  endif
  return ""
endfunction

function graft#node#getVersion()
  silent return split(system("node --version"), "\n")[0]
endfunction

function graft#node#getVariableUnderCursor()
  let cword = expand("<cword>")
  let curIsk = &iskeyword
  setlocal iskeyword+=\.
  let jsword = split(expand("<cword>"), '\.')
  let &iskeyword = curIsk

  if cword == jsword[0]
    return [ cword, '' ]
  else
    return [ jsword[0], cword ]
  endif
endfunction

function graft#node#findVariableDefinition(var)
  let line = search(a:var . " = require", "n")
  if (line == 0)
    let line = search("import " . a:var, "nb")
  endif
  return line
endfunction

function graft#node#highlightVariableProperty(str)
  call search("\\(exports\\.\\|export.*\\)\\zs" . a:str . "\\ze = ")
  call matchadd("Search", a:str)
endfunction
