-- lua/nvim_updater/utils.lua

local U = {}

--- Helper to heck if a directory exists
---@function directory_exists
---@param path string The directory path to check
---@return boolean exists True if the directory exists, false otherwise
function U.directory_exists(path)
	local expanded_path = vim.fn.expand(path)
	return vim.fn.isdirectory(expanded_path) == 1
end

--- Create a temporary file to check write permissions in the directory or parent directory.
---@function check_write_permissions
---@param dir string The directory path to check
---@return boolean writable True if the directory is writable, false otherwise
function U.check_write_permissions(dir)
	local temp_file_path = dir .. "/nvim_updater_tmp_file.txt"

	-- Try to open the temporary file for writing
	local file = io.open(temp_file_path, "w")

	if file then
		file:close() -- Close the file to ensure it's written
		vim.fn.delete(temp_file_path) -- Cleanup: remove the temporary file
		return true -- Directory is writable
	else
		return false -- Directory is not writable
	end
end

--- Helper to display notifications consistently
---@function notify
---@param message string The message to display in a notification
---@param level number The logging level of the notification (e.g., vim.log.levels.INFO or vim.log.levels.ERROR)
---@param force? boolean True if the notification should be displayed regardless of the config settings
function U.notify(message, level, force)
	-- Get config
	local default_config = require("nvim_updater").default_config
	-- Check if the config verbose option is false.
	-- If so, suppress INFO and DEBUG notifications based on the log level.
	if (level == vim.log.levels.INFO or level == vim.log.levels.DEBUG) and not default_config.verbose then
		-- If the notification is not forced, return early.
		if not force then
			return
		end
	end

	-- If config verbose = true then display all notifications
	vim.notify(message, level, { title = "Neovim Updater" })
end

---@function Function to generate a y/n confirmation prompt
---@param prompt string The prompt text to display
---@param action function|string The action to execute if the user confirms the prompt, or a Vim command as a string
---@return boolean condition true if the user confirms the prompt, false otherwise
function U.ConfirmPrompt(prompt, action)
	-- Validate the action parameter
	local function perform_action()
		if type(action) == "function" then
			action() -- Call the function
		elseif type(action) == "string" then
			vim.fn.nvim_exec_lua(action, {}) -- Run the Vim command as Lua
		else
			U.notify("Action must be a function or a string", vim.log.levels.ERROR)
		end
	end

	-- Create a new buffer
	local buf = vim.api.nvim_create_buf(false, true) -- Create a new empty buffer

	-- Set the prompt text in the buffer
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { prompt, "y/n: " })

	-- Variables for the floating window
	local win_height = 2 -- Height of the floating window
	local win_width = math.floor(vim.o.columns * 0.25) -- Width of the floating window
	local row = math.floor((vim.o.lines - win_height) / 2) -- Position row
	local col = math.floor((vim.o.columns - win_width) / 2) -- Position column
	local win_border = "rounded"
	local style = "minimal"

	-- Create a floating window
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = win_width,
		height = win_height,
		col = col,
		row = row,
		style = style,
		border = win_border,
	})

	-- Move the cursor to the end of the buffer
	vim.api.nvim_win_set_cursor(win, { 2, 5 })

	-- Function for closing the window and cleaning up
	local autocmd_id
	local function close_window()
		if autocmd_id then
			vim.api.nvim_del_autocmd(autocmd_id) -- Remove the resize autocmd
			autocmd_id = nil
		end
		vim.api.nvim_win_close(win, true) -- Close the window
	end

	-- Update the floating window size on Vim resize events
	autocmd_id = vim.api.nvim_create_autocmd({ "VimResized" }, {
		callback = function()
			-- Get new dimensions of the main UI
			win_width = math.floor(vim.o.columns * 0.25) -- Update width
			col = math.floor((vim.o.columns - win_width) / 2) -- Recalculate center column
			row = math.floor((vim.o.lines - win_height) / 2) -- Recalculate center row

			-- Update floating window configuration
			vim.api.nvim_win_set_config(win, {
				relative = "editor",
				width = win_width,
				height = win_height,
				col = col,
				row = row,
			})
		end,
	})

	-- Define the yes function
	local yes = function()
		close_window() -- Close window before performing action
		perform_action() -- Perform the action
		return true
	end

	-- Define the no function
	local no = function()
		close_window() -- Close window and notify
		U.notify("Action Canceled", vim.log.levels.INFO)
	end

	-- Define buffer-specific key mappings
	local keymaps = {
		y = yes,
		n = no,
		q = no,
		["<Esc>"] = no,
	}

	-- Set the key mappings
	for key, callback in pairs(keymaps) do
		vim.api.nvim_buf_set_keymap(buf, "n", key, "", {
			noremap = true,
			nowait = true,
			callback = callback,
			desc = key == "y" and "Confirm action" or "Cancel action",
		})
	end

	return false
end

--- Options table for configuring the floating terminal.
---@class TerminalOptions
---@field command string The shell command to run in the terminal
---@field filetype? string Custom filetype for terminal buffer (optional)
---@field ispreupdate? boolean @deprecated Whether the terminal is for changelog before updating Neovim (optional)
---                            (This is deprecated and will be removed in a future version)
---                            Please use the `callback` function instead.
---@field autoclose? boolean Whether the terminal should be automatically closed (optional)
---@field callback? fun(params?: TerminalCloseParams) Callback function to run after the terminal is closed
---@field enter_insert? boolean Whether to enter insert mode immediately (optional)

--- Callback parameter table for the floating terminal close event.
---@class TerminalCloseParams
---@field ev? table The close event object (optional)
---@field result_code? integer The exit code of the terminal command process (optional)
---@field output? string The complete terminal output (optional)

-- Helper to display floating terminal in a centered, minimal Neovim window.
-- This is useful for running long shell commands like building Neovim.
-- You can pass arguments either as positional values or as a table of options.
---@param command_or_opts string|TerminalOptions Either a shell command (string) or a table of options
---@param filetype? string Custom filetype for terminal buffer (optional if using positional arguments)
---@param ispreupdate? boolean @deprecated Whether the terminal is for changelog before updating Neovim (optional if using positional arguments)
---                            (This is deprecated and will be removed in a future version)
---                            Please use the `callback` function instead.
---@param autoclose? boolean Whether the terminal should be automatically closed (optional if using positional arguments)
---@param callback? fun(params?: TerminalCloseParams) Callback function to run after the terminal is closed
---@param enter_insert? boolean Whether to enter insert mode immediately (optional if using positional arguments)
function U.open_floating_terminal(command_or_opts, filetype, ispreupdate, autoclose, callback, enter_insert)
	local opts
	local result_code = -1 -- Indicates the command is still running
	local output_lines = {} -- Store terminal output lines

	-- Determine if the first argument is a table or positional arguments
	if type(command_or_opts) == "table" then
		opts = command_or_opts
	else
		opts = {
			command = command_or_opts or "",
			filetype = filetype or "FloatingTerm",
			ispreupdate = ispreupdate or false,
			autoclose = autoclose or false,
			callback = callback or nil,
			enter_insert = enter_insert or false,
		}
	end

	-- Extract options from the table
	local command = opts.command or ""
	filetype = opts.filetype or "FloatingTerm"
	ispreupdate = opts.ispreupdate or false
	autoclose = opts.autoclose or false
	callback = opts.callback or function()
		return true
	end
	enter_insert = opts.enter_insert or false

	-- Create a new buffer for the terminal, set it as non-listed and scratch
	local buf = vim.api.nvim_create_buf(false, true)
	if not buf or buf == 0 then
		U.notify("Failed to create terminal buffer", vim.log.levels.ERROR)
		return
	end

	-- Set the filetype of the terminal buffer
	vim.api.nvim_set_option_value("filetype", filetype, { buf = buf })

	-- Create the floating window
	local win
	local autocmd_id

	local function open_window()
		-- Get UI dimensions to calculate window size
		local ui = vim.api.nvim_list_uis()[1]
		local win_width = math.floor(ui.width * 0.8)
		local win_height = math.floor(ui.height * 0.8)

		-- Define window options
		local win_opts = {
			style = "minimal",
			relative = "editor",
			width = win_width,
			height = win_height,
			row = math.floor((ui.height - win_height) / 2),
			col = math.floor((ui.width - win_width) / 2),
			border = "rounded",
		}

		-- Create or update the floating window
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_set_config(win, win_opts) -- Update window config
		else
			win = vim.api.nvim_open_win(buf, true, win_opts) -- Open new window
			if not win or win == 0 then
				U.notify("Failed to create floating window", vim.log.levels.ERROR)
				return
			end
		end

		-- Additional settings for the window
		vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
		vim.api.nvim_set_option_value("winblend", 10, { win = win })
	end

	open_window() -- Initial window creation

	-- Update window size on Vim resize events
	autocmd_id = vim.api.nvim_create_autocmd({ "VimResized" }, {
		callback = function()
			open_window() -- Call the function to update the window size
		end,
	})

	-- Create the closing callback
	local function closing()
		-- Remove the autocmd to prevent errors after the window is closed
		if autocmd_id then
			vim.api.nvim_del_autocmd(autocmd_id)
			autocmd_id = nil
		end

		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		if os.getenv("NVIMUPDATER_HEADLESS") then
			vim.cmd("qa")
		end
		if ispreupdate then
			U.ConfirmPrompt("Perform Neovim update?", function()
				require("nvim_updater").update_neovim()
			end)
		end
	end

	-- Run the terminal command
	vim.fn.jobstart(command, {
		term = true, -- Use terminal mode
		on_stdout = function(_, data)
			if data then
				for _, line in ipairs(data) do
					table.insert(output_lines, line)
				end
			end
		end,
		on_stderr = function(_, data)
			if data then
				for _, line in ipairs(data) do
					table.insert(output_lines, line)
				end
			end
		end,
		on_exit = function(_, exit_code)
			result_code = exit_code
			if exit_code == 0 then
				if autoclose then -- If autoclose is true, close the terminal window
					closing()
					return
				end

				-- Wait for a keypress before closing the terminal window
				-- Bind different keys to closing the terminal
				for _, key in ipairs({ "q", "<Space>", "<CR>", "<Esc>", "y" }) do
					vim.api.nvim_buf_set_keymap(buf, "n", key, "", {
						noremap = true,
						silent = true,
						callback = function()
							closing()
						end,
						desc = "Close terminal window",
					})
				end
			else
				U.notify("Command failed with exit code: " .. exit_code, vim.log.levels.DEBUG)
				vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
					noremap = true,
					silent = true,
					callback = function()
						if vim.api.nvim_win_is_valid(win) then
							vim.api.nvim_win_close(win, true)
						end
					end,
					desc = "Close terminal window after failure",
				})
			end
		end,
	})

	if enter_insert then
		-- Enter insert mode immediately
		vim.cmd("startinsert")

		-- Create an autocmd to ensure insert mode when the window gets focus
		vim.api.nvim_create_autocmd("WinEnter", {
			buffer = buf,
			callback = function()
				vim.cmd("startinsert")
			end,
		})
	end

	-- Create an autocmd for the window closing callback
	if callback then
		local winid = tostring(win)
		vim.api.nvim_create_autocmd("WinClosed", {
			pattern = winid, -- Use the window ID as the pattern
			callback = function(ev)
				callback({
					ev = ev,
					result_code = result_code,
					output = table.concat(output_lines, "\n"),
				})
				return true
			end,
		})
	end
end

--- Helper function to check if a plugin is installed
---@function is_installed
---@param plugin string The name of the plugin to check
---@return boolean is_installed True if the plugin is installed, false otherwise
function U.is_installed(plugin)
	if pcall(require, plugin) then
		return true
	else
		return false
	end
end

--- Helper function to remove the build directory and update Neovim
---@param opts table|nil Optional options for the update process
function U.rm_build_then_update(opts)
	opts = opts or {}
	local default_config = require("nvim_updater").default_config
	local source_dir = opts.source_dir ~= "" and opts.source_dir or default_config.source_dir
	local build_dir = source_dir .. "/build"
	local build_dir_exists = U.directory_exists(build_dir)
	local source_dir_exists = U.directory_exists(source_dir)
	if build_dir_exists and source_dir_exists then
		require("nvim_updater").last_status.retry = true
		require("nvim_updater").remove_source_dir({ source_dir = build_dir })
	end
end
return U
