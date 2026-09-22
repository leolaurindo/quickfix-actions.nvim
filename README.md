# quickfix-actions.nvim

Collection of native actions for Neovim quickfix and location lists.
Open, close, jump, pick, delete, clear, and replace entries in Neovim's native list UI.
It also opens history as native quickfix lists.
No runtime dependencies.

Requires Neovim 0.10+.

Part the [quickfix-kit.nvim](https://github.com/leolaurindo/quickfix-kit.nvim) package; 

## Installation

With lazy.nvim:

```lua
{ "leolaurindo/quickfix-actions.nvim", opts = {} }
```

With `vim.pack` (Neovim 0.12+):

```lua
vim.pack.add({ "https://github.com/leolaurindo/quickfix-actions.nvim" }, { load = true })
require("quickfix_actions").setup()
```

## Setup

```lua
require("quickfix_actions").setup()
```


## Targets

Use stable native list IDs:

```lua
{ kind = "quickfix", id = 42 }
{ kind = "location", id = 17, winid = 1001 }
```

For a location list, `winid` is its owning file window. An omitted target uses
the current list. Explicit stale IDs and invalid owners return `nil, error`
instead of falling back.

## Lua API

```lua
local actions = require("quickfix_actions")

local current = assert(actions.current())
local item = assert(actions.item({ kind = current.kind, id = current.id, winid = current.winid }, 1))
actions.replace({ kind = current.kind, id = current.id, winid = current.winid }, current.items, current.index, current.changedtick)
actions.delete_current()
actions.clear()
actions.open()
actions.close()
actions.toggle()
actions.history()
actions.open_history()
actions.pick()
actions.search()
```

Available operations are `read`, `current`, `item`, `replace`, `delete`,
`delete_current`, `clear`, `jump`, `select`, `open`, `close`, `is_open`,
`toggle`, `history`, `open_history`, `entries`, `pick`, and `search`.
`history()` returns live native quickfix or location-list history entries;
`open_history()` opens them in a native quickfix list. Snapshots retain native
fields and `user_data`. Mutations can check an expected `changedtick`; `clear` and
`delete_current` use the snapshot tick they read.

`entries()` returns picker entries. `pick()` uses `vim.ui.select` and native
`cc`/`ll` navigation. `search()` searches path and native entry text with a
compact live picker when Snacks is available, then focuses the selected row in
the open quickfix/location-list window without jumping to the source buffer.
Without Snacks, it falls back to `vim.ui.select`.

Customize the search display and confirmation behavior:

```lua
actions.search({
  prompt = "Search diagnostics",
  format_item = function(entry)
    return (entry.path or "[no file]") .. " - " .. entry.text
  end,
  on_confirm = function(entry)
    return actions.select(entry.list, entry.index)
  end,
})
```

## Commands and mappings

| Command | Action |
| --- | --- |
| `:QuickfixActionsOpen [quickfix\|location]` | Open a list |
| `:QuickfixActionsClose [quickfix\|location]` | Close a list |
| `:QuickfixActionsToggle [quickfix\|location]` | Toggle a list |
| `:QuickfixActionsHistory [quickfix\|location]` | Open the history browser |
| `:QuickfixActionsPick` | Pick an entry and jump to its source |
| `:QuickfixActionsSearch` | Search the current list and focus the selected row |
| `:QuickfixActionsJump` | Jump to the current entry |
| `:QuickfixActionsDelete` / `:QuickfixActionsDeleteCurrent` | Delete the current entry |
| `:QuickfixActionsClear` | Clear the current list |

Default qf-local mappings are `<CR>` for jump and `dd` for delete. Configure or
disable them without taking over native navigation:

```lua
require("quickfix_actions").setup({
  mappings = {
    qf = {
      ["<CR>"] = false,
      dd = "delete",
    },
  },
})
```

Set `mappings.qf = false` for no qf-local mappings. `[q`, `]q`, `[l`, and `]l`
remain native; the plugin does not own `quickfixtextfunc`.

## Tests

```sh
nvim --headless -u NONE -l test/run.lua
```
