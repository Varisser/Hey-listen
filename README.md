# Hey Listen!

This repo holds two addons for **World of Warcraft: Forever**:

- **[Hey Listen!](#hey-listen-1)**: fishing pole, totem and quest reminders.
- **[Death Roll Ledger](#death-roll-ledger)**: tracks gold won and lost in death rolls.

---

## Hey Listen!

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

---

## Death Roll Ledger

Keeps a running total of gold won and lost in death rolls, plus a separate win/loss balance with each player.

### How it works

- **On-screen button.** A small button stays on screen and shows `Death Roll: ON/OFF` and your total winnings. Left-click turns tracking on or off. Right-click opens the ledger. Shift-drag moves it.
- **While tracking is ON, every change to your gold counts as winnings or losses:**
  - **Trades:** gold you receive or give in a trade goes to that player's balance.
  - **Mail:** gold you take from a player's mail, or send to a player, goes to their balance. Postage is not counted.
  - **Anything else** (loot, vendors, repairs, auction house mail) goes to an **Other (no player)** row. It counts toward the total unless you turn that off with `/dr other`.
- **Death rolls are detected automatically** from `/roll` messages (`1-1000`, then `1-<previous result>`, and so on until someone rolls a 1). When you're one of the players, the result is added to the history with that player and to your W-L record against them.
- **Per-player history.** The ledger lists everyone you've won from or lost to, with your W-L record and net gold. Click a player to see each entry with its date, source, amount and running balance.

For example, if you win 3g from Xan, win 5g from Yul and lose 1g to Zed, the total shows **+7g**. Xan's history shows +3g, Yul's +5g and Zed's -1g.

### Fixing entries

In a player's history, left-click an entry to move it to another player. This is handy for an "Other" entry that was really a death roll payout. Right-click an entry to delete it. `/dr add <player> <amount>` adds an entry by hand.

### Install

Copy the `DeathRollLedger` folder into `World of Warcraft/_forever_/Interface/AddOns/`. History is saved per character.

### Commands

| Command | What it does |
|---|---|
| `/dr` | Open or close the ledger (`/drl` and `/deathroll` also work) |
| `/dr on`, `/dr off`, `/dr toggle` | Same as clicking the button |
| `/dr add <player> <amount>` | Manual entry, e.g. `/dr add Bob 5g` or `/dr add Bob -2g50s` (a plain number means gold) |
| `/dr other` | Count or ignore gold with no player in the total |
| `/dr resetpos` | Move the button and window back to their default spots |
| `/dr reset` | Wipe all history (asks first) |

### Notes

- Gold is only matched to a player when it actually moves through a trade or mail. Agreeing on a roll doesn't move gold, so nothing is booked until they pay you or you pay them.
- Inside instances, Forever can hide chat text from addons (Midnight's "secret values"). Rolls made there won't be detected. Trades and mail are unaffected.
- Roll detection reads the `RANDOM_ROLL_RESULT` text from the client, so it should work in any language.
