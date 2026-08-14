# vim9-toc

**Unified table of contents for Vim — folds + helptoc delegation.**

A single `:Toc` command that gives any buffer an interactive, hierarchical
table of contents in a popup window. It delegates to Vim's built-in
[helptoc](https://github.com/vim/vim) for the filetypes helptoc already
understands, and derives an outline from Vim's own folding for everything else
— so any filetype that ships a folding ftplugin (TOML, YAML, JSON, Git, Vim
script, ...) works out of the box.

## Features

- One entry point for all filetypes: `:Toc`
- Delegates to the built-in helptoc for structured formats (help, markdown,
  LaTeX, HTML, AsciiDoc, man, ...)
- Fold-driven outline for anything Vim can fold (`foldmethod` expr / marker /
  syntax / indent)
- Indentation-based outline as a last resort for buffers without folding
- Extensible per-filetype "collectors" via `toc#AddCollector()`
- Interactive popup: navigate, jump, and collapse/expand levels

## Requirements

- Vim 9.0+ with `+popupwin`
- The helptoc delegation additionally requires Vim 9.1.1230+ (built-in
  helptoc); without it, `:Toc` still works via folding/indentation

## Installation

* **With vim-plug:**

```vim
Plug 'VimWei/vim9-toc'
```

* **Or with Vim built-in packages:**

```sh
mkdir -p ~/.vim/pack/toc/start
cd ~/.vim/pack/toc/start
git clone https://github.com/VimWei/vim9-toc.git
```

## Usage

```
:Toc
```

You may want a mapping:

```vim
nnoremap <Leader>ht <Cmd>Toc<CR>
```

### Popup mappings

| Key | Action |
|-----|--------|
| `j` / `k` / `<Down>` / `<Up>` | Select next / previous entry |
| `J` / `K` | Same as `j` / `k`, and jump the buffer to that entry |
| `gg` / `<Home>` | Select the first entry |
| `G` / `<End>` | Select the last entry |
| `H` / `L` | Collapse / expand one level |
| `<C-D>` / `<C-U>` | Scroll down / up half a page |
| `<PageDown>` / `<PageUp>` | Scroll down / up a whole page |
| `z` | Redraw with the selected entry centered |
| `?` | Show / hide the help window |
| `<C-J>` / `<C-K>` | Scroll the help window down / up one line |
| `<Enter>` | Jump to the selected entry and close |
| `<Esc>` | Close without jumping |

The popup title shows `index/total (current-level/max-level)` with a
`press ? for help ` hint on the right.

## Resolution order

For each buffer, `:Toc` resolves an outline in this order (highest priority
first):

1. helptoc native filetype → built-in `:HelpToc`
2. custom collector for the filetype → `toc#AddCollector()`
3. Vim folding → `'foldmethod'`
4. indentation fallback
5. gentle message (nothing to outline)

## Configuration

```vim
" String repeated per level below 1 in the popup (default "| ")
let g:toc_level_indicator = '| '

" Delegate helptoc native filetypes to the built-in :HelpToc (default 1)
let g:toc_use_helptoc = 1
```

## Extending

The preferred way to support a new format is to give it a folding ftplugin —
set `foldmethod`/`foldexpr` and `:Toc` picks it up automatically.

For formats whose headings are awkward to express as folds, register a custom
collector: a function that takes no arguments and returns a list of
`{lnum, lvl, text}` dictionaries (`lvl` starts at 1).

```vim
function! MyRstCollector() abort
    let entries = []
    for lnum in range(1, line('$'))
        let line = getline(lnum)
        if lnum < line('$') && line !~# '^\s*$'
                \ && getline(lnum + 1) =~# '^[=-]\+\s*$'
            let lvl = getline(lnum + 1) =~# '^=' ? 1 : 2
            call add(entries, {'lnum': lnum, 'lvl': lvl, 'text': trim(line)})
        endif
    endfor
    return entries
endfunction
call toc#AddCollector('rst', 'MyRstCollector')
```

## Documentation

```
:help toc
```

## Testing

See [doc/TESTING.md](doc/TESTING.md). Quick start:

```sh
cd test && make test            # Linux/macOS/Git Bash
cd test; .\run-tests.ps1        # Windows PowerShell
```

## Acknowledgements

Inspired by Vim's built-in [helptoc](https://github.com/vim/vim) and the
testing methodology of [vim-markdown-plus](https://github.com/VimWei/vim-markdown-plus).
