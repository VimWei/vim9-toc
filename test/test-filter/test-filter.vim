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

# --- 报告 ---
g:RunTestInBuffer(function('Test_fuzzy_filter_single_match'))
g:RunTestInBuffer(function('Test_fuzzy_filter_multiple_matches'))
g:RunTestInBuffer(function('Test_fuzzy_empty_query_restores_full'))
g:RunTestInBuffer(function('Test_fuzzy_no_match'))

if len(v:errors) > 0
    for err in v:errors
        echomsg err
    endfor
    cquit!
else
    echo 'test-filter: All tests passed'
    quitall!
endif
