# Hall of Mogs Addon

Hall of Mogs is a lightweight World of Warcraft Retail addon that exports your character's currently visible transmog into the code format used by Hall of Mogs.

It is built for one job: generate a clean import code you can copy from the game and paste into the website.

Website:

- https://hallofmogs.com

## Features

- Exports the look your character is visibly wearing, not just the raw equipped item IDs
- Handles hidden visuals such as hidden tabards
- Falls back through multiple Blizzard transmog APIs when one path does not expose the visible item cleanly
- Opens a copy-ready window with the export already selected
- Keeps the scope intentionally small: no saved variables, no libraries, no outfit management

## Compatibility

- Game version: World of Warcraft Retail
- Addon version: `0.1.0`
- Export format: `v2`

## Installation

1. Download the latest release zip.
2. Extract the archive.
3. Copy the `HallOfMogs` folder into your WoW addons folder:
   - `World of Warcraft/_retail_/Interface/AddOns/`
4. Make sure the final path looks like this:
   - `World of Warcraft/_retail_/Interface/AddOns/HallOfMogs/HallOfMogs.toc`
5. Start the game or run `/reload`.

## Usage

1. Log into the character you want to export.
2. Make sure the visible transmog is exactly how you want it.
3. Type `/hom` in chat.
4. Copy the generated code from the popup.
5. Paste it into Hall of Mogs.

### Available commands

- `/hom`
- `/hallofmogs`
- `/mogcode`

### Support command

- `/homdebug`

`/homdebug` is kept as a troubleshooting tool. It opens a verbose dump of Blizzard transmog data for each slot and is only meant for debugging when an export does not match what is visible in game.

## Export format

The addon exports this structure:

```text
v2|classId|raceId|bodyType|armorType|characterName|head,shoulder,back,chest,shirt,tabard,wrist,hands,waist,legs,feet,mainHand,offHand
```

Example:

```text
v2|7|91|masculine|mail|Thrall|249648,249650,260312,249645,0,246795,249652,257203,249303,249324,249320,251083,251105
```

## What the addon exports

- Character class ID
- Character race ID
- Body type as `masculine` or `feminine` when WoW provides it
- Armor type
- URL-encoded character name
- Visible item IDs for:
  - head
  - shoulders
  - back
  - chest
  - shirt
  - tabard
  - wrist
  - hands
  - waist
  - legs
  - feet
  - main hand
  - off hand

`0` means the slot is hidden or empty.

## How visible items are resolved

The addon tries to match what the player is actually showing in this order:

1. Player actor / model scene data
2. Transmog slot APIs
3. Active outfit appearance data
4. Equipped item ID as a final fallback when the slot is not transmogrified

This keeps the export closer to the wardrobe preview and avoids common edge cases with hidden visuals and placeholder items.

## Scope

This addon is intentionally narrow in scope:

- It does not manage outfits
- It does not save profiles
- It does not sync data automatically
- It does not depend on external libraries

It exists only to export a clean Hall of Mogs code from inside the game.

## Support

If an export does not match what you see in game:

1. Run `/hom` once more after the character fully loads.
2. If the result is still wrong, run `/homdebug`.
3. Open an issue and include:
   - what was visible in game
   - the exported code
   - the `/homdebug` output
