vim9script

source ../init.vim

# --- toc#IsAvailable() ---

def Test_is_available_manual()
    setlocal foldmethod=manual
    assert_false(toc#IsAvailable())
enddef

def Test_is_available_expr()
    setlocal foldmethod=expr
    setlocal foldexpr=TocTestTomlFold(v:lnum)
    assert_true(toc#IsAvailable())
enddef

# --- toc#AddCollector() ---

def Test_add_collector()
    toc#AddCollector('xyzfmt', 'SomeFunc')
    assert_true(has_key(g:toc_collectors, 'xyzfmt'))
    assert_equal('SomeFunc', g:toc_collectors['xyzfmt'])
enddef

# --- 调度优先级：自定义 collector 优先于 fold ---

def Test_dispatch_collector_over_fold()
    setlocal filetype=myfmt2
    setlocal foldmethod=marker
    setlocal foldmarker={{{,}}}
    setline(1, ['# Fold {{{1'])
    toc#AddCollector('myfmt2', 'TocTestCollector')
    assert_equal(['Hello', '| World'], g:GetTocContent())
enddef

# --- 无任何来源时：轻柔提示，不产生 popup ---

def Test_dispatch_no_outline()
    setlocal filetype=
    setlocal foldmethod=manual
    setline(1, ['just a line'])
    assert_equal([], g:GetTocContent())
enddef

# --- 标题格式：index/total (curlvl/maxlvl) ---

def Test_title_format()
    setlocal foldmethod=expr
    setlocal foldexpr=TocTestTomlFold(v:lnum)
    setline(1, ['[a]', 'x', '[a.b]', 'y', '[c]'])
    g:CloseAllPopups()
    toc#Open()
    var title = g:GetTocTitle()
    g:CloseAllPopups()
    assert_true(title =~ '^ 1/3 (2/2)', 'title=' .. string(title))
enddef

# --- helptoc 委托（内置 helptoc 可用时）---

def Test_dispatch_helptoc_delegate()
    if !(v:version > 901 || (v:version == 901 && has('patch1230')))
        echo 'Skipping: built-in helptoc not available'
        return
    endif
    var saved = g:toc_use_helptoc
    g:toc_use_helptoc = true
    setlocal filetype=markdown
    setline(1, ['# Title', '## Section'])
    assert_equal(['Title', '| Section'], g:GetTocContent())
    g:toc_use_helptoc = saved
enddef

# --- 报告 ---
g:RunTestInBuffer(function('Test_is_available_manual'))
g:RunTestInBuffer(function('Test_is_available_expr'))
g:RunTestInBuffer(function('Test_add_collector'))
g:RunTestInBuffer(function('Test_dispatch_collector_over_fold'))
g:RunTestInBuffer(function('Test_dispatch_no_outline'))
g:RunTestInBuffer(function('Test_title_format'))
g:RunTestInBuffer(function('Test_dispatch_helptoc_delegate'))

if len(v:errors) > 0
    for err in v:errors
        echomsg err
    endfor
    cquit!
else
    echo 'test-dispatch: All tests passed'
    quitall!
endif
