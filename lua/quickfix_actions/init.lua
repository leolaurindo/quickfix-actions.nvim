local lists = require("quickfix_actions.lists")
local picker = require("quickfix_actions.picker")

local M = {}

local defaults = {
	mappings = {
		qf = {
			["<CR>"] = "jump",
			dd = "delete",
		},
	},
}

local config = vim.deepcopy(defaults)
local setup_done = false

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

local function install_commands()
	command("QuickfixActionsOpen", function(opts)
		report(function()
			return M.open(command_target(opts))
		end)
	end, { nargs = "?", complete = function()
		return { "quickfix", "location" }
	end, desc = "Open a native quickfix or location list" })
	command("QuickfixActionsClose", function(opts)
		report(function()
			return M.close(command_target(opts))
		end)
	end, { nargs = "?", complete = function()
		return { "quickfix", "location" }
	end, desc = "Close a native quickfix or location list" })
	command("QuickfixActionsToggle", function(opts)
		report(function()
			return M.toggle(command_target(opts))
		end)
	end, { nargs = "?", complete = function()
		return { "quickfix", "location" }
	end, desc = "Toggle a native quickfix or location list" })
	command("QuickfixActionsPick", function()
		report(function()
			return M.pick()
		end)
	end, { desc = "Pick an entry from the current native list" })
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
	local focus = options.focus ~= false
	local owner = resolved.kind == "location" and resolved.winid
	local ok, err = with_owner(owner, focus, function()
		select_history(value, resolved.kind)
		local command_name = resolved.kind == "location" and "lopen" or "copen"
		local height = tonumber(options.height)
		if height then
			vim.cmd(("silent %s %d"):format(command_name, height))
		else
			vim.cmd("silent " .. command_name)
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
	if target and target.id then
		local value, err = lists.read(target)
		if not value then
			return nil, err
		end
	end
	local owner = kind == "location" and (target and target.winid or lists.current_owner())
	if kind == "location" and (not owner or not vim.api.nvim_win_is_valid(owner)) then
		return nil, "invalid location-list owner window"
	end
	local focus = opts.focus ~= false
	local ok, err = with_owner(owner, focus, function()
		vim.cmd("silent " .. (kind == "location" and "lclose" or "cclose"))
	end)
	if not ok then
		return nil, tostring(err)
	end
	return true
end

function M.is_open(target)
	if target and target.id then
		local value, err = lists.read(target)
		if not value then
			return nil, err
		end
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
	if M.is_open(target) then
		return M.close(target, opts)
	end
	return M.open(target, opts)
end

return M
