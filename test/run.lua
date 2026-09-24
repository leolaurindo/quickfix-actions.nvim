vim.opt.rtp:prepend(vim.fn.getcwd())

local actions = require("quickfix_actions")

local function check(value, message)
	assert(value, message)
	return value
end

actions.setup()
check(vim.fn.exists(":QuickfixActionsOpen") == 0)
check(vim.fn.exists(":QuickfixActionsClose") == 0)
check(vim.fn.exists(":QuickfixActionsToggle") == 2)
check(vim.fn.exists(":QuickfixActionsDelete") == 2)
check(vim.fn.exists(":QuickfixActionsSearch") == 2)
check(vim.fn.exists(":QuickfixActionsHistory") == 2)
check(vim.fn.exists(":QuickfixActionsSetText") == 2)

local file = vim.fs.joinpath(vim.fn.getcwd(), "README.md")
vim.fn.setqflist({}, "r", {
	title = "diagnostics",
	context = { source = "test", keep = true },
	items = {
		{
			filename = file,
			lnum = 3,
			end_lnum = 4,
			col = 2,
			text = "problem",
			user_data = { producer = "test", nested = { keep = true } },
		},
		{ filename = file, lnum = 8, text = "second", user_data = { id = 2 } },
	},
})
check(actions.open())
local current = check(actions.current())
local target = { kind = "quickfix", id = current.id }
check(current.item and current.item.user_data.producer == "test")
check(actions.item(target, 1).user_data.nested.keep)

local original_tick = current.changedtick
vim.fn.setqflist({}, "r", {
	items = current.items,
	title = current.title,
	context = current.context,
	idx = current.index,
})
local stale_ok, stale_err = actions.replace(target, current.items, 1, original_tick)
check(not stale_ok and stale_err:find("changed", 1, true))

local refreshed = check(actions.read(target))
local replacement = vim.deepcopy(refreshed.items)
replacement[1].text = "updated"
replacement[1].user_data.extra = "preserved"
check(actions.replace(target, replacement, 1, refreshed.changedtick))
local after_replace = check(actions.read(target))
check(after_replace.title == "diagnostics")
check(after_replace.context.source == "test")
check(after_replace.items[1].user_data.extra == "preserved")

vim.api.nvim_win_set_cursor(0, { 2, 0 })
check(actions.delete_current())
check(#check(actions.read(target)).items == 1)
check(actions.clear(target))
check(#check(actions.read(target)).items == 0)

check(actions.close())
check(not actions.is_open({ kind = "quickfix" }))
check(actions.toggle({ kind = "quickfix" }))
check(actions.is_open({ kind = "quickfix" }))
check(actions.toggle({ kind = "quickfix" }))
check(not actions.is_open({ kind = "quickfix" }))

vim.fn.setqflist({}, " ", {
	title = "history first",
	items = { { filename = file, lnum = 1, text = "first" } },
})
local history_first = vim.fn.getqflist({ id = 0 }).id
vim.fn.setqflist({}, " ", {
	title = "picker",
	items = {
		{ filename = file, lnum = 3, text = "pick me" },
		{ filename = file, lnum = 8, text = "find this" },
	},
})
check(actions.open())
local entries = check(actions.entries({ list = { kind = "quickfix", id = vim.fn.getqflist({ id = 0 }).id } }))
check(#entries == 2 and entries[1].text == "pick me")
local history = check(actions.history({ kind = "quickfix" }))
check(history[#history].title == "picker" and history[#history].current)
check(history[#history - 1].id == history_first and history[#history - 1].count == 1)
check(actions.open_history({ kind = "quickfix" }))
local history_browser = check(actions.current())
local history_list = check(actions.read(history_browser))
check(history_list.title == "Quickfix history" and history_list.items[#history - 1].text:find("history first", 1, true))
check(vim.api.nvim_get_current_line() == history_list.items[1].text)
check(actions.open_history({ kind = "quickfix" }))
check(check(actions.current()).id == history_browser.id)
check(actions.jump(history_browser, #history - 1))
check(vim.fn.getqflist({ id = 0 }).id == history_first)
check(actions.open(entries[1].list))
local old_select = vim.ui.select
local selected
vim.ui.select = function(_, _, callback)
	callback("pick me", 1)
	selected = true
end
check(actions.pick({ list = entries[1].list }))
check(selected)
check(actions.open(entries[1].list))
local search_format
vim.ui.select = function(items, opts, callback)
	search_format = opts.format_item(items[2])
	callback(items[2], 2)
end
local source_buf = vim.api.nvim_get_current_buf()
check(actions.search({ list = entries[1].list }))
check(search_format:find("find this", 1, true) and vim.api.nvim_get_current_buf() == source_buf)
check(vim.api.nvim_win_get_cursor(0)[1] == 2)
vim.ui.select = old_select

local picker_id = entries[1].list.id
vim.fn.setqflist({}, "f", { id = picker_id })
local freed_qf, freed_qf_err = actions.read(entries[1].list)
check(not freed_qf and freed_qf_err:find("stale", 1, true))

vim.cmd("cclose")
vim.fn.setloclist(0, {}, "r", {
	title = "local diagnostics",
	context = { owner = true },
	items = { { filename = file, lnum = 5, text = "local", user_data = { keep = "yes" } } },
})
local owner = vim.api.nvim_get_current_win()
vim.cmd("lopen")
local local_current = check(actions.current())
check(local_current.kind == "location" and local_current.winid == owner)
local local_target = { kind = "location", id = local_current.id, winid = owner }
local local_value = check(actions.read(local_target))
local local_items = vim.deepcopy(local_value.items)
local_items[1].text = "local updated"
check(actions.replace(local_target, local_items, 1, local_value.changedtick))
local local_after = check(actions.read(local_target))
check(local_after.title == "local diagnostics")
check(local_after.context.owner and local_after.items[1].user_data.keep == "yes")

local invalid_ok, invalid_err = actions.read({ kind = "location", id = local_target.id, winid = 999999 })
check(not invalid_ok and invalid_err:find("invalid location", 1, true))
vim.api.nvim_set_current_win(owner)
vim.fn.setloclist(owner, {}, " ", {
	title = "local history second",
	items = { { filename = file, lnum = 6, text = "local second" } },
})
local local_history = check(actions.history({ kind = "location", winid = owner }))
check(local_history[#local_history].title == "local history second" and local_history[#local_history].current)
check(local_history[#local_history - 1].id == local_target.id)
check(actions.open_history({ kind = "location", winid = owner }))
local local_history_browser = check(actions.current())
check(check(actions.read(local_history_browser)).title == "Location-list history")
check(actions.jump(local_history_browser, #local_history - 1))
check(vim.fn.getloclist(owner, { id = 0 }).id == local_target.id)
check(actions.close(local_target))
check(actions.open(local_target, { vertical = true, width = 29 }))
local location_qfwin = vim.api.nvim_get_current_win()
check(vim.fn.getwininfo(location_qfwin)[1].loclist == 1)
check(vim.api.nvim_win_get_width(location_qfwin) == 29)
check(actions.close(local_target))
check(not actions.is_open({ kind = "location", winid = owner }))

local freed_id = local_target.id
vim.fn.setloclist(owner, {}, "f", { id = freed_id })
local freed_value, freed_err = actions.read(local_target)
check(not freed_value and freed_err:find("stale", 1, true))

local add_list_items = {
	{ filename = file, lnum = 2, text = "keep" },
}
vim.fn.setqflist({}, " ", {
	title = "append target",
	context = { marker = true },
	items = add_list_items,
})
local add_target = { kind = "quickfix", id = vim.fn.getqflist({ id = 0 }).id }
check(actions.add_file(add_target, file))
local file_level = check(actions.read(add_target))
check(#file_level.items == 2 and file_level.items[2].lnum == 0 and file_level.items[2].text == "")
check(file_level.title == "append target" and file_level.context.marker)
local text_snapshot = check(actions.current(add_target))
check(actions.set_text(add_target, 1, "updated note", text_snapshot.changedtick))
local text_updated = check(actions.read(add_target))
check(text_updated.items[1].text == "updated note" and text_updated.context.marker)
local stale_text, stale_text_err = actions.set_text(add_target, 1, "stale", text_snapshot.changedtick)
check(not stale_text and stale_text_err:find("changed", 1, true))
local append_tick = text_updated.changedtick
check(actions.add_file(add_target, file, 3, 6, append_tick))
local range_item = check(actions.read(add_target)).items[3]
check(range_item.lnum == 3 and range_item.end_lnum == 6)
local stale_append, stale_append_err = actions.add_file(add_target, file, nil, nil, append_tick)
check(not stale_append and stale_append_err:find("changed", 1, true))
check(#check(actions.read(add_target)).items == 3)

local old_select_history = vim.ui.select
local chosen_history
vim.ui.select = function(labels, opts, callback)
	check(labels[1]:find("#", 1, true))
	callback(labels[1], 1)
end
check(actions.choose_history({ kind = "quickfix" }, function(target)
	chosen_history = target
end))
check(chosen_history and chosen_history.kind == "quickfix" and chosen_history.id)
vim.ui.select = function(_, _, callback)
	callback(nil, nil)
end
local unchanged_items = #check(actions.read(add_target)).items
check(actions.choose_history({ kind = "quickfix" }, function()
	error("cancel should not select")
end))
check(#check(actions.read(add_target)).items == unchanged_items)
vim.ui.select = old_select_history

vim.cmd(("QuickfixActionsAddFile %s 8:10 %d"):format(file, add_target.id))
local command_item = check(actions.read(add_target)).items[4]
check(vim.api.nvim_buf_get_name(command_item.bufnr) == file and command_item.lnum == 8 and command_item.end_lnum == 10)
vim.api.nvim_set_current_buf(vim.fn.bufadd(file))
vim.cmd("QuickfixActionsAddCurrent")
vim.cmd("2,4QuickfixActionsAddRange")
vim.cmd(("QuickfixActionsAddCurrent %d"):format(add_target.id))
vim.cmd(("QuickfixActionsAddFile %s 14:15"):format(file))
local command_items = check(actions.read(add_target)).items
check(#command_items == 8 and command_items[5].lnum == 0 and command_items[7].lnum == 0)
check(command_items[6].lnum == 2 and command_items[6].end_lnum == 4)
check(command_items[8].lnum == 14 and command_items[8].end_lnum == 15)
vim.ui.select = function(labels, _, callback)
	for index, label in ipairs(labels) do
		if label:find("#" .. add_target.id .. ",", 1, true) then
			callback(label, index)
			return
		end
	end
	error("append target was not offered in history")
end
vim.cmd(("QuickfixActionsAddFileHistory %s 12:13"):format(file))
vim.ui.select = old_select_history
local selected_item = check(actions.read(add_target)).items[9]
check(selected_item.lnum == 12 and selected_item.end_lnum == 13)

check(actions.open(add_target, { vertical = true, width = 31, wrap = true, linebreak = true, breakindent = true }))
local qfwin = vim.api.nvim_get_current_win()
check(vim.fn.getwininfo(qfwin)[1].quickfix == 1)
check(vim.api.nvim_win_get_width(qfwin) == 31)
check(vim.wo[qfwin].wrap and vim.wo[qfwin].linebreak and vim.wo[qfwin].breakindent)
vim.api.nvim_win_set_cursor(qfwin, { 2, 0 })
vim.cmd("QuickfixActionsSetText added manual message")
check(check(actions.read(add_target)).items[2].text == "added manual message")
check(actions.close())
check(actions.open(add_target, { height = 7 }))
check(vim.api.nvim_win_get_height(0) == 7)
check(actions.close())
check(actions.toggle(add_target, { vertical = true, width = 30 }))
check(actions.is_open(add_target) and vim.api.nvim_win_get_width(0) == 30)
check(actions.toggle(add_target))
check(actions.open_history({ kind = "quickfix" }, { vertical = true, width = 32, wrap = true }))
local browser_win = vim.api.nvim_get_current_win()
check(vim.fn.getwininfo(browser_win)[1].quickfix == 1)
check(vim.api.nvim_win_get_width(browser_win) == 32 and vim.wo[browser_win].wrap)
check(actions.close())

print("quickfix_actions tests passed")
