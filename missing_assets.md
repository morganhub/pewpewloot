# Missing assets

Rapport des assets référencés dans les JSON avec **prompts Ludo.ai** pour générer l'image et, pour ennemis, bosses et missiles uniquement, une **suggestion de prompt pour l'animation**. Tous les prompts sont en anglais, style **hand-painted** ou peint à la main, détaillés et sans crochets ni parenthèses.

**Convention :** path vide → path proposé. **Animation** = uniquement pour ennemis, bosses et missiles. **Vue :** tous les assets et prompts image sont en **strict top-down view**, seen directly from above, orthographic, no perspective, not isometric, not three quarter view. Pour les **ennemis et bosses**, l’orientation doit être **facing downward**, nose pointed toward the bottom of the image. Il manque les **7 thèmes** industrial, lava, mine, necro, titan, alien, magic, chacun avec les **5 types** swarmer, fighter, tank, artillery, elite.

---

## 1. Enemies
 

Paths : `res://assets/enemies/<theme>/<theme>_<type>.tres` avec theme = industrial, lava, mine, necro, titan, alien, magic et type = swarmer, fighter, tank, artillery, elite.

#### Industrial
- **industrial_swarmer** — **Path :** `res://assets/enemies/industrial/industrial_swarmer.tres`  
  **Prompt image Ludo.ai :** Small hostile industrial swarm drone, hand-painted style, circular body, grey metal and rust, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, clean readable silhouette for a top-down shoot em up, sixty-four by sixty-four pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, four to eight frames, idle hover and wobble, tiny propeller flicker, seamless loop.
- **industrial_fighter** — **Path :** `res://assets/enemies/industrial/industrial_fighter.tres`  
  **Prompt image Ludo.ai :** Medium industrial fighter craft, hand-painted 2D sprite, triangular silhouette, grey and orange metal, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, readable wings and central cockpit shape for a top-down shooter, seventy by seventy pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, six to eight frames, short dash and recoil, subtle engine flicker, seamless loop.
- **industrial_tank** — **Path :** `res://assets/enemies/industrial/industrial_tank.tres`  
  **Prompt image Ludo.ai :** Heavy industrial tank ship, hand-painted style, square bulky silhouette, dark metal, rivets and armor plates, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, heavy readable mass for a top-down shooter, ninety by ninety pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, four to six frames, slow heavy idle pulse, slight tread or panel shift, seamless loop.
- **industrial_artillery** — **Path :** `res://assets/enemies/industrial/industrial_artillery.tres`  
  **Prompt image Ludo.ai :** Industrial artillery ship, hand-painted 2D game sprite, hexagonal chassis with a large forward cannon, boiler and vent details, grey-brown metal, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, cannon and nose pointed toward the bottom of the image, seventy by seventy pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, six to eight frames, charge up and fire recoil, steam vent flicker, seamless loop.
- **industrial_elite** — **Path :** `res://assets/enemies/industrial/industrial_elite.tres`  
  **Prompt image Ludo.ai :** Elite industrial warship, hand-painted style, diamond silhouette, ornate metal plating, cables and glowing core accents, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, premium readable boss-like enemy design for a top-down shooter, one hundred by one hundred pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, eight to ten frames, glow pulse and attack wind up, subtle body vibration, seamless loop.

#### Lava
- **lava_swarmer** — **Path :** `res://assets/enemies/lava/lava_swarmer.tres`  
  **Prompt image Ludo.ai :** Small lava swarm drone, hand-painted 2D sprite, circular molten shell, ember vents, red-orange and black palette, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, clean top-down shooter silhouette, sixty-four by sixty-four pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, four to eight frames, hover and ember flicker, seamless loop.
- **lava_fighter** — **Path :** `res://assets/enemies/lava/lava_fighter.tres`  
  **Prompt image Ludo.ai :** Lava fighter ship, hand-painted style, triangular silhouette, molten plating and black rock armor, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, seventy by seventy pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, six to eight frames, dash and recoil, heat shimmer pulse, seamless loop.
- **lava_tank** — **Path :** `res://assets/enemies/lava/lava_tank.tres`  
  **Prompt image Ludo.ai :** Heavy lava tank ship, hand-painted 2D game sprite, square bulky silhouette, magma core and obsidian armor, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, ninety by ninety pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, four to six frames, slow molten pulse and lava drip glow, seamless loop.
- **lava_artillery** — **Path :** `res://assets/enemies/lava/lava_artillery.tres`  
  **Prompt image Ludo.ai :** Lava artillery ship, hand-painted style, hexagonal body with a volcanic forward cannon, red-black molten rock design, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, cannon pointed toward the bottom of the image, seventy by seventy pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, six to eight frames, charge and erupt, brief recoil, seamless loop.
- **lava_elite** — **Path :** `res://assets/enemies/lava/lava_elite.tres`  
  **Prompt image Ludo.ai :** Elite lava warship, hand-painted 2D sprite, diamond silhouette, molten crown details, obsidian armor, flame vents, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, one hundred by one hundred pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, eight to ten frames, flame pulse and attack wind up, seamless loop.

#### Mine
- **mine_swarmer** — **Path :** `res://assets/enemies/mine/mine_swarmer.tres`  
  **Prompt image Ludo.ai :** Small mining swarm drone, hand-painted style, circular silhouette, crystal nodes and stone plating, purple-brown palette, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, sixty-four by sixty-four pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, four to eight frames, hover and crystal shimmer, seamless loop.
- **mine_fighter** — **Path :** `res://assets/enemies/mine/mine_fighter.tres`  
  **Prompt image Ludo.ai :** Mining fighter craft, hand-painted 2D game sprite, triangular silhouette, gem and ore plating, crystal edges, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, seventy by seventy pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, six to eight frames, dash and recoil, seamless loop.
- **mine_tank** — **Path :** `res://assets/enemies/mine/mine_tank.tres`  
  **Prompt image Ludo.ai :** Heavy mining tank ship, hand-painted style, square bulky silhouette, crystal armor and ore plates, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, ninety by ninety pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, four to six frames, slow heavy pulse and crystal glow, seamless loop.
- **mine_artillery** — **Path :** `res://assets/enemies/mine/mine_artillery.tres`  
  **Prompt image Ludo.ai :** Mining artillery ship, hand-painted 2D sprite, hexagonal chassis, large forward crystal cannon or drill barrel, brown-violet palette, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, cannon pointed toward the bottom of the image, seventy by seventy pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, six to eight frames, charge and fire, crystal flash, seamless loop.
- **mine_elite** — **Path :** `res://assets/enemies/mine/mine_elite.tres`  
  **Prompt image Ludo.ai :** Elite mining warship, hand-painted style, diamond silhouette, ornate crystals, ore armor and carved stone patterns, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, one hundred by one hundred pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, eight to ten frames, crystal glow and attack wind up, seamless loop.

#### Necro
- **necro_swarmer** — **Path :** `res://assets/enemies/necro/necro_swarmer.tres`  
  **Prompt image Ludo.ai :** Small necro swarm drone, hand-painted 2D game sprite, circular silhouette, ghostly metal, bone motifs and violet-black energy, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, sixty-four by sixty-four pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, four to eight frames, float and spectral flicker, seamless loop.
- **necro_fighter** — **Path :** `res://assets/enemies/necro/necro_fighter.tres`  
  **Prompt image Ludo.ai :** Necro fighter ship, hand-painted style, triangular silhouette, spectral plating and bone details, violet-black energy core, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, seventy by seventy pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, six to eight frames, dash and recoil, ghost trail flicker, seamless loop.
- **necro_tank** — **Path :** `res://assets/enemies/necro/necro_tank.tres`  
  **Prompt image Ludo.ai :** Heavy necro tank ship, hand-painted 2D sprite, square bulky silhouette, skull motifs and dark armor, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, ninety by ninety pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, four to six frames, slow pulse and heavy idle, seamless loop.
- **necro_artillery** — **Path :** `res://assets/enemies/necro/necro_artillery.tres`  
  **Prompt image Ludo.ai :** Necro artillery ship, hand-painted style, hexagonal body, soul cannon or altar-like forward weapon, violet-black palette, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, cannon pointed toward the bottom of the image, seventy by seventy pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, six to eight frames, charge and soul burst, seamless loop.
- **necro_elite** — **Path :** `res://assets/enemies/necro/necro_elite.tres`  
  **Prompt image Ludo.ai :** Elite necro warship, hand-painted 2D game sprite, diamond silhouette, ornate ghost crown, bone filigree and spectral vents, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, one hundred by one hundred pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, eight to ten frames, spectral pulse and attack wind up, seamless loop.

#### Titan
- **titan_swarmer** — **Path :** `res://assets/enemies/titan/titan_swarmer.tres`  
  **Prompt image Ludo.ai :** Small titan swarm drone, hand-painted style, circular divine machine, golden and amber, rune details, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, sixty-four by sixty-four pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, four to eight frames, hover and gleam pulse, seamless loop.
- **titan_fighter** — **Path :** `res://assets/enemies/titan/titan_fighter.tres`  
  **Prompt image Ludo.ai :** Titan fighter craft, hand-painted 2D sprite, triangular silhouette, gold and white armor, sacred rune accents, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, seventy by seventy pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, six to eight frames, dash and recoil, holy glow pulse, seamless loop.
- **titan_tank** — **Path :** `res://assets/enemies/titan/titan_tank.tres`  
  **Prompt image Ludo.ai :** Heavy titan tank ship, hand-painted style, square bulky silhouette, divine armor, runes and amber core, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, ninety by ninety pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, four to six frames, slow rune pulse and heavy idle, seamless loop.
- **titan_artillery** — **Path :** `res://assets/enemies/titan/titan_artillery.tres`  
  **Prompt image Ludo.ai :** Titan artillery ship, hand-painted 2D game sprite, hexagonal chassis, holy cannon or divine seal weapon mounted forward, gold-amber palette, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, cannon pointed toward the bottom of the image, seventy by seventy pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, six to eight frames, charge and holy fire burst, seamless loop.
- **titan_elite** — **Path :** `res://assets/enemies/titan/titan_elite.tres`  
  **Prompt image Ludo.ai :** Elite titan warship, hand-painted style, diamond silhouette, ornate divine crown, gold armor and sacred core, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, one hundred by one hundred pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, eight to ten frames, holy glow and attack wind up, seamless loop.

#### Alien
- **alien_swarmer** — **Path :** `res://assets/enemies/alien/alien_swarmer.tres`  
  **Prompt image Ludo.ai :** Small alien swarm drone, hand-painted 2D sprite, circular organic silhouette, chitin shell, green and purple palette, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose or head pointed toward the bottom of the image, sixty-four by sixty-four pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, four to eight frames, hover and twitch, seamless loop.
- **alien_fighter** — **Path :** `res://assets/enemies/alien/alien_fighter.tres`  
  **Prompt image Ludo.ai :** Alien fighter craft, hand-painted style, triangular organic silhouette, biomass and carapace plating, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, seventy by seventy pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, six to eight frames, dash and recoil, organic pulse, seamless loop.
- **alien_tank** — **Path :** `res://assets/enemies/alien/alien_tank.tres`  
  **Prompt image Ludo.ai :** Heavy alien tank ship, hand-painted 2D game sprite, square bulky silhouette, armored carapace and living biomass, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, ninety by ninety pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, four to six frames, breathing pulse and heavy idle, seamless loop.
- **alien_artillery** — **Path :** `res://assets/enemies/alien/alien_artillery.tres`  
  **Prompt image Ludo.ai :** Alien artillery ship, hand-painted style, hexagonal organic chassis, bio-cannon or spore pod mounted forward, green-purple palette, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, forward weapon pointed toward the bottom of the image, seventy by seventy pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, six to eight frames, charge and spit attack, seamless loop.
- **alien_elite** — **Path :** `res://assets/enemies/alien/alien_elite.tres`  
  **Prompt image Ludo.ai :** Elite alien warship, hand-painted 2D sprite, diamond silhouette, ornate hive crown, layered carapace and glowing biomass core, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, one hundred by one hundred pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, eight to ten frames, organic pulse and attack wind up, seamless loop.

#### Magic
- **magic_swarmer** — **Path :** `res://assets/enemies/magic/magic_swarmer.tres`  
  **Prompt image Ludo.ai :** Small magic swarm drone, hand-painted style, circular arcane construct, runes and ether, violet-magenta palette, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, sixty-four by sixty-four pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, four to eight frames, hover and sparkle pulse, seamless loop.
- **magic_fighter** — **Path :** `res://assets/enemies/magic/magic_fighter.tres`  
  **Prompt image Ludo.ai :** Magic fighter craft, hand-painted 2D game sprite, triangular silhouette, arcane energy fins and rune details, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, seventy by seventy pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, six to eight frames, dash and recoil, mana flicker, seamless loop.
- **magic_tank** — **Path :** `res://assets/enemies/magic/magic_tank.tres`  
  **Prompt image Ludo.ai :** Heavy magic tank ship, hand-painted style, square bulky silhouette, rune armor, wards and a glowing mana core, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, ninety by ninety pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, four to six frames, rune pulse and heavy idle, seamless loop.
- **magic_artillery** — **Path :** `res://assets/enemies/magic/magic_artillery.tres`  
  **Prompt image Ludo.ai :** Magic artillery ship, hand-painted 2D sprite, hexagonal arcane chassis, forward mana cannon or crystal focus, violet-magenta palette, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, cannon pointed toward the bottom of the image, seventy by seventy pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, six to eight frames, charge and mana burst, seamless loop.
- **magic_elite** — **Path :** `res://assets/enemies/magic/magic_elite.tres`  
  **Prompt image Ludo.ai :** Elite magic warship, hand-painted style, diamond silhouette, ornate arcane crown, rune circles and ether vents, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing downward, nose pointed toward the bottom of the image, one hundred by one hundred pixels, transparent background.  
  **Prompt animation Ludo.ai :** Same hand-painted sprite, strict top-down view, facing downward, eight to ten frames, mana glow and attack wind up, seamless loop.

---

## 2. Bosses 
 
### Bosses Magic

| Boss | Path | Prompt image Ludo.ai | Prompt animation Ludo.ai |
|------|------|----------------------|--------------------------|
| magic_boss_1 | `res://assets/bosses/magic/magic_boss_1.png` and `.tres` | Arcane magic boss, hand-painted style, rune sentinel, circular silhouette with floating rune rings, violet and magenta palette, crystal core and ether wisps, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, front side oriented toward the bottom of the image, four hundred thirty pixels, transparent background. | Hand-painted sprite sheet, strict top-down view, eight to twelve frames, runes lighting up, mana pulse, idle float, seamless loop. |
| magic_boss_2 | `res://assets/bosses/magic/magic_boss_2.png` and `.tres` | Arcane magic boss, hand-painted 2D game sprite, spellblade cruiser, triangular silhouette with arcane fins, bright crystal edges and glowing sigils, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, front side oriented toward the bottom of the image, four hundred forty pixels, transparent background. | Hand-painted sprite sheet, strict top-down view, eight to twelve frames, mana flare, dash recoil, rune shimmer, idle loop. |
| magic_boss_3 | `res://assets/bosses/magic/magic_boss_3.png` and `.tres` | Arcane magic boss, hand-painted style, mana artillery shrine, hexagonal silhouette with giant forward crystal cannon, rune plates, ether vents and floating shards, violet-magenta palette, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, cannon oriented toward the bottom of the image, four hundred fifty pixels, transparent background. | Hand-painted sprite sheet, strict top-down view, eight to twelve frames, mana charge, crystal burst, recoil pulse, seamless loop. |
| magic_boss_4 | `res://assets/bosses/magic/magic_boss_4.png` and `.tres` | Arcane magic boss, hand-painted 2D game sprite, warded titan construct, broad square silhouette, layered rune armor, magic shields, glowing ether seams and a radiant central core, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, front side oriented toward the bottom of the image, four hundred sixty pixels, transparent background. | Hand-painted sprite sheet, strict top-down view, eight to twelve frames, shield pulse, arcane flare, heavy idle vibration, seamless loop. |
| magic_boss_5 | `res://assets/bosses/magic/magic_boss_5.png` and `.tres` | Arcane magic boss, hand-painted style, ether crown sovereign, diamond silhouette with ornate arcane crown, floating sigils, crystal wings and luminous mana core, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, front side oriented toward the bottom of the image, four hundred eighty pixels, transparent background. | Hand-painted sprite sheet, strict top-down view, eight to twelve frames, rune orbit, mana glow, teleport flicker, idle loop. |
| magic_boss_final | `res://assets/bosses/magic/magic_boss_final.png` and `.tres` | Final arcane magic boss, hand-painted 2D game sprite, colossal mana weaver throne, huge circular silhouette with layered rune halos, giant crystal focus, ether machinery and radiant magenta-violet energy, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, front side oriented toward the bottom of the image, five hundred pixels, transparent background. | Hand-painted sprite sheet, strict top-down view, ten to fourteen frames, rune storm, mana wave, partial teleport, ultimate idle glow, seamless loop. |

### Projectiles des boss

Tous les boss référencent le type de projectile **missile_boss_heavy** dans `data/bosses.json`, mais ce missile n’est pas défini dans `data/missiles/missiles.json`. Il manque donc l’asset (et éventuellement l’entrée missile) pour ce projectile.

#### missile_boss_heavy
- **Path proposé :** `res://assets/missiles/boss_heavy.tres`
- **Prompt image Ludo.ai :** Heavy boss projectile, hand-painted style, large menacing round or oval shot, dark red or purple core with outer glow, slight directional tip toward the bottom of the image, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, twenty-four to thirty-two pixels, transparent background.
- **Prompt animation Ludo.ai :** Hand-painted sprite sheet, strict top-down view, four to six frames, pulse glow and slight size breathing, optional short trail, seamless loop.

---

### Son commun
- **Path :** `res://assets/sounds/boss_roar.wav`
- **Prompt image Ludo.ai :** N/A audio. For audio tool: boss roar, deep growl, one to two seconds, game SFX.

---

## 3. Missiles

### missile_default blue_energy
- **Path :** `res://assets/missiles/blue_energy.tres`
- **Prompt image Ludo.ai :** Small blue energy projectile, hand-painted style, glowing orb with a slightly elongated downward trail, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, circular core, sixteen to twenty-four pixels, soft glow, transparent background.
- **Prompt animation Ludo.ai :** Hand-painted sprite sheet, strict top-down view, four to six frames, pulse glow and slight size breathing, seamless loop.

### missile_car energy_burst
- **Path :** `res://assets/missiles/energy_burst.tres`
- **Prompt image Ludo.ai :** Red energy burst projectile, hand-painted 2D sprite, small circular core with bright outward flare, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, twenty pixels, bright red glow, transparent background.
- **Prompt animation Ludo.ai :** Hand-painted sprite sheet, strict top-down view, four to six frames, burst expands and contracts, seamless loop.

### missile_homing energy_ball
- **Path :** `res://assets/missiles/energy_ball.png`
- **Prompt image Ludo.ai :** Homing energy ball, hand-painted style, red-pink color, circular core with a subtle directional tip toward the bottom of the image, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, twenty pixels, transparent background.
- **Prompt animation Ludo.ai :** Hand-painted sprite sheet, strict top-down view, four to six frames, rotation or swirl, seamless loop.

### missile_wave sacred_missile
- **Path :** `res://assets/missiles/sacred_missile.tres`
- **Prompt image Ludo.ai :** Sacred light missile, hand-painted 2D game sprite, cyan-blue holy glow, small circular projectile with a clean directional streak toward the bottom of the image, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixteen pixels, transparent background.
- **Prompt animation Ludo.ai :** Hand-painted sprite sheet, strict top-down view, four to six frames, gentle wave pulse, seamless loop.

### missile_ice
- **Path :** `res://assets/missiles/missile_ice.tres`
- **Prompt image Ludo.ai :** Ice missile, hand-painted style, pale blue-white, crystalline projectile with a pointed lower tip, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixteen pixels, frost aura, transparent background.
- **Prompt animation Ludo.ai :** Hand-painted sprite sheet, strict top-down view, four to six frames, frost shimmer and crystal spin, seamless loop.

### missile_poison
- **Path :** `res://assets/missiles/missile_poison.tres`
- **Prompt image Ludo.ai :** Poison missile, hand-painted 2D sprite, toxic green glow, small rounded projectile with swirling venom aura, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixteen pixels, transparent background.
- **Prompt animation Ludo.ai :** Hand-painted sprite sheet, strict top-down view, four to six frames, drip or bubble and poison swirl, seamless loop.

### missile_void
- **Path :** `res://assets/missiles/missile_void.tres`
- **Prompt image Ludo.ai :** Void missile, hand-painted style, purple-dark color, diamond-like core with a subtle lower point, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, eighteen pixels, void distortion effect, transparent background.
- **Prompt animation Ludo.ai :** Hand-painted sprite sheet, strict top-down view, four to six frames, void pulse and dark swirl, seamless loop.

### energy_missile super_powers
- **Path :** `res://assets/missiles/energy_missile.tres`
- **Prompt image Ludo.ai :** Generic energy missile for super powers, hand-painted 2D game sprite, magenta-cyan palette, versatile projectile with a bright core and downward travel streak, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, thirty to forty pixels, transparent background.
- **Prompt animation Ludo.ai :** Hand-painted sprite sheet, strict top-down view, six to eight frames, energy spiral or burst, seamless loop.

### default_explosion
- **Path proposé :** `res://assets/vfx/explosion_default.png` or .tres
- **Prompt image Ludo.ai :** Small explosion VFX, hand-painted style, orange-yellow burst, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, forty pixels diameter, game VFX sprite, transparent background.
- **Prompt animation Ludo.ai :** Hand-painted sprite sheet, strict top-down view, six to ten frames, expand then fade, one-shot explosion animation.

---
 

---

## 5. Loot and items

### 5a. loot_table.json – icons by slot and rarity

Chaque slot a une entrée `icon` avec une clé par rareté. Path proposé si vide : `res://assets/items/<slot_id>/<slot_id>_<rarity>.png`. Primary garde les paths existants rocket_4 à rocket_8. Style hand-painted pour tous les prompts.

#### reactor – Réacteur
| Rarity     | Path | Prompt image Ludo.ai |
|------------|------|----------------------|
| common     | `res://assets/items/reactor/reactor_common.png` | Reactor or energy core icon for common tier, hand-painted style, gray and dull metal, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| uncommon   | `res://assets/items/reactor/reactor_uncommon.png` | Reactor or energy core icon for uncommon tier, hand-painted 2D, green tint, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| rare       | `res://assets/items/reactor/reactor_rare.png` | Reactor or energy core icon for rare tier, hand-painted style, blue glow, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| epic       | `res://assets/items/reactor/reactor_epic.png` | Reactor or energy core icon for epic tier, hand-painted 2D, purple and bright, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| legendary  | `res://assets/items/reactor/reactor_legendary.png` | Reactor or energy core icon for legendary tier, hand-painted style, orange-gold glow, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |

#### engine – Moteur
| Rarity     | Path | Prompt image Ludo.ai |
|------------|------|----------------------|
| common     | `res://assets/items/engine/engine_common.png` | Engine or thruster icon for common tier, hand-painted style, gray metal, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| uncommon   | `res://assets/items/engine/engine_uncommon.png` | Engine or thruster icon for uncommon tier, hand-painted 2D, green tint, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| rare       | `res://assets/items/engine/engine_rare.png` | Engine or thruster icon for rare tier, hand-painted style, blue accent, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| epic       | `res://assets/items/special/crystal_power.png` | Same as crystal_power, crystal or power gem, hand-painted style, epic look, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background. |
| legendary  | `res://assets/items/engine/engine_legendary.png` | Engine or thruster icon for legendary tier, hand-painted 2D, orange-gold, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |

#### armor – Blindage
| Rarity     | Path | Prompt image Ludo.ai |
|------------|------|----------------------|
| common     | `res://assets/items/armor/armor_common.png` | Armor or hull plating icon for common tier, hand-painted style, gray metal, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| uncommon   | `res://assets/items/armor/armor_uncommon.png` | Armor or hull plating icon for uncommon tier, hand-painted 2D, green tint, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| rare       | `res://assets/items/armor/armor_rare.png` | Armor or hull plating icon for rare tier, hand-painted style, blue accent, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| epic       | `res://assets/items/armor/armor_epic.png` | Armor or hull plating icon for epic tier, hand-painted 2D, purple and sturdy, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| legendary  | `res://assets/items/armor/armor_legendary.png` | Armor or hull plating icon for legendary tier, hand-painted style, orange-gold reinforced, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |

#### shield – Bouclier
| Rarity     | Path | Prompt image Ludo.ai |
|------------|------|----------------------|
| common     | `res://assets/items/shield/shield_common.png` | Shield or barrier icon for common tier, hand-painted style, gray simple shape, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| uncommon   | `res://assets/items/shield/shield_uncommon.png` | Shield or barrier icon for uncommon tier, hand-painted 2D, green tint, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| rare       | `res://assets/items/special/crystal_power.png` | Same as crystal_power, crystal or power gem, hand-painted style, rare look, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background. |
| epic       | `res://assets/items/shield/shield_epic.png` | Shield or barrier icon for epic tier, hand-painted style, purple glow, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| legendary  | `res://assets/items/shield/shield_legendary.png` | Shield or barrier icon for legendary tier, hand-painted 2D, orange-gold aura, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |

#### primary – Arme Principale
| Rarity     | Path | Prompt image Ludo.ai |
|------------|------|----------------------|
| common     | `res://assets/items/primary/rocket_4.png` | Primary weapon rocket launcher icon for common tier, hand-painted style, gray and simple, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| uncommon   | `res://assets/items/primary/rocket_5.png` | Primary weapon rocket launcher icon for uncommon tier, hand-painted 2D, green tint, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| rare       | `res://assets/items/primary/rocket_8.png` | Primary weapon rocket launcher icon for rare tier, hand-painted style, blue accent, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| epic       | `res://assets/items/primary/rocket_8_vertical.png` | Primary weapon rocket launcher icon for epic tier, hand-painted 2D, vertical double barrel, purple, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| legendary  | `res://assets/items/primary/rocket_6.png` | Primary weapon rocket launcher icon for legendary tier, hand-painted style, orange-gold premium look, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |

#### missiles – Missiles
| Rarity     | Path | Prompt image Ludo.ai |
|------------|------|----------------------|
| common     | `res://assets/items/missiles/missiles_common.png` | Missile or ordnance icon for common tier, hand-painted style, gray bullet or rocket, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| uncommon   | `res://assets/items/missiles/missiles_uncommon.png` | Missile or ordnance icon for uncommon tier, hand-painted 2D, green tint, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| rare       | `res://assets/items/missiles/missiles_rare.png` | Missile or ordnance icon for rare tier, hand-painted style, blue accent, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| epic       | `res://assets/items/missiles/missiles_epic.png` | Missile or ordnance icon for epic tier, hand-painted 2D, purple and powerful, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| legendary  | `res://assets/items/missiles/missiles_legendary.png` | Missile or ordnance icon for legendary tier, hand-painted style, orange-gold salvo, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |

#### targeting – Ciblage
| Rarity     | Path | Prompt image Ludo.ai |
|------------|------|----------------------|
| common     | `res://assets/items/targeting/targeting_common.png` | Targeting or crosshair icon for common tier, hand-painted style, gray reticle, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| uncommon   | `res://assets/items/targeting/targeting_uncommon.png` | Targeting or crosshair icon for uncommon tier, hand-painted 2D, green tint, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| rare       | `res://assets/items/targeting/targeting_rare.png` | Targeting or crosshair icon for rare tier, hand-painted style, blue accent, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| epic       | `res://assets/items/targeting/targeting_epic.png` | Targeting or crosshair icon for epic tier, hand-painted 2D, purple scope, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| legendary  | `res://assets/items/targeting/targeting_legendary.png` | Targeting or crosshair icon for legendary tier, hand-painted style, orange-gold precision, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |

#### utility – Utilitaire
| Rarity     | Path | Prompt image Ludo.ai |
|------------|------|----------------------|
| common     | `res://assets/items/utility/utility_common.png` | Utility or tool icon for common tier, hand-painted style, gray wrench or magnet, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| uncommon   | `res://assets/items/utility/utility_uncommon.png` | Utility or tool icon for uncommon tier, hand-painted 2D, green tint, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| rare       | `res://assets/items/utility/utility_rare.png` | Utility or tool icon for rare tier, hand-painted style, blue accent, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| epic       | `res://assets/items/utility/utility_epic.png` | Utility or tool icon for epic tier, hand-painted 2D, purple gadget, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |
| legendary  | `res://assets/items/utility/utility_legendary.png` | Utility or tool icon for legendary tier, hand-painted style, orange-gold premium tool, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, clean readable game item icon, sixty-four by sixty-four pixels, transparent background. |

**Prompt animation Ludo.ai :** N/A for all loot_table slot icons.

---

### 5b. Slot icons crystal_power and rockets
- **crystal_power** — **Prompt image Ludo.ai :** Crystal or power gem icon for game UI, hand-painted style, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, epic or rare look, transparent background, clean readable game icon.
- **rocket_4 to 8** — **Prompt image Ludo.ai :** Rocket launcher equipment icon for common, uncommon, rare, epic or legendary tier, hand-painted 2D game icon, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, clean UI style, transparent background.
- **Prompt animation Ludo.ai :** N/A.

### Uniques item sprites
- **unique_root_amulet** — **Prompt image Ludo.ai :** Amulet with roots and leaves, hand-painted style, forest relic, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background.
- **unique_bark_shield** — **Prompt image Ludo.ai :** Shield made of bark, hand-painted 2D game item icon, forest theme, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background.
- **unique_thorn_blade** — **Prompt image Ludo.ai :** Thorn blade or vine sword, hand-painted style, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background.
- **unique_vine_whip** — **Prompt image Ludo.ai :** Vine whip weapon, hand-painted 2D sprite, green color, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background.
- **unique_spore_ring** — **Prompt image Ludo.ai :** Ring with spores or fungus, hand-painted style, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background.
- **unique_mycelium_core** — **Prompt image Ludo.ai :** Organic reactor core with mycelium, hand-painted 2D item icon, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background.
- **unique_heartwood_plate** — **Prompt image Ludo.ai :** Breastplate made of heartwood, hand-painted style, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background.
- **unique_ancient_sap** — **Prompt image Ludo.ai :** Vial of glowing sap, hand-painted 2D item icon, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background.
- **unique_fungal_crown** — **Prompt image Ludo.ai :** Crown with mushrooms, hand-painted style, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background.
- **unique_decay_orb** — **Prompt image Ludo.ai :** Corrosive decay orb, hand-painted 2D sprite, purple-green, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background.
- **unique_guardian_heart** — **Prompt image Ludo.ai :** Guardian heart core, hand-painted style, forest green, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background.
- **unique_primordial_seed** — **Prompt image Ludo.ai :** Primordial glowing seed, hand-painted 2D item icon, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background.
- **unique_sylvan_crown** — **Prompt image Ludo.ai :** Sylvan lord crown with leaves and branches, hand-painted style, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background.
- **unique_asteroid_core** — **Prompt image Ludo.ai :** Asteroid core, hand-painted 2D item icon, rocky with glow, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background.
- **unique_guardian_shield** — **Prompt image Ludo.ai :** Guardian fragment shield, hand-painted style, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background.
- **unique_spectral_reactor** — **Prompt image Ludo.ai :** Spectral reactor, hand-painted 2D sprite, ghostly style, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background.
- **unique_ghost_engine** — **Prompt image Ludo.ai :** Phantom engine, hand-painted style, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background.
- **unique_void_primary** — **Prompt image Ludo.ai :** Void cannon weapon icon, hand-painted 2D game item, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background.
- **unique_architect_reactor** — **Prompt image Ludo.ai :** Architect core, hand-painted style, geometric design, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, transparent background.

For other uniques by theme use the same format: hand-painted 2D game item icon, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, sixty-four by sixty-four pixels, theme and name, transparent background.
- **Prompt animation Ludo.ai :** N/A.

---

## 6. Game and UI

### Main menu
- **main_menu_bg** — **Prompt image Ludo.ai :** Main menu background, hand-painted style, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, space or neon atmosphere, seven hundred twenty p or ten eighty p, no UI elements, game menu backdrop.
- **logo pewpewloot_final** — **Prompt image Ludo.ai :** Game logo with text Pewpewloot, hand-painted or painted by hand style, readable stylized title, clean game logo, four hundred by three hundred pixels approximately, transparent or dark background.

### Reward screen
- **reward_bg** — **Prompt image Ludo.ai :** Reward or loot screen background, hand-painted style, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, dark panel environment, 2D game UI, seven hundred twenty p.
- **btn_equip** — **Prompt image Ludo.ai :** Equip button for game UI, hand-painted 2D UI element, clean readable shape, green or gold color, one hundred forty by fifty pixels.
- **btn_destroy** — **Prompt image Ludo.ai :** Destroy or discard button for game UI, hand-painted style UI element, clean readable shape, red color, one hundred forty by fifty pixels.

 

### Ship menu and WorldSelect
- **ship_background** — **Prompt image Ludo.ai :** Ship selection background, hand-painted style, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, hangar or menu environment, 2D game background.
- **equipment.jpg** — **Prompt image Ludo.ai :** Equipment or inventory screen background, hand-painted 2D game menu, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view.
- **world_select_menu** — **Prompt image Ludo.ai :** World select screen background, hand-painted style, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, thematic 2D game menu.

### UI icons
  
- **button_gold green red blue** — **Prompt image Ludo.ai :** Buttons in gold, green, red and blue, hand-painted style UI elements, one hundred forty by fifty pixels, clean readable design.
- **Stat icons** — **Prompt image Ludo.ai :** Stat icons set for power, trophy, heart, speed, missile, crit, dodge, special, shield, all hp, hand-painted 2D game UI, twenty-four to thirty pixels, consistent readable style.
- **level.png** — **Prompt image Ludo.ai :** Level icon, hand-painted style, 2D game UI, clean readable design.
- **cart.png cart.tres** — **Prompt image Ludo.ai :** Shop cart icon, hand-painted 2D game UI, forty by forty pixels, clean readable design.
- **locked.png** — **Prompt image Ludo.ai :** Locked icon, hand-painted style, padlock symbol, 2D game UI, clean readable design.
- **popup_background** — **Prompt image Ludo.ai :** Popup panel background, hand-painted 2D game UI, semi-transparent dark panel, clean readable layout.
- **ship_select_background** — **Prompt image Ludo.ai :** Ship slot background, hand-painted style, 2D UI, plus selected variant with highlight, clean readable design.
- **super_power_button unique_power_button** — **Prompt image Ludo.ai :** Super power and unique power buttons, hand-painted 2D game UI, sixty-four by sixty-four pixels, clean readable design.
- **frame_empty** — **Prompt image Ludo.ai :** Empty slot frame, hand-painted style, 2D game UI, clean readable design.
- **SkillsMenu reactor engine all** — **Prompt image Ludo.ai :** Reactor, engine and all icons for skills menu, hand-painted 2D game UI, clean readable design.

### Upgrade and craft
- **popup_upgrade.tres** — **Prompt image Ludo.ai :** 2D sprite sheet for upgrade success effect, hand-painted style, sparkle or level up burst, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, six to ten frames, loop or one-shot animation.

No animation prompts for UI except optional crystal.tres.

---

## 7. Override protocols

- **override_popup_bg** — **Prompt image Ludo.ai :** Override popup background, hand-painted style, 2D game UI panel, clean readable design.
- **btn_override_active inactive** — **Prompt image Ludo.ai :** Active and inactive override buttons, hand-painted 2D game UI, clean readable design.
- **checkbox_on off** — **Prompt image Ludo.ai :** Checkbox checked and unchecked states, hand-painted style, 2D game UI, thirty-two by thirty-two pixels, clean readable design.
- **corruption.tres** — **Prompt image Ludo.ai :** Corruption or dark spread effect as sprite sheet, hand-painted 2D top-down VFX, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, four to eight frames, loop.
- **mine_explosion.tres** — **Prompt image Ludo.ai :** Small mine explosion as sprite sheet, hand-painted style, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, 2D game VFX, six to ten frames, one-shot.

---

## 8. Enemy modifiers

- **wall.png** — **Prompt image Ludo.ai :** Barrier wall ability icon, hand-painted style, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, 2D game asset, thirty-two by thirty-two or sixty-four by sixty-four pixels, clean readable design.
- **mine.tres** — **Prompt image Ludo.ai :** Mine modifier sprite and animation, hand-painted 2D top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, mine drop device, four to six frames, idle then trigger.
- **arcane_orb.tres** — **Prompt image Ludo.ai :** Magic orb, hand-painted style, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, 2D game sprite, four to six frames idle glow.
- **arcane_beam.tres** — **Prompt image Ludo.ai :** Magic beam or laser, hand-painted 2D top-down VFX, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, four to eight frames.
- **graviton.tres** — **Prompt image Ludo.ai :** Gravity well or vortex pull effect, hand-painted style, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, 2D game sprite, six to eight frames loop.
- **elite_frame_blue red purple** — **Prompt image Ludo.ai :** Elite health bar frames in blue, red and purple, hand-painted 2D UI frame, clean readable design.
- **aura_blue_grid aura_red aura_blue** — **Prompt image Ludo.ai :** Aura background effects, hand-painted 2D top-down VFX, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, subtle grid or glow in blue and red.

SFX such as heavy_missile mine_explosion laser_hum shield_hit are audio only, no image prompt.

---

## 9. Worlds backgrounds and themes

### Forest
- **tile_forest_world** — **Prompt image Ludo.ai :** Forest world theme texture, hand-painted style, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, tiling 2D background, leaves, roots and forest floor, seamless tile.
- **forest_music** — N/A audio.
- **level_0 to N** — **Prompt image Ludo.ai :** Forest level background, hand-painted 2D top-down parallax style, far layer, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, seven hundred twenty p.

### Mine Atlantis and other worlds
- **tile_mine_world** — **Prompt image Ludo.ai :** Mine theme tiling texture, hand-painted style, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, rocks and crystals, 2D seamless tile.
- **world_mine_0** — **Prompt image Ludo.ai :** Mine level background for level card and far layer, hand-painted 2D top-down game background, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, seven hundred twenty p.
- Same logic for atlantis ocean, industrial factory, lava volcanic, necro cemetery, titan golden, alien organic, magic arcane: theme name plus level background, hand-painted 2D game background, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, seven hundred twenty p, no UI.

---

## 10. Ships

- **countryman.tres** — **Prompt image Ludo.ai :** Ship named Countryman, hand-painted style, compact spaceship, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing upward or neutral for player readability, sixty-four by sixty-four pixels, sprite sheet four to six frames idle thrust.
- **swordwing.tres** — **Prompt image Ludo.ai :** Ship named Swordwing, hand-painted 2D game sprite, blade-like shape, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing upward or neutral for player readability, sixty-four by sixty-four pixels, four to six frames.
- **beetMech.tres** — **Prompt image Ludo.ai :** Ship named BeetMech, hand-painted style, beetle-mech hybrid spaceship, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing upward or neutral for player readability, sixty-four by sixty-four pixels, four to six frames.
- **ecraseur.png** — **Prompt image Ludo.ai :** Ship named Ecraseur, hand-painted 2D sprite, heavy cruiser silhouette, strict top-down view, seen directly from above, orthographic, no perspective, not isometric, not three quarter view, facing upward or neutral for player readability, sixty-four by sixty-four pixels, static or single frame.

No animation prompt for ships; only enemies, bosses and missiles use animation prompts.

---

## Summary

- **Image:** Each asset has a Ludo.ai prompt in English, **hand-painted or painted by hand style**, with a much stronger constraint for **strict top-down view**, **seen directly from above**, **orthographic**, **no perspective**, **not isometric**, **not three quarter view**.
- **Enemies:** Forest and atlantis already present; **7 themes missing** — industrial, lava, mine, necro, titan, alien, magic — each with 5 vehicle types: swarmer, fighter, tank, artillery, elite. Paths: `res://assets/enemies/<theme>/<theme>_<type>.tres`.
- **Bosses and enemies orientation:** prompts now explicitly force **facing downward** and **nose pointed toward the bottom of the image** when applicable, to reduce Ludo.ai outputs in 3/4 view.
- **Animation:** Only enemies, bosses, missiles: hand-painted sprite sheet four to fourteen frames, loop or one-shot, same strict top-down view style.
- **UI, items, scenery, SFX:** No animation prompt except special cases like crystal.tres, popup_upgrade, corruption, mine_explosion.