vim9script noclear

# toc.vim - unified table of contents
# Maintainer: W.Chen
#
# 降级链：helptoc 原生类型 → 自定义 collector → fold → 缩进兜底 → 提示
#
# 扩展方式：
#   - 途径 A（首选）：为格式写 ftplugin/{filetype}.vim 设置 foldmethod/foldexpr，
#     插件自动通过 fold collector 生效。
#   - 途径 B：注册格式专用 collector（函数名字符串）：
#         call toc#AddCollector('rst', 'MyRstCollector')
#     collector 契约：返回 list<dict<any>>，每项 {lnum, lvl, text}，lvl >= 1。

# Config {{{1
g:toc_level_indicator = get(g:, 'toc_level_indicator', '| ')
g:toc_use_helptoc = get(g:, 'toc_use_helptoc', true)

# HELP_TEXT {{{2
const HELP_TEXT: list<string> =<< trim END
    normal commands in help window
    ──────────────────────────────
    ?      hide this help window
    <C-J>  scroll down one line
    <C-K>  scroll up one line

    normal commands in TOC menu
    ────────────────────────────
    j      select next entry
    k      select previous entry
    J      same as j, and jump to corresponding line in main buffer
    K      same as k, and jump to corresponding line in main buffer
    g      select first entry
    G      select last entry
    H      collapse one level
    L      expand one level
    z      redraw menu with selected entry at center
    /      look for given text with fuzzy algorithm

    <C-D>      scroll down half a page
    <C-U>      scroll up half a page
    <PageDown> scroll down a whole page
    <PageUp>   scroll up a whole page
    <Home>     select first entry
    <End>      select last entry

    title meaning
    ─────────────
    example: 12/34 (5/6)
        12  index of selected entry
        34  index of last entry
         5  index of deepest level currently visible
         6  index of maximum possible level

    tip
    ───
    after inserting a pattern to look for with the / command,
    if you press <Esc> instead of <CR>, you can then get
    more context for each remaining entry by pressing J or K
END

# 会话状态（popup 为阻塞式，同一时刻仅一个 TOC 弹出，脚本局部即可）
var toc_all_entries: list<dict<any>> = []
var toc_fuzzy_entries: list<dict<any>> = null_list
var toc_curlvl: number = 0
var toc_maxlvl: number = 0
var toc_width: number = 30
var toc_match: number = 0
var help_winid: number = 0

# Interface {{{1
export def Open()
    if g:toc_use_helptoc && IsHelptocSupported() && IsHelptocNative()
        execute 'packadd helptoc'
        execute 'HelpToc'
        return
    endif
    var entries: list<dict<any>> = CollectCustom(&filetype)
    if empty(entries) && IsAvailable()
        entries = FoldEntries()
    endif
    if empty(entries)
        entries = CollectIndent()
    endif
    if empty(entries)
        echomsg 'Toc: no outline available for this buffer'
        return
    endif
    toc_all_entries = entries
    toc_fuzzy_entries = null_list
    toc_maxlvl = MaxLevel(entries)
    toc_curlvl = toc_maxlvl
    OpenPopup()
enddef

def MaxLevel(entries: list<dict<any>>): number
    var m: number = 0
    for e in entries
        var l: number = e.lvl
        if l > m
            m = l
        endif
    endfor
    return m
enddef

export def IsAvailable(): bool
    return &foldmethod != '' && &foldmethod != 'manual' && has('popupwin')
enddef

export def AddCollector(ft: string, fn: any)
    if !exists('g:toc_collectors')
        g:toc_collectors = {}
    endif
    g:toc_collectors[ft] = fn
enddef

# Custom collectors (registry) {{{1
# g:toc_collectors 值为函数名字符串（非 Funcref），经由 call() 调用
def CollectCustom(ft: string): list<dict<any>>
    if !exists('g:toc_collectors') || !g:toc_collectors->has_key(ft)
        return []
    endif
    return call(g:toc_collectors[ft], [])
enddef

# Fold collectors {{{1
def FoldEntries(): list<dict<any>>
    var key: string = $'{&foldmethod}:{&foldexpr}:{b:changedtick}'
    var cache: dict<any> = get(b:, 'toc_cache', {})
    if cache->has_key(key)
        return cache[key]
    endif
    # 用户可能设了 nofoldenable（所有折叠打开），此时 foldlevel()/foldclosed()
    # 都会返回 0/-1。临时开启 foldenable 才能读到正确的折叠层级。
    var saved_enable = &foldenable
    var entries: list<dict<any>> = []
    try
        &foldenable = true
        entries = CollectEntries()
    finally
        &foldenable = saved_enable
    endtry
    cache[key] = entries
    b:toc_cache = cache
    return entries
enddef

def CollectEntries(): list<dict<any>>
    if &foldmethod == 'expr'
        return CollectExpr()
    elseif &foldmethod == 'marker'
        return CollectMarker()
    else
        return CollectGeneric()
    endif
enddef

# legacy helper：在 legacy 上下文求值 foldexpr（vim9 的 eval() 无法调用
# 用户 ftplugin 里定义的 legacy 全局函数，故经此中转）
legacy function! TocEvalFoldexpr(fexpr, lnum) abort
    let l:expr = substitute(a:fexpr, '\<v:lnum\>', a:lnum, 'g')
    return eval(l:expr)
endfunction

def CollectExpr(): list<dict<any>>
    var entries: list<dict<any>> = []
    for lnum in range(1, line('$'))
        var res = call('TocEvalFoldexpr', [&foldexpr, lnum])
        if type(res) == v:t_string && res =~ '^>'
            entries->add({lnum: lnum, lvl: str2nr(res[1 : ]), text: getline(lnum)->trim()})
        endif
    endfor
    return entries
enddef

def CollectMarker(): list<dict<any>>
    var entries: list<dict<any>> = []
    var open = split(&foldmarker, ',')[0]
    for lnum in range(1, line('$'))
        var line = getline(lnum)
        var idx = line->stridx(open)
        if idx >= 0
            var text = idx > 0 ? line[0 : idx - 1] : ''
            entries->add({lnum: lnum, lvl: foldlevel(lnum), text: text->trim()})
        endif
    endfor
    return entries
enddef

def CollectGeneric(): list<dict<any>>
    # fold 起点集合（lnum -> lvl）。两条路径取并集：
    # 1) foldlevel 跃迁：识别嵌套层级、缩进折叠的 sibling（中间有降级）与 EOF 处的起点。
    # 2) 逐级临时关闭折叠后用 foldclosed(lnum) == lnum 枚举语法折叠中 foldlevel
    #    相同的同级 sibling（如 JSON 相邻的 "CommitConfig" / "CommitLengthConfig"）。
    var starts: dict<number> = {}
    var maxlvl: number = 0
    var prev: number = 0
    for lnum in range(1, line('$'))
        var lvl = foldlevel(lnum)
        if lvl > maxlvl
            maxlvl = lvl
        endif
        if lvl > 0 && lvl > prev
            starts[lnum] = lvl
        endif
        prev = lvl
    endfor
    if maxlvl == 0
        return []
    endif
    var saved = &foldlevel
    try
        for target in range(1, maxlvl)
            &foldlevel = target - 1
            for lnum in range(1, line('$'))
                if foldclosed(lnum) == lnum && !starts->has_key(lnum)
                    starts[lnum] = foldlevel(lnum)
                endif
            endfor
        endfor
    finally
        &foldlevel = saved
    endtry
    var entries: list<dict<any>> = []
    for lnum in range(1, line('$'))
        if starts->has_key(lnum)
            entries->add({lnum: lnum, lvl: starts[lnum], text: getline(lnum)->trim()})
        endif
    endfor
    return entries
enddef

# Indent fallback {{{1
def CollectIndent(): list<dict<any>>
    var entries: list<dict<any>> = []
    var shift = shiftwidth()
    for lnum in range(1, line('$'))
        var line = getline(lnum)
        if line =~ '^\s*$'
            continue
        endif
        var cur = indent(lnum)
        var next = NextNonBlankIndent(lnum)
        if next > cur
            entries->add({lnum: lnum, lvl: cur / shift + 1, text: line->trim()})
        endif
    endfor
    return entries
enddef

def NextNonBlankIndent(lnum: number): number
    for n in range(lnum + 1, line('$'))
        var l = getline(n)
        if l !~ '^\s*$'
            return indent(n)
        endif
    endfor
    return -1
enddef

# Popup {{{1
def OpenPopup()
    var winpos = win_screenpos(winnr())
    var height = winheight(0) - 2
    var width = winwidth(0) / 3
    if width < 30
        width = 30
    endif
    toc_width = width
    var visible = GetVisibleEntries()
    var winid = popup_menu(BuildTexts(visible), {
        line: winpos[0],
        col: winpos[1] + winwidth(0) - 1,
        pos: 'topright',
        highlight: 'Normal',
        minheight: height,
        maxheight: height,
        minwidth: width,
        maxwidth: width,
        title: MakeTitle(1, len(visible)),
        filter: Filter,
        callback: Callback,
        border: [1, 1, 1, 1],
        borderchars: ['─', '│', '─', '│', '┌', '┐', '┘', '└'],
        borderhighlight: [],
        close: 'none',
        drag: true,
        scrollbar: false,
    })
    ApplyTocSyntax(winid)
    MatchDelete()
enddef

def ApplyTocSyntax(winid: number)
    # 层级指示符（如 "| "）用 NonText（灰色），正文用 Normal（白色），与 helptoc 对齐
    var ind = g:toc_level_indicator
    Win_execute(winid, [
        'syntax match TocLevel _^\(' .. ind .. '\)*_ contained',
        'syntax region TocText start=_^\(' .. ind .. '\)*_ end=_$_ contains=TocLevel',
        'highlight link TocText Normal',
        'highlight link TocLevel NonText',
    ])
enddef

def GetVisibleEntries(): list<dict<any>>
    if toc_fuzzy_entries != null_list
        return toc_fuzzy_entries
    endif
    return toc_all_entries
        ->copy()
        ->filter((_, e: dict<any>): bool => e.lvl <= toc_curlvl)
enddef

def BuildTexts(entries: list<dict<any>>): list<any>
    if toc_fuzzy_entries != null_list
        return entries->get(0, {})->has_key('props')
            ? entries
            : entries->copy()->map((_, e: dict<any>): string => e.text)
    endif
    var texts: list<string> = []
    for e in entries
        texts->add(repeat(g:toc_level_indicator, max([e.lvl - 1, 0])) .. e.text)
    endfor
    return texts
enddef

def GetBufLnum(winid: number): number
    var toc_lnum = line('.', winid)
    var visible = GetVisibleEntries()
    if toc_lnum < 1 || toc_lnum > len(visible)
        return 0
    endif
    return visible[toc_lnum - 1].lnum
enddef

def Filter(winid: number, key: string): bool
    if ['j', 'J', 'k', 'K', "\<Down>", "\<Up>", "\<C-N>", "\<C-P>",
            "\<C-D>", "\<C-U>",
            "\<PageUp>", "\<PageDown>", 'g', 'G', "\<Home>", "\<End>", 'z']
            ->index(key) >= 0
        var scroll_cmd = {
            J: 'j', K: 'k',
            g: '1G', "\<Home>": '1G', "\<End>": 'G', z: 'zz',
        }->get(key, key)
        # 显式检测边界做回绕：不依赖「移动后新旧行号是否相同」来判断是否越界。
        # 后者在 popup 内容可滚动、redraw 触发滚动时存在竞态，会偶发误判为
        # 「未移动」而错误回绕到顶部/底部（表现为按 J 却跳回第一条）。
        var cur_lnum = line('.', winid)
        var last_lnum = line('$', winid)
        if (key == 'j' || key == 'J' || key == "\<Down>" || key == "\<C-N>") && cur_lnum >= last_lnum
            Win_execute(winid, 'normal! 1G')
        elseif (key == 'k' || key == 'K' || key == "\<Up>" || key == "\<C-P>") && cur_lnum <= 1
            Win_execute(winid, 'normal! G')
        else
            Win_execute(winid, 'normal! ' .. scroll_cmd)
        endif
        if key == 'J' || key == 'K'
            var lnum = GetBufLnum(winid)
            if lnum > 0
                execute('normal! 0' .. string(lnum) .. 'zt')
                MatchDelete()
                toc_match = matchaddpos('IncSearch', [lnum], 0, -1)
            endif
        endif
        SetTitle(winid)
        return true
    endif
    if (key == 'H' && toc_curlvl > 1) || (key == 'L' && toc_curlvl < toc_maxlvl)
        CollapseOrExpand(winid, key)
        return true
    endif
    if key == '?'
        ToggleHelp(winid)
        return true
    endif
    if (key == "\<C-J>" || key == "\<C-K>") && help_winid != 0
        var scroll_cmd = key == "\<C-J>" ? 'j' : 'k'
        Win_execute(help_winid, 'normal! ' .. scroll_cmd)
        return true
    endif
    if key == '/'
        DisplayNonFuzzyToc(winid)
        [{
            group: 'Toc',
            event: 'CmdlineChanged',
            pattern: '@',
            cmd: $'FuzzySearch({winid})',
            replace: true,
        }, {
            group: 'Toc',
            event: 'CmdlineLeave',
            pattern: '@',
            cmd: 'TearDown()',
            replace: true,
        }]->autocmd_add()
        var input_mappings: list<string> =<< trim eval END
          cnoremap <buffer><nowait> <Down> <ScriptCmd>Filter({winid}, 'j')<CR>
          cnoremap <buffer><nowait> <Up> <ScriptCmd>Filter({winid}, 'k')<CR>
          cnoremap <buffer><nowait> <C-N> <ScriptCmd>Filter({winid}, 'j')<CR>
          cnoremap <buffer><nowait> <C-P> <ScriptCmd>Filter({winid}, 'k')<CR>
        END
        input_mappings->execute()
        var look_for: string
        try
            popup_setoptions(winid, {mapping: true})
            look_for = input('look for: ', '', $'custom,{Complete->string()}')
                | redraw
                | echo ''
        catch /Vim:Interrupt/
            TearDown()
        finally
            popup_setoptions(winid, {mapping: false})
        endtry
        return look_for == '' ? true : popup_filter_menu(winid, "\<CR>")
    endif
    return popup_filter_menu(winid, key)
enddef

def FuzzySearch(winid: number)
    FuzzyMatch(winid, getcmdline())
enddef

export def FuzzyMatch(winid: number, look_for: string)
    if look_for == ''
        DisplayNonFuzzyToc(winid)
        return
    endif
    var display: list<dict<any>> = toc_all_entries
        ->copy()
        ->map((_, e: dict<any>): dict<any> => ({
            lnum: e.lnum,
            lvl: e.lvl,
            text: repeat(g:toc_level_indicator, max([e.lvl - 1, 0])) .. e.text,
        }))
    var matches: list<list<any>> = display->matchfuzzypos(look_for, {key: 'text'})
    var entries: list<dict<any>> = matches->get(0, [])
    var pos: list<list<number>> = matches->get(1, [])
    if !has('textprop')
        toc_fuzzy_entries = entries
    else
        var buf = winid->winbufnr()
        if prop_type_get('toc-fuzzy', {bufnr: buf}) == {}
            prop_type_add('toc-fuzzy', {bufnr: buf, combine: false, highlight: 'IncSearch'})
        endif
        toc_fuzzy_entries = entries->map((i: number, e: dict<any>): dict<any> => ({
            text: e.text,
            lnum: e.lnum,
            lvl: e.lvl,
            props: pos[i]->copy()->map((_, col: number): dict<any> => ({
                col: col + 1,
                length: 1,
                type: 'toc-fuzzy',
            })),
        }))
    endif
    popup_settext(winid, BuildTexts(toc_fuzzy_entries))
    Win_execute(winid, 'normal! 1Gzt')
    SetTitle(winid)
enddef

def DisplayNonFuzzyToc(winid: number)
    toc_fuzzy_entries = null_list
    popup_settext(winid, BuildTexts(GetVisibleEntries()))
    SetTitle(winid)
enddef

def TearDown()
    autocmd_delete([{group: 'Toc'}])
    silent! cunmap <buffer> <Down>
    silent! cunmap <buffer> <Up>
    silent! cunmap <buffer> <C-N>
    silent! cunmap <buffer> <C-P>
enddef

def Complete(..._): string
    return toc_all_entries
        ->copy()
        ->map((_, e: dict<any>): string => e.text)
        ->sort()
        ->uniq()
        ->join("\n")
enddef

def Callback(winid: number, choice: number): void
    if help_winid != 0
        help_winid->popup_close()
        help_winid = 0
    endif
    if choice >= 1
        var visible = GetVisibleEntries()
        if choice <= len(visible)
            var lnum: number = visible[choice - 1].lnum
            if lnum > 0
                execute('normal! ' .. string(lnum) .. 'Gzvzt')
            endif
        endif
    endif
    MatchDelete()
enddef

def ToggleHelp(menu_winid: number)
    if help_winid == 0
        var height = min([HELP_TEXT->len(), winheight(0) * 2 / 3])
        var longest: number = 0
        for line in HELP_TEXT
            var l = line->strcharlen()
            if l > longest
                longest = l
            endif
        endfor
        var width = min([longest, winwidth(0) - 4])
        var zindex = popup_getoptions(menu_winid)->get('zindex', 50) + 1
        help_winid = HELP_TEXT->popup_create({
            pos: 'center',
            minheight: height,
            maxheight: height,
            minwidth: width,
            maxwidth: width,
            highlight: 'Normal',
            zindex: zindex,
            border: [1, 1, 1, 1],
            borderchars: ['─', '│', '─', '│', '┌', '┐', '┘', '└'],
            scrollbar: true,
        })
        setwinvar(help_winid, '&cursorline', true)
        setwinvar(help_winid, '&linebreak', true)
        matchadd('Special', '^<\S\+\|^\S\{,2}  \@=', 0, -1, {window: help_winid})
        matchadd('Number', '\d\+', 0, -1, {window: help_winid})
    else
        if IsVisible(help_winid)
            popup_hide(help_winid)
        else
            popup_show(help_winid)
        endif
    endif
enddef

def IsVisible(winid: number): bool
    return popup_getpos(winid)->get('visible', true)
enddef

def CollapseOrExpand(winid: number, key: string)
    var buf_lnum = GetBufLnum(winid)
    if key == 'H'
        while toc_curlvl > 1
            var old_entries = GetVisibleEntries()
            --toc_curlvl
            var new_entries = GetVisibleEntries()
            if new_entries->empty()
                ++toc_curlvl
                break
            endif
            if new_entries != old_entries || toc_curlvl == 1
                break
            endif
        endwhile
    else
        while toc_curlvl < toc_maxlvl
            var old_entries = GetVisibleEntries()
            ++toc_curlvl
            if GetVisibleEntries() != old_entries || toc_curlvl == toc_maxlvl
                break
            endif
        endwhile
    endif
    var visible = GetVisibleEntries()
    popup_settext(winid, BuildTexts(visible))
    var toc_lnum: number = 0
    for e in visible
        if e.lnum > buf_lnum
            break
        endif
        ++toc_lnum
    endfor
    Win_execute(winid, 'normal! ' .. (toc_lnum > 0 ? toc_lnum : 1) .. 'G')
    SetTitle(winid)
enddef

def SetTitle(winid: number)
    var curlnum: number = line('.', winid)
    var lastlnum: number = line('$', winid)
    if lastlnum == 1 && winbufnr(winid)->getbufoneline(1) == ''
        [curlnum, lastlnum] = [0, 0]
    endif
    popup_setoptions(winid, {title: MakeTitle(curlnum, lastlnum)})
enddef

def MakeTitle(curlnum: number, lastlnum: number): string
    var t = printf(' %*d/%d (%d/%d)', len(string(lastlnum)), curlnum, lastlnum, toc_curlvl, toc_maxlvl)
    return printf('%s%*s', t, toc_width - t->strlen(), 'press ? for help ')
enddef

def Win_execute(winid: number, cmd: any)
    win_execute(winid, cmd)
    redraw
enddef

def MatchDelete()
    if toc_match != 0
        toc_match->matchdelete()
        toc_match = 0
    endif
enddef

# Helpers {{{1
def IsHelptocSupported(): bool
    return v:version > 901 || (v:version == 901 && has('patch1230'))
enddef

def IsHelptocNative(): bool
    if &buftype == 'terminal'
        return true
    endif
    return index(['help', 'info', 'asciidoc', 'html', 'man', 'markdown', 'tex', 'vim', 'xhtml'], &filetype) >= 0
enddef

# vim:et:ts=4:sw=4:sts=4:
