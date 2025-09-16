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
---@field env? table Additional environment variables for the command (optional)

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
---@param env? table Additional environment variables for the command (optional if using positional arguments)
function U.open_floating_terminal(command_or_opts, filetype, ispreupdate, autoclose, callback, enter_insert, env)
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
			env = env or {},
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
	env = opts.env or {}

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
		env = env,
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

--- Ensure the source code is up to date by fetching and pulling latest changes
--- This version runs in floating terminal for better user feedback
---@function ensure_latest_code
---@param source_dir string The source directory path
---@param callback function Callback function to call when operation completes
---@param env table Environment variables for git commands
function U.ensure_latest_code(source_dir, callback, env)
	callback = callback or function() end
	env = env or {}

	if not U.directory_exists(source_dir) then
		U.notify("Source directory does not exist: " .. source_dir, vim.log.levels.ERROR)
		callback(false)
		return
	end

	-- Check if it's a git repository
	local git_dir = source_dir .. "/.git"
	if not U.directory_exists(git_dir) then
		U.notify("Not a git repository: " .. source_dir, vim.log.levels.ERROR)
		callback(false)
		return
	end

	-- Build update command that handles various git states
	local update_command = "cd " .. source_dir .. [[ &&
echo "Fetching latest changes..."
git fetch origin 2>/dev/null || true

echo "Getting current branch info..."
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")

if [ "$CURRENT_BRANCH" != "HEAD" ]; then
    echo "Currently on branch: $CURRENT_BRANCH"
    echo "Pulling latest changes..."
    if ! git pull origin "$CURRENT_BRANCH" 2>/dev/null; then
        echo "Pull failed, trying to switch to main branch..."
        if git switch master 2>/dev/null || git switch main 2>/dev/null; then
            echo "Switched to main branch, pulling latest changes..."
            MAIN_BRANCH=$(git rev-parse --abbrev-ref HEAD)
            git pull origin "$MAIN_BRANCH" 2>/dev/null || true
        else
            echo "Warning: Could not switch to main branch, but continuing..."
        fi
    fi
else
    echo "Currently in detached HEAD state"
    echo "Checking if this is a shallow clone..."

    # Check if this is a shallow clone
    if [ -f .git/shallow ]; then
        echo "This is a shallow clone in detached HEAD state"
        echo "For shallow clones, we'll skip updating to avoid conflicts"
        echo "The target will be switched in the next step if needed"
    else
        echo "Attempting to switch to main branch..."
        if git switch master 2>/dev/null || git switch main 2>/dev/null; then
            echo "Switched to main branch, pulling latest changes..."
            MAIN_BRANCH=$(git rev-parse --abbrev-ref HEAD)
            git pull origin "$MAIN_BRANCH" 2>/dev/null || true
        else
            echo "Warning: Could not switch to main branch"
            echo "This might be a shallow clone or have limited refs"
            echo "Continuing with current state..."
        fi
    fi
fi

echo "Source code update process completed!"
]]

	U.notify("Updating source code to latest...", vim.log.levels.INFO)

	U.open_floating_terminal({
		command = update_command,
		filetype = "neovim_updater_term.updating_source",
		autoclose = true,
		env = env,
		callback = function(results)
			if results.result_code == 0 then
				U.notify("Successfully updated source code to latest", vim.log.levels.INFO, true)
				callback(true)
			else
				U.notify("Failed to update source code", vim.log.levels.ERROR)
				callback(false)
			end
		end,
	})
end

--- Smart clone function that optimizes clone based on target type
--- Uses shallow clone and single branch when possible to reduce download size
---@function smart_clone
---@param repo string Repository URL
---@param target_dir string Target directory for clone
---@param target string Target tag or branch name
---@param callback function Callback function to call when operation completes
---@param env table Environment variables for git commands
function U.smart_clone(repo, target_dir, target, callback, env)
	callback = callback or function() end
	env = env or {}

	-- Ensure parent directory exists and navigate to it
	local parent_dir = target_dir:match("^(.+)/[^/]+$") or "."
	local dir_name = target_dir:match("([^/]+)$") or target_dir

	-- Build smart clone command based on target type
	local clone_command = "mkdir -p " .. parent_dir .. " && cd " .. parent_dir .. " && echo 'Preparing to clone repository with optimizations...' && "

	-- First, try to determine if target is likely a tag or branch without full clone
	-- We'll use a lightweight approach: try shallow clone with single branch first
	clone_command = clone_command .. [[

echo "Attempting optimized clone for target: ]] .. target .. [["

# Strategy 1: Try to clone specific branch (if it's a branch)
echo "Trying to clone as branch..."
if git clone --depth 1 --single-branch --branch ]] .. target .. [[ ]] .. repo .. [[ ]] .. dir_name .. [[ 2>/dev/null; then
    echo "Successfully cloned branch: ]] .. target .. [["
    cd ]] .. dir_name .. [[
    echo "Current commit:"
    git log --oneline -1
    echo "Clone completed with optimizations!"
    exit 0
fi

echo "Branch clone failed, trying tag approach..."

# Strategy 2: If branch clone failed, try shallow clone and then fetch tag
echo "Performing shallow clone..."
if git clone --depth 1 ]] .. repo .. [[ ]] .. dir_name .. [[; then
    cd ]] .. dir_name .. [[
    echo "Fetching tag: ]] .. target .. [["

    # Check if target exists as a tag
    if git ls-remote --tags origin | grep -q "refs/tags/]] .. target .. [[$"; then
        echo "Found tag ]] .. target .. [[, fetching..."
        # Fetch the specific tag
        git fetch origin tag ]] .. target .. [[ --depth 1
        # Switch to the tag
        git checkout ]] .. target .. [[
        echo "Successfully switched to tag: ]] .. target .. [["
        echo "Current commit:"
        git log --oneline -1
        echo "Clone and tag switch completed!"
        exit 0
    else
        echo "Tag not found, keeping current state"
        echo "Current commit:"
        git log --oneline -1
        exit 0
    fi
else
    echo "Shallow clone failed, falling back to full clone..."
    # Strategy 3: Full clone as last resort
    git clone ]] .. repo .. [[ ]] .. dir_name .. [[
    cd ]] .. dir_name .. [[
    echo "Full clone completed, now switching to target..."

    # Try to switch to target
    if git checkout ]] .. target .. [[ 2>/dev/null || git switch ]] .. target .. [[ 2>/dev/null; then
        echo "Successfully switched to: ]] .. target .. [["
    else
        echo "Warning: Could not switch to ]] .. target .. [[, staying on default branch"
    fi

    echo "Current commit:"
    git log --oneline -1
fi
]]

	U.notify("Starting optimized clone for: " .. target, vim.log.levels.INFO)

	U.open_floating_terminal({
		command = clone_command,
		filetype = "neovim_updater_term.smart_cloning",
		autoclose = true,
		env = env,
		callback = function(results)
			if results.result_code == 0 then
				U.notify("Repository cloned successfully with optimizations", vim.log.levels.INFO, true)
				callback(true)
			else
				U.notify("Failed to clone repository", vim.log.levels.ERROR)
				callback(false)
			end
		end,
	})
end

--- Switch to specified tag or branch
--- This version runs in floating terminal for better user feedback
---@function switch_to_target
---@param source_dir string The source directory path
---@param target string The target tag or branch name
---@param callback function Callback function to call when operation completes
---@param env table Environment variables for git commands
function U.switch_to_target(source_dir, target, callback, env)
	callback = callback or function() end
	env = env or {}

	if not U.directory_exists(source_dir) then
		U.notify("Source directory does not exist: " .. source_dir, vim.log.levels.ERROR)
		callback(false)
		return
	end

	-- Build switch command that auto-detects target type and handles fallbacks
	local switch_command = "cd " .. source_dir .. [[

echo "Checking target type for: ]] .. target .. [["

# Check if target is a tag
if git tag -l ]] .. target .. [[ | grep -q "^]] .. target .. [[$"; then
    echo "Target is a tag, switching to detached HEAD..."
    TARGET_TYPE="tag"
    SWITCH_CMD="git switch --detach ]] .. target .. [["
elif git branch -r --list origin/]] .. target .. [[ | grep -q "origin/]] .. target .. [[$"; then
    echo "Target is a remote branch, creating/switching to local branch..."
    TARGET_TYPE="branch"
    SWITCH_CMD="git switch ]] .. target .. [["
else
    echo "Target not found as tag or remote branch, trying as local branch or commit..."
    TARGET_TYPE="unknown"
    SWITCH_CMD="git switch ]] .. target .. [["
fi

echo "Executing: $SWITCH_CMD"
if eval "$SWITCH_CMD"; then
    echo "Successfully switched to $TARGET_TYPE: ]] .. target .. [["
    git log --oneline -1
else
    echo "git switch failed, trying git checkout as fallback..."
    if git checkout ]] .. target .. [[; then
        echo "Successfully checked out: ]] .. target .. [["
        git log --oneline -1
    else
        echo "Failed to switch to: ]] .. target .. [["
        exit 1
    fi
fi
]]

	U.notify("Switching to target: " .. target, vim.log.levels.INFO)

	U.open_floating_terminal({
		command = switch_command,
		filetype = "neovim_updater_term.switching",
		autoclose = true,
		env = env,
		callback = function(results)
			if results.result_code == 0 then
				U.notify("Successfully switched to: " .. target, vim.log.levels.INFO, true)
				callback(true)
			else
				U.notify("Failed to switch to: " .. target, vim.log.levels.ERROR)
				callback(false)
			end
		end,
	})
end

return U
