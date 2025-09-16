# nvim-updater.nvim

![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)
[![nvim-updater.nvim](https://dotfyle.com/plugins/rootiest/nvim-updater.nvim/shield?style=for-the-badge)](https://dotfyle.com/plugins/rootiest/nvim-updater.nvim)

A powerful Neovim plugin that allows you to effortlessly update Neovim from source with intelligent tag-based version management, optimized cloning strategies, and comprehensive build customization - all without leaving your editor.

## ✨ 核心特性

- **智能版本管理**: 支持稳定版本标签和开发分支的自动切换
- **优化克隆策略**: 使用浅克隆技术减少下载时间和存储空间
- **灵活构建系统**: 支持Release、Debug和RelWithDebInfo构建类型
- **异步操作界面**: 所有操作都在浮动终端中异步执行，提供实时反馈
- **智能错误处理**: 自动检测和处理各种Git状态和构建错误
- **状态栏集成**: 提供丰富的状态栏组件用于显示更新状态

## 📋 系统要求

- **操作系统**: Linux系统（当前不支持macOS和Windows）
- **Neovim版本**: 0.9+ （推荐0.10+）
- **构建依赖**: 满足[Neovim构建前提条件](https://github.com/neovim/neovim/blob/master/BUILD.md#build-prerequisites)
- **Git**: 用于源代码管理
- **编译工具**: make, cmake, gcc/clang等

> [!IMPORTANT]
> 建议在使用此插件安装源码编译版本后，卸载发行版提供的neovim包，以防止包管理器更新覆盖本地编译的版本。

### 🔌 可选依赖

- [diffview.nvim](https://github.com/sindrets/diffview.nvim) - 在DiffView中显示新提交
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) - 在Telescope中显示新提交

## 📦 安装配置

### 使用 [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "rootiest/nvim-updater.nvim",
  version = "*", -- 锁定到GitHub releases
  config = function()
    require("nvim_updater").setup({
      source_dir = "~/.local/src/neovim",  -- 自定义源码目录
      build_type = "Release",              -- 构建类型
      tag = "stable",                      -- 跟踪稳定版本
      default_keymaps = false,             -- 禁用默认按键映射
      use_shallow_clone = true,            -- 使用浅克隆优化
      update_before_switch = true,         -- 切换前更新源代码
    })
  end,
  keys = { -- 自定义按键映射
    {
      "<Leader>nu",
      function()
        require('nvim_updater').update_neovim()
      end,
      desc = "更新Neovim"
    },
    {
      "<Leader>nd",
      function()
        require('nvim_updater').update_neovim({ build_type = 'Debug' })
      end,
      desc = "Debug构建Neovim"
    },
    {
      "<Leader>nr",
      ":NVUpdateRemoveSource<CR>",
      desc = "删除Neovim源代码目录",
    },
  }
}
```

### 最小化配置

```lua
{
  "rootiest/nvim-updater.nvim",
  version = "*",
  opts = {},
}
```

### 使用 [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "rootiest/nvim-updater.nvim",
  tag = "*",
  config = function()
    require("nvim_updater").setup({
      source_dir = "~/.local/src/neovim",
      build_type = "Release",
      tag = "stable",
      default_keymaps = false,
    })

    -- 自定义按键映射
    vim.keymap.set("n", "<Leader>nu", function()
      require('nvim_updater').update_neovim()
    end, { desc = "更新Neovim" })

    vim.keymap.set("n", "<Leader>nd", function()
      require('nvim_updater').update_neovim({ build_type = 'Debug' })
    end, { desc = "Debug构建Neovim" })

    vim.keymap.set("n", "<Leader>nr", ":NVUpdateRemoveSource<CR>",
      { desc = "删除Neovim源代码目录" })
  end,
}
```

## ⚙️ 配置选项

### 核心配置

| 选项              | 类型    | 默认值                  | 描述                                   |
| ----------------- | ------- | ----------------------- | -------------------------------------- |
| `source_dir`      | string  | `"~/.local/src/neovim"` | Neovim源代码目录路径                   |
| `build_type`      | string  | `"Release"`             | 构建类型：Release/Debug/RelWithDebInfo |
| `tag`             | string  | `"stable"`              | 目标版本标签或分支名                   |
| `verbose`         | boolean | `false`                 | 启用详细输出                           |
| `default_keymaps` | boolean | `false`                 | 启用默认按键映射                       |

### 高级配置

| 选项                   | 类型    | 默认值  | 描述                 |
| ---------------------- | ------- | ------- | -------------------- |
| `build_fresh`          | boolean | `true`  | 编译前清理构建目录   |
| `force_update`         | boolean | `false` | 强制更新源代码       |
| `update_before_switch` | boolean | `true`  | 切换版本前更新源代码 |
| `use_shallow_clone`    | boolean | `true`  | 使用浅克隆优化       |
| `env`                  | table   | `{}`    | 额外的环境变量       |

### 构建类型说明

- **Release**: 优化的发布版本，无调试符号（推荐日常使用）
- **Debug**: 包含完整调试符号，用于开发调试
- **RelWithDebInfo**: 发布版本包含部分调试符号，平衡性能和调试能力

### 版本标签说明

- **stable**: 最新稳定版本
- **v0.10.x**: 特定版本标签
- **master**: 开发主分支（nightly构建）
- **release-0.10**: 发布分支

## 🎯 默认按键映射

当启用`default_keymaps = true`时，插件提供以下默认按键：

- `<Leader>uU`: 使用默认配置更新Neovim
- `<Leader>uD`: 使用Debug构建更新Neovim
- `<Leader>uR`: 使用Release构建更新Neovim
- `<Leader>uC`: 删除Neovim源代码目录

## 🔧 命令接口

### 用户命令

#### `:NVUpdateNeovim [tag] [build_type] [source_dir] [force]`

更新Neovim，支持可选参数：

```vim
:NVUpdateNeovim                           " 使用默认配置
:NVUpdateNeovim stable Release           " 指定版本和构建类型
:NVUpdateNeovim v0.10.0 Debug ~/.local/src/neovim force
```

#### `:NVUpdateCloneSource [source_dir] [tag]`

克隆Neovim源代码：

```vim
:NVUpdateCloneSource                      " 使用默认配置
:NVUpdateCloneSource ~/.local/src/neovim stable
```

#### `:NVUpdateRemoveSource [source_dir]`

删除源代码目录：

```vim
:NVUpdateRemoveSource                     " 删除默认目录
:NVUpdateRemoveSource ~/.local/src/neovim " 删除指定目录
```

### Lua API

#### 更新Neovim

```lua
require("nvim_updater").update_neovim({
  tag = "stable",
  build_type = "Release",
  source_dir = "~/.local/src/neovim",
  force_update = false
})
```

#### 克隆源代码

```lua
require("nvim_updater").generate_source_dir({
  source_dir = "~/.local/src/neovim",
  tag = "stable"
})
```

#### 删除源代码

```lua
require("nvim_updater").remove_source_dir({
  source_dir = "~/.local/src/neovim"
})
```

#### 获取状态栏信息

```lua
local status = require("nvim_updater").get_statusline()
-- 返回包含count, text, icon, icon_text, icon_count, color的表
```

## 📊 状态栏集成

### Lualine集成示例

```lua
require("lualine").setup {
  sections = {
    lualine_x = {
      {
        function()
          return require("nvim_updater").get_statusline().icon_text
        end,
        color = function()
          return require("nvim_updater").get_statusline().color
        end,
        on_click = function()
          require("nvim_updater").update_neovim()
        end,
      },
    },
  },
}
```

### 文件类型集成

插件为终端缓冲区分配自定义文件类型：

- `neovim_updater_term.building` - 构建过程中
- `neovim_updater_term.cloning` - 克隆过程中
- `neovim_updater_term.switching` - 切换版本中
- `neovim_updater_term.updating_source` - 更新源代码中

## 🔄 外部使用

### 命令行集成

设置环境变量`NVIMUPDATER_HEADLESS=1`可以在命令行中直接使用：

```bash
NVIMUPDATER_HEADLESS=1 nvim "+NVUpdateNeovim"
```

创建别名简化使用：

```bash
# Bash/Zsh
alias nvimup='NVIMUPDATER_HEADLESS=1 nvim "+NVUpdateNeovim"'

# Fish
alias --save nvimup='NVIMUPDATER_HEADLESS=1 nvim "+NVUpdateNeovim"'
```

### 桌面快捷方式

创建桌面文件`~/.local/share/applications/nvimup.desktop`：

```desktop
[Desktop Entry]
Name=Neovim Updater
Exec=env NVIMUPDATER_HEADLESS=1 nvim "+NVUpdateNeovim"
Terminal=true
Type=Application
Icon=nvim
```

## 🔍 健康检查

运行以下命令检查插件状态：

```vim
:checkhealth nvim_updater
```

健康检查会验证：

- Neovim版本兼容性
- 源代码目录状态
- 目录写权限
- 远程标签有效性

## ⚡ 性能优化

### 浅克隆优化

当启用`use_shallow_clone = true`时，插件使用智能克隆策略：

1. **分支优化**: 直接克隆目标分支(`--single-branch --depth 1`)
2. **标签优化**: 浅克隆后获取特定标签
3. **降级策略**: 必要时回退到完整克隆

### 环境变量配置

通过`env`选项传递额外的环境变量：

```lua
require("nvim_updater").setup({
  env = {
    CMAKE_BUILD_TYPE = "Release",
    MAKEFLAGS = "-j4",  -- 并行编译
  }
})
```

## 🛡️ 兼容性说明

- **平台支持**: 主要针对Linux环境开发，使用`sudo make install`
- **Neovim版本**: 需要0.9+，推荐0.10+以获得最佳体验
- **Git要求**: 需要现代Git版本支持浅克隆和switch命令

## 🤝 贡献指南

欢迎提交Issues和Pull Requests！

### 报告问题时请包含

1. `nvim --version`的输出
2. 详细的错误信息
3. 重现步骤
4. 系统环境信息

### Pull Request指南

1. Fork此仓库
2. 创建功能分支
3. 确保代码经过测试
4. 提交PR并详细描述更改

## 📝 许可证

本项目采用[MIT许可证](LICENSE)。

---

## 🙏 致谢

感谢所有贡献者和Neovim社区的支持。

<div align="center">

**[⬆ 回到顶部](#nvim-updaternvim)**

</div>

