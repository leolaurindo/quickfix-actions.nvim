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
actions.open(nil, { vertical = true, width = 40, wrap = true })
actions.close()
actions.toggle()
actions.history()
actions.open_history()
actions.pick()
actions.search()
```

Available operations are `read`, `current`, `item`, `replace`, `append`,
`set_text`, `add_file`, `delete`, `delete_current`, `clear`, `jump`, `select`,
`open`, `close`, `is_open`, `toggle`, `history`, `open_history`, `choose_history`,
`entries`, `pick`, and `search`.
`history()` returns live native quickfix or location-list history entries;
`open_history()` opens them in a native quickfix list. Snapshots retain native
fields and `user_data`. Mutations can check an expected `changedtick`; `clear` and
`delete_current` use the snapshot tick they read.

`entries()` returns picker entries. `pick()` uses `vim.ui.select` and native
`cc`/`ll` navigation. `search()` searches path and native entry text with a
compact live picker when Snacks is available, then focuses the selected row in
the open quickfix/location-list window without jumping to the source buffer.
Without Snacks, it falls back to `vim.ui.select`.

`open(target, opts)` accepts `vertical = true` and optional `width`; otherwise
it retains the horizontal layout and `height` behavior. `wrap`, `linebreak`, and
`breakindent` are optional window-local booleans and are only applied when
specified. The same options are accepted by `toggle()` and `open_history()`.

`append(target, items, expected_tick)` appends native items while preserving
list contents and metadata. `replace(target, items, idx, expected_tick)` replaces
the full item array while retaining list metadata. `set_text(target, index, text,
expected_tick)` changes one item's message without requiring callers to rebuild
the list. All three can guard against concurrent edits with `changedtick`.

`add_file(target, path, first, last, expected_tick)` adds a file-level item or
an item retaining the supplied start/end line range; its text is empty by
default. Pass `{ kind = "quickfix" }` to use the current list or include `id`
for a specific list. `choose_history(callback)` uses `vim.ui.select()` and calls
back with a stable `{ kind, id, winid }` target. Canceling does not mutate lists.

Example: change one entry's message without replacing the list yourself:

```lua
local current = assert(actions.current())
actions.set_text({ kind = current.kind, id = current.id, winid = current.winid }, 1, "reviewed", current.changedtick)
```

The add commands are quickfix-list scoped. Their optional list ID defaults to
the current quickfix list. IDs are trailing arguments:
`QuickfixActionsAddCurrent [id]`, `QuickfixActionsAddRange [id]`, and
`QuickfixActionsAddFile {path} [start:end] [id]`. File ranges use `3:6`; the
current-file range command accepts a visual or Ex line range. The `...History`
variants select a list from history instead of using the current list.

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
| `:QuickfixActionsToggle [quickfix\|location]` | Toggle a list |
| `:QuickfixActionsHistory [quickfix\|location]` | Open the history browser |
| `:QuickfixActionsPick` | Pick an entry and jump to its source |
| `:QuickfixActionsSearch` | Search the current list and focus the selected row |
| `:QuickfixActionsJump` | Jump to the current entry |
| `:QuickfixActionsDelete` / `:QuickfixActionsDeleteCurrent` | Delete the current entry |
| `:QuickfixActionsClear` | Clear the current list |
| `:QuickfixActionsAddCurrent [id]` | Add the current file to the current or specified quickfix list |
| `:[range]QuickfixActionsAddRange [id]` | Add the current file and range to the current or specified list |
| `:QuickfixActionsAddFile {path} [start:end] [id]` | Add a file or range to the current or specified list |
| `:QuickfixActionsAddCurrentHistory` | Choose a history list, then add the current file |
| `:[range]QuickfixActionsAddRangeHistory` | Choose a history list, then add the current range |
| `:QuickfixActionsAddFileHistory {path} [start:end]` | Choose a history list, then add a file or range |
| `:QuickfixActionsSetText {text}` | Replace the current entry's message from an open list window |

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
