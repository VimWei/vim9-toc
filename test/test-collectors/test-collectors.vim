vim9script

source ../init.vim

# --- CollectExpr（foldmethod=expr，TOML 风格 foldexpr）---

def Test_expr_toml_siblings_and_nesting()
    setlocal foldmethod=expr
    setlocal foldexpr=TocTestTomlFold(v:lnum)
    setline(1, ['[server]', 'host = "localhost"', '[server.ssl]', 'enabled = true', '[database]'])
    assert_equal(['[server]', '| [server.ssl]', '[database]'], g:GetTocContent())
enddef

def Test_expr_empty_foldexpr_result()
    # 空 buffer：无任何折叠起点
    setlocal foldmethod=expr
    setlocal foldexpr=TocTestTomlFold(v:lnum)
    setline(1, ['just content', 'more content'])
    assert_equal([], g:GetTocContent())
enddef

# --- CollectMarker（foldmethod=marker，去掉行尾折叠标记）---

def Test_marker_strips_foldmarker()
    setlocal foldmethod=marker
    setlocal foldmarker={{{,}}}
    setline(1, ['# Top {{{1', 'x', '# Sub {{{2', 'y', '# Top2 {{{1'])
    assert_equal(['# Top', '| # Sub', '# Top2'], g:GetTocContent())
enddef

# --- CollectGeneric（foldmethod=syntax/indent 走 foldlevel 跃迁）---

def Test_generic_indent_fold()
    setlocal foldmethod=indent
    setlocal shiftwidth=2
    setline(1, ['top1', '  child', '    grand', 'top2', '  child2'])
    # indent 折叠的 fold 起点是「更缩进」的那一行
    assert_equal(['child', '| grand', 'child2'], g:GetTocContent())
enddef

def Test_generic_syntax_siblings()
    # JSON 语法折叠：同级对象（CommitConfig / CommitLengthConfig）都应被识别，
    # 且各自的 properties 是其子级（回归：语法折叠的 sibling 会漏检）。
    setlocal filetype=json
    syntax on
    runtime! syntax/json.vim
    setlocal foldmethod=syntax
    setline(1, [
        \ '{',
        \ '  "$defs": {',
        \ '    "CommitConfig": {',
        \ '      "properties": {',
        \ '        "signOff": {',
        \ '          "type": "boolean"',
        \ '        }',
        \ '      }',
        \ '    },',
        \ '    "CommitLengthConfig": {',
        \ '      "properties": {',
        \ '        "show": {',
        \ '          "type": "boolean"',
        \ '        }',
        \ '      }',
        \ '    }',
        \ '  }',
        \ '}',
        \ ])
    assert_equal([
        \ '"$defs": {',
        \ '| "CommitConfig": {',
        \ '| | "properties": {',
        \ '| | | "signOff": {',
        \ '| "CommitLengthConfig": {',
        \ '| | "properties": {',
        \ '| | | "show": {',
        \ ], g:GetTocContent())
enddef

# --- CollectIndent（foldmethod=manual 时的缩进兜底）---

def Test_indent_fallback()
    setlocal foldmethod=manual
    setlocal shiftwidth=2
    setline(1, ['top1', '  child', 'top2', '  child2'])
    # 后一行更缩进 → 视为标题
    assert_equal(['top1', 'top2'], g:GetTocContent())
enddef

def Test_indent_fallback_shiftwidth_zero()
    # shiftwidth=0（如 Go 的 recommended style）→ 有效 shiftwidth 回退到 tabstop，
    # tab 缩进应正确映射为层级（回归：此前 shift 硬编码 1 导致层级放大的 bug）
    setlocal foldmethod=manual
    setlocal shiftwidth=0
    setlocal tabstop=4
    setline(1, ['func foo() {', "\tif err != nil {", "\t\treturn err", "\t}", '}'])
    assert_equal(['func foo() {', '| if err != nil {'], g:GetTocContent())
enddef

# --- 自定义 collector ---

def Test_custom_collector()
    setlocal filetype=myfmt
    toc#AddCollector('myfmt', 'TocTestCollector')
    assert_equal(['Hello', '| World'], g:GetTocContent())
enddef

# --- 报告 ---
g:RunTestInBuffer(function('Test_expr_toml_siblings_and_nesting'))
g:RunTestInBuffer(function('Test_expr_empty_foldexpr_result'))
g:RunTestInBuffer(function('Test_marker_strips_foldmarker'))
g:RunTestInBuffer(function('Test_generic_indent_fold'))
g:RunTestInBuffer(function('Test_generic_syntax_siblings'))
g:RunTestInBuffer(function('Test_indent_fallback'))
g:RunTestInBuffer(function('Test_indent_fallback_shiftwidth_zero'))
g:RunTestInBuffer(function('Test_custom_collector'))

if len(v:errors) > 0
    for err in v:errors
        echomsg err
    endfor
    cquit!
else
    echo 'test-collectors: All tests passed'
    quitall!
endif
