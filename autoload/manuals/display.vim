" vim:set fileencoding=utf-8 sw=3 ts=8 et:vim
"
" Author: Marko Mahnič
" Created: March 2010
" License: GPL (http://www.gnu.org/copyleft/gpl.html)
" This program comes with ABSOLUTELY NO WARRANTY.

if vxlib#plugin#StopLoading('#au#manuals#display')
   finish
endif

" =========================================================================== 
" Local Initialization - on autoload
" =========================================================================== 
" call vxlib#python#prepare() Note: This will be called by vimuiex when used
exec vxlib#plugin#MakeSID()
" =========================================================================== 

" Displayers

" Display text
function! manuals#display#Echo(rslt)
   for line in a:rslt[1]
      echo line . "\n"
   endfor
   return -1
endfunc


" Select a choice from list
function! manuals#display#InputList(rslt)
   let choices = []
   let i = 0
   for chc in a:rslt[1][0:&lines-3]
      call add(choices, (i + 1) . '. ' . a:rslt[1][i])
      let i += 1
   endfor

   if len(choices) < 1
      return -1
   endif
   
   let sel = inputlist(choices)
   if sel == '' | return -1 | endif
   let nsel = 0 + sel
   if nsel < 1 || nsel > len(choices)
      return -1
   endif
   return nsel - 1
endfunc


" Use an existing QuickFixList.
" The QuickFixList is a self-contained displayer.
function! manuals#display#QuickFixList(rslt)
   copen
   return -1
endfunc


function! manuals#display#FindHelpWindow()
   " Try to find a vimhelp window
   let nwin = winnr('$')
   for iw in range(nwin)
      let ibuf = winbufnr(iw+1)
      let bt=getbufvar(ibuf, '&buftype')
      if bt=='help'
         return iw+1
      endif
   endfor

   " try to find g:manuals_help_buffer
   let reHelpBuf = escape(g:manuals_help_buffer, '\*.') . '$'
   for iw in range(nwin)
      let ibuf = winbufnr(iw+1)
      let bname = bufname(ibuf)
      if bname =~ reHelpBuf
         return iw+1
      endif 
   endfor

   " try to find a read-only help buffer
   for iw in range(nwin)
      let ibuf = winbufnr(iw+1)
      let bt = getbufvar(ibuf, '&filetype')
      let bro = getbufvar(ibuf, '&readonly')
      if bt == 'help' && bro != 0
         return iw+1
      endif
   endfor
 
   return -1
endfunc

function! manuals#display#MakeTmpHelpBuf(tagfiles, createwin)
   if a:createwin
      let iwhelp = manuals#display#FindHelpWindow()
      if iwhelp >= 0
        silent! exec iwhelp . ' wincmd w'
      else
         " no help window found: create one
         silent! help
      endif
   endif
   let name = g:manuals_help_buffer
   silent! exec 'edit ' . name
   setl buftype=nofile readonly nomodifiable nobuflisted noswapfile nonumber
   let bufnr=bufnr(name)
   if a:tagfiles != ''
      let &l:tags=a:tagfiles
   endif
   return bufnr
endfunc


" Display text - in a temporary buffer
function! manuals#display#OpenManualsBuffer(rslt)
   let lines = a:rslt[1]
   let pos = getpos(".")
   let win = winnr()
   "let nw = winnr('$')
   let tmpbuf = manuals#display#MakeTmpHelpBuf('', 1)
   "let wincreated = (nw != winnr('$'))
   setl modifiable noreadonly
   norm! ggVGd
   call setline(1, lines)
   norm! gg
   setl readonly nomodifiable
endfunc


" Display text
" TODO: title&cmd might be additional parameters
" TODO: currently using VxPopup (list of items); need to implement 'textbox' in vimuiex
" TODO: if type contains 'b', load items from a buffer
function! manuals#display#OpenVxText(rslt)
   let popopt = {}
   call vimuiex#vxlist#VxPopup(a:rslt[1], 'Manual-Text', popopt)
   return -1
endfunc

function! s:VxcbInitOpenGrepResults(pyListVar)
   " Items that start with number and colon are NOT title items; others are
   exec 'python ' . a:pyListVar . '.setTitleItems(r"^\s*\d+:", 0)'
   exec 'python ' . a:pyListVar . '.hasTitles = True'
endfunc

" Select a choice from a grep or keyword list
" TODO: add handlers for two types of lists: keywrods and grep results
"    keywords: should rerun the search on a single keyword to get text
"    grep results: should jump to result
" TODO: Get the title from the caller
function! manuals#display#OpenVxList(rslt)
   let popopt = {}
   if a:rslt[0] =~ 'h'
      let popopt['init'] = s:SNR . 'VxcbInitOpenGrepResults'
      let popopt['current'] = 1
   endif
   let slctd = vimuiex#vxlist#VxPopup(a:rslt[1], 'Manual-List', popopt)
   if len(slctd) < 1
      return -1
   endif
   return slctd[0]
endfunc

" Select a choice from a menu
" TODO: Get the title from the caller
function! manuals#display#OpenVxMenu(rslt)
   let popopt = {}
   let slctd = vimuiex#vxlist#VxPopup(a:rslt[1], 'Menu', popopt)
   if len(slctd) < 1
      return -1
   endif
   return slctd[0]
endfunc


" =========================================================================== 
" Global Initialization - Processed by Plugin Code Generator
" =========================================================================== 
finish

" id=display-function
" Types of display:
"    - text
"    - list of keywords (one will be selected used in next search)
"    - list of grep results (one will be selected an displayed)
"    - menu (select a getter to execute)
"    @see: <url:manuals.vim#r=flagdefs>
"
" * Function for Menu
"   Must return the index of the selected item.
"   The index will be used by ShowManual to execute the selected getter.
"   If index is less than 0, ShowManual will end.
"
"   Alternative: the function gets a callback function to call when an item
"   is selected. ShowManual doesn't process the functions result. The function
"   will execute the selected getter.
"
" * Function for List of keywords
"   Must return the index of the selected item.
"   The index will be used by ShowManual to find the text for the item.
"   (The getter may provide a function to extract the keyword from an item).
"
"   Alternative: the function gets a callback function to call when an item
"   is selected. ShowManual doesn't process the functions result. The function
"   will execute a getter (TODO: which one?).
"
" * Function for Grep results
"   Must return the index of the selected item.
"   The index will be used by ShowManual to find the text for the item.
"   (The getter should provide the list of items in standard format: something
"   like '[I' or grep).
"
"   Alternative: the function gets a callback function to call when an item
"   is selected. ShowManual doesn't process the functions result. The function
"   will process the item an display the text.
"
"   Alternative: the displayer is self-contained and ignores the parameters
"   from ShowManual. Examples: qfixlist, locationlist, VxOccur-ShowResults.
"
" * Function for text
"   Displays the recieved text.
"   Doesn't need to return anything.
"
" Types of input 
"    - l: array (list) of strings
"    - b: ordinary buffer
"    - q, o: qfixlist, locationlist
"
" The displayer must define the types of input it can handle, in order of
" preference. The getters can inspect this order to prepare the data in the
" desired format. If a getter doesn't provide a format supported by the
" displayer, ShowManual may convert the getters result into displayers format.

" <PLUGINFUNCTION id="manuals#var-mandisplaylist">
if !exists("g:VxlibManuals_NewDisplayers")
   let g:VxlibManuals_NewDisplayers = []
endif
" </PLUGINFUNCTION>
" <PLUGINFUNCTION id="manuals#addtextdisplay" name="VxMan_AddTextDisplay">
function! s:VxMan_AddTextDisplay(name, dispfn, datatypes)
   call add(g:VxlibManuals_NewDisplayers, ['t', a:name, a:dispfn, a:datatypes])
endfunc
" </PLUGINFUNCTION>
" <PLUGINFUNCTION id="manuals#addmenudisplay" name="VxMan_AddMenuDisplay">
function! s:VxMan_AddMenuDisplay(name, dispfn)
   call add(g:VxlibManuals_NewDisplayers, ['m', a:name, a:dispfn, ''])
endfunc
" </PLUGINFUNCTION>
" <PLUGINFUNCTION id="manuals#addlistdisplay" name="VxMan_AddListDisplay">
function! s:VxMan_AddListDisplay(name, dispfn, datatypes)
   call add(g:VxlibManuals_NewDisplayers, ['k', a:name, a:dispfn, a:datatypes])
endfunc
" </PLUGINFUNCTION>
" <PLUGINFUNCTION id="manuals#addgrepdisplay" name="VxMan_AddGrepDisplay">
function! s:VxMan_AddGrepDisplay(name, dispfn, datatypes)
   call add(g:VxlibManuals_NewDisplayers, ['g', a:name, a:dispfn, a:datatypes])
endfunc
" </PLUGINFUNCTION>

" <VIMPLUGIN id="manuals#display" >
   call s:VxMan_AddMenuDisplay('choice', 'manuals#display#InputList')

   call s:VxMan_AddTextDisplay('echo', 'manuals#display#Echo', 'lb')
   call s:VxMan_AddTextDisplay('manbuffer', 'manuals#display#OpenManualsBuffer', 'bl')

   call s:VxMan_AddListDisplay('choice', 'manuals#display#InputList', 'l')
   call s:VxMan_AddGrepDisplay('choice', 'manuals#display#InputList', 'l')
   call s:VxMan_AddGrepDisplay('qfixlist', 'manuals#display#QuickFixList', 'q')

   "call s:AddGrepDisplay('qfixlist', 'manuals#display#QFixList', 'qo')

   if s:PluginExists('vimuiex#vxlist', 'autoload/vimuiex/vxlist.vim')
      call s:VxMan_AddMenuDisplay('vimuiex', 'manuals#display#OpenVxMenu')

      call s:VxMan_AddTextDisplay('vimuiex', 'manuals#display#OpenVxText', 'lb')

      call s:VxMan_AddListDisplay('vimuiex', 'manuals#display#OpenVxList', 'l')
      call s:VxMan_AddGrepDisplay('vimuiex', 'manuals#display#OpenVxList', 'l')
   endif

   if s:PluginExists('tlib', 'plugin/02tlib.vim')
      call s:VxMan_AddListDisplay('tlib', 'manuals#display#OpenTlibList', 'bl')
      call s:VxMan_AddGrepDisplay('tlib', 'manuals#display#OpenTlibList', 'bl')
   endif
" </VIMPLUGIN>

