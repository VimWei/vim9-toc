# vim9-toc 测试指南

## 测试哲学

与 vim-markdown-plus 一致，遵循三个原则：

1. **零依赖**：只用 Vim 内置 `assert_*` 函数和 `v:errors` 机制，不引入第三方测试框架。
2. **自包含**：每个测试文件自己就是完整运行器，`source ../init.vim` 后定义并运行测试。
3. **最小化工具链**：仅用 Makefile（Linux/macOS/Git Bash）和 PowerShell/CMD 脚本（Windows）编排。

## 目录结构

```
test/
├── Makefile              # 顶层运行器
├── run-tests.ps1         # PowerShell 运行器（Windows）
├── run-tests.cmd         # CMD 运行器（Windows 备选）
├── init.vim              # 公共初始化 + 测试辅助函数
├── test-collectors/      # 收集器测试（expr/marker/indent/fallback/自定义）
│   ├── Makefile
│   └── test-collectors.vim
└── test-dispatch/        # 调度测试（IsAvailable/AddCollector/优先级/标题/helptoc 委托）
    ├── Makefile
    └── test-dispatch.vim
```

## 运行方式

```bash
# Linux/macOS/Git Bash
cd test && make test

# Windows PowerShell
cd test; .\run-tests.ps1            # 全部
cd test; .\run-tests.ps1 test-collectors   # 单组

# Windows CMD
cd test
run-tests.cmd

# 单个测试文件（须在测试组目录下运行，source ../init.vim 依赖 CWD）
cd test/test-collectors
vim -es -T dumb --not-a-term --noplugin -n -u test-collectors.vim +qall
```

## 核心机制：headless 检查 popup 内容

vim9-toc 的输出是 `popup_menu()`（交互式弹窗），而 popup 交互在 `-es`（silent ex）模式下无法注入按键。关键发现：**`popup_menu()` 在 `-es` 模式下立即返回，但 popup 窗口仍然创建，可通过 `popup_list()` + `winbufnr()` + `getbufline()` 检查其内容**。

`test/init.vim` 提供辅助函数 `g:GetTocContent()`：调用 `toc#Open()` 后读取 popup 内容并清理。测试通过该函数断言目录内容，而不触碰内部脚本局部函数：

```vim
def Test_expr_toml_siblings_and_nesting()
    setlocal foldmethod=expr
    setlocal foldexpr=TocTestTomlFold(v:lnum)
    setline(1, ['[server]', 'host = "localhost"', '[server.ssl]', 'enabled = true', '[database]'])
    assert_equal(['[server]', '| [server.ssl]', '[database]'], g:GetTocContent())
enddef
```

## 测试覆盖

- **expr**（`Test_expr_toml_siblings_and_nesting`）：TOML 表头的同级 + 嵌套折叠。
- **expr 空结果**（`Test_expr_empty_foldexpr_result`）：无折叠起点时返回空。
- **marker**（`Test_marker_strips_foldmarker`）：`foldmethod=marker`，剥离行尾折叠标记，校验层级。
- **indent**（`Test_generic_indent_fold`）：`foldmethod=indent` 的折叠起点（含缩进折叠的 sibling）。
- **syntax 同级 sibling**（`Test_generic_syntax_siblings`）：JSON 语法折叠里相邻的同级对象（`CommitConfig` / `CommitLengthConfig`）都能被识别，且各自的 `properties` 是子级。这是对「语法折叠 sibling 漏检」bug 的回归测试。
- **缩进兜底**（`Test_indent_fallback`）：无 foldmethod 时的缩进大纲。
- **自定义 collector**（`Test_custom_collector`）：`toc#AddCollector()` 注册的 collector 生效。
- **调度**（`test-dispatch/`）：`IsAvailable`、`AddCollector`、collector 优先于 fold、无来源提示、标题格式、helptoc 委托。

以上折叠收集器测试都在 `nofoldenable` 下运行（见下文陷阱 5），覆盖了 `foldenable` 关闭时的回归场景。

## 关键陷阱

### 1. `legacy function!` 定义 foldexpr 辅助函数

`foldexpr` 是 legacy 表达式，且插件内部通过 legacy `eval()` 求值它（因为 vim9 的 `eval()` 无法调用用户 ftplugin 里的 legacy 全局函数）。因此测试里的 foldexpr 辅助函数必须用 `legacy function!` 定义：

```vim
legacy function! TocTestTomlFold(lnum) abort
    let l = getline(a:lnum)
    if l =~ '^\s*\[' 
        let dots = len(substitute(l, '[^.]', '', 'g'))
        return printf('>%d', dots + 1)
    endif
    return 1
endfunction
```

**注意**：`legacy function!` 的函数体里不要用 `.` 做字符串拼接（如 `' >' . (dots + 1)`），否则会被 vim9 解析器误报 `E488`。改用 `printf()`。

### 2. `setlocal foldmethod=` 非法

vim9 里 `setlocal foldmethod=`（置空）会报 `E474`。测试「空 foldmethod」场景应改用其他方式，或直接省略（`foldmethod` 默认是 `manual`，非空，`toc#IsAvailable()` 对它的判定已由 manual 用例覆盖）。

### 3. 测试文件必须从测试组目录运行

测试文件里的 `source ../init.vim` 是**相对 CWD** 的路径。运行器（Makefile/`run-tests.ps1`）通过 `-WorkingDirectory $testDir` 把 CWD 设为测试组目录。直接手敲命令时也要先 `cd` 到对应测试组目录。

### 4. `legacy function!` 与 vim9 的调用边界

vim9 脚本不能直接调用 legacy 全局函数（`E117`）。测试里对 foldexpr 辅助函数、自定义 collector 的调用都经由插件内部的 `call('FuncName', [])` 完成，测试自身只注册函数名字符串，不直接调用它们。

### 5. `nofoldenable` 陷阱

用户配置常含 `set nofoldenable`（所有折叠默认打开）。此时 Vim 的 `foldlevel(lnum)` / `foldclosed(lnum)` 对**每一行都返回 0 / -1**，折叠结构完全读不到。插件在 `FoldEntries()` 里临时 `&foldenable = true` 收集折叠，收集完恢复。

测试公共初始化 `g:RunTestInBuffer()` 里已 `setlocal nofoldenable`，使所有折叠收集器测试都在该条件下运行——若去掉插件里的 foldenable 处理，`Test_marker_strips_foldmarker`、`Test_generic_indent_fold`、`Test_generic_syntax_siblings` 都会失败（已实测验证）。

## 测试文件模板

```vim
vim9script

source ../init.vim

def Test_example()
    setlocal foldmethod=expr
    setlocal foldexpr=TocTestTomlFold(v:lnum)
    setline(1, ['[a]', 'x', '[b]'])
    assert_equal(['[a]', '[b]'], g:GetTocContent())
enddef

g:RunTestInBuffer(function('Test_example'))

if len(v:errors) > 0
    for err in v:errors
        echomsg err
    endfor
    cquit!
else
    echo 'test-xxx: All tests passed'
    quitall!
endif
```

## 测试辅助函数（test/init.vim）

| 函数 | 作用 |
|------|------|
| `g:RunTestInBuffer(F)` | 为每个测试创建独立缓冲区（`new` + `bwipe!`），隔离 foldmethod/foldexpr/foldenable 等状态（含 `setlocal nofoldenable`） |
| `g:CloseAllPopups()` | 关闭所有 popup（清理测试残留） |
| `g:GetTocContent()` | 调用 `toc#Open()` 并返回 popup 内容（`list<string>`），随后清理 popup |
| `g:GetTocTitle()` | 返回当前 popup 标题（需在 popup 打开时调用） |
| `TocTestTomlFold(lnum)` | 测试用 legacy foldexpr（模拟 TOML：表头 `>N`，普通行数字） |
| `TocTestCollector()` | 测试用 legacy collector（返回固定两条目） |
