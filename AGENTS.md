# AGENTS.md

## Repo facts
- **Vim plugin** (`vim9-toc`) — unified table of contents: folds + helptoc delegation
- **Vim9 script only** — every `.vim` file starts with `vim9script`; use Vim9 syntax (not legacy VimL)
- **Min Vim version**: 9.0 with `+popupwin`. The helptoc delegation additionally requires 9.1.1230+ (guarded at runtime).
- **Remote**: `git@github.com:VimWei/vim9-toc.git`
- Test guide in `doc/TESTING.md`.

## Directory layout
| Path | Role |
|---|---|
| `plugin/toc.vim` | Plugin entrypoint; defines the `:Toc` command → `toc.Open()` |
| `autoload/toc.vim` | All logic: dispatcher, collectors, popup navigation |
| `doc/toc.txt` | Help doc (`:help toc`) |
| `doc/TESTING.md` | Test guide (zero-dependency, `assert_*` + `v:errors`) |
| `test/` | Test infrastructure and test groups (`test-collectors/`, `test-dispatch/`, `test-filter/`) |

## External dependencies
- **Built-in helptoc** (`$VIMRUNTIME/pack/dist/opt/helptoc`) — delegated to for
  helptoc native filetypes; loaded via `packadd helptoc` at runtime. Optional:
  the plugin falls back to folding/indentation when helptoc is absent.

## Core concepts
- **Resolution order** (highest priority first):
  1. helptoc native filetype (`help info asciidoc html man markdown tex vim xhtml`, or `buftype=terminal`) → built-in `:HelpToc`
  2. custom collector (`g:toc_collectors`, see below) → `toc#AddCollector()`
  3. Vim folding (`'foldmethod'` expr / marker / syntax / indent)
  4. indentation fallback
  5. gentle message
- **Collector contract**: a function name (String) taking no args, returning a
  list of `{lnum, lvl, text}` dicts (`lvl` starts at 1). Registered via
  `toc#AddCollector(ft, fn)`; takes precedence over folding for its filetype.
- **Public API**: `toc#Open()`, `toc#IsAvailable()`, `toc#AddCollector(ft, fn)`,
  `toc#FuzzyMatch(winid, text)`.

## Conventions
- Config via `g:toc_level_indicator` (default `'| '`) and `g:toc_use_helptoc`
  (default `1`).
- Popup mappings: `j/k/<Down>/<Up>` move, `J/K` move + jump buffer, `gg/<Home>`
  first entry, `G/<End>` last entry, `H/L` collapse/expand level,
  `<C-D>/<C-U>/<PageDown>/<PageUp>` scroll, `z` center, `/` fuzzy search,
  `?` toggle help window, `<C-J>/<C-K>` scroll help window, `<Enter>` jump+close,
  `<Esc>` close. The
  navigation keys mirror helptoc's `Filter()`; the title right-aligned hint is
  "press ? for help ".
- Fold collectors read `'foldmethod'` directly — never mutate the buffer's fold
  settings (the indentation fallback scans indentation without touching folds).

## Key implementation notes
- **Legacy foldexpr bridge**: Vim9's `eval()` cannot call legacy global
  functions defined in user ftplugins (E117). `CollectExpr` therefore evaluates
  the foldexpr through `legacy function! TocEvalFoldexpr()` via `call()`. Do not
  remove this indirection.
- **Do not use `.` string concatenation inside `legacy function!` bodies** — it
  is mis-parsed by the Vim9 scanner (E488). Use `printf()`.
- **`setlocal foldmethod=` (empty) is invalid** (E474); `'foldmethod'` is never
  truly empty (defaults to `"manual"`).
- **`'foldenable'` must be on to read folds**: with `nofoldenable` (common in
  user configs), `foldlevel()` and `foldclosed()` return `0`/`-1` for every
  line. `FoldEntries()` therefore temporarily sets `&foldenable = true` around
  the collection and restores it afterwards. `CollectGeneric` additionally
  temporarily adjusts `'foldlevel'` to enumerate sibling folds.
- **Popup syntax**: `ApplyTocSyntax()` defines `TocLevel`/`TocText` syntax in
  the popup buffer — the level indicator is linked to `NonText` (dim), the text
  to `Normal` — matching helptoc's `SanitizedTocSyntax()`. It runs right after
  `popup_menu()` (which returns the winid immediately, not blocking).
- **Fuzzy search** (`/`): mirrors helptoc's `FuzzySearch()` — `autocmd_add`
  (`CmdlineChanged`→`FuzzySearch`, `CmdlineLeave`→`TearDown`) + cmdline
  `<buffer>` mappings + `input()` with `custom,{Complete->string()}` completion,
  then `matchfuzzypos()` + textprops (`toc-fuzzy`, `IncSearch`) for the match
  highlight. `matchfuzzypos()` returns match positions as *character* indices,
  but text prop `col`/`length` are counted in *bytes* — so the props are built
  with `byteidx()` (char index → byte offset) and the byte length of each matched
  char (`byteidx(cp + 1) - byteidx(cp)`).  This mirrors the upstream helptoc fix
  (vim/vim#21056) for multibyte text.

## Testing
- **Runners**: `make test` (from `test/`, Linux/macOS/Git Bash),
  `.\run-tests.ps1` (PowerShell, from `test/`), `run-tests.cmd` (CMD).
- **Single test**: `vim -es -T dumb --not-a-term --noplugin -n -u test-xxx.vim +qall`
  (run from the test group directory — `source ../init.vim` is CWD-relative).
- **Headless popup inspection**: `popup_menu()` returns immediately in `-es`
  mode but still creates the popup window; tests assert the outline by reading
  it back via `popup_list()` + `getbufline()`. See `test/init.vim` helpers
  (`g:GetTocContent()`, `g:RunTestInBuffer()`, ...).
- **Rules**: pure Vim9 script, no test framework, built-in `assert_*`, each test
  function independent (wrapped by `g:RunTestInBuffer()`).
- **Test groups**:
  - `test-collectors/`: expr (sibling + nesting), marker, generic (indent +
    JSON syntax siblings), indentation fallback, custom collector
  - `test-dispatch/`: `IsAvailable`, `AddCollector`, collector-over-fold
    priority, no-outline, title format, helptoc delegation
  - `test-filter/`: `/` fuzzy search (single/multiple match, empty query
    restores full view, no match)

## Gotchas
- helptoc delegation emits a harmless `pack/*/start/helptoc` not-found message
  under `--noplugin` (the "start" round before the "opt" round). Expected, not
  an error.
