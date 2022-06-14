{ config, pkgs, ... }: {
  programs.vim = {
    enable = true;

    plugins = [
      pkgs.vimPlugins.ale
      pkgs.vimPlugins.coc-nvim
      pkgs.vimPlugins.coc-go
      pkgs.vimPlugins.coc-yaml
      pkgs.vimPlugins.coc-json
      pkgs.vimPlugins.coc-vetur
      pkgs.vimPlugins.coc-eslint
      pkgs.vimPlugins.nerdtree
      pkgs.vimPlugins.nerdtree-git-plugin
      pkgs.vimPlugins.auto-pairs
      pkgs.vimPlugins.vim-gitgutter
      pkgs.vimPlugins.vim-commentary
      pkgs.vimPlugins.vim-airline
      pkgs.vimPlugins.fzf-vim
      pkgs.vimPlugins.vim-polyglot
      pkgs.vimPlugins.vim-devicons
      pkgs.vimPlugins.vim-tmux-navigator
      pkgs.vimPlugins.vim-surround
      pkgs.vimPlugins.vim-go
      pkgs.vimPlugins.vim-nix
      pkgs.vimPlugins.onedark-vim
    ];

    extraConfig =
    ''
      syntax on
      set number
      set relativenumber
      set hidden
      set backspace=indent,eol,start
      set re=0
      filetype plugin indent on

      let $RTP=split(&runtimepath, ',')[0]

      inoremap jk <Esc>

      set t_Co=256
      let base16colorspace=256
      set bg=dark
      set showcmd
      set cursorline
      set wildmenu
      set lazyredraw
      set showmatch

      set encoding=utf-8
      set nocompatible
      set swapfile
      set dir=/tmp

      command! -nargs=0 Sw w !sudo tee % > /dev/null

      set incsearch
      set hlsearch
      nnoremap <leader><space> :nohlsearch<CR>

      set foldenable
      set foldlevelstart=10
      set foldnestmax=10
      set foldmethod=indent

      nnoremap j gj
      nnoremap k gk
      nnoremap <C-J> <C-W><C-J>
      nnoremap <C-K> <C-W><C-K>
      nnoremap <C-L> <C-W><C-L>
      nnoremap <C-H> <C-W><C-H>
      set splitbelow
      set splitright

      if has("autocmd")
        au BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif
      endif

      set nobackup
      set nowritebackup
      set cmdheight=2
      set updatetime=300
      set shortmess+=c
      set signcolumn=yes

      inoremap <silent><expr> <TAB>
            \ pumvisible() ? "\<C-n>" :
            \ <SID>check_back_space() ? "\<TAB>" :
            \ coc#refresh()
      inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"
      function! s:check_back_space() abort
          let col = col('.') - 1
          return !col || getline('.')[col - 1]  =~# '\s'
      endfunction
      if has('nvim')
        inoremap <silent><expr> <c-space> coc#refresh()
      else
          inoremap <silent><expr> <c-@> coc#refresh()
      endif
      inoremap <silent><expr> <cr> pumvisible() ? coc#_select_confirm()
                                    \: "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"
      nmap <silent> [g <Plug>(coc-diagnostic-prev)
      nmap <silent> ]g <Plug>(coc-diagnostic-next)"
      nnoremap <silent> K :call <SID>show_documentation()<CR>
      function! s:show_documentation()
        if (index(['vim','help'], &filetype) >= 0)
          execute 'h '.expand('<cword>')
        elseif (coc#rpc#ready())
          call CocActionAsync('doHover')
        else
          execute '!' . &keywordprg . " " . expand('<cword>')
        endif
      endfunction
      autocmd CursorHold * silent call CocActionAsync('highlight')
      nmap <leader>rn <Plug>(coc-rename)
      nnoremap <nowait><expr> <C-f> coc#float#has_scroll() ? coc#float#scroll(1) : "\<C-f>"
      nnoremap <nowait><expr> <C-b> coc#float#has_scroll() ? coc#float#scroll(0) : "\<C-b>"
      inoremap <nowait><expr> <C-f> coc#float#has_scroll() ? "\<c-r>=coc#float#scroll(1)\<cr>" : "\<Right>"
      inoremap <nowait><expr> <C-b> coc#float#has_scroll() ? "\<c-r>=coc#float#scroll(0)\<cr>" : "\<Left>"
      let $FZF_DEFAULT_COMMAND = 'ag --hidden --ignore .git -g ""'
      let $FZF_DEFAULT_OPTS = "--preview 'bat --theme Dracula --color=always --style=header,grid --line-range :300 {}'"
      let g:fzf_preview_window = ['right:50%', 'ctrl-/']
      let g:fzf_layout = { 'window': { 'width': 0.9, 'height': 0.6  } }
      let g:fzf_colors =
      \ { 'fg':      ['fg', 'Normal'],
        \ 'bg':      ['bg', 'Normal'],
        \ 'hl':      ['fg', 'Comment'],
        \ 'fg+':     ['fg', 'CursorLine', 'CursorColumn', 'Normal'],
        \ 'bg+':     ['bg', 'CursorLine', 'CursorColumn'],
        \ 'hl+':     ['fg', 'Statement'],
        \ 'info':    ['bg', 'PreProc'],
        \ 'border':  ['fg', 'Keyword'],
        \ 'prompt':  ['fg', 'Conditional'],
        \ 'pointer': ['fg', 'Exception'],
        \ 'marker':  ['fg', 'Keyword'],
        \ 'spinner': ['fg', 'Label'],
        \ 'header':  ['fg', 'Comment'] }
      nnoremap <leader>f :Files<CR>
      nnoremap <leader>F :Rg<CR>
      nnoremap <leader>b :Buffers<CR>
      nnoremap <leader>t :BTags<CR>
      nnoremap <leader>T :Tags<CR>
      nmap <silent> ]e <Plug>(ale_next_wrap)
      nmap <silent> [e <Plug>(ale_previous_wrap)
      nnoremap gd :ALEGoToDefinition<CR>
      nnoremap <C-n> :NERDTreeToggle<CR>
      autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif
      let NERDTreeIgnore = [ '__pycache__', '\.pyc$', '\.o$', '\.swp',  '*\.swp',  'node_modules/' ]
      let NERDTreeShowHidden=1
      let NERDTreeChDirMode=2
      set laststatus=2
      function! s:check_back_space() abort
          let col = col('.') - 1
          return !col || getline('.')[col - 1]  =~# '\s'
      endfunction

      colorscheme onedark
    '';
  };
}
