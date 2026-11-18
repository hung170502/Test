# Steal-An-Egg

Auto-farm hub for **Steal An Egg** on Roblox (Potassium executor).

## Features

- Egg ESP (rarity, zone, distance)
- Auto farm: pick rarest allowed egg → carry home → deposit → repeat
- Pathfinding (treadmill / trap avoidance)
- Auto place / auto sell / inventory management
- Pet care, base pen automation
- Hub UI (Drawing UI or VoidUI) — toggle with **G**

## Quick start

Remote executor (no local files required):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/hung170502/Test/main/run.lua"))()
```

Local workspace:

```lua
loadstring(readfile("Steal-An-Egg/run.lua"))()
-- or
loadfile("Steal-An-Egg/hub_loader.lua")()
```

Press **G** to open the hub menu.

## Requirements

- [Potassium](https://potassium.pro/) (or compatible executor with `readfile` / `loadfile`)
- Game: Steal An Egg

## Optional: MCP bridge (Cursor debug)

Run `potassium_bridge.lua` in-game while using Cursor MCP tools.

## Disclaimer

For educational / personal use. Use at your own risk on Roblox ToS.
"# Test"
