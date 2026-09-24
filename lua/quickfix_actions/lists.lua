local M = {}

local history_browsers = {}

local function current_info()
	return vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
end

local function location_owner(qfwin)
	for _, winid in ipairs(vim.api.nvim_list_wins()) do
		local ok, value = pcall(vim.fn.getloclist, winid, { all = 1 })
		if ok and value.winid == qfwin then
			return winid
		end
	end
end

local function current_kind()
	local info = current_info()
	if info and info.loclist == 1 then
		return "location"
	end
	return "quickfix"
end

local function current_owner()
	local info = current_info()
	if info and info.loclist == 1 then
		return location_owner(info.winid)
	end
	return vim.api.nvim_get_current_win()
end

local function check_kind(kind)
	if kind ~= "quickfix" and kind ~= "location" then
		return nil, "kind must be quickfix or location"
	end
	return kind
end

local function check_id(id, kind)
	if id == nil then
		return true
	end
	if type(id) ~= "number" or id < 1 or id % 1 ~= 0 then
		return nil, ("%s list id must be a positive integer"):format(kind)
	end
	return true
end

local function resolved_target(target)
	target = target or {}
	if type(target) ~= "table" then
		return nil, "target must be a table"
	end
	local kind, err = check_kind(target.kind or current_kind())
	if not kind then
		return nil, err
	end
	local ok, id_err = check_id(target.id, kind)
	if not ok then
		return nil, id_err
	end
	if kind == "quickfix" then
		return { kind = kind, id = target.id }
	end
	local owner = target.winid
	if owner == nil then
		owner = current_owner()
	end
	if type(owner) ~= "number" or not vim.api.nvim_win_is_valid(owner) then
		return nil, "invalid location-list owner window"
	end
	return { kind = kind, id = target.id, winid = owner }
end

local function get_list(resolved)
	local request = { all = 1 }
	if resolved.id then
		request.id = resolved.id
	end
	local ok, value
	if resolved.kind == "location" then
		ok, value = pcall(vim.fn.getloclist, resolved.winid, request)
	else
		ok, value = pcall(vim.fn.getqflist, request)
	end
	if not ok then
		return nil, tostring(value)
	end
	if resolved.id and (not value or value.id ~= resolved.id) then
		return nil, ("stale %s list id: %s"):format(resolved.kind, resolved.id)
	end
	if not value or not value.id or value.id < 1 then
		return nil, ("no current %s list"):format(resolved.kind)
	end
	resolved.id = value.id
	return value, nil, resolved
end

local function displayed(resolved, value)
	if vim.bo.buftype ~= "quickfix" then
		return false
	end
	if resolved.kind == "quickfix" then
		local current = vim.fn.getqflist({ id = 0 })
		return current.id == resolved.id
	end
	return value.winid == vim.api.nvim_get_current_win()
end

local function list_window(resolved)
	if resolved.kind == "location" then
		local value = vim.fn.getloclist(resolved.winid, { all = 1 })
		local winid = value and value.winid
		return winid and winid > 0 and vim.api.nvim_win_is_valid(winid) and winid or nil
	end
	local current = vim.fn.getqflist({ id = 0 })
	if current.id ~= resolved.id then
		return nil
	end
	for _, info in ipairs(vim.fn.getwininfo()) do
		if info.quickfix == 1 and info.loclist ~= 1 and vim.api.nvim_win_is_valid(info.winid) then
			return info.winid
		end
	end
end

function M.window(target)
	local value, err, resolved = M.read(target)
	if not value then
		return nil, err
	end
	return list_window(resolved)
end

local function current_index(resolved, value)
	local index = value.idx or 0
	if displayed(resolved, value) then
		local row = vim.fn.line(".")
		if row > 0 and row <= #(value.items or {}) then
			index = row
		end
	end
	return index
end

function M.read(target)
	local resolved, err = resolved_target(target)
	if not resolved then
		return nil, err
	end
	return get_list(resolved)
end

function M.history(target)
	local resolved, err = resolved_target(target)
	if not resolved then
		return nil, err
	end
	resolved.id = nil
	local get = resolved.kind == "location" and vim.fn.getloclist or vim.fn.getqflist
	local owner = resolved.kind == "location" and resolved.winid
	local request = { nr = "$" }
	local ok, last
	if owner then
		ok, last = pcall(get, owner, request)
	else
		ok, last = pcall(get, request)
	end
	if not ok then
		return nil, tostring(last)
	end
	local current, current_err = get_list(resolved)
	if not current then
		return nil, current_err
	end
	local entries = {}
	for nr = 1, last.nr or 0 do
		local value
		if owner then
			ok, value = pcall(get, owner, { nr = nr, all = 1 })
		else
			ok, value = pcall(get, { nr = nr, all = 1 })
		end
		local browser = value and value.context and value.context.quickfix_actions and value.context.quickfix_actions.history_browser
		if ok and value and value.id and value.id > 0 and not browser then
			entries[#entries + 1] = {
				kind = resolved.kind,
				id = value.id,
				winid = resolved.winid,
				nr = nr,
				title = value.title,
				count = #(value.items or {}),
				current = value.id == current.id,
			}
		end
	end
	return entries
end

function M.history_text(info)
	local items = vim.fn.getqflist({ id = info.id, items = 1 }).items
	local lines = {}
	for index = info.start_idx, info.end_idx do
		lines[#lines + 1] = items[index].text
	end
	return lines
end

function M.open_history(target)
	local entries, err = M.history(target)
	if not entries then
		return nil, err
	end
	if #entries == 0 then
		return nil, "quickfix history is empty"
	end
	local items = {}
	for _, entry in ipairs(entries) do
		local title = entry.title and entry.title ~= "" and entry.title or "[untitled]"
		items[#items + 1] = {
			valid = 0,
			text = ("%s%d: %s (#%d, %d items)"):format(entry.current and "* " or "  ", entry.nr, title, entry.id, entry.count),
			user_data = {
				quickfix_actions = {
					history = { kind = entry.kind, id = entry.id, winid = entry.winid },
				},
			},
		}
	end
	local key = entries[1].kind == "location" and "location:" .. entries[1].winid or "quickfix"
	local id = history_browsers[key]
	local value = id and vim.fn.getqflist({ id = id })
	local what = {
		title = entries[1].kind == "location" and "Location-list history" or "Quickfix history",
		context = { quickfix_actions = { history_browser = true } },
		items = items,
		quickfixtextfunc = M.history_text,
	}
	if value and value.id == id then
		what.id = id
	end
	local ok, result = pcall(vim.fn.setqflist, {}, what.id and "r" or " ", what)
	if not ok then
		return nil, tostring(result)
	end
	if not what.id then
		id = vim.fn.getqflist({ id = 0 }).id
		history_browsers[key] = id
	end
	return { kind = "quickfix", id = id }
end

function M.current(target)
	local value, err, resolved = M.read(target)
	if not value then
		return nil, err
	end
	local index = current_index(resolved, value)
	return {
		kind = resolved.kind,
		id = resolved.id,
		winid = resolved.winid,
		index = index,
		item = value.items and value.items[index],
		items = value.items or {},
		title = value.title,
		context = value.context,
		changedtick = value.changedtick,
		list = value,
	}, nil
end

function M.item(target, index)
	local value, err, resolved = M.read(target)
	if not value then
		return nil, err
	end
	if type(index) ~= "number" or index < 1 or index > #(value.items or {}) then
		return nil, "list entry is empty"
	end
	return value.items[index], nil, vim.tbl_extend("force", resolved, { list = value, index = index })
end

function M.select(target, index)
	local value, err, resolved = M.read(target)
	if not value then
		return nil, err
	end
	if type(index) ~= "number" or index < 1 or index > #(value.items or {}) then
		return nil, "list entry is empty"
	end
	local winid = list_window(resolved)
	if not winid then
		return nil, "native list is not open"
	end
	local ok, cursor_err = pcall(vim.api.nvim_win_set_cursor, winid, { index, 0 })
	if not ok then
		return nil, tostring(cursor_err)
	end
	vim.api.nvim_set_current_win(winid)
	return true
end

local function set_list(resolved, value, items, idx)
	local what = {
		id = value.id,
		title = value.title,
		context = value.context,
		items = items,
		idx = idx,
		quickfixtextfunc = value.quickfixtextfunc,
	}
	local ok, result
	if resolved.kind == "location" then
		ok, result = pcall(vim.fn.setloclist, resolved.winid, {}, "r", what)
	else
		ok, result = pcall(vim.fn.setqflist, {}, "r", what)
	end
	if not ok then
		return nil, ("could not replace %s list: %s"):format(resolved.kind, tostring(result))
	end
	return true
end

function M.replace(target, items, idx, expected_tick)
	if type(items) ~= "table" then
		return nil, "items must be a table"
	end
	local value, err, resolved = M.read(target)
	if not value then
		return nil, err
	end
	if expected_tick ~= nil and value.changedtick ~= expected_tick then
		return nil, "list changed while it was being edited"
	end
	return set_list(resolved, value, items, idx == nil and value.idx or idx)
end

function M.append(target, items, expected_tick)
	if type(items) ~= "table" then
		return nil, "items must be a table"
	end
	local value, err, resolved = M.read(target)
	if not value then
		return nil, err
	end
	if expected_tick ~= nil and value.changedtick ~= expected_tick then
		return nil, "list changed while it was being edited"
	end
	local appended = vim.deepcopy(value.items or {})
	for _, item in ipairs(items) do
		appended[#appended + 1] = vim.deepcopy(item)
	end
	return M.replace(resolved, appended, value.idx, value.changedtick)
end

function M.set_text(target, index, text, expected_tick)
	if type(text) ~= "string" then
		return nil, "text must be a string"
	end
	local value, err, resolved = M.read(target)
	if not value then
		return nil, err
	end
	if expected_tick ~= nil and value.changedtick ~= expected_tick then
		return nil, "list changed while it was being edited"
	end
	if type(index) ~= "number" or index % 1 ~= 0 or not value.items[index] then
		return nil, "list entry is empty"
	end
	local items = vim.deepcopy(value.items)
	items[index].text = text
	return M.replace(resolved, items, value.idx, value.changedtick)
end

function M.clear(target)
	local value, err, resolved = M.read(target)
	if not value then
		return nil, err
	end
	return M.replace(resolved, {}, 0, value.changedtick)
end

function M.add_file(target, file, first, last, expected_tick)
	if type(file) ~= "string" or file == "" then
		return nil, "file must be a non-empty path"
	end
	local item = { filename = file }
	if first ~= nil or last ~= nil then
		first = tonumber(first)
		last = tonumber(last or first)
		if
			not first
			or not last
			or first < 1
			or last < first
			or first % 1 ~= 0
			or last % 1 ~= 0
		then
			return nil, "range must contain positive, ordered line numbers"
		end
		item.lnum = first
		item.end_lnum = last
	end
	return M.append(target, { item }, expected_tick)
end

function M.choose_history(target, callback)
	if type(callback) ~= "function" then
		return nil, "callback must be a function"
	end
	local entries, err = M.history(target)
	if not entries then
		return nil, err
	end
	if #entries == 0 then
		return nil, "quickfix history is empty"
	end
	local labels = {}
	for _, entry in ipairs(entries) do
		local title = entry.title and entry.title ~= "" and entry.title or "[untitled]"
		labels[#labels + 1] = ("%s (#%d, %d items)"):format(title, entry.id, entry.count)
	end
	vim.ui.select(labels, { prompt = "Quickfix history" }, function(_, index)
		if index then
			callback({ kind = entries[index].kind, id = entries[index].id, winid = entries[index].winid })
		end
	end)
	return true
end

function M.delete(target, index, expected_tick)
	local value, err, resolved = M.read(target)
	if not value then
		return nil, err
	end
	if expected_tick ~= nil and value.changedtick ~= expected_tick then
		return nil, "list changed while it was being edited"
	end
	index = index or current_index(resolved, value)
	if not value.items[index] then
		return nil, "list entry is empty"
	end
	local items = vim.deepcopy(value.items)
	table.remove(items, index)
	local next_index = #items == 0 and 0 or math.min(value.idx or 1, #items)
	return M.replace(resolved, items, next_index, value.changedtick)
end

function M.delete_current(target)
	local current, err = M.current(target)
	if not current or not current.item then
		return nil, err or "empty quickfix row"
	end
	return M.delete(
		{ kind = current.kind, id = current.id, winid = current.winid },
		current.index,
		current.changedtick
	)
end

function M.current_kind()
	return current_kind()
end

function M.current_owner()
	return current_owner()
end

function M.owner(target)
	if target and target.winid then
		return target.winid
	end
	return current_owner()
end

function M.is_displayed(target)
	local value, err, resolved = M.read(target)
	if not value then
		return nil, err
	end
	return displayed(resolved, value)
end

return M
