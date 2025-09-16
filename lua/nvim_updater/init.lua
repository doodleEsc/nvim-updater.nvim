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
	force_update = false, -- Force update source code before build
	update_before_switch = true, -- Update source code before switching to target
	use_shallow_clone = true, -- Use shallow clone to reduce download size
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
--- This function now ensures source code is updated to latest before switching to target tag/branch.
---@param opts table|nil Optional options for the update process
---@field tag string Target tag or branch name (default: config.tag)
---@field build_type string Build type: "Release" or "Debug" (default: config.build_type)
---@field source_dir string Source directory path (default: config.source_dir)
---@field force_update boolean Force update source code regardless of config (default: false)
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

	-- Forward declarations for async step functions
	local step1_clone_if_needed, step2_update_if_needed, step3_switch_to_target, step4_build_and_install

	-- Step 4: Build and install
	step4_build_and_install = function()
		local build_command = "cd "
			.. source_dir
			.. " && echo 'Starting build process...' && make distclean"
			.. " && echo 'Building with CMAKE_BUILD_TYPE="
			.. build_type
			.. "' && make CMAKE_BUILD_TYPE="
			.. build_type
			.. " && echo 'Installing...' && sudo make install && echo 'Installation completed!'"

		utils.open_floating_terminal({
			command = build_command,
			filetype = "neovim_updater_term.building",
			ispreupdate = false,
			autoclose = true,
			enter_insert = true,
			env = P.default_config.env,
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
					P.last_status.count = "0"
				end
			end,
		})
	end

	-- Step 3: Switch to target tag/branch
	step3_switch_to_target = function()
		utils.switch_to_target(source_dir, tag, function(success)
			if success then
				step4_build_and_install()
			else
				utils.notify("Failed to switch to target: " .. tag, vim.log.levels.ERROR)
			end
		end, P.default_config.env)
	end

	-- Step 2: Update source code to latest if configured
	step2_update_if_needed = function()
		-- Check if this is a shallow clone by looking for .git/shallow file
		local shallow_file = source_dir .. "/.git/shallow"
		local is_shallow_clone = utils.directory_exists(shallow_file:gsub("/[^/]*$", ""))
			and vim.fn.filereadable(shallow_file) == 1

		if is_shallow_clone and P.default_config.use_shallow_clone then
			-- For existing shallow clones, skip update and go directly to target switch
			utils.notify("Detected shallow clone, skipping update step", vim.log.levels.INFO)
			step3_switch_to_target()
		elseif P.default_config.update_before_switch or opts.force_update then
			utils.ensure_latest_code(source_dir, function(success)
				if success then
					step3_switch_to_target()
				else
					utils.notify("Failed to update source code. Continuing with current state.", vim.log.levels.WARN)
					step3_switch_to_target()
				end
			end, P.default_config.env)
		else
			step3_switch_to_target()
		end
	end

	-- Step 1: Handle source directory setup (clone if needed)
	step1_clone_if_needed = function()
		if not dir_exists then
			if P.default_config.use_shallow_clone then
				-- Use smart clone with optimizations for the target tag/branch
				-- Smart clone handles both cloning AND switching to the target, so we can skip step2 and step3
				utils.smart_clone("https://github.com/neovim/neovim", source_dir, tag, function(clone_success)
					if clone_success then
						utils.notify(
							"Successfully cloned Neovim repository with optimizations",
							vim.log.levels.INFO,
							true
						)
						-- Smart clone already handled target switching, go directly to build
						step4_build_and_install()
					else
						utils.notify("Failed to clone Neovim repository", vim.log.levels.ERROR)
					end
				end, P.default_config.env)
			else
				-- Use traditional full clone, then need to update and switch
				local clone_command = "echo 'Cloning Neovim repository (full clone)...' && git clone --progress https://github.com/neovim/neovim "
					.. source_dir
					.. " && echo 'Repository cloned successfully!'"

				utils.open_floating_terminal({
					command = clone_command,
					filetype = "neovim_updater_term.cloning",
					autoclose = true,
					env = P.default_config.env,
					callback = function(results)
						if results.result_code == 0 then
							utils.notify("Successfully cloned Neovim repository", vim.log.levels.INFO, true)
							-- Traditional clone needs update and switch steps
							step2_update_if_needed()
						else
							utils.notify("Failed to clone Neovim repository", vim.log.levels.ERROR)
						end
					end,
				})
			end
		else
			-- Directory exists, proceed to next step
			step2_update_if_needed()
		end
	end

	-- Start the async process
	step1_clone_if_needed()
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
		if P.default_config.use_shallow_clone then
			-- Use smart clone that optimizes for the target tag/branch
			utils.notify("Cloning Neovim source with optimizations...", vim.log.levels.INFO)

			utils.smart_clone(repo, source_dir, tag, function(clone_success)
				if clone_success then
					utils.notify("Neovim source cloned successfully with optimizations", vim.log.levels.INFO, true)
					P.last_status.count = "0"
				else
					utils.notify("Failed to clone Neovim source", vim.log.levels.ERROR)
					P.last_status.count = "?"
				end
			end, P.default_config.env or {})
		else
			-- Use traditional full clone and then switch
			local clone_command = "echo 'Cloning Neovim repository (full clone) from "
				.. repo
				.. "...' && git clone --progress "
				.. repo
				.. " "
				.. source_dir
				.. " && echo 'Repository cloned successfully!'"

			utils.notify("Cloning Neovim source...", vim.log.levels.INFO)

			utils.open_floating_terminal({
				command = clone_command,
				filetype = "neovim_updater_term.cloning",
				ispreupdate = false,
				autoclose = true,
				callback = function(results)
					if results.result_code == 0 then
						utils.notify("Neovim source cloned successfully", vim.log.levels.INFO, true)
						-- Switch to the specified tag/branch using the new async function
						utils.switch_to_target(source_dir, tag, function(switch_success)
							if switch_success then
								P.last_status.count = "0"
							else
								utils.notify("Failed to switch to target: " .. tag, vim.log.levels.ERROR)
								P.last_status.count = "?"
							end
						end)
					else
						utils.notify("Failed to clone Neovim source: " .. results.result_code, vim.log.levels.ERROR)
						P.last_status.count = "?"
					end
				end,
			})
		end
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
	--- Define NVUpdateNeovim command to accept tag, build_type, source_dir, and force as optional arguments
	vim.api.nvim_create_user_command("NVUpdateNeovim", function(opts)
		local args = vim.split(opts.args, " ")
		local tag = (args[1] == "" and P.default_config.tag or args[1])
		local build_type = (args[2] == "" and P.default_config.build_type or args[2])
		local source_dir = (args[3] == "" and P.default_config.source_dir or args[3])
		local force_update = (args[4] == "force" or args[4] == "true")

		P.update_neovim({ tag = tag, build_type = build_type, source_dir = source_dir, force_update = force_update })
	end, {
		desc = "Update Neovim with optional tag, build_type, source_dir, and force",
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
