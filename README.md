# LANSHANProject — Godot 4.6 Port

兰山计划 (Lanshan Project) visual novel — 1:1 port from React/TypeScript web version to Godot Engine 4.6.

## Quick Start

1. Download and open [Godot Engine 4.6+](https://godotengine.org/)
2. Click **Import** → select `project.godot`
3. Press **F5** to run

## Controls

| Key | Action |
|-----|--------|
| `W` / `↑` / `A` / `←` | Navigate up |
| `S` / `↓` / `D` / `→` | Navigate down |
| `Enter` / `Space` | Confirm / Advance dialogue |
| `Esc` | Back / Cancel |
| `Tab` | In-game system menu |
| `X` | Toggle skip mode |
| `A` (in VN) | Toggle auto-play |
| `S` (in VN) | Open save menu |

## Project Structure

```
godot_project/
├── project.godot              # Engine configuration
├── assets/
│   ├── Characters/            # Character sprites
│   ├── Scenes/                # Background images
│   ├── Music/                 # BGM and SFX (.mp3)
│   ├── Icons/                 # UI icons (FWS.png, LSP_icon_big.png)
│   ├── fonts/                 # Font files
│   └── plot/                  # Story scripts (.txt)
├── scripts/                   # Data classes and parser
│   ├── PlotNode.gd            # Plot node data class
│   ├── PlotData.gd            # Plot container
│   ├── PlotOption.gd          # Choice option data
│   ├── LocText.gd             # Localized text pair
│   ├── AudioCommand.gd        # Audio play/stop command
│   ├── SaveData.gd            # Save slot data
│   ├── AppSettings.gd         # Application settings
│   └── ScriptParser.gd        # .txt script → PlotData parser
└── scenes/
    ├── SceneManager.gd/.tscn  # Root scene router
    ├── Autoload/              # Global singletons
    │   ├── EventBus.gd        # Global signal hub
    │   ├── GameManager.gd     # Save/settings persistence
    │   └── AudioManager.gd    # Audio playback
    ├── Menu/
    │   ├── SplashScene.gd/.tscn
    │   └── MainMenu.gd/.tscn
    ├── VN/
    │   ├── VNInterface.gd/.tscn
    │   └── TabMenu.gd
    ├── SaveLoad/
    │   └── LoadScene.gd/.tscn
    ├── Settings/
    │   └── SettingsScene.gd/.tscn
    ├── About/
    │   └── AboutScene.gd/.tscn
    ├── Rewards/
    │   └── RewardsScene.gd/.tscn
    ├── Registration/
    │   └── RegistrationScene.gd/.tscn
    ├── Modals/
    │   ├── QuitConfirm.gd
    │   └── OverwriteConfirm.gd
    └── UI/
        └── LSPTheme.tres
```

## Features

- **Splash/Warning screen** — Logo display + epilepsy/legal disclaimer
- **Main Menu** — Animated parallax background, keyboard/mouse navigation, sweep effects
- **Visual Novel** — Background/character display, typewriter text, choices, skip/auto
- **Save/Load** — 20-slot grid with ConfigFile persistence
- **Settings** — Audio volume, text speed, language, display mode, shader quality
- **Tab Menu** — Multi-level in-game system menu (MAIN → SYSTEM → CONFIG)
- **Registration** — Name input form
- **Glitch Effects** — Visual distortion, screen shake for dramatic moments
- **Chinese/English** — Full bilingual support

## Script Format (.txt)

```
[Title: My Story]
[ID: my_id]

@chapter(章节名, Chapter Name)
@bg(path/to/background.jpg)
@music(path/to/bgm.mp3)
@ch(path/to/sprite.png)

Character: Dialogue text here.
Narration without speaker.

@glitch()
???: Unknown speaker.

? What will you do?
> Option A -> next_chapter@0
> Option B -> 5
```

## Architecture

- **MVC pattern** — PlotNode/PlotData (Model), Scene scripts (View), GameManager (Controller)
- **Autoloads** — EventBus, GameManager, AudioManager
- **Composition** — Scenes are self-contained Controls, SceneManager routes between them
- **Signals** — Decoupled communication via EventBus
- **Static typing** — All GDScript uses full type annotations

## Web Version → Godot Mapping

| Web (React/TS) | Godot |
|---|---|
| `App.tsx` scene routing | `SceneManager.gd` |
| `saveService.ts` + localStorage | `GameManager.gd` + ConfigFile |
| `audioService.ts` + Web Audio API | `AudioManager.gd` + AudioStreamPlayer |
| `parser.ts` + fetch() | `ScriptParser.gd` + FileAccess |
| React components + Tailwind | Control nodes + Theme |
| Framer Motion animations | Tweens |
| CSS glitch/keyframes | Tween + ColorRect filters |
