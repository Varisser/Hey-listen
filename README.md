# Hey Listen!

An addon for **World of Warcraft: Forever** (interface `16001`) that warns you when you're forgetting something important.

## Features

- **Fishing pole reminder.** A small "Fishing Pole equipped" line shows near the top of the screen while a fishing pole is in your main hand.
- **"You're attacking with a fishing pole!" warning.** If you start auto-attacking or enter combat with the pole still equipped, a large pulsing red warning appears in the middle of the screen with a raid-warning sound. The sound repeats every few seconds while you keep swinging. The warning names the weapons you had on before and goes away as soon as you swap back.
- **`/hl swap`** re-equips the weapons you were using before the fishing pole. You can put it in a macro.
- **Totem tracker (Shaman only).** Shows an icon for each active totem with a count of how many group members have its buff, such as `3/5`. The count is green when everyone is covered, yellow when only some are, and red when nobody is. Each icon also shows the totem's remaining time. Totems that don't give a buff (Searing, Magma, Tremor, Earthbind, Stoneclaw, and so on) show only the timer.
- **Quest turn-in counter.** A small "N quests ready to turn in" line that appears only when at least one quest is complete.

## Install

Copy the `HeyListen` folder into `World of Warcraft/_forever_/Interface/AddOns/`.

The TOC declares `## Interface: 16001` (client 1.60.1). If a patch changes it and the addon shows as "out of date", type `/dump select(4, GetBuildInfo())` in game and put that number in `HeyListen/HeyListen.toc`, or tick **Load out of date AddOns**.

## Commands

| Command | What it does |
|---|---|
| `/hl unlock` / `/hl lock` | Show and drag the on-screen elements, then lock them in place |
| `/hl reset` | Reset all positions |
| `/hl fishing`, `/hl totems`, `/hl quests` | Turn each feature on or off |
| `/hl sound` | Turn the warning sound on or off |
| `/hl swap` | Re-equip your previous weapons |
| `/hl test` | Preview the fishing pole warning |

## How it works around Forever's combat restrictions

Forever uses the modern addon API, including Midnight's combat restrictions. While you're in combat, the game hides some data from addons ("secret values"). This includes `GetTotemInfo`, and possibly party members' buffs.

- **Out of combat:** totem counts and timers are exact and update twice a second.
- **Totems placed before the fight:** the timer keeps counting and the last count is shown greyed out with a `?`, such as `3/5?`.
- **Totems placed during the fight:** the icon and a cooldown sweep still appear, because the game lets hidden values go straight to the display, but the count shows `?` until combat ends.
- **Combat ends:** everything refreshes immediately.

The fishing pole warning and the quest counter use only your own equipment, combat state and quest log, which aren't hidden.

## Notes

- Totem buffs are matched by name, so the totem tracker currently works on English clients only.
- Totems affect only your party, or your subgroup in a raid, so counts include you plus `party1` through `party4`. Dead or offline members are not counted.
- If you destroy a totem early mid-combat, its icon can stay up until combat ends or its timer runs out.
- Fishing poles are assumed to go in the main-hand slot as in Classic, rather than a profession tool slot.
