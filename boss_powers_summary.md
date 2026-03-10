# Boss Powers Summary

## Scope
- Scope: graphical assets currently used by the 54 bosses available in the debug arena.
- Structure: bosses use one base `missile_id` for their regular shots, plus reusable `special_power_id` entries from `data/missiles/boss_powers.json`.
- Format note: `.tres` here means an animated `SpriteFrames` resource. `.png` means a static texture.
- Beam/cone note: beam and cone textures are currently stretched over the zone. They are not tile-repeated by default.
- Void-zone note: `void_zone` attacks are still using placeholder polygon visuals only. There is no dedicated asset hook used there yet.

## Boss Missiles

### `missile_boss_heavy`
- Used by: all 54 bosses as their base `missile_id`.
- Type: `missile`
- Current asset: `res://assets/missiles/red_energy_burst.tres`
- Current format: `.tres`
- Expected asset type: projectile / missile visual
- Art expectation: non-tileable moving projectile. Best fit is an animated `.tres` SpriteFrames resource. A static `.png` is technically possible if switched to `visual.asset`, but the current setup is animated `.tres`.

## Boss Powers

### `power_root_snare`
- Type: `missile` + `void_zone`
- Current missile asset: `res://assets/missiles/green_energy_burst.tres`
- Current missile format: `.tres`
- Current void-zone asset: none, placeholder colored zone only
- Expected missile asset type: projectile / missile, non-tileable, animated `.tres`
- Expected void-zone asset type: other / ground-zone effect; currently no active asset slot consumed in code

### `power_leaf_storm`
- Type: `missile`
- Current asset: `res://assets/missiles/green_energy_burst.tres`
- Current format: `.tres`
- Expected asset type: projectile / missile, non-tileable, animated `.tres`

### `power_thorn_wall`
- Type: `missile`
- Current asset: `res://assets/missiles/green_energy_burst.tres`
- Current format: `.tres`
- Expected asset type: projectile / missile, non-tileable, animated `.tres`

### `power_vine_whip`
- Type: `missile`
- Current asset: `res://assets/missiles/orange_energy_burst.tres`
- Current format: `.tres`
- Expected asset type: projectile / missile, non-tileable, animated `.tres`

### `power_spore_cloud`
- Type: `missile`
- Current asset: `res://assets/missiles/green_energy_burst.tres`
- Current format: `.tres`
- Expected asset type: projectile / missile, non-tileable, animated `.tres`

### `power_bramble_burst`
- Type: `missile`
- Current asset: `res://assets/missiles/blue_energy_burst.tres`
- Current format: `.tres`
- Expected asset type: projectile / missile, non-tileable, animated `.tres`

### `power_tree_slam`
- Type: `missile` + `beam`
- Current missile asset: `res://assets/missiles/orange_energy_burst.tres`
- Current beam asset: `res://assets/missiles/orange_energy_burst.tres`
- Current formats: `.tres` / `.tres`
- Expected missile asset type: projectile / missile, non-tileable, animated `.tres`
- Expected beam asset type: beam line texture stretched over the active zone, static `.png` or animated `.tres`

### `power_seed_barrage`
- Type: `missile`
- Current asset: `res://assets/missiles/gradient_energy_burst.tres`
- Current format: `.tres`
- Expected asset type: projectile / missile, non-tileable, animated `.tres`

### `power_forest_fury`
- Type: `missile`
- Current asset: `res://assets/missiles/green_energy_burst.tres`
- Current format: `.tres`
- Expected asset type: projectile / missile, non-tileable, animated `.tres`

### `power_mushroom_gas`
- Type: `missile`
- Current asset: `res://assets/missiles/green_energy_burst.tres`
- Current format: `.tres`
- Expected asset type: projectile / missile, non-tileable, animated `.tres`

### `power_moss_shield`
- Type: `missile`
- Current asset: `res://assets/missiles/green_energy_burst.tres`
- Current format: `.tres`
- Expected asset type: projectile / missile, non-tileable, animated `.tres`

### `power_ancient_roar`
- Type: `missile`
- Current asset: `res://assets/missiles/gradient_energy_burst.tres`
- Current format: `.tres`
- Expected asset type: projectile / missile, non-tileable, animated `.tres`

### `power_canopy_crush`
- Type: `missile`
- Current asset: `res://assets/missiles/green_energy_burst.tres`
- Current format: `.tres`
- Expected asset type: projectile / missile, non-tileable, animated `.tres`

### `power_nature_wrath`
- Type: `missile` + `cone`
- Current missile asset: `res://assets/missiles/blue_energy_burst.tres`
- Current cone asset: `res://assets/missiles/gradient_energy_burst.tres`
- Current formats: `.tres` / `.tres`
- Expected missile asset type: projectile / missile, non-tileable, animated `.tres`
- Expected cone asset type: cone-zone texture stretched over the cone area, static `.png` or animated `.tres`

### `power_guardian_rage`
- Type: `missile` + `void_zone` + `beam`
- Current missile asset: `res://assets/missiles/gradient_energy_burst.tres`
- Current beam asset: `res://assets/missiles/gradient_energy_burst.tres`
- Current void-zone asset: none, placeholder colored zone only
- Current formats: `.tres` / `.tres` / placeholder
- Expected missile asset type: projectile / missile, non-tileable, animated `.tres`
- Expected beam asset type: beam line texture stretched over the active zone, static `.png` or animated `.tres`
- Expected void-zone asset type: other / ground-zone effect; currently no active asset slot consumed in code

## Quick Production Rules
- `missile`: create a projectile asset, not a tile. Best target is an animated `.tres`.
- `beam`: create a long beam texture meant to be stretched over a rectangular zone. `.png` or animated `.tres`.
- `cone`: create a cone/spray texture meant to be stretched over a cone polygon. `.png` or animated `.tres`.
- `void_zone`: create only if we decide to extend the code path, because the current runtime still uses placeholder polygon visuals.
