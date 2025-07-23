---@class monitor.Monitor
---@field buf integer
---@field win integer
---@field header_height integer
---@field job? vim.SystemObj
Monitor = {}

---@alias monitor.Style
---| "floating"
---| "horizontal"
---| "vertical"

---@class monitor.Opts
---@field width? integer: The width of the monitor window
---@field height? integer: The height of the monitor window
---@field header? string[]: The header lines of the monitor window
---@field style? monitor.Style: The style of the monitor window

---@param opts? monitor.Opts
---@return monitor.Monitor
function Monitor:new(opts)
	opts = opts or {}

	---@type vim.api.keyset.win_config
	local win_config = {style = "minimal"}
	local width, height = vim.o.columns, vim.o.lines
	if opts.style == "floating" or not opts.style then
		width = opts.width or math.floor(vim.o.columns * 0.65)
		height = opts.height or math.floor(vim.o.lines * 0.8)
		win_config.relative = "editor"
		win_config.col = math.floor((vim.o.columns - width) / 2)
		win_config.row = math.floor((vim.o.lines - height) / 2)
		win_config.border = "rounded"
	elseif opts.style == "horizontal" then
		height = opts.height or math.floor(vim.o.lines * 0.5)
		win_config.split = "above"
	elseif opts.style == "vertical" then
		width = opts.width or math.floor(vim.o.columns * 0.5)
		win_config.split = "right"
	end
	win_config.width = width
	win_config.height = height

	local buf = vim.api.nvim_create_buf(false, true)

	local header = {} ---@type string[]
	if opts.header then
		for _, line in pairs(opts.header) do
			header[#header+1] = string.rep(" ", (width - #line) / 2) .. line
		end
		vim.api.nvim_buf_set_lines(buf, 0, 1, false, header)
	end

	vim.bo[buf].modifiable = false
	vim.bo[buf].modified = false

	local win = vim.api.nvim_open_win(buf, true, win_config)
	vim.api.nvim_win_set_cursor(win, {vim.api.nvim_buf_line_count(buf), 0})

	self.buf = buf
	self.win = win
	self.header_height = #header

	return self
end

---@param data string
function Monitor:write(data)
	if not data then
		return
	end
	vim.schedule(function ()
		local escaped = vim.fn.split(data, "\n", false)
		vim.bo[self.buf].modifiable = true
		local before = vim.api.nvim_buf_line_count(self.buf)
		vim.api.nvim_buf_set_lines(self.buf, -1, -1, true, escaped)

		if vim.api.nvim_win_get_cursor(self.win)[1] == before then
			vim.api.nvim_win_set_cursor(self.win, {vim.api.nvim_buf_line_count(self.buf), 0})
		end

		vim.bo[self.buf].modifiable = false
		vim.bo[self.buf].modified = false
	end)
end

function Monitor:clear()
	if not self or self.buf == -1 or self.win == -1 then
		return
	end
	vim.schedule(function ()
		vim.bo[self.buf].modifiable = true
		vim.api.nvim_buf_set_lines(self.buf, self.header_height, -1, true, {})
		vim.api.nvim_win_set_cursor(self.win, {self.header_height, 0})
		vim.bo[self.buf].modifiable = false
		vim.bo[self.buf].modified = false
	end)
end

---@param msg? string
function Monitor:kill_job(msg)
	if self.job then
		self.job:kill(1)
		self.job = nil
		if msg then
			self:write(msg)
		end
	end
end

---@param cmd string[]
function Monitor:start_job(cmd)
	if self.job then
		return
	end

	self.job = vim.system(cmd, {
		text = true,
		stdout = function (_, data) self:write(data) end,
		stderr = function (_, data) self:write(data) end,
	})
end

return Monitor
