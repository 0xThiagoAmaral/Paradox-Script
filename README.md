# Paradox-Script

A high-performance automated combo script for the hero **Paradox** in the game **Deadlock**, designed for the Umbrella framework.

This repository contains a collection of Lua scripts that implement automated combos, aim assistance, damage calculation, and kill stealing mechanics for Paradox, allowing for perfect ability and item execution.

## Features

- **Automated Combo System**: Perfectly executes Paradox's combo sequence (Swap -> Pulse Grenade -> Kinetic Carbine).
- **Item Integration**: Automatically uses active items during the combo phase (e.g., Mystic Vulnerability, Silence Glyph, Slowing Hex, Knockdown, Echo Shard).
- **Auto Aim & Prediction**: Highly accurate aiming logic and prediction for Kinetic Carbine and Paradoxical Swap.
- **Damage Calculation**: Real-time lethal damage calculation to ensure the combo secures the kill.
- **Kill Stealer**: Automatically secures low-HP targets.
- **Wall & Swap Logic**: Specialized scripts for optimizing Time Wall placements and Swap angles.

## File Structure

- `1_paradox_combo_core.lua` / `paradox_combo.lua`: Core logic and user interface for the main combo execution.
- `0_paradox_build.lua`: Auto-build system integration.
- `0_paradox_swap.lua` / `0_paradox_wall.lua`: Specific ability assistants.
- `aim.lua` / `prediction.lua`: Tracking, targeting, and projectile prediction.
- `damage_calc.lua`: Calculations for lethal thresholds.
- `killstealer.lua`: Logic to auto-cast abilities on low-hp enemies.
- `target_selector.lua` / `ally_manager.lua`: Logic for prioritizing targets and avoiding bad engagements.
- `utils.lua`: Helper functions used across the scripts.

## Requirements

- Designed for the Umbrella framework / Deadlock scripting API.
- Place all files in your Umbrella scripts directory.

## Disclaimer

This script is for educational and testing purposes. Ensure you comply with the terms of service of the game and the framework you are using.
