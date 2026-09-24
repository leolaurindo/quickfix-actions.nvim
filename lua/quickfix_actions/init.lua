local lists = require("quickfix_actions.lists")
local picker = require("quickfix_actions.picker")

local M = {}

local defaults = {
	layout = "bottom",
	mappings = {
		qf = {
			["<CR>"] = "jump",
			dd = "delete",
		},
	},
}

local config = vim.deepcopy(defaults)
local setup_done = false
local remembered_layouts = {}
local remembered_windows = {}
local layout_cycle = { "bottom", "left", "top", "right" }
local layout_aliases = { horizontal = "bottom", vertical = "right" }

local function normalize_layout(layout)
	layout = layout_aliases[layout] or layout
	if layout == "full" then
		return layout
	end
	for _, value in ipairs(layout_cycle) do
		if value == layout then
			return value
		end
	end
end

local function target_key(target)
	return table.concat({ target.kind, target.id or 0, target.winid or 0 }, ":")
end

local function remember_layout(target, layout)
	if target and target.id then
		remembered_layouts[target_key(target)] = layout
	end
end

local function target_layout(target)
	return remembered_layouts[target_key(target)] or config.layout
end

local function target_window(target)
	local winid = lists.window(target)
	if winid then
		return winid
	end
	winid = remembered_windows[target_key(target)]
	if not winid or not vim.api.nvim_win_is_valid(winid) then
		return
	end
	local info = vim.fn.getwininfo(winid)[1]
	if not info or info.quickfix ~= 1 then
		return
	end
	if target.kind == "location" then
		local ok, value = pcall(vim.fn.getloclist, winid, { all = 1 })
		if ok and value.id == target.id and value.filewinid == target.winid then
			return winid
		end
	elseif vim.fn.getqflist({ id = 0 }).id == target.id then
		return winid
	end
end

local function next_layout(layout)
	for index, value in ipairs(layout_cycle) do
		if value == layout then
			return layout_cycle[index % #layout_cycle + 1]
		end
	end
	return layout_cycle[1]
end

local function notify(message, level)
	vim.notify(message, level, { title = "QuickfixActions" })
end

local function report(callback)
	local ok, err = callback()
	if not ok and err then
		notify(tostring(err), vim.log.levels.WARN)
	end
	return ok, err
end

local function command_target(opts)
	if opts.args == "" then
		return nil
	end
	return { kind = opts.args }
end

local function command(name, callback, opts)
	vim.api.nvim_create_user_command(name, callback, vim.tbl_extend("force", { force = true }, opts or {}))
end

local function window_layout(winid)
	local previous = vim.api.nvim_get_current_win()
	if previous ~= winid then
		vim.api.nvim_set_current_win(winid)
	end
	local tree = vim.fn.winlayout()
	if previous ~= winid and vim.api.nvim_win_is_valid(previous) then
		vim.api.nvim_set_current_win(previous)
	end
	if tree[1] == "leaf" and tree[2] == winid then
		return "full"
	end
	local function locate(node)
		if node[1] == "leaf" then
			return node[2] == winid, nil
		end
		local children = node[2]
		for index, child in ipairs(children) do
			local found, layout = locate(child)
			if found then
				if layout or #children == 1 then
					return true, layout
				end
				local before_middle = index <= #children / 2
				if node[1] == "row" then
					return true, before_middle and "left" or "right"
				end
				return true, before_middle and "top" or "bottom"
			end
		end
		return false
	end
	local _, layout = locate(tree)
	return layout
end

local function close_list_window(winid, kind, target)
	vim.api.nvim_set_current_win(winid)
	if window_layout(winid) == "full" then
		vim.cmd("silent tabclose")
	else
		vim.cmd("silent " .. (kind == "location" and "lclose" or "cclose"))
	end
	if target then
		remembered_windows[target_key(target)] = nil
	end
end

local function install_commands()
	command("QuickfixActionsToggle", function(opts)
		report(function()
			return M.toggle(command_target(opts))
		end)
	end, { nargs = "?", complete = function()
		return { "quickfix", "location" }
	end, desc = "Toggle a native quickfix or location list window" })
	command("QuickfixActionsLayoutToggle", function(opts)
		report(function()
			local target = command_target(opts)
			local current, err = M.current(target)
			if not current then
				return nil, err
			end
			target = { kind = current.kind, id = current.id, winid = current.winid }
			local winid = target_window(target)
			local layout
			if winid then
				layout = window_layout(winid)
				if not layout then
					return nil, "could not determine native list position"
				end
				layout = next_layout(layout)
				local ok, close_err = M.close(target)
				if not ok then
					return nil, close_err
				end
			else
				layout = target_layout(target)
			end
			return M.open(target, { layout = layout })
		end)
	end, { nargs = "?", complete = function()
		return { "quickfix", "location" }
	end, desc = "Toggle a native quickfix or location list" })
	command("QuickfixActionsLayout", function(opts)
		report(function()
			local layout, kind = unpack(opts.fargs)
			layout = normalize_layout(layout)
			if not layout then
				return nil, "usage: QuickfixActionsLayout full|top|left|right|bottom [quickfix|location]"
			end
			kind = kind or lists.current_kind()
			if kind ~= "quickfix" and kind ~= "location" then
				return nil, "list kind must be quickfix or location"
			end
			if #opts.fargs > 2 then
				return nil, "usage: QuickfixActionsLayout full|top|left|right|bottom [quickfix|location]"
			end
			local current, err = M.current({ kind = kind })
			if not current then
				return nil, err
			end
			local target = { kind = current.kind, id = current.id, winid = current.winid }
			if M.is_open(target) then
				local ok, close_err = M.close(target)
				if not ok then
					return nil, close_err
				end
			end
			return M.open(target, { layout = layout })
		end)
	end, { nargs = "+", complete = function(_, line)
		local args = vim.split(line, "%s+")
		if #args <= 2 then
			return { "full", "top", "left", "right", "bottom" }
		end
		return { "quickfix", "location" }
	end, desc = "Set the current native list split position" })
	command("QuickfixActionsPick", function()
		report(function()
			return M.pick()
		end)
	end, { desc = "Pick an entry from the current native list" })
	command("QuickfixActionsHistory", function(opts)
		report(function()
			return M.open_history(command_target(opts))
		end)
	end, { nargs = "?", complete = function()
		return { "quickfix", "location" }
	end, desc = "Pick a native quickfix or location-list history entry" })
	command("QuickfixActionsSearch", function()
		report(function()
			return M.search()
		end)
	end, { desc = "Search the current native list" })
	command("QuickfixActionsJump", function()
		report(function()
			return M.jump()
		end)
	end, { desc = "Jump to the current native list entry" })
	command("QuickfixActionsDelete", function()
		report(function()
			return M.delete_current()
		end)
	end, { desc = "Delete the current native list entry" })
	command("QuickfixActionsDeleteCurrent", function()
		report(function()
			return M.delete_current()
		end)
	end, { desc = "Delete the current native list entry" })
	command("QuickfixActionsClear", function()
		report(function()
			return M.clear()
		end)
	end, { desc = "Clear the current native list" })
	local function add_current(target, first, last)
		local file = vim.api.nvim_buf_get_name(0)
		return M.add_file(target, file, first, last)
	end
	command("QuickfixActionsAddCurrent", function(opts)
		report(function()
			local id = opts.args ~= "" and tonumber(opts.args) or nil
			if opts.args ~= "" and not id then
				return nil, "quickfix list ID must be a number"
			end
			return add_current({ kind = "quickfix", id = id })
		end)
	end, { nargs = "?", desc = "Add the current file to the current or specified quickfix list" })
	command("QuickfixActionsAddRange", function(opts)
		report(function()
			local id = opts.args ~= "" and tonumber(opts.args) or nil
			if opts.args ~= "" and not id then
				return nil, "quickfix list ID must be a number"
			end
			return add_current({ kind = "quickfix", id = id }, opts.line1, opts.line2)
		end)
	end, { nargs = "?", range = true, desc = "Add the current file and selected range to the current or specified quickfix list" })
	local function command_range(value)
		if not value then
			return nil, nil, true
		end
		local first, last = value:match("^(%d+):(%d+)$")
		if not first then
			return nil, nil, false
		end
		return tonumber(first), tonumber(last), true
	end
	command("QuickfixActionsAddFile", function(opts)
		report(function()
			local args = opts.fargs
			local file, range = args[1], args[2]
			local first, last, valid_range = command_range(range)
			local id
			if range and not valid_range then
				id = #args == 2 and tonumber(range) or nil
				if not id then
					return nil, "usage: QuickfixActionsAddFile {file} [start:end] [id]"
				end
			elseif #args == 3 then
				id = tonumber(args[3])
			elseif #args > 3 then
				return nil, "usage: QuickfixActionsAddFile {file} [start:end] [id]"
			end
			if not file or (#args == 3 and not id) then
				return nil, "usage: QuickfixActionsAddFile {file} [start:end] [id]"
			end
			return M.add_file({ kind = "quickfix", id = id }, file, first, last)
		end)
	end, { nargs = "+", desc = "Add a file or range to the current or specified quickfix list" })
	local function choose_and_add(file, first, last)
		return lists.choose_history({ kind = "quickfix" }, function(target)
			report(function()
				return M.add_file(target, file, first, last)
			end)
		end)
	end
	command("QuickfixActionsAddCurrentHistory", function()
		report(function()
			return choose_and_add(vim.api.nvim_buf_get_name(0))
		end)
	end, { desc = "Choose a quickfix history list and add the current file" })
	command("QuickfixActionsAddRangeHistory", function(opts)
		report(function()
			return choose_and_add(vim.api.nvim_buf_get_name(0), opts.line1, opts.line2)
		end)
	end, { range = true, desc = "Choose a quickfix history list and add the current range" })
	command("QuickfixActionsAddFileHistory", function(opts)
		report(function()
			local file, range = unpack(opts.fargs)
			local first, last, valid_range = command_range(range)
			if not file or not valid_range or #opts.fargs > 2 then
				return nil, "usage: QuickfixActionsAddFileHistory {file} [start:end]"
			end
			return choose_and_add(file, first, last)
		end)
	end, { nargs = "+", desc = "Choose a quickfix history list and add a file or range" })
	command("QuickfixActionsSetText", function(opts)
		report(function()
			if vim.bo.filetype ~= "qf" then
				return nil, "run QuickfixActionsSetText from a quickfix or location-list window"
			end
			local current, err = M.current()
			if not current or not current.item then
				return nil, err or "list entry is empty"
			end
			return M.set_text(
				{ kind = current.kind, id = current.id, winid = current.winid },
				current.index,
				opts.args,
				current.changedtick
			)
		end)
	end, { nargs = "+", desc = "Set the current quickfix entry's message text" })
end

local function qf_action(action)
	if action == "jump" then
		return function()
			report(function()
				return M.jump()
			end)
		end
	end
	if action == "delete" then
		return function()
			report(function()
				return M.delete_current()
			end)
		end
	end
	return type(action) == "function" and action or nil
end

local function setup_qf_buffer(buf)
	local mappings = config.mappings.qf
	if mappings == false then
		return
	end
	for lhs, action in pairs(mappings or {}) do
		if action ~= false then
			local callback = qf_action(action)
			if callback then
				vim.keymap.set("n", lhs, callback, {
					buffer = buf,
					nowait = true,
					desc = action == "jump" and "Jump to quickfix entry" or "Delete quickfix entry",
				})
			end
		end
	end
end

local function with_owner(owner, focus, callback)
	local previous = vim.api.nvim_get_current_win()
	if owner and previous ~= owner then
		vim.api.nvim_set_current_win(owner)
	end
	local ok, result = pcall(callback)
	if not focus and vim.api.nvim_win_is_valid(previous) then
		vim.api.nvim_set_current_win(previous)
	end
	if not ok then
		return nil, result
	end
	return true, result
end

local function normalize_lifecycle_target(target, opts)
	if
		target
		and type(target) == "table"
		and not target.kind
		and not target.id
		and not target.winid
		and not target.target
	then
		opts = target
		target = opts.target
	end
	opts = opts or {}
	if not target and opts.kind then
		target = { kind = opts.kind, winid = opts.winid, id = opts.id }
	end
	return target, opts
end

local function select_history(value, kind)
	if not value.nr or value.nr < 1 then
		return
	end
	local command_name = kind == "location" and "lhistory" or "chistory"
	vim.cmd(("silent %d%s"):format(value.nr, command_name))
end

function M.setup(opts)
	config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	config.layout = normalize_layout(config.layout) or defaults.layout
	if opts and opts.layout and not normalize_layout(opts.layout) then
		notify("layout must be full, top, left, right, or bottom", vim.log.levels.WARN)
	end
	if opts and opts.mappings and opts.mappings.qf == false then
		config.mappings.qf = false
	elseif opts and opts.qf_mappings then
		config.mappings.qf = opts.qf_mappings
	end
	if setup_done then
		return M
	end
	setup_done = true
	local group = vim.api.nvim_create_augroup("QuickfixActions", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = "qf",
		callback = function(event)
			setup_qf_buffer(event.buf)
		end,
	})
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function(event)
			if vim.bo[event.buf].filetype == "qf" then
				setup_qf_buffer(event.buf)
			end
		end,
	})
	install_commands()
	return M
end

function M.read(target)
	return lists.read(target)
end

function M.current(target)
	return lists.current(target)
end

function M.item(target, index)
	return lists.item(target, index)
end

function M.select(target, index)
	return lists.select(target, index)
end

function M.replace(target, items, idx, expected_tick)
	return lists.replace(target, items, idx, expected_tick)
end

function M.append(target, items, expected_tick)
	return lists.append(target, items, expected_tick)
end

function M.set_text(target, index, text, expected_tick)
	return lists.set_text(target, index, text, expected_tick)
end

function M.add_file(target, file, first, last, expected_tick)
	return lists.add_file(target, file, first, last, expected_tick)
end

function M.choose_history(target, callback)
	if type(target) == "function" then
		callback, target = target, nil
	end
	return lists.choose_history(target or { kind = "quickfix" }, callback)
end

function M.clear(target)
	return lists.clear(target)
end

function M.delete(target, index, expected_tick)
	return lists.delete(target, index, expected_tick)
end

function M.delete_current(target)
	return lists.delete_current(target)
end

function M.entries(opts)
	return picker.entries(opts)
end

function M.history(target)
	return lists.history(target)
end

function M.open_history(target, opts)
	local browser, err = lists.open_history(target)
	if not browser then
		return nil, err
	end
	return M.open(browser, opts)
end

function M.pick(opts)
	return picker.pick(opts)
end

function M.search(opts)
	return picker.search(opts)
end

function M.jump(target, index)
	local value, err, resolved = lists.read(target)
	if not value then
		return nil, err
	end
	if index == nil then
		local current = lists.current(resolved)
		index = current and current.index
	end
	if not index or not value.items[index] then
		return nil, "list entry is empty"
	end
	local user_data = value.items[index].user_data
	local history = type(user_data) == "table" and user_data.quickfix_actions and user_data.quickfix_actions.history
	if history then
		return M.open(history)
	end
	if resolved.kind == "quickfix" then
		select_history(value, resolved.kind)
		vim.cmd(("silent cc %d"):format(index))
		return true
	end
	local ok, jump_err = with_owner(resolved.winid, true, function()
		select_history(value, resolved.kind)
		vim.cmd(("silent ll %d"):format(index))
	end)
	if not ok then
		return nil, tostring(jump_err)
	end
	return true
end

local function lifecycle_value(target, opts)
	target, opts = normalize_lifecycle_target(target, opts)
	local value, err, resolved = lists.read(target)
	if not value then
		return nil, err
	end
	return value, resolved, opts
end

function M.open(target, opts)
	local value, resolved, options = lifecycle_value(target, opts)
	if not value then
		return nil, resolved
	end
	local explicit_layout = options.layout ~= nil
	local layout
	if explicit_layout then
		layout = normalize_layout(options.layout)
	elseif options.vertical then
		layout = "right"
	end
	if explicit_layout and not layout then
		return nil, "layout must be full, top, left, right, or bottom"
	end
	local focus = options.focus ~= false
	local owner = resolved.kind == "location" and resolved.winid
	local ok, err = with_owner(owner, focus, function()
		if explicit_layout or options.vertical then
			local existing = target_window(resolved)
			if existing then
				close_list_window(existing, resolved.kind, resolved)
				if owner and vim.api.nvim_win_is_valid(owner) then
					vim.api.nvim_set_current_win(owner)
				end
			end
		end
		select_history(value, resolved.kind)
		local command_name = resolved.kind == "location" and "lopen" or "copen"
		local layout_commands = {
			full = "tab " .. command_name,
			top = "topleft " .. command_name,
			left = "topleft vertical " .. command_name,
			right = "botright vertical " .. command_name,
			bottom = "botright " .. command_name,
		}
		local open_command = explicit_layout and layout_commands[layout]
			or options.vertical and ("vertical " .. command_name)
			or command_name
		local height = tonumber(options.height)
		if height and layout ~= "full" and not (layout == "left" or layout == "right") then
			vim.cmd(("silent %s %d"):format(open_command, height))
		else
			vim.cmd("silent " .. open_command)
		end
		local qfwin = vim.api.nvim_get_current_win()
		local width = tonumber(options.width)
		if width and (layout == "left" or layout == "right" or options.vertical) then
			vim.api.nvim_win_set_width(qfwin, width)
		end
		if height and explicit_layout and (layout == "top" or layout == "bottom") then
			vim.api.nvim_win_set_height(qfwin, height)
		end
		local actual_layout = window_layout(qfwin) or layout or "bottom"
		remember_layout(resolved, actual_layout)
		remembered_windows[target_key(resolved)] = qfwin
		for option, enabled in pairs({ wrap = options.wrap, linebreak = options.linebreak, breakindent = options.breakindent }) do
			if enabled ~= nil then
				vim.api.nvim_set_option_value(option, enabled, { win = qfwin })
			end
		end
	end)
	if not ok then
		return nil, tostring(err)
	end
	return true
end

function M.close(target, opts)
	target, opts = normalize_lifecycle_target(target, opts)
	local kind = target and target.kind or opts.kind or lists.current_kind()
	if kind ~= "quickfix" and kind ~= "location" then
		return nil, "kind must be quickfix or location"
	end
	local close_target = target
	if not close_target or not close_target.id then
		local current = lists.current(close_target or { kind = kind, winid = opts.winid, id = opts.id })
		if current then
			close_target = { kind = current.kind, id = current.id, winid = current.winid }
		end
	end
	if close_target and close_target.id then
		local value, err = lists.read(close_target)
		if not value then
			return nil, err
		end
	end
	local existing = close_target and close_target.id and target_window(close_target)
	local owner = kind == "location" and (target and target.winid or lists.current_owner())
	if kind == "location" and (not owner or not vim.api.nvim_win_is_valid(owner)) then
		return nil, "invalid location-list owner window"
	end
	local focus = opts.focus ~= false
	local ok, err = with_owner(owner, focus, function()
		if existing and vim.api.nvim_win_is_valid(existing) then
			close_list_window(existing, kind, close_target)
		else
			vim.cmd("silent " .. (kind == "location" and "lclose" or "cclose"))
		end
	end)
	if not ok then
		return nil, tostring(err)
	end
	return true
end

function M.is_open(target)
	if target and target.id then
		local value, err, resolved = lists.read(target)
		if not value then
			return nil, err
		end
		return target_window(resolved) ~= nil
	end
	local kind = target and target.kind or lists.current_kind()
	local owner = kind == "location" and (target and target.winid or lists.current_owner())
	for _, winid in ipairs(vim.api.nvim_list_wins()) do
		local info = vim.fn.getwininfo(winid)[1]
		if info and info.quickfix == 1 then
			if kind == "quickfix" and info.loclist == 0 then
				return true
			end
			if kind == "location" and info.loclist == 1 and owner then
				local value = vim.fn.getloclist(owner, { all = 1 })
				if value.winid == info.winid then
					return true
				end
			end
		end
	end
	return false
end

function M.toggle(target, opts)
	target, opts = normalize_lifecycle_target(target, opts)
	local value, err, resolved = lists.read(target)
	if not value then
		return nil, err
	end
	local winid = target_window(resolved)
	if winid then
		remember_layout(resolved, window_layout(winid))
		return M.close(resolved, opts)
	end
	opts = opts or {}
	if opts.layout == nil and opts.vertical == nil then
		opts.layout = target_layout(resolved)
	end
	return M.open(resolved, opts)
end

return M
