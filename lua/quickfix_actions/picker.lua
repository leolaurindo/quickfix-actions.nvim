local lists = require("quickfix_actions.lists")

local M = {}

function M.entries(opts)
	opts = opts or {}
	local value, err, target = lists.read(opts.list or opts.target)
	if not value then
		return nil, err
	end
	local entries = {}
	for index, item in ipairs(value.items or {}) do
		local path = item.filename
		if (not path or path == "") and item.bufnr and item.bufnr > 0 and vim.api.nvim_buf_is_valid(item.bufnr) then
			path = vim.api.nvim_buf_get_name(item.bufnr)
		end
		entries[#entries + 1] = {
			list = vim.deepcopy(target),
			target = vim.deepcopy(target),
			index = index,
			item = item,
			path = path,
			line = item.lnum,
			text = item.text or "",
		}
	end
	return entries
end

local function format_entry(entry)
	local location = entry.path or "[no file]"
	if entry.line then
		location = ("%s:%s"):format(location, entry.line)
	end
	return ("%s - %s"):format(location, (entry.text or ""):gsub("\n", " "))
end

function M.pick(opts, on_confirm)
	opts = opts or {}
	local entries, err = M.entries(opts)
	if not entries then
		return nil, err
	end
	if #entries == 0 then
		return nil, "quickfix list is empty"
	end
	local choose = on_confirm or opts.on_confirm
	if not choose then
		choose = function(entry)
			return require("quickfix_actions").jump(entry.list, entry.index)
		end
	end
	local labels = vim.tbl_map(format_entry, entries)
	local selected
	vim.ui.select(labels, { prompt = opts.prompt or "Quickfix" }, function(_, index)
		if index then
			selected = choose(entries[index])
		end
	end)
	return selected == nil and true or selected
end

function M.search(opts)
	opts = opts or {}
	local entries, err = M.entries(opts)
	if not entries then
		return nil, err
	end
	if #entries == 0 then
		return nil, "quickfix list is empty"
	end
	local choose = opts.on_confirm or function(entry)
		return require("quickfix_actions").select(entry.list, entry.index)
	end
	local select_opts = {
		prompt = opts.prompt or "Search quickfix",
		format_item = opts.format_item or format_entry,
	}
	local selected
	local function on_choice(_, index)
		if index then
			selected = choose(entries[index])
		end
	end
	local ok, Snacks = pcall(require, "snacks")
	if ok and Snacks.picker and Snacks.picker.select then
		select_opts.snacks = { layout = { preset = "select" } }
		return Snacks.picker.select(entries, select_opts, on_choice)
	end
	vim.ui.select(entries, select_opts, on_choice)
	return selected == nil and true or selected
end

return M
