vim9script

source ../init.vim

# --- 模糊过滤：仅保留匹配行，其余隐藏 ---

def Test_fuzzy_filter_single_match()
    setlocal foldmethod=expr
    setlocal foldexpr=TocTestTomlFold(v:lnum)
    setline(1, ['[server]', 'x', '[server.ssl]', 'y', '[database]'])
    assert_equal(['| [server.ssl]'], g:GetFuzzyContent('ssl'))
enddef

def Test_fuzzy_filter_multiple_matches()
    setlocal foldmethod=expr
    setlocal foldexpr=TocTestTomlFold(v:lnum)
    setline(1, ['[server]', 'x', '[server.ssl]', 'y', '[database]'])
    assert_equal(['[server]', '| [server.ssl]'], g:GetFuzzyContent('server'))
enddef

def Test_fuzzy_empty_query_restores_full()
    setlocal foldmethod=expr
    setlocal foldexpr=TocTestTomlFold(v:lnum)
    setline(1, ['[server]', 'x', '[server.ssl]', 'y', '[database]'])
    assert_equal(['[server]', '| [server.ssl]', '[database]'], g:GetFuzzyContent(''))
enddef

def Test_fuzzy_no_match()
    setlocal foldmethod=expr
    setlocal foldexpr=TocTestTomlFold(v:lnum)
    setline(1, ['[server]', 'x', '[database]'])
    assert_equal([''], g:GetFuzzyContent('zzz'))
enddef

def Test_fuzzy_multibyte_props()
    setlocal foldmethod=expr
    setlocal foldexpr=TocTestTomlFold(v:lnum)
    setline(1, ['[中文标题]'])
    # 匹配 '标' '题'：字符索引 3/4 → 字节列 8/11，每字 3 字节
    assert_equal([{col: 8, length: 3}, {col: 11, length: 3}], g:GetFuzzyProps('标题'))
enddef

# --- 报告 ---
g:RunTestInBuffer(function('Test_fuzzy_filter_single_match'))
g:RunTestInBuffer(function('Test_fuzzy_filter_multiple_matches'))
g:RunTestInBuffer(function('Test_fuzzy_empty_query_restores_full'))
g:RunTestInBuffer(function('Test_fuzzy_no_match'))
g:RunTestInBuffer(function('Test_fuzzy_multibyte_props'))

if len(v:errors) > 0
    for err in v:errors
        echomsg err
    endfor
    cquit!
else
    echo 'test-filter: All tests passed'
    quitall!
endif
