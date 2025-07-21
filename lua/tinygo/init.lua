local M = {
	config_file = ".tinygo.json",
	tinygo = "tinygo",

	floating = {
		buf = -1,
		win = -1,
	},
}

function M.setup(opts)
	local ok, goEnv = pcall(vim.fn.system, "go env -json")
	if not ok then vim.print("go is not in the PATH..."); return end

	local ok, goEnvJSON = pcall(vim.fn.json_decode, goEnv)
	if not ok then vim.print("error parsing the go environment"); return end

	M.loadOptions(opts)

	M["originalGOROOT"]  = goEnvJSON["GOROOT"]
	M["originalGOFLAGS"] = goEnvJSON["GOFLAGS"]
	M["currentTarget"] = "original"
	M["currentGOROOT"]  = M["originalGOROOT"]
	M["currentGOFLAGS"] = M["originalGOFLAGS"]

	local pipe = io.popen(M.tinygo .. " targets")

	if not pipe then
		vim.print("error executing 'tinygo targets'...")
		return
	end

	local targets = {"original"}
	for target in pipe:lines() do
		table.insert(targets, target)
	end

	M["targets"] = targets

	vim.api.nvim_create_user_command("TinyGoSetTarget", M.setTarget, {nargs = 1, complete = M.targetOptions})
	vim.api.nvim_create_user_command("TinyGoTargets", M.printTargets, {nargs = 0})
	vim.api.nvim_create_user_command("TinyGoEnv", M.printEnv, {nargs = 0})
	vim.api.nvim_create_user_command("TinyGoFlash", M.flash, {nargs = "?", complete = M.targetOptions})
	vim.api.nvim_create_user_command("TinyGoMonitor", M.toggleMonitor, {nargs = "*"})

	vim.api.nvim_create_autocmd({"LspAttach"}, {
		group=vim.api.nvim_create_augroup("TinyGoApplyConfigFile", {}),
		pattern="*.go",
		callback=function (ev)
			if #vim.lsp.get_clients({bufnr=ev.buf, name="gopls"}) > 0 and M.currentTarget == "original" then
				M.applyConfigFile()
			end
		end,
	})
	vim.api.nvim_create_autocmd({"BufWritePost"}, {pattern=M.config_file, callback=M.applyConfigFile})
end

function M.loadOptions(opts)
	if opts["config_file"] then
		M.config_file = opts["config_file"]
	end
	if opts["cmd"] then
		M.tinygo = opts["cmd"]
	end
end

-- As seen on https://neovim.io/doc/user/api.html#nvim_create_user_command(), autocompletions written in
-- Lua are treated as custom autocompletions, so we cannot leverage Nvim's builtin regexps...
function M.targetOptions(ArgLead, cmdLine, cursorPos)
	local filteredTargets = {}
	for _, target in ipairs(M["targets"]) do
		if string.find(target, ArgLead, 1, true) == 1 then
			table.insert(filteredTargets, target)
		end
	end

	return filteredTargets
end

function M.setTarget(opts)
	local ok, lspconfig = pcall(require, "lspconfig")
	if not ok then
		vim.print("error requiring lspconfig...")
		return
	end

	if opts.fargs[1] == "original" then
		M["currentTarget"] = opts.fargs[1]
		M["currentGOROOT"] = M["originalGOROOT"]
		M["currentGOFLAGS"] = M["originalGOFLAGS"]

		lspconfig.gopls.setup({
			cmd_env = {
				GOROOT  = M["originalGOROOT"],
				GOFLAGS = M["originalGOFLAGS"]
			}
		})
		return
	end

	local ok, rawData = pcall(vim.fn.system, string.format(M.tinygo .. " info -json %s", opts.fargs[1]))
	if not ok then
		vim.print("error calling tinygo: " .. rawData)
		return
	end

	local ok, rawJSON = pcall(vim.fn.json_decode, rawData)
	if not ok then
		vim.print("error decoding the JSON: " .. rawJSON)
		return
	end

	if not vim.fn.has_key(rawJSON, "goroot") or not vim.fn.has_key(rawJSON, "build_tags") then
		vim.print("the generated JSON is missing keys...")
		return
	end

	local currentGOROOT = rawJSON["goroot"]
	local currentGOFLAGS = "-tags=" .. vim.fn.join(rawJSON["build_tags"], ',')

	M["currentTarget"] = opts.fargs[1]
	M["currentGOROOT"] = currentGOROOT
	M["currentGOFLAGS"] = currentGOFLAGS

	-- This'll restart the LSP server!
	lspconfig.gopls.setup({
		cmd_env = {
			GOROOT = currentGOROOT,
			GOFLAGS = currentGOFLAGS
		}
	})
end

function M.flash(opts)
	local target = opts.fargs[1]
	vim.print(target)
	if not target then
		target = M["currentTarget"]
	end

	if target == "original" then
		vim.print("cannot flash: no target set")
		return
	end

	vim.system({M.tinygo, "flash", "-target", target, "."}, {
		text = true,
		stdout = function (_, data) if data then vim.print(data) end end,
		stderr = function (_, data) if data then vim.print(data) end end,
	}):wait()
end


function M.printTargets()
	local ok, targets = pcall(vim.fn.system, M.tinygo .. " targets")
	if not ok then
		vim.print("error calling tinygo: " .. targets)
		return
	end
	vim.print(targets)
end

function M.printEnv()
	vim.print(string.format(
		"Current Target: %q\nCurrent GOROOT: %q\nCurrent GOFLAGS: %q",
		M["currentTarget"], M["currentGOROOT"], M["currentGOFLAGS"]
	))
end

function M.applyConfigFile()
	local f = io.open(M.config_file, "r")
	if not f then
		return
	end

	local ok, rawCfg = pcall(f.read, f, "a")
	if not ok then
		vim.print("error reading config file")
		f:close()
		return
	end
	f:close()

	local ok, cfg = pcall(vim.json.decode, rawCfg)
	if not ok then
		vim.print("error decoding config file")
		return
	end

	local target = cfg["target"]
	if target then
		vim.cmd.TinyGoSetTarget(cfg["target"])
	end
end

local function createFloatingWindow(opts)
	opts = opts or {}
	local width = math.floor(vim.o.columns * 0.8)
	local height = math.floor(vim.o.lines * 0.8)

	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	local buf = vim.api.nvim_create_buf(false, true)

	if opts.title then
		local padding = string.rep(" ", (width - #opts.title) / 2)
		local title = padding .. opts.title
		vim.api.nvim_buf_set_lines(buf, 0, 1, false, {title})
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
	return { buf = buf, win = win }
end

function M.toggleMonitor(opts)
	M.floating = createFloatingWindow({title = "Monitor"})

	if M.floating.job then
		M.floating.job:kill(1)
	end

	vim.api.nvim_create_autocmd({"BufLeave"}, {once=true, buffer=M.floating.buf, callback=function ()
		if M.floating.job then
			M.floating.job:kill(1)
		end
		M.floating = { buf = -1, win = -1 }
	end})

	vim.keymap.set({"n"},"q", function ()
		vim.api.nvim_win_close(M.floating.win, true)
	end, {buffer=M.floating.buf, silent=true, noremap=true})

	local args = ""
	if opts.args then
		args = opts.args
	end

	M.floating.job = vim.system({M.tinygo, "monitor", args}, {
		text = true,
		stdout = M.writeToFloatingWindow,
		stderr = M.writeToFloatingWindow,
	})
end

function M.writeToFloatingWindow(_, data)
	if not data or M.floating.buf == -1 or M.floating.win == -1 then
		return
	end
	vim.schedule(function ()
		local escaped = vim.fn.split(data, "\n", false)
		vim.bo[M.floating.buf].modifiable = true
		vim.api.nvim_buf_set_lines(M.floating.buf, -1, -1, true, escaped)
		vim.api.nvim_win_set_cursor(M.floating.win, {vim.api.nvim_buf_line_count(M.floating.buf), 0})
		vim.bo[M.floating.buf].modifiable = false
		vim.bo[M.floating.buf].modified = false
	end)
end

return M
