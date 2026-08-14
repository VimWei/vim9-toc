vim9script noclear

# toc.vim - unified table of contents (folds + helptoc delegation)
# Maintainer: W.Chen

import autoload '../autoload/toc.vim'

command -bar Toc toc.Open()
