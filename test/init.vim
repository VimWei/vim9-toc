vim9script

# vim9-toc 测试公共初始化
# 用法：每个测试文件开头 `source ../init.vim`

set nocompatible
&runtimepath = simplify(fnamemodify(expand('<sfile>'), ':h') .. '/..') .. ',' .. &runtimepath
set noswapfile
set nomore
set hidden
set verbose=1
set nowrap

# 加载插件（定义 :Toc 命令，并触发 autoload 注册）
execute 'source ' .. simplify(fnamemodify(expand('<sfile>'), ':h') .. '/../plugin/toc.vim')

# 测试用 foldexpr（legacy：foldexpr 是 legacy 表达式）
# 模拟 TOML：表头返回 '>N'（N = 点号数 + 1），普通行返回数字 1
legacy function! TocTestTomlFold(lnum) abort
    let l = getline(a:lnum)
    if l =~ '^\s*\[' 
        let dots = len(substitute(l, '[^.]', '', 'g'))
        return printf('>%d', dots + 1)
    endif
    return 1
endfunction

# 测试用 collector（返回固定条目）
legacy function! TocTestCollector() abort
    return [{'lnum': 1, 'lvl': 1, 'text': 'Hello'}, {'lnum': 2, 'lvl': 2, 'text': 'World'}]
endfunction

# 每个测试提供独立缓冲区（隔离 foldmethod/foldexpr/foldmarker 等状态）
def g:RunTestInBuffer(TestFunc: func)
    new
    setlocal foldmethod=manual
    setlocal foldexpr=
    setlocal nofoldenable
    try
        TestFunc()
    finally
        bwipe!
    endtry
enddef

# 关闭所有 popup
def g:CloseAllPopups()
    for id in popup_list()
        popup_close(id)
    endfor
enddef

# 调用 toc#Open()，返回其产生的 popup 内容，最后清理 popup
# 注意：popup_menu 在 -es 模式下立即返回，但 popup 窗口仍可检查
def g:GetTocContent(): list<string>
    g:CloseAllPopups()
    toc#Open()
    var lines: list<string> = []
    for id in popup_list()
        lines->extend(getbufline(winbufnr(id), 1, '$'))
    endfor
    g:CloseAllPopups()
    return lines
enddef

# 获取当前 popup 标题（需在 popup 打开时调用）
def g:GetTocTitle(): string
    for id in popup_list()
        return popup_getoptions(id)->get('title', '')
    endfor
    return ''
enddef
