# dotfiles 脚手架

目标：构建一个可持续扩展的 dotfiles 一键安装与部署脚手架。

当前阶段：完成基础架构，明确边界。

## 项目结构

```text
.
├── setup.sh                  # 标准入口
├── scripts/
│   ├── lib/                  # 通用库（无业务）
│   │   ├── export.sh         # 统一加载入口（固定顺序 source 其余库）
│   │   ├── log.sh            # 统一日志输出与错误终止
│   │   ├── cmd.sh            # 命令检测、命令执行、dry-run
│   │   ├── privilege.sh      # as_root/as_user、目标用户解析
│   │   ├── os.sh             # 系统信息检测（OS/CPU/内存/内核）与达标校验
│   │   ├── cli.sh            # 通用参数解析（--dry-run, -h/--help）
│   │   ├── pkg.sh            # 包管理器检测与统一安装接口
│   │   └── env.sh            # 环境变量规格读取与校验
│   └── funcs/                # 可组合功能模块（按序号执行）
│       ├── 000-deploy-dotfiles.sh
│       └── 001-install-packages.sh
├── manifests/
│   └── packages/
│       └── default.txt       # 软件包清单（每行一个）
└── dotfiles/                 # stow 包目录
	└── .gitkeep
```

## 入口命令

```bash
./setup.sh
./setup.sh --dry-run
```

`setup.sh` 执行顺序由脚本内的 `RUN_FUNCS` 数组决定，支持：

- 仅写编号：`"000"`, `"001"`
- 写完整名：`"000-deploy-dotfiles.sh"`

运行前会扫描 `scripts/funcs`，若发现编号前缀重复（如两个 `000-*`）会直接报错退出。

## 创建功能脚本

```bash
./new-func.sh install-fonts
```

- 传入不带序号的功能名。
- 脚本会自动读取 `scripts/funcs` 中最大序号并 `+1`。
- 生成的文件会自动包含统一参数解析与三钩子模板（`show_help/env_spec/run_impl/dry_run_impl`）。

## dotfiles 目录说明

- `dotfiles/` 本身就是 `$HOME` 的镜像根目录。
- 例如 `dotfiles/.zshrc` 会直接映射到 `$HOME/.zshrc`。
- 例如 `dotfiles/.config/nvim/init.lua` 会直接映射到 `$HOME/.config/nvim/init.lua`。
- 不需要再加一层 `zsh/`、`git/` 这种“包目录”前缀。
- 仓库初始通过 `.gitkeep` 保持空目录可提交；实际配置按需逐步加入。

## 边界约束

- `scripts/lib` 只保留可复用基础能力，不放业务流程。
- `scripts/funcs` 按 `000/001/...` 编号组织可组合能力脚本。
- `setup.sh` 使用 `RUN_FUNCS` 单链路按顺序执行，不区分 required/optional。
- dotfiles 部署统一通过 `stow`。

## CLI 约定

- 所有脚本统一通过 `scripts/lib/cli.sh` 解析 `--dry-run` 与 `-h/--help`。
- 每个脚本都在文件内提供 `show_help`，执行 `-h` 时可直接查看该脚本说明。
- 每个脚本都提供 `env_spec`（返回 `KEY|DEFAULT|DESC` 列表）。
- 新增脚本建议固定四钩子：`show_help + env_spec + run_impl + dry_run_impl`。
- 功能脚本入口建议直接使用一行：`cli::run_noargs_hooks "xxx.sh" show_help env_spec run_impl dry_run_impl "$@"`。
- `setup.sh -h` 会按 `RUN_FUNCS` 顺序自动汇总并打印每个 func 的环境变量说明。

## lib 命名约定

- `scripts/lib` 对外函数统一使用命名空间前缀。
- 示例：`cli::parse_common`、`log::info`、`cmd::run`、`pkg::install`、`privilege::as_user`。
- 目的：快速定位来源、避免与系统命令或业务函数重名。

## lib 加载约定

- 功能脚本只 source 一个文件：`scripts/lib/export.sh`。
- `export.sh` 负责按顺序加载所有库，避免每个脚本重复 source。
- lib 默认不执行副作用动作；如需错误 trap，脚本内显式调用 `log::enable_err_trap`。

## dry-run 安全约定

- 所有会触发系统变更的 lib 路径统一经由 `cmd::run` 执行。
- `cmd::run` 在 dry-run 模式下只打印命令，不执行实质变更。

## 000 备份策略

- `000-deploy-dotfiles.sh` 在 stow 链接前会先备份目标路径中已存在的文件/目录。
- 备份参数通过 `env_spec` 暴露，可在 `-h` 中查看并通过环境变量覆盖。
- 默认会忽略 `.gitkeep`，避免将占位文件链接到 `$HOME`。