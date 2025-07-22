local M = {}

---@class floating.Window
---@field buf integer: The buffer number of the floating window
---@field win integer: The window number of the floating window
---@field header_height integer: The height of the floating windows header
---@field job? vim.SystemObj: The window job

---@class floating.WindowOpts
---@field width? integer: The width of the floating window
---@field height? integer: The height of the floating window
---@field header? string[]: The header lines of the floating window

---@param opts? floating.WindowOpts
---@return floating.Window
function M.new(opts)
	opts = opts or {}
	local width = opts.width or math.floor(vim.o.columns * 0.65)
	local height = opts.height or math.floor(vim.o.lines * 0.8)

	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	local buf = vim.api.nvim_create_buf(false, true)

	---@type string[]
	local header = {}
	if opts.header then
		for _, line in pairs(opts.header) do
			header[#header+1] = string.rep(" ", (width - #line) / 2) .. line
		end
		vim.api.nvim_buf_set_lines(buf, 0, 1, false, header)
	end

	vim.bo[buf].modifiable = false
	vim.bo[buf].modified = false

	local win_config = {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal",
		border = "rounded",
	}
	local win = vim.api.nvim_open_win(buf, true, win_config)

	---@type floating.Window
	return { buf = buf, win = win, header_height = #header }
end

---@param float floating.Window
---@param data string
function M.write(float, data)
	if not data or not float then
		return
	end
	vim.schedule(function ()
		local escaped = vim.fn.split(data, "\n", false)
		vim.bo[float.buf].modifiable = true
		local lenBefore = vim.api.nvim_buf_line_count(float.buf)
		vim.api.nvim_buf_set_lines(float.buf, -1, -1, true, escaped)

		if vim.api.nvim_win_get_cursor(float.win)[1] == lenBefore then
			vim.api.nvim_win_set_cursor(float.win, {vim.api.nvim_buf_line_count(float.buf), 0})
		end

		vim.bo[float.buf].modifiable = false
		vim.bo[float.buf].modified = false
	end)
end

---@param float floating.Window
function M.clear(float)
	if not float or float.buf == -1 or float.win == -1 then
		return
	end
	vim.schedule(function ()
		vim.bo[float.buf].modifiable = true
		vim.api.nvim_buf_set_lines(float.buf, float.header_height, -1, true, {})
		vim.api.nvim_win_set_cursor(float.win, {float.header_height, 0})
		vim.bo[float.buf].modifiable = false
		vim.bo[float.buf].modified = false
	end)
end

return M
