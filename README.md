# LANSHANProject: An Unrecorded Story 

**火兰山中学** (c) FuncWork Studios

这是《火兰山中学》的程序部分。

使用Godot完成。Godot是一个新兴的游戏引擎，由C++开发，使用GDScript这种解释型语言。

游戏玩法以解密为主，玩家通过解密来推进故事的走向。

UI由 `@konita2314` 和 `@LZJFRRFJRL` 设计。但仍有许多不足之处。

故事来自 `@在下成才` 、 `@灰鱼` 、 `@星诚极光` ，由 `@因心慕芸`、 `@U+25A0*5` 校对和编辑。

程序来自 `@konita2314` 、 `@BAKVAC` 、 `@NCD(dec.)` 、 `@猫猫重度依赖。` 。

音乐来自 `@在下成才` 、 `@Team Tangent` 、 `@YuUkiiz.` 。

美术来自 `@雪夜冰` 、 `@超级无敌高冷大帅哥` 、 `@山楠` 、 `@白洲Azusa` 。

纪念已故的 `@Sakana.iku` 、 `@NCD` 。

## 主要介绍

这是一款解谜游戏，通过搜集证据推理线索。

## 文件结构

```
godot_project/
├── project.godot                 # 项目配置（autoload、输入映射、渲染设置）
├── export_presets.cfg            # 导出预设（exclude_filter 已排除 addons/、.vscode/、scenes/debug/）
├── locale/                       # zh.po / en.po 翻译文件
├── assets/
│   ├── backgrounds/scenes/       # 场景背景
│   ├── backgrounds/menu/         # 菜单背景
│   ├── characters/               # 角色立绘
│   ├── music/                    # BGM
│   ├── sfx/                      # 音效
│   ├── fonts/                    # 字体文件
│   ├── icons/                    # 图标
│   ├── map/                      # 校园地图图片
│   └── about/                    # 关于页素材
├── scenes/
│   ├── SceneManager.tscn/.gd     # 唯一的引擎级主场景 — 场景路由、过渡、共享背景层
│   ├── debug/                    # DebugBoot — 单场景调试入口（不参与发布）
│   ├── ui/                       # BackBar、BackgroundLayer、OptionRow、HintBar、tips/
│   ├── mainmenu/                 # 主菜单、启动画面、QuitModal
│   │   ├── about/                # 关于页（滚动字幕）
│   │   ├── rewards/              # RewardsScene、AchievementList/Reached、MusicGallery、SceneGallery
│   │   ├── save_load/            # 存档/读档
│   │   └── settings/             # 设置页
│   └── game/
│       ├── vn/                   # VN 核心（VNInterface、ChoicesMenu、SaveMenu、LogScreen、
│       │                         #          VNBackground、LoadingScreen）
│       ├── tab_menu/             # 游戏内 Tab 菜单
│       ├── map/                  # 校园交互地图
│       ├── calendar/             # 日历
│       ├── dateswitch/           # 日期跳转
│       ├── operations/           # Notebook、OpProgress（OpStart 开始卡 / OpAcc 完成卡）
│       └── registration/         # 新游戏注册页（模拟网页表单）
├── scripts/
│   ├── autoload/                 # 5 个全局单例：EventBus、GameManager、AudioManager、
│   │                             #                VNAudioService、FlowManager
│   ├── parser/                   # ScriptParser、ScriptContext、ScriptExpression
│   ├── resources/                # 数据类（SaveData、AppSettings、PlotData、PlotNode…）
│   ├── gallery/                  # SceneGalleryData、MusicGalleryData、ScenesData
│   ├── story/                    # 剧本（见下「剧本登记」）
│   │   ├── Intro/                # 序章
│   │   ├── Main/                 # M1–M4 主线章节（M1 含 Locations/ 地点子剧本）
│   │   ├── GL/                   # 角色路线（LinZixin / JiangShixuan / ShiQingwen）
│   │   └── SideStory/            # 支线故事（LiDaquan）
│   ├── AssetResolver.gd          # 资源路径规范化与短名解析
│   └── MenuSelection.gd
├── shaders/                      # blur、crt_effect、pixelate
└── themes/                       # lsp_theme.tres
```

## 架构要点

**单场景架构。** 引擎级主场景只有 `scenes/SceneManager.tscn` 一个。其余 `.tscn` 都由
`SceneManager` 懒加载成它 `SceneContainer` 下的子节点，靠 `_on_enter()` / `_on_exit()`
协议与 duck-typed 信号连线（`back_requested`、`save_selected`、`flow_return` …）驱动；
共享背景层与全局 CanvasLayer（Tips、行动标题卡 OpStart / OpAcc、成就弹窗）也由它创建。

因此**子场景不能独立 F6 运行** —— 直接运行会缺少整个驱动器。需要单场景调试时请用
`scenes/debug/DebugBoot.tscn`（用法见该脚本头部注释）。

**剧本登记。** 剧本以 GDScript 字符串常量存储（`extends RefCounted` + `const TEXT`），
跨文件加载必须登记进 `VNInterface.STORY_TEXTS` 或 `SIDE_STORY`，否则运行时报
`Could not load plot`。脚本内的 `:: id` 必须与注册表的 key 一致
（`VNInterface._load_plot_internal` 对此有运行时校验）。

## 依赖

`addons/meow_godot_mcp/`（Godot 编辑器 MCP 插件）**未纳入版本控制**，但 `project.godot`
的 `editor_plugins/enabled` 会引用它。克隆仓库后需自行放置该插件目录，否则编辑器会提示
插件缺失（不影响游戏本体运行与导出）。
