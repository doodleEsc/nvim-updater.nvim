-- lua/nvim_updater/init.lua

-- Import the 'utils' module for helper functions
local utils = require("nvim_updater.utils")

-- Define the Neovim updater plugin
local P = {}

-- Default values for plugin options (editable via user config)
P.default_config = {
	source_dir = vim.fn.expand("~/.local/src/neovim"), -- Default Neovim source location
	build_type = "Release", -- Default build type
	tag = "stable", -- Default Neovim branch to track
	verbose = false, -- Default verbose mode
	default_keymaps = false, -- Use default keymaps
	build_fresh = true, -- Always remove build dir before building
	env = {}, -- Additional environment variables for commands
}

P.last_status = {
	count = "?",
	retry = false,
}

--- Setup default keymaps for updating Neovim or removing source based on user configuration.
---@function setup_plug_keymaps
local function setup_plug_keymaps()
	-- Create <Plug> mappings for update and remove functionalities
	vim.keymap.set("n", "<Plug>(NVUpdateNeovim)", function()
		P.update_neovim()
	end, { desc = "Update Neovim via <Plug>", noremap = false, silent = true })

	vim.keymap.set("n", "<Plug>(NVUpdateNeovimDebug)", function()
		P.update_neovim({ build_type = "Debug" })
	end, { desc = "Update Neovim with Debug build via <Plug>", noremap = false, silent = true })

	vim.keymap.set("n", "<Plug>(NVUpdateNeovimRelease)", function()
		P.update_neovim({ build_type = "Release" })
	end, { desc = "Update Neovim with Release build via <Plug>", noremap = false, silent = true })

	vim.keymap.set("n", "<Plug>(NVUpdateRemoveSource)", function()
		P.remove_source_dir()
	end, { desc = "Remove Neovim source directory via <Plug>", noremap = false, silent = true })

	vim.keymap.set("n", "<Plug(NVUpdateCloneSource)", function()
		P.generate_source_dir()
	end, { desc = "Generate Neovim source directory via <Plug>", noremap = false, silent = true })
end

--- Setup user-friendly key mappings for updating Neovim or removing source.
---@function setup_user_friendly_keymaps
local function setup_user_friendly_keymaps()
	-- Create user-friendly bindings for the <Plug> mappings using <Leader> keys
	if P.default_config.default_keymaps then
		vim.keymap.set(
			"n",
			"<Leader>uU",
			"<Plug>(NVUpdateNeovim)",
			{ desc = "Update Neovim", noremap = true, silent = true }
		)
		vim.keymap.set(
			"n",
			"<Leader>uD",
			"<Plug>(NVUpdateNeovimDebug)",
			{ desc = "Update Neovim with Debug build", noremap = true, silent = true }
		)
		vim.keymap.set(
			"n",
			"<Leader>uR",
			"<Plug>(NVUpdateNeovimRelease)",
			{ desc = "Update Neovim with Release build", noremap = true, silent = true }
		)
		vim.keymap.set(
			"n",
			"<Leader>uC",
			"<Plug>(NVUpdateRemoveSource)",
			{ desc = "Remove Neovim source directory", noremap = true, silent = true }
		)
	end
end

--- Setup default keymaps during plugin initialization.
---@function setup_default_keymaps
local function setup_default_keymaps()
	setup_plug_keymaps() -- Set up <Plug> mappings
	setup_user_friendly_keymaps() -- Set up user-friendly mappings
end

--- Helper function to retry update
local function update_with_retry()
	if P.last_status.retry then
		P.last_status.retry = false
		utils.notify("Removal succeeded. Retrying update...", vim.log.levels.INFO, true)
		P.update_neovim()
	end
end

--- Update Neovim from source and show progress in a floating terminal.
---@param opts table|nil Optional options for the update process (tag, build_type, etc.)
function P.update_neovim(opts)
	opts = opts or {}
	local source_dir = opts.source_dir ~= "" and opts.source_dir or P.default_config.source_dir
	local build_type = opts.build_type ~= "" and opts.build_type or P.default_config.build_type
	local tag = opts.tag ~= "" and opts.tag or P.default_config.tag

	local notification_msg = "Starting Neovim update...\nSource: "
		.. source_dir
		.. "\\Tag: "
		.. tag
		.. "\nBuild: "
		.. build_type
	utils.notify(notification_msg, vim.log.levels.INFO)

	local dir_exists = utils.directory_exists(source_dir)
	local git_commands = ""

	if not dir_exists then
		git_commands = "git clone https://github.com/neovim/neovim " .. source_dir .. " && cd " .. source_dir .. " && "
	else
		-- Check if we're in a git repo and get current branch
		git_commands = "cd " .. source_dir .. " && git fetch origin && git pull && "
	end

	-- Only switch tag if we're not already on the target tag
	git_commands = git_commands .. 'test "$(git rev-parse --abbrev-ref HEAD)" = "' .. tag .. '" || '
	git_commands = git_commands .. "git switch --detach " .. tag

	local build_command = "cd "
		.. source_dir
		.. " && make distclean"
		.. " && make CMAKE_BUILD_TYPE="
		.. build_type
		.. " && sudo make install"

	local update_command = git_commands .. " && " .. build_command .. " && " .. "git checkout master"

	-- Use the open_floating_terminal from the 'utils' module
	utils.open_floating_terminal({
		command = update_command,
		filetype = "neovim_updater_term.updating",
		ispreupdate = false,
		autoclose = true,
		enter_insert = true,
		env = P.default_config.env, -- Pass environment variables
		callback = function(results)
			if results.result_code ~= 0 then
				utils.notify("Neovim update failed with error code: " .. results.result_code, vim.log.levels.ERROR)
				if P.default_config.build_fresh == false then
					utils.ConfirmPrompt("Remove build directory and try again?", function()
						P.last_status.count = "?"
						P.last_status.retry = true
						P.remove_source_dir({ source_dir = source_dir .. "/build" })
					end)
				end
			else
				utils.notify("Neovim update complete!", vim.log.levels.INFO, true)
				utils.notify("Please restart Neovim for the changes to take effect.", vim.log.levels.INFO)
				-- Update the status count
				P.last_status.count = "0"
			end
		end,
	})
end

--- Remove the Neovim source directory or a custom one.
---@function P.remove_source_dir
---@param opts table|nil Optional table for 'source_dir'
---@return boolean|nil success True if the directory was successfully removed
---                            False if the directory does not exist or an error occurred
---                            nil if the function is delayed until the terminal is closed
---                            Check the U.defered_value variable for the result
function P.remove_source_dir(opts)
	opts = opts or {}
	local source_dir = opts.source_dir ~= "" and opts.source_dir or P.default_config.source_dir

	if utils.directory_exists(source_dir) then
		-- Check if vim.fs.rm is available
		if vim.fs.rm then
			-- Use pcall to attempt to call the function
			local success, err = pcall(vim.fs.rm, source_dir, { recursive = true, force = true })
			if success then
				P.last_status.count = "?"
				utils.notify("Successfully removed Neovim source directory: " .. source_dir, vim.log.levels.INFO, true)
				utils.notify("Source directory removed with vim.fs.rm", vim.log.levels.DEBUG)
				update_with_retry()
				return true
			else
				if not err then
					err = "Unknown error"
				end
				utils.notify("Source directory removal failed with vim.fs.rm", vim.log.levels.DEBUG)

				-- Define callback function for checking rm
				local function check_rm()
					-- Check if the source directory still exists
					if not utils.directory_exists(source_dir) then
						P.last_status.count = "?"
						utils.notify(
							"Successfully removed Neovim source directory: " .. source_dir,
							vim.log.levels.INFO,
							true
						)
						update_with_retry()
						return true
					end
					utils.notify("Failed to remove Neovim source directory: " .. source_dir, vim.log.levels.ERROR)
					return false
				end

				-- Attempt to remove with elevated privileges

				local elevate_perms_explained = ""
				if P.default_config.verbose then
					elevate_perms_explained = "echo Removing the directory failed using traditional methods.\n"
						.. "echo This typically indicates a permissions issue with the directory.\n"
				end
				local rm_msg = elevate_perms_explained
					.. "echo Attempting to remove "
					.. source_dir
					.. " directory with elevated privileges.\n"
					.. "echo Please authorize sudo and press enter.\n"
				local privileged_rm = rm_msg .. "sudo rm -rf " .. source_dir
				utils.open_floating_terminal({
					command = privileged_rm,
					filetype = "neovim_updater_term.privileged_rm",
					ispreupdate = false,
					autoclose = true,
					callback = function(results)
						if results.result_code == 0 then
							-- Double-check the results
							check_rm()
						else
							utils.notify(
								"Failed to remove Neovim source directory: " .. source_dir,
								vim.log.levels.ERROR
							)
						end
					end,
				})
				-- Go to insert mode
				vim.cmd("startinsert")

				return nil
			end
		end
		-- Fallback to vim.fn.delete if vim.fs.rm is not available
		local success, err = vim.fn.delete(source_dir, "rf")
		if success == 0 then
			P.last_status.count = "?"
			utils.notify("Successfully removed Neovim source directory: " .. source_dir, vim.log.levels.INFO, true)
			utils.notify("Source directory removed with vim.fn.delete", vim.log.levels.DEBUG)
			update_with_retry()
			return true
		else
			if not err then
				err = "Unknown error"
			end
			utils.notify("Error removing Neovim source directory: " .. source_dir .. "\n" .. err, vim.log.levels.ERROR)
			utils.notify("Source directory removal failed with vim.fn.delete", vim.log.levels.DEBUG)
			return false
		end
	else
		utils.notify("Source directory does not exist: " .. source_dir, vim.log.levels.WARN)
		return false
	end
end

--- Generate the Neovim source directory.
---@function P.generate_source_dir
---@param opts table|nil Optional table for 'source_dir'
---@return string source_dir The source directory
function P.generate_source_dir(opts)
	opts = opts or {}
	-- Define the source
	local source_dir = opts.source_dir ~= "" and opts.source_dir or P.default_config.source_dir
	local repo = "https://github.com/neovim/neovim.git"
	local tag = opts.tag ~= "" and opts.tag or P.default_config.tag

	if not utils.directory_exists(source_dir) then
		-- Build the command to fetch the latest changes from the remote repository
		local fetch_command = ("cd ~ && git clone %s %s"):format(repo, source_dir)

		-- Checkout the tag
		local checkout_command = "cd " .. source_dir .. " && git checkout " .. tag

		-- Combine commands
		local complete_command = fetch_command .. " && " .. checkout_command

		-- Notify the user that the clone is starting
		utils.notify("Cloning Neovim source...", vim.log.levels.INFO)

		-- Open a terminal window
		utils.open_floating_terminal({
			command = complete_command,
			filetype = "neovim_updater_term.cloning",
			ispreupdate = false,
			autoclose = true,
			callback = function(results)
				if results.result_code == 0 then
					utils.notify("Neovim source cloned successfully", vim.log.levels.INFO, true)
					-- Set the update count to "0"
					P.last_status.count = "0"
				else
					utils.notify("Failed to clone Neovim source: " .. results.result_code, vim.log.levels.ERROR)
					P.last_status.count = "?"
				end
			end,
		})
	else
		-- Notify the user that the source directory already exists
		utils.notify("Neovim source directory already exists: " .. source_dir, vim.log.levels.WARN)
	end

	-- Return the source directory
	return source_dir
end

--- Function to return a statusline component
---@function get_statusline
---@return table status The statusline component
---   - count: The number of new commits
---   - text: The text of the status
---   - icon: The icon of the status
---   - icon_text: The icon and text of the status
---   - icon_count: The icon and count of the status
---   - color: The color of the status
function P.get_statusline()
	local status = {}
	local count = P.last_status.count
	status.count = count
	if count == "?" then
		status.text = "ERROR"
		status.icon = "󰨹 "
		status.color = "DiagnosticError"
	elseif count == "0" then
		status.text = "Up to date"
		status.icon = "󰅠 "
		status.color = "DiagnosticOk"
	elseif count == "1" then
		status.text = count .. " new update"
		status.icon = "󰅢 "
		status.color = "DiagnosticWarn"
	else
		status.text = count .. " new updates"
		status.icon = "󰅢 "
		status.color = "DiagnosticWarn"
	end

	status.icon_text = status.icon .. " " .. status.text
	status.icon_count = status.icon .. " " .. count

	return status
end

--- Create user commands for both updating and removing Neovim source directories
---@function P.setup_usercmd
function P.setup_usercmds()
	--- Define NVUpdateNeovim command to accept branch, build_type, and source_dir as optional arguments
	vim.api.nvim_create_user_command("NVUpdateNeovim", function(opts)
		local args = vim.split(opts.args, " ")
		local tag = (args[1] == "" and P.default_config.tag or args[1])
		local build_type = (args[2] == "" and P.default_config.build_type or args[2])
		local source_dir = (args[3] == "" and P.default_config.source_dir or args[3])

		P.update_neovim({ tag = tag, build_type = build_type, source_dir = source_dir })
	end, {
		desc = "Update Neovim with optional branch, build_type, and source_dir",
		nargs = "*", -- Accept multiple (optional) arguments
	})

	--- Define NVUpdateCloneSource command to accept source_dir and branch as optional arguments
	vim.api.nvim_create_user_command("NVUpdateCloneSource", function(opts)
		local args = vim.split(opts.args, " ")
		local source_dir = (args[1] == "" and P.default_config.source_dir or args[1])
		local tag = (args[2] == "" and P.default_config.tag or args[2])

		P.generate_source_dir({ source_dir = source_dir, tag = tag })
	end, {
		desc = "Clone Neovim source directory with optional branch",
		nargs = "*", -- Accept multiple (optional) arguments
	})

	--- Define NVUpdateRemoveSource command to optionally accept a custom `source_dir`
	vim.api.nvim_create_user_command("NVUpdateRemoveSource", function(opts)
		local args = vim.split(opts.args, " ")
		P.remove_source_dir({
			source_dir = #args > 0 and (args[1] == "" and P.default_config.source_dir or args[1]) or nil,
		})
	end, {
		desc = "Remove Neovim source directory (optionally specify custom path)",
		nargs = "?", -- Allow one optional argument
	})
end

--- Initialize Neovim updater plugin configuration
---@function P.setup
---@param user_config table|nil User configuration overriding default values
function P.setup(user_config)
	P.default_config = vim.tbl_deep_extend("force", P.default_config, user_config or {})

	-- Setup default keymaps only if not overridden by user configuration
	setup_default_keymaps()

	-- Setup Neovim user commands
	P.setup_usercmds()
end

return P
