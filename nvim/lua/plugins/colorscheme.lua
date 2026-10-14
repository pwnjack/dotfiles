-- Follow the wallpaper: pywal16.nvim reads ~/.cache/wal/colors-wal.vim, which
-- nvim/apply_wal_colors.sh renders on every palette change. Before that file
-- exists, LazyVim's default tokyonight stays the fallback.
-- nvim/apply_wal_colors.sh re-applies the scheme in running instances.
local function wal_colors()
  local cache = os.getenv("XDG_CACHE_HOME")
  if not cache or cache == "" then
    cache = os.getenv("HOME") .. "/.cache"
  end
  return cache .. "/wal/colors-wal.vim"
end

return {
  {
    "uZer/pywal16.nvim",
    name = "pywal16",
    lazy = false,
    priority = 1000,
    init = function()
      -- The scheme never sets g:colors_name, which apply_wal_colors.sh reads to
      -- tell a pywal16 instance from one whose user picked another scheme.
      vim.api.nvim_create_autocmd("ColorScheme", {
        pattern = "pywal16",
        callback = function()
          vim.g.colors_name = "pywal16"
        end,
      })
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        if vim.fn.filereadable(wal_colors()) == 1 then
          vim.cmd.colorscheme("pywal16")
        else
          vim.cmd.colorscheme("tokyonight")
        end
      end,
    },
  },
}
