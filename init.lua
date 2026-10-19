-- Neovim config: LSP (Go, TypeScript/React), treesitter highlighting,
-- merge conflict navigation.
--
-- Requirements on each machine: Neovim >= 0.12, git, a C compiler,
-- tree-sitter CLI (`brew install tree-sitter-cli`), Go (for gopls),
-- Node (for the TypeScript server). Plugins and language servers
-- install themselves on first launch.

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Options -------------------------------------------------------------------

local opt = vim.opt
opt.number = true
opt.relativenumber = true
opt.signcolumn = "yes"
opt.termguicolors = true
opt.cursorline = true
opt.scrolloff = 8
opt.mouse = "a"
opt.clipboard = "unnamedplus"
opt.ignorecase = true
opt.smartcase = true
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.splitright = true
opt.splitbelow = true
opt.undofile = true
opt.updatetime = 250
opt.completeopt = { "menuone", "noselect", "popup" }

-- Go uses tabs.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "go",
  callback = function()
    vim.opt_local.expandtab = false
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
  end,
})

-- Plugins (lazy.nvim, bootstrapped on first run) -----------------------------

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

local parsers = {
  "go", "gomod", "gosum", "gowork",
  "typescript", "tsx", "javascript", "jsdoc",
  "json", "yaml", "html", "css",
  "lua", "vim", "vimdoc", "bash", "markdown", "markdown_inline",
}

require("lazy").setup({
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    config = function()
      vim.cmd.colorscheme("catppuccin-mocha")
    end,
  },

  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").install(parsers)
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          -- Start highlighting for any filetype that has a parser installed.
          if pcall(vim.treesitter.start, args.buf) then
            vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
  },

  -- Server definitions for vim.lsp.enable().
  { "neovim/nvim-lspconfig" },

  -- Installs language servers and enables them.
  { "mason-org/mason.nvim", opts = {} },
  {
    "mason-org/mason-lspconfig.nvim",
    dependencies = { "mason-org/mason.nvim", "neovim/nvim-lspconfig" },
    opts = {
      ensure_installed = { "gopls", "ts_ls" },
    },
  },
}, {
  install = { colorscheme = { "catppuccin-mocha" } },
  change_detection = { notify = false },
})

-- LSP ----------------------------------------------------------------------

vim.lsp.config("gopls", {
  settings = {
    gopls = {
      gofumpt = false,
      staticcheck = true,
      usePlaceholders = true,
      analyses = { unusedparams = true },
    },
  },
})

vim.diagnostic.config({
  virtual_text = true,
  severity_sort = true,
  float = { border = "rounded" },
})

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = assert(vim.lsp.get_client_by_id(args.data.client_id))
    local buf = args.buf
    local map = function(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { buffer = buf, desc = desc })
    end

    -- Built-in defaults already cover: K (hover), grn (rename),
    -- gra (code action), grr (references), gri (implementation),
    -- gO (document symbols), [d / ]d (diagnostics), <C-s> (signature help).
    map("gd", vim.lsp.buf.definition, "Go to definition")
    map("gD", vim.lsp.buf.declaration, "Go to declaration")
    map("gy", vim.lsp.buf.type_definition, "Go to type definition")
    map("<leader>e", vim.diagnostic.open_float, "Show diagnostic")

    -- Built-in completion popup as you type.
    if client:supports_method("textDocument/completion") then
      vim.lsp.completion.enable(true, client.id, buf, { autotrigger = true })
    end

    -- Go: organize imports and format on save.
    if client.name == "gopls" then
      vim.api.nvim_create_autocmd("BufWritePre", {
        buffer = buf,
        callback = function()
          local params = vim.lsp.util.make_range_params(0, client.offset_encoding)
          params.context = { only = { "source.organizeImports" }, diagnostics = {} }
          local res = client:request_sync("textDocument/codeAction", params, 1000, buf)
          for _, action in ipairs(res and res.result or {}) do
            if action.edit then
              vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
            end
          end
          vim.lsp.buf.format({ bufnr = buf, id = client.id, timeout_ms = 1000 })
        end,
      })
    end
  end,
})

-- Merge conflicts ------------------------------------------------------------

-- Matches the start of a conflict block as written by git and Sapling.
local conflict_start = [[^<<<<<<<\( \|$\)]]

local function jump_conflict(backward)
  local flags = backward and "bW" or "W"
  if vim.fn.search(conflict_start, flags) == 0 then
    -- Wrap around, but say so.
    local pos = vim.api.nvim_win_get_cursor(0)
    vim.api.nvim_win_set_cursor(0, backward and { vim.fn.line("$"), 0 } or { 1, 0 })
    if vim.fn.search(conflict_start, backward and "bcW" or "cW") == 0 then
      vim.api.nvim_win_set_cursor(0, pos)
      vim.notify("No merge conflicts in buffer", vim.log.levels.INFO)
      return
    end
    vim.notify("Wrapped around", vim.log.levels.INFO)
  end
  vim.cmd("normal! zz")
end

local function list_conflicts()
  vim.cmd("silent! vimgrep /" .. conflict_start .. "/j %")
  if #vim.fn.getqflist() == 0 then
    vim.notify("No merge conflicts in buffer", vim.log.levels.INFO)
  else
    vim.cmd("copen")
  end
end

vim.keymap.set("n", "]x", function() jump_conflict(false) end, { desc = "Next merge conflict" })
vim.keymap.set("n", "[x", function() jump_conflict(true) end, { desc = "Previous merge conflict" })
vim.keymap.set("n", "<leader>x", list_conflicts, { desc = "List merge conflicts" })

-- Highlight conflict markers so they stand out.
vim.api.nvim_set_hl(0, "ConflictMarker", { link = "DiffText" })
vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
  callback = function()
    if vim.w.conflict_match then return end
    vim.w.conflict_match = vim.fn.matchadd(
      "ConflictMarker", [[^\(<<<<<<<\|=======\||||||||\|>>>>>>>\)\( .*\)\?$]]
    )
  end,
})

-- General keymaps ------------------------------------------------------------

vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")
