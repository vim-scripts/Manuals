" vim:set fileencoding=utf-8 sw=3 ts=8 et:vim
"
" Author: Marko Mahnič
" Created: March 2010
" License: GPL (http://www.gnu.org/copyleft/gpl.html)
" This program comes with ABSOLUTELY NO WARRANTY.

if vxlib#plugin#StopLoading('#au#manuals#search')
   finish
endif


" Getters

function! s:SmartCapture(cmd) " TODO: vxlib#cmd#SmartCapture()
   let t1 = []
   if has('gui_running') != 0
      let t1 = vxlib#cmd#Capture(a:cmd, 1)
   else
      if a:cmd =~ '^\s*!'
         let t1 = vxlib#cmd#CaptureShell(a:cmd)
      else
         let t1 = vxlib#cmd#Capture(a:cmd, 1)
      endif
   endif
   "let captured = []
   "for line in t1
   "   call add(s:captured, vxlib#cmd#ReplaceCtrlChars(line))
   "endfor
   return t1
endfunc

function! s:VimHelpScore(tag, srch)
   " exact match
   if a:tag == a:srch | return 10 | endif

   " vim object match
   if a:tag =~ '^[:+>]' . a:srch . '$' | return 9 | endif
   if a:tag == a:srch . '()' | return 9 | endif
   if a:tag == '''' . a:srch . '''' | return 9 | endif
   if a:tag == '''no' . a:srch . '''' | return 9 | endif

   " vim object prefix match
   if a:tag =~ '^[:+>'']' . a:srch | return 6 | endif
   if a:tag =~ '^''no' . a:srch | return 6 | endif

   " vim object postfix match
   if a:tag =~ a:srch . '()$' | return 4 | endif
   if a:tag =~ a:srch . '''$' | return 4 | endif

   " any vim objects come first
   if a:tag =~ '^[:''+]' | return 3 | endif

   " prefix match
   if a:tag =~ '^' . a:srch | return 2 | endif

   return 1
endfunc

let s:helpword=''
function! s:VimHelpCompare(i1, i2)
   let s1 = s:VimHelpScore(a:i1, s:helpword)
   let s2 = s:VimHelpScore(a:i2, s:helpword)
   if s1 > s2 | return -1 | endif
   if s1 < s2 | return 1 | endif
   return a:i1 == a:i2 ? 0 : a:i1 > a:i2 ? 1 : -1
endfunc

function! s:GetBufferNumbers()
   let buffs = vxlib#cmd#Capture('ls!', 1)
   call map(buffs, '0 + matchstr(v:val, ''\s*\zs\d\+\ze'')')
   return buffs
endfunc

" safely wipeout buffers
function! s:WipeoutBuffers(buflist)
   for bnr in a:buflist
      " getbufvar(bnr, '&filetype') == 'help' && " not working for never-loaded buffers
      if bufexists(bnr) && !buflisted(bnr) && bufwinnr(bnr) == -1 && ! getbufvar(bnr, '&modified')
         silent! exec "bwipeout " . bnr
      endif
   endfor
endfunc

" Keep the buffers from the list and (safely) wipeout others
function! s:KeepBuffers(buflist)
   let newlist = s:GetBufferNumbers()
   let bufdict = {}
   for bnr in a:buflist
      let bufdict[bnr] = 1
   endfor
   let rmlist=[]
   for bnr in newlist
      if !has_key(bufdict, bnr) 
         call add(rmlist, bnr)
      endif
   endfor
   if len(rmlist) > 0
      call s:WipeoutBuffers(rmlist)
   endif
endfunc


" id=getter-function
" w1 - word under cursor
" w2 - section (eg. command range)
" kind - what to do (t-find text, k-find keywords/tags, g-grep text)
" getterDef - an entry from VxlibManual_Getters; may contain additional parameters
" TODO: displayDef - where will the results be diplayed; may influence the result-type
" @returns ['kind/type', data, filetype]
"       type: a set of flags (eg. 'tl'): @see <url:manuals.vim#flagdefs>
"       filetype: suggested filetype when the result (full text) is displayed
"          in a vim buffer
function! manuals#search#VimHelp(w1, w2, kind, getter, displayer, ...)
   let result = ['']
   if a:kind == 'k'
      let tmpbuf='***ManualsHelpType***'
      try
         " use a temp help buffer to build the taglist
         " (because taglist() uses a buffer-local setting)
         silent! exec 'edit ' . tmpbuf
         setl filetype=help
         let tagfiles=globpath(&rtp, "doc/tags")
         let tagfiles=escape(tagfiles, ', \')
         let tagfiles=join(split(tagfiles, "\n"), ',')
         let &l:tags=tagfiles
         setl buftype=nofile
         let htags=taglist(a:w1)
         let htlist = []
         for ht in htags
            call add(htlist, ht.name)
         endfor
         let s:helpword = a:w1
         call sort(htlist, "s:VimHelpCompare")
         " call map(htlist, 'v:val . " " . s:VimHelpScore(v:val, s:helpword)') " debug
         " echom a:w1 . " " . len(htags)
         let result=['kl', htlist, '']
      finally
         setl nomodified
         silent! exec 'bwipeout ' . tmpbuf
      endtry
   elseif a:kind == 'g'
      let curbuf = bufnr("%")
      try
         let knownbufs=s:GetBufferNumbers()
         silent! exec "helpgrep " . a:w1
         " possible results are in quickfix list; TODO: maybe a loaction list should be used, lhelpgrep
         let items = getqflist()

         if len(items) < 1
            let result = ['']
         else
            let [ids, gritems] = vxlib#cmd#TransformQFixItems(items)
            unlet items
            " unload quickfix files (make a list before helpgrep, remove new entries)
            " TODO: clearing quickfix depends on the type of displayer; if
            " displayer IS quickfix, keep the list and the unlisted buffers
            call s:KeepBuffers(knownbufs)
            call setqflist([])
            let result = ['hl', gritems, '']
         endif
      finally
         if curbuf != bufnr("%") && &filetype=='help'
            bwipeout 
         endif
      endtry
   else
      silent! exec "help " . a:w1
      let result = ['']
   endif
   return result
endfunc

function! s:FindHelpWindow()
   let ihelp = -1
   let nwin = winnr('$')
   for iw in range(nwin)
      let ibuf = winbufnr(iw+1)
      let bt=getbufvar(ibuf, '&buftype')
      if bt=='help'
         let ihelp = iw+1
         return ihelp
      endif
   endfor
   if ihelp < 0
      for iw in range(nwin)
         let ibuf = winbufnr(iw+1)
         let bt=getbufvar(ibuf, '&filetype')
         if bt=='help'
            let ihelp = iw+1
            return ihelp
         endif
      endfor
   endif
 
   return ihelp
endfunc

function! s:FindTagFiles(roots, tagfiles)
   let tagfiles=globpath(a:roots, a:tagfiles)
   let tagfiles=escape(tagfiles, ', \')
   let tagfiles=join(split(tagfiles, "\n"), ',')
   return tagfiles
endfunc

function! s:MakeTmpHelpBuf(tagfiles, createwin)
   if a:createwin
      let iwhelp = s:FindHelpWindow()
      if iwhelp >= 0
        silent! exec iwhelp . ' wincmd w'
      else
         silent! help
      endif
   endif
   let name = '***ManualsHelpType***'
   silent! exec 'edit ' . name
   let bufnr=bufnr(name)
   let &l:tags=a:tagfiles
   setl buftype=nofile readonly nomodifiable nobuflisted
   return bufnr
endfunc

let s:helpAutocmdsSet = {}

" Get help from files in vimhelp format that are stored in non-standard locations
" HACK: a temporary buffer is created with &l:tags set so that the correct
"       tags are used. The commands :tag, taglist() and (not yet) :vimgrep are
"       used instead of :help, :h_Ctrl-D and :helpgrep. Only .txt extension is
"       supported.
function! manuals#search#ExternVimHelp(w1, w2, kind, getter, displayer, ...)
   if !has_key(a:getter, 'params')
      return manuals#search#VimHelp(a:w1, a:w2, a:kind, a:getter, a:displayer)
   endif

   let curbuf = bufnr('%')
   let opts = a:getter.params

   " we need autocmds to set ft&ro for files from opts.helpdirs
   if !has_key(s:helpAutocmdsSet, opts.helpdirs)
      for adir in split(opts.helpdirs, ',')
         exec 'autocmd BufEnter ' . adir . 
                  \ '/*.txt setl ft=help readonly nomodifiable nobuflisted isk=!-~,^*,^\|,^\"'
      endfor
      let s:helpAutocmdsSet[opts.helpdirs] = 1
   endif

   let result = ['']
   if a:kind == 't'
      try
         let wincreated = 0
         let tagfiles = s:FindTagFiles(opts.helpdirs, 'tags')
         if tagfiles == &l:tags
            let tmpbuf = -1
         else
            let nw = winnr('$')
            let tmpbuf = s:MakeTmpHelpBuf(tagfiles, 1)
            let wincreated = (nw != winnr('$'))
         endif
         try
            " if :tag doesn't find a tag, an exception is thrown
            silent! exec "tag " . a:w1

            " XXX: another Vim nightmare: if buftype=help is not set, we will end
            " up with multiple help windows; if buftype is set, vim uses tags
            " from its own help system.
            " (according to <url:vimhelp:special-buffers> ) buftype=help can't be set)
            " exec 'setl buftype=help readonly tags=' . tagfiles
            " Alternative: use local variable to distinguish types
            let &l:tags=tagfiles
            let b:manual_type = 'extern-help'

            " Save the setings for current extern-help file so that they can
            " be used by the _choosevimhelp getter.
            let b:manual_options = opts
         catch /.*/
         endtry
      finally
         if bufnr('%') == tmpbuf && !wincreated
            " a tag was not found, tmpbuf is still active
            "    => select curbuf to keep the window after bwipeout
            "       but only if it wasn't created by MakeTmpHelpBuf
            silent! exec 'b ' . curbuf
         endif
         if tmpbuf >= 0
            " silent! exec 'bwipeout! ' . tmpbuf
            silent! exec 'bdelete! ' . tmpbuf
         endif
      endtry
   elseif a:kind == 'k'
      try
         let tagfiles = s:FindTagFiles(opts.helpdirs, 'tags')
         if tagfiles == &l:tags
            let tmpbuf = -1
         else
            let tmpbuf = s:MakeTmpHelpBuf(tagfiles, 0)
         endif
         let htags=taglist(a:w1)
         let htlist = []
         for ht in htags
            call add(htlist, ht.name)
         endfor
         let s:helpword = a:w1
         call sort(htlist, "s:VimHelpCompare")
         let result=['kl', htlist, '']
      finally
         if tmpbuf >= 0
            silent! exec 'bwipeout! ' . tmpbuf
         endif
      endtry
   elseif a:kind == 'g'
      let dirs = split(opts.helpdirs, ',')
      if len(dirs) > 0
         let parms = ''
         for adir in dirs
            let parms = parms . ' ' . adir . '/*.txt'
         endfor
         let knownbufs = s:GetBufferNumbers()
         exec "vimgrep /" . a:w1 . '/ ' . parms
         let items = getqflist()

         " TODO: maybe qfixlist should be converted to list in ShowManual and the
         " buffers should not be removed
         if len(items) < 1
            let result = ['']
         else
            let [ids, gritems] = vxlib#cmd#TransformQFixItems(items)
            call s:KeepBuffers(knownbufs)
            call setqflist([])
            let result = ['hl', gritems, '']
         endif
      endif
   endif

   return result
endfunc


" Handler for files with filetype=help that chooses between normal vim help
" and extern help handler. The decision depends on the contents of
" buffer-local variables.
function! manuals#search#ChooseVimHelp(w1, w2, kind, getter, displayer, ...)
   if exists('b:manual_type') && b:manual_type == 'extern-help'
      let hfunc = 'manuals#search#ExternVimHelp'
      if exists('b:manual_options')
         let a:getter.params = b:manual_options
      endif
   else
      let hfunc = 'manuals#search#VimHelp'
   endif
   " echom "Chosen: " . hfunc
   let vparms = ''
   for i in range(a:0)
      let vparms = vparms . ', a:' . (i+1)
   endfor
   silent! exec 'let rslt=' . hfunc . '(a:w1, a:w2, a:kind, a:getter, a:displayer' . vparms . ')'
   return rslt
endfunc


call vxlib#plugin#CheckSetting('g:manuals_prg_man',
         \ '"!MANWIDTH=${width} man -P cat ${section} ${word} | col -b"')
call vxlib#plugin#CheckSetting('g:manuals_max_man_width', '80')
function! manuals#search#Man(w1, count, kind, getter, displayer, ...)
   let section = ''
   let cmd = g:manuals_prg_man
   if has_key(a:getter, 'params')
      let opts = a:getter.params
      if opts.has_key('cmd') | let cmd = opts.cmd | endif
      if opts.has_key('section') | let section = opts.section | endif
   elseif a:count > 0 
      let section = '' . a:count
   endif

   let mw = &columns - 20
   if mw > g:manuals_max_man_width | let mw = g:manuals_max_man_width | endif
   if mw < 20 | let mw = 20 | endif
   if mw > &columns | let mw = &columns | endif

   if section != '' | let section = '-S ' . section | endif
   " let cmd = '!MANWIDTH=' . mw . ' man -P cat ' . section . a:w1 . ' | col -b'
   let cmd = substitute(cmd, '\${width}', mw, '')
   let cmd = substitute(cmd, '\${section}', section, '')
   let cmd = substitute(cmd, '\${word}', a:w1, '')
   let page = s:SmartCapture(cmd)
   if len(page) < 2 || page[1] =~ "No manual entry"
      return ['w', "No manual entry for " . a:w1]
   endif
   return ['tl', page, '']
endfunc


call vxlib#plugin#CheckSetting('g:manuals_prg_pydoc', '"pydoc"')
" if w2 is nonzero, the search can be interactive: pass -k to pydoc to find
" keywords and display a list of matches; then select an entry in the list to
" display help for that item; requires an interactive viewer (list on first
" level, text on second level).
function! manuals#search#Pydoc(w1, w2, kind, getter, displayer, ...)
   let type = a:kind . 'l'
   if a:kind == 'g'
      let cmd = '!' . g:manuals_prg_pydoc . ' -k ' . a:w1
   else
      let cmd = '!' . g:manuals_prg_pydoc . ' ' . a:w1
   endif
   let rslt = s:SmartCapture(cmd)
   if len(rslt) < 1 || match(rslt[0], 'no Python documentation found for') == 0
      let rslt = []
      let type = ''
   endif
   return [type, rslt, '']
endfunc


call vxlib#plugin#CheckSetting('g:manuals_prg_grep', '"grep"')
" TODO (maybe) '"!grep -e \"${word}\" ${files}"'
function! manuals#search#Pydiction(w1, w2, kind, getterer, displayer, ...)
   let type = a:kind . 'l'
   if a:kind != 'k'
      return ['e', 'Invalid getter mode ' . a:kind . '.']
   endif
   if exists('g:pydiction_location') && filereadable(g:pydiction_location)
      let dictfile = g:pydiction_location
   else
      let dictfile = g:vxlib_manuals_directory . "/pydiction/complete-dict"
   endif
   if ! filereadable(dictfile)
      return ['e', 'g:pydiction_location not set or file not readable.']
   endif

   " TODO: special behaviour if vimgrep is used
   let cmd = '!' . g:manuals_prg_grep .' -e "' . escape(a:w1, ' \"()') . '" ' . escape(dictfile, ' \')
   let capt = s:SmartCapture(cmd)
   if len(capt) > 0 && len(capt) < 4 && capt[2] =~ '\Cshell\s*returned' 
      return ['tl', ['Pydiction', 'No matches found for "' . a:w1 . '"'], '']
   elseif len(capt) > 0
      let rslt = []
      for word in capt
         let kword = matchstr(word, '^\%(\w\|\.\)\+')
         if kword == '' | continue | endif
         " Doesn't work well ... and it's slow
         "let descr = s:SmartCapture('!pydoc ' . kword) 
         "if len(descr) > 4 && match(descr[1], 'no Python documentation found for') < 0
         "   call add(rslt, kword . "\t" . descr[4])
         "endif
         call add(rslt, kword)
      endfor
      call sort(rslt)
      return [type, rslt, '']
   endif
   return ['']
endfunc


call vxlib#plugin#CheckSetting('g:manuals_prg_dict', '"dict"')
function! manuals#search#Dict(w1, w2, kind, getter, displayer, ...)
   if a:kind != 't'
      return ['e', 'Invalid getter mode ' . a:kind . '.']
   endif
   let type = 'tl'
   let cmd = '!' . g:manuals_prg_dict . ' ' . a:w1
   let rslt = s:SmartCapture(cmd)
   "if len(rslt) < 2 || match(rslt[1], 'No definitions found') == 0
   "   return ['w', 'No definitions found']
   "endif
   return [type, rslt, '']
endfunc

" =========================================================================== 
" Global Initialization - Processed by Plugin Code Generator
" =========================================================================== 
finish

" a utility function that is copied to the beginning of a generated plugin script
" <PLUGINFUNCTION id="manuals#addgetter" name="VxMan_AddGetter">
if !exists("g:VxlibManuals_NewGetters")
   let g:VxlibManuals_NewGetters = []
endif
function! s:VxMan_AddGetter(getterdef)
   call add(g:VxlibManuals_NewGetters, a:getterdef)
endfunc
" </PLUGINFUNCTION>

" <PLUGINFUNCTION id="manuals#addcontexts" name="VxMan_AddContexts">
if !exists("g:VxlibManuals_NewContexts")
   let g:VxlibManuals_NewContexts = []
endif
function! s:VxMan_AddContexts(contexts, getters)
   call add(g:VxlibManuals_NewContexts, [a:contexts, a:getters])
endfunc
" </PLUGINFUNCTION>

" TODO: (maybe) s:AddGetter may accept a function that verifies if it is possible
" to use the getter; if not, the getter is not added to the VxlibManual_Getters
" eg. in case of dict it verifies if dict is installed.
" (late inititalization/verification)
" <VIMPLUGIN id="manuals#search" >
   if !exists("g:vxlib_manuals_directory")
      let rtp0 = split(&rtp, ',')[0]
      let g:vxlib_manuals_directory = expand(rtp0 . "/manuals")
   endif

   call s:VxMan_AddGetter(['vimhelp', 'tkg', 'manuals#search#VimHelp', 'Get Vim Help.'])
   call s:VxMan_AddGetter(['extvimhelp>vimhelp', 'tkg', 'manuals#search#ExternVimHelp', 'Get Help in Vim Format.'])
   call s:VxMan_AddGetter(['_choosevimhelp>vimhelp', 'tkg', 'manuals#search#ChooseVimHelp', 'Get Help in Vim Format.'])
   call s:VxMan_AddGetter(['pydoc', 'tg', 'manuals#search#Pydoc', 'Get help for current word using pydoc.'])
   call s:VxMan_AddGetter(['man', 't', 'manuals#search#Man', 'Get a man entry for current word.'])
   call s:VxMan_AddGetter(['dict', 't', 'manuals#search#Dict', 'Get a dictionary entry for current word.'])

   call s:VxMan_AddContexts(['vim'], ['vimhelp'])
   call s:VxMan_AddContexts(['help'], ['_choosevimhelp'])
   call s:VxMan_AddContexts(['python'], ['pydoc'])
   call s:VxMan_AddContexts(['sh'], ['man'])
   call s:VxMan_AddContexts(['*/*comment', '*/*string', 'text', 'tex', '*'], ['dict'])

   if exists('g:pydiction_location') && filereadable(g:pydiction_location)
            \ || filereadable(g:vxlib_manuals_directory . "/pydiction/complete-dict")
      " pydiction(850)
      call s:VxMan_AddGetter(['pydiction', 'k', 'manuals#search#Pydiction',
               \ 'Get a list of symbols using pydiction complete-dict.'])
      call s:VxMan_AddContexts(['python'], ['pydiction'])
   endif

   if filereadable(g:vxlib_manuals_directory . '/cmakeref/cmakecmds.txt')
      " cmakeref(3045)
      let s:hdir = g:vxlib_manuals_directory . '/cmakeref'
      call s:VxMan_AddGetter(['cmakeref>extvimhelp', 'tkg', 'manuals#search#ExternVimHelp',
               \ 'Get help for CMake.',
               \ { 'helpdirs': s:hdir, 'helpext': '.txt' }
               \ ]) " XXX { helpext: } unused, defaults to .txt
      call s:VxMan_AddContexts(['cmake'], ['cmakeref'])
      unlet s:hdir
   endif

   if filereadable(g:vxlib_manuals_directory . '/cssref/css21.txt')
      " css21(918)
      let s:hdir = g:vxlib_manuals_directory . '/cssref'
      call s:VxMan_AddGetter(['cssref>extvimhelp', 'tkg', 'manuals#search#ExternVimHelp',
               \ 'Get help for CSS.',
               \ { 'helpdirs': s:hdir }
               \ ])
      call s:VxMan_AddContexts(['css', 'html*/css*', 'xhtml/*.css'], ['cssref'])
      unlet s:hdir
   endif

   if filereadable(g:vxlib_manuals_directory . '/crefvim/crefvim.txt')
      " crefvim(614)
      " TODO: stlref(2353) can be put in the same dir
      let s:hdir = g:vxlib_manuals_directory . '/crefvim'
      call s:VxMan_AddGetter(['crefvim>extvimhelp', 'tkg', 'manuals#search#ExternVimHelp',
               \ 'Get help for C.',
               \ { 'helpdirs': s:hdir }
               \ ])
      call s:VxMan_AddContexts(['c', 'cpp'], ['crefvim'])
      unlet s:hdir
   endif

   if filereadable(g:vxlib_manuals_directory . '/luarefvim/lua50refvim.txt')
            \ || filereadable(g:vxlib_manuals_directory . '/luarefvim/lua51refvim.txt')
      " luarefvim(1291)
      let s:hdir = g:vxlib_manuals_directory . '/luarefvim'
      call s:VxMan_AddGetter(['luarefvim>extvimhelp', 'tkg', 'manuals#search#ExternVimHelp',
               \ 'Get help for Lua.',
               \ { 'helpdirs': s:hdir }
               \ ])
      call s:VxMan_AddContexts(['lua'], ['luarefvim'])
      unlet s:hdir
   endif
" </VIMPLUGIN>

