" vim:set fileencoding=utf-8 sw=3 ts=8 et:vim
"
" Author: Marko Mahnič
" Created: March 2010
" License: GPL (http://www.gnu.org/copyleft/gpl.html)
" This program comes with ABSOLUTELY NO WARRANTY.

if vxlib#plugin#StopLoading('#au#manuals#core')
   finish
endif

" id=flagdefs
" helpkinds/resultkinds:
"    - t text
"    - k keywords
"    - g grep results (format: filename, line, text)
"    - h grep results (filenames as titles, format= n: lineno (type) text)
"    - e error (data = description)
" resulttypes:
"    - l returned as a list (data = array of strings)
"    - b returned as a buffer (data = buffer name)
"    - q returned as qfixlist (data = ?)
"    - o returned as location list (data = list-id?)
" @see: <url:manuals_g.vim#r=getter-function>
let s:helpkinds    = { 't': 'text', 'k': 'keywords', 'g': 'grep' } 
let s:resultkinds  = { 't': 'text', 'k': 'keywords', 'g': 'grep', 'h': 'grep', 'e': 'error' } 
let s:resulttypes  = { 'l': 'list', 'b': 'buffer', 'q': 'qfixlist', 'o': 'locationlist' }

" displaykinds:
"    - t text
"    - k keyword list
"    - g grep results
"    - menu
" @see: <url:manuals_d.vim#r=display-function>
let s:displaykinds = { 't': 'text', 'k': 'keywords', 'g': 'grep', 'm': 'menu' } 

" 1. A function to extract the documentation for the current context
"  examples:
"     vim: call :help
"     bash: call :!man
"     python: call :!pydoc
"  definition:
"     filetype, extractor-function, (result-type)
"  result-type should be 'string', 'array' or 'buffer'
"     - maybe the extractor function should return the type of the result it
"     returned; also a result type may be: nothing, text, list (which leads to
"     new queries, eg. pydoc -k); also the type of text may be returned for
"     display in a vim buffer (eg. 'help' for vim help).
"
"  The context could be narrower than filetype, ie. syntax element:
"     python/keyword - describe a keyword
"     java/comment - describe a javadoc element
"     etc.
"     Only the narrowest context applies. The extractor-function recieves the
"     context as a parameter.
"
"  Check other libraries for extractors (manpageview#489, help#561)
"
"  Kinds of getters:
"     - (T) return the full text of the first/best matching keyword (tag)
"     - (K) return the list of matching keywords (tags)
"        - if exactly one keyword matches, return full text
"        - find full full text in step 2
"     - (G) grep manuals to find matching words, return list of locations
"        - if exactly one match found, return full text
"        - find the location in step 2
"  A single getter can support multiple kinds, the available types are defined
"  with flags ('tkg').

" { 'extractors-function'={ 'fn'='extractor-function', ... }, ... }
let s:VxlibManual_Getters = {}
function! s:RegisterNewGetters()
   if !exists("g:VxlibManuals_NewGetters")
      return
   endif

   for gtd in g:VxlibManuals_NewGetters
      " Different getters may call a default ('downstream') getter to get help.
      " Example:
      "   Help for css is in vimhelp format, but not part of vim help
      "   (installed in a different location). The getter function getCssHelp
      "   calls manuals_g#VimHelp with additional parameters. The getters id
      "   is 'cssmanual', but we want to use the settings of the getter
      "   'vimhelp' by default. Hence we add the getter with:
      "      call s:AddGetter(['cssmanual>vimhelp', 'tkg', ...])

      let id = split(gtd[0], '>')
      let gdef={}
      let gdef.id    = id[0]  " this ID is used in g:VxlibManual_DisplayOrder (s:FindMatchingDisplayer)
      let gdef.kinds = gtd[1] " flags for kinds of results the getter can provide (t-text,k-keywords,g-grep)
      let gdef.fn    = gtd[2] " the extractor function
      let gdef.doc   = gtd[3] " the string to be displayed in a menu
      if len(id) > 1
         let gdef.typeid = id[1] " id of the downstream getter used by this getter
      endif
      if len(gtd) > 4
         let gdef.params = gtd[4]
      endif
      " TODO: warn when overriding an existing getter
      let s:VxlibManual_Getters[gdef.id] = gdef
      " echom s:VxlibManual_Getters[gdef.id].doc
   endfor
   "echo "Getters"
   "echo s:VxlibManual_Getters

   unlet g:VxlibManuals_NewGetters
endfunc


" [ [context, handler-id], ... ]
let s:VxlibManual_Contexts = []
function! s:RegisterNewContexts()
   if !exists("g:VxlibManuals_NewContexts")
      return
   endif

   call vxlib#context#RegisterContextHandlers(s:VxlibManual_Contexts, g:VxlibManuals_NewContexts)

   unlet g:VxlibManuals_NewContexts
endfunc


" 2. A command to display the documentation
"  examples:
"     preview buffer
"     help buffer
"     normal buffer (no file attached)
"     VxPopup/VxView
"     tlib
"  The display type is set by the user. Default is for all types, but some
"  types may have special display (eg. VxView for all, except vim-help
"  displayed in help buffer).
let s:NoDisplay = { 'name': '', 'fn': '', 'datafmts': 'lbqo' }
let s:disp_echo = { 'name': 'echo', 'fn': 'manuals#display#Echo', 'datafmts': 'lb' }
let s:disp_choice = { 'name': 'choice', 'fn': 'manuals#display#InputList', 'datafmts': 'l' }
let s:ChoiceMenu = s:disp_choice
let s:VxlibManual_Displayers = {
         \ 'text': {'echo': s:disp_echo},
         \ 'menu': {'choice': s:disp_choice },
         \ 'keywords': {'choice': s:disp_choice },
         \ 'grep': {'choice': s:disp_choice } }
unlet s:disp_choice
unlet s:disp_echo
function! s:RegisterNewDisplayers()
   if !exists("g:VxlibManuals_NewDisplayers")
      return
   endif

   for ndis in g:VxlibManuals_NewDisplayers
      let type = ndis[0]
      if !has_key(s:displaykinds, type)
         continue
      endif
      let type = s:displaykinds[type]
      let entry = s:VxlibManual_Displayers[type]
      let ddef = {}
      let ddef.name     = ndis[1] " the name of the displayer
      let ddef.fn       = ndis[2] " the function to call
      let ddef.datafmts = ndis[3] " the data-formats that the displayer can process
      let entry[ddef.name] = ddef
   endfor
   "echo "Displayers"
   "echo s:VxlibManual_Displayers

   unlet g:VxlibManuals_NewDisplayers
endfunc


function! s:FindGetters(contexts, helpkinds)
   if len(a:contexts) < 1 || len(a:helpkinds) < 1
      " TODO: user defined default getter
      return []
   endif

   " find the getters for the contexts
   let getters = vxlib#context#FindContextHandlers(s:VxlibManual_Contexts, a:contexts, 1)

   " remove the getters that don't provide help of helpkind
   let kinds = []
   for i in range(len(a:helpkinds))
      call add(kinds, a:helpkinds[i])
   endfor
   let result = []
   for gtrid in getters
      if ! has_key(s:VxlibManual_Getters, gtrid)
         continue
      endif
      let gtr = s:VxlibManual_Getters[gtrid]
      let ok = 0
      for hk in kinds 
         if (gtr.kinds =~ hk)
            let ok = 1
            break
         endif
      endfor
      if ok
         call add(result, gtr)
      endif
   endfor

   return result
endfunc


" Users choice: what displayer to use with what getter
" Example: (hardcoded defaults)
"    default-m: 'vimuiex,tlib,choice'
"    default-t: 'vimuiex,preview,echo'
"    default-k: 'vimuiex,tlib,choice'
"    default-g: 'vimuiex,tlib,qfixlist,choice'
"    vimhelp-t: ''  ==> no displayer, keep whatever the getter did
let s:VxlibManual_DisplayOrder = {
         \ 'default': 'echo',
         \ 'default-m': 'vimuiex,tlib,choice',
         \ 'default-t': 'vimuiex,manbuffer,echo',
         \ 'default-k': 'vimuiex,tlib,choice',
         \ 'default-g': 'vimuiex,tlib,qfixlist,choice',
         \ 'vimhelp-t': ''
         \}
function! s:FindMatchingDisplayer(dispkind, getter)
   " TODO: 
   "     find 'getter.id-dispkind' in s:VxlibManual_DisplayOrder
   "     if not found, try 'default-dispkind'
   "     if not found, use 'default'
   "     select the first displayer that exists
   let dispkind = a:dispkind
   if len(dispkind) < 1
      echoe 's:FindMatchingDisplayer: Missing parameter dispkind; using "t"'
      let dispkind = 't'
   endif
   let dispkind = dispkind[0]
   if !has_key(s:displaykinds, dispkind)
      throw 'InvalidDisplayKind'
   endif

   " Get the order of preferred displayers for this getter
   let vxord = s:VxlibManual_DisplayOrder
   for i in range(4)
      if i == 0 | let orderName = a:getter.id . '-' . dispkind 
      elseif i == 1 
         " scan the chain of downstream getters (by getter.typeid) to find an order entry
         let gttr = a:getter
         let maxdepth = 5
         while maxdepth > 0 && has_key(gttr, 'typeid') 
            let orderName = gttr.typeid . '-' . dispkind
            if has_key(vxord, orderName)
               break
            endif
            let maxdepth -= 1
            if has_key(s:VxlibManual_Getters, gttr.typeid) " next getter in chain
               let gttr = s:VxlibManual_Getters[gttr.typeid]
            else | break
            endif
         endwhile
      elseif i == 2 | let orderName = 'default-' . dispkind 
      elseif i == 3 | let orderName = 'default'
      else | let orderName = ''
      endif
      if orderName != '' && has_key(vxord, orderName)
         break
      endif
   endfor
   if orderName == ''
      throw 'DisplayOrderNotFound'
   endif

   let order = split(vxord[orderName], ',')
   if len(order) < 1
      return s:NoDisplay
   endif

   let dispkind = s:displaykinds[dispkind]
   let displist = s:VxlibManual_Displayers[dispkind]
   for dispname in order
      if has_key(displist, dispname)
         return displist[dispname]
      endif
   endfor
   throw 'DisplayerNotFound'
endfunc

function! s:GetMenuDisplayer()
   " Get the order of preferred displayers for this getter
   let vxord = s:VxlibManual_DisplayOrder
   for i in range(2)
      if i == 0 | let orderName = 'default-m'
      elseif i == 1 | let orderName = 'default'
      else | let orderName = ''
      endif
      if orderName != '' && has_key(vxord, orderName)
         break
      endif
   endfor
   if orderName == ''
      throw 'MenuDisplayOrderNotFound'
   endif

   let order = split(vxord[orderName], ',')
   let displist = s:VxlibManual_Displayers['menu']
   for dispname in order
      if has_key(displist, dispname)
         return displist[dispname]
      endif
   endfor
   return s:ChoiceMenu
endfunc

" Operation:
"  Find all functions that can provide help for the current context. Execute
"  functions until you get a result (or maybe execute all and concatenate or
"  let the user decide which one to display; remember what the user selected
"  for the next time).
"
"  Display the results in a suitable viewer.
"
" Registration:
"  Additional plugins register getters and displayers during startup (plugin
"  reading stage).
" @see also <url:vimhelp:map-operator#tn=F4>
function! manuals#core#ShowManual(count, visual, helpkind)
   call s:RegisterNewGetters()
   call s:RegisterNewContexts()
   call s:RegisterNewDisplayers()
   if a:visual == ''
      let w1 = expand("<cword>")
   else " visual mode
      let sel_save = &selection
      let &selection = "inclusive"
      let reg_save = @@
      silent exe "normal! `<" . a:visual . "`>y"
      let w1 = @@
      let &selection = sel_save
      let @@ = reg_save
   endif

   " helpkind is a parameter;
   " TODO: what if multiple kinds (tkg) are given?
   "   Try each in turn (? t is last, skip m)
   "   If the found getter for k gives exactly one result and t is in kinds,
   "   try with kind=t on the new keyword.
   let helpkind = 't' " tkg
   let helpkind = a:helpkind
   let showmenu = (a:helpkind =~ 'm')
   let helpkind = substitute(helpkind, 'm', '', 'g')
   if showmenu && len(helpkind) == ''
      let helpkind='tkg'  " TODO: user defined order?
   endif

   let ctx = vxlib#context#GetCursorContext()
   let getters = s:FindGetters(ctx, helpkind)

   if len(getters) < 1
      echom 'Don''t know how to provide help(' . helpkind . ') in context "' . ctx[0] . '".'
      return
   endif
   "for gttr in getters | echom gttr.doc | endfor
   "call getchar()

   if !showmenu
      let gttr = getters[0]
   else
      let mdisp = s:GetMenuDisplayer()
      let rslt = ['', []]
      let gttr_kind = []
      for gttr in getters
         for i in range(len(helpkind)) " TODO: use only kinds that are also in helpkind, in helpkind order
            try
               if !(gttr.kinds =~ helpkind[i])
                  continue
               endif
               let descr = s:helpkinds[helpkind[i]]
               call add(rslt[1], gttr.doc . ' (' . descr . ')')
               call add(gttr_kind, [gttr, helpkind[i]])
            catch /.*/
            endtry
         endfor
      endfor
      " TODO: menu needs a title, etc: the displayer should accept additional parameters (dictionary?)
      exec 'let choice=' . mdisp.fn . '(rslt)'
      if choice < 0
         return
      endif
      let [gttr, helpkind] = gttr_kind[choice]
      unlet gttr_kind
   endif
   "echo "Getter"
   "echo gttr

   let disply = s:FindMatchingDisplayer(helpkind, gttr)
   "echo "Display"
   "echo disply

   exec 'let rslt=' . gttr.fn . '(w1, a:count, helpkind, gttr, disply)'
   " TODO: the getter will return the kind and type of data it prepared;
   "    if multiple displayers were found (disply should be a list),
   "    the first one matching the returned kind should be used.

   " TODO: save the getter/displayer information for later use; also store
   " retrieved items so they can be redisplayed without a query (only when
   " returned type is 'l'). Implement a history of searches (limit on the
   " total number of items in stored lists). Also remember results from level
   " 2 (retrieve text) below.

   if rslt[0] =~ 'e'
      echom "Error: " . rslt[1]
   elseif rslt[0] =~ 'w'
      echom rslt[1]
   elseif disply.fn != "" && rslt[0] != ''
      " TODO: convert the result (rslt[1]) if necessary
      exec 'let choice=' . disply.fn . '(rslt)'
      if ! (rslt[0] =~ 't') && choice >= 0
         let keyword = rslt[1][choice] " TODO: rslt[1] may not be a list: check type in rslt[0]!
         let keyword = split(keyword, "\t")[0]
         if rslt[0] =~ 'h' || rslt[0] =~ 'g'
            " A grep result was selected: jump to location
            echo "TODO: jump to grep location"
         elseif rslt[0] =~ 'k' && ! (helpkind =~ 't')
            " A keyword was selected: perform another text search
            let textgetters = s:FindGetters(ctx, 't')
            if len(textgetters) < 1
               echom 'Don''t know how to provide help(t) in context "' . ctx[0] . '".'
            else
               " select the same getter if possible (XXX should this be an option?)
               let found = 0
               for tgttr in textgetters
                  if tgttr.id == gttr.id
                     let found = 1
                     break
                  endif
               endfor
               if !found
                  let tgttr = textgetters[0]
               endif
               " get text for keyword
               let tdisply = s:FindMatchingDisplayer('t', tgttr)
               exec 'let rslt=' . tgttr.fn . '(keyword, 0, "t", tgttr, tdisply)'
               if tdisply.fn != "" && rslt[0] != ''
                  exec 'call ' . tdisply.fn . '(rslt)'
               endif
            endif
         endif
      endif
   endif

endfunc

" =========================================================================== 
" Global Initialization - Processed by Plugin Code Generator
" =========================================================================== 
finish

" ShowManual can be called with a key or with a command.
"  with key
"     - expand cword or cWORD or let the plugin do it (w1 = '')
"     - pass possible range
"     - plugins have to account for w1='' and should extract the word
"       themselves
"     - the position has to be restored afterwards (ShowManual can do that)
"  with command
"     - enter word
"     - enter additional parameters (-k, ...)
"
" The extractor function should get the information, what will be done with
" the result next - what kind of result does the displayer require so that it
" can prepare the results accordingly. ie. the type ('buffer', 'array', ...)
" should be in VxlibManual_Display, not in VxlibManual_Getters.
"    - get a getter
"    - get the displayer for the getter type
"    - get the expected input-type for displayer
"    - pass the input-type when calling the getter
"
" <VIMPLUGIN id="manuals#showmanual" >
   call s:CheckSetting('g:manuals_help_buffer', '"*Manual*"')
   nmap <silent> <unique> <Plug>VxManText :call manuals#core#ShowManual(v:count,'','t')<cr>
   vmap <silent> <unique> <Plug>VxManText :<C-U>call manuals#core#ShowManual(v:count,visualmode(),'t')<cr>
   nmap <silent> <unique> <Plug>VxManKeyword :call manuals#core#ShowManual(v:count,'','k')<cr>
   vmap <silent> <unique> <Plug>VxManKeyword :<C-U>call manuals#core#ShowManual(v:count,visualmode(),'k')<cr>
   nmap <silent> <unique> <Plug>VxManGrep :call manuals#core#ShowManual(v:count,'','g')<cr>
   vmap <silent> <unique> <Plug>VxManGrep :<C-U>call manuals#core#ShowManual(v:count,visualmode(),'g')<cr>
   nmap <silent> <unique> <Plug>VxManMenu :call manuals#core#ShowManual(v:count,'','m')<cr>
   vmap <silent> <unique> <Plug>VxManMenu :<C-U>call manuals#core#ShowManual(v:count,visualmode(),'m')<cr>
" </VIMPLUGIN>

" <VIMPLUGIN id="manuals#maps" >
   nmap K <Plug>VxManText
   vmap K <Plug>VxManText
   nmap <leader>kk <Plug>VxManKeyword
   vmap <leader>kk <Plug>VxManKeyword
   nmap <leader>kg <Plug>VxManGrep
   vmap <leader>kg <Plug>VxManGrep
   nmap <leader>km <Plug>VxManMenu
   vmap <leader>km <Plug>VxManMenu
" </VIMPLUGIN>

