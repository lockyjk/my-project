# Storm Chaser Simulator

A Roblox simulator in which you catch living weather spirits with an upgradable Storm Jar. You sell them for Charge, hatch and fuse Stormlings, build your own sky island and Ascend. Server-wide storms roll in every 10 minutes.

The design, economy formulas, zone table, odds and monetization are in [DESIGN.md](DESIGN.md). Every balance value is in [`src/shared/Config.luau`](src/shared/Config.luau).

## Run it

**Quick look:** run `rojo build -o StormChaserSimulator.rbxlx`, open the file in Roblox Studio and press Play. The server builds the whole placeholder world when it starts.

**Live development:**
1. Install the toolchain with `rokit install` (see `rokit.toml`).
2. Run `rojo serve` and connect the Rojo plugin in Studio.
3. For saving to work in Studio, turn on *Game Settings → Security → Enable Studio Access to API Services*. Without it, data is kept in memory for the session.

**Checks:** `./scripts/check.sh` runs strict `luau-lsp` type-checking with Roblox types, then `selene` when it can download the Roblox API dump, then the Lune test suite.
- `lune run scripts/run-tests [filter]` runs only the tests.
- `lune run scripts/simulate 7 -v` prints the pacing timeline for the current Config.
- The same `tests/*.spec.luau` files run in Studio with TestEZ: `require(TestEZ).TestBootstrap:run({ game.ServerStorage.Tests })`.

## Before publishing

1. **IDs in `Config.luau`:**
   - Create the Game Passes and Developer Products and put their ids in `Config.GamePasses` / `Config.Products`. While an id is 0, that item shows "Coming soon" and can't be bought.
   - Set `Config.Group.GroupId`.
   - Add sound asset ids to `Config.Sounds`. Empty ids are skipped.
2. **Prices:** keep product prices in line with `priceHint`. The UI always shows the live price. The Starter Pack "worth" line is worked out from the live prices and is hidden if any of them is unavailable.
3. **Experience settings:** turn on API services. Complete the experience questionnaire, which covers paid random items.
4. **Art:** replace the placeholders (see below).

## Project layout

```
src/shared   → ReplicatedStorage.Shared
  Config        every balance value (zones, spirits, pets, eggs, upgrades, storms, events, quests,
                pass, decorations, potions, passes/products, security, world layout)
  Theme         art direction: colours, fonts, UI sizes, materials, scale language
  EconomyMath   pure economy formulas            Defs        validated lookups by id
  Net           remotes + payload schemas + rate limits
  Migrations    save versioning                  DataTemplate  default save
  QuestGen / PassRewards / Schedule / WorldLayout / Format / Signal / Types
src/server   → ServerScriptService.Server
  init.server   bootstrap (build world → init → start)
  Services/     Data, Stats, Currency, Upgrade, Zone, Island, Pet, Reward, Rebirth, Quest,
                Retention, StormPass, Leaderboard, Trade, Shop, Analytics, WeatherEvent,
                Tutorial, Dev
  Util/         SessionStore (session-locked DataStore wrapper), GameEvents (event bus)
  World/        WorldBuilder (placeholder geometry)
src/client   → StarterPlayerScripts.Client
  Controllers/  ClientState, Spirit, PetFollow, CharacterVisuals, Weather, Gate, Tutorial,
                Effects, ModelFactory
  UI/           UIKit, Windows, HUD, and one module per window
tests        → ServerStorage.Tests (TestEZ-style specs + pacing simulator)
```

**Adding content needs no code changes.** Each of these is a table entry in `Config.luau`:
- a zone
- a spirit
- a Stormling
- an egg
- a storm
- a live event (with UTC start/end)
- a decoration
- a quest template
- an achievement row
- a potion
- a product

`Defs.luau` checks cross-references when the game starts, so a typo fails loudly instead of silently.

## Placeholder art

Every generated part has the CollectionService tag `Placeholder` and an `ArtistNote` attribute that says what it should become. There are two ways to swap models in without touching code:
- **World pieces:** put a Model with a PrimaryPart in `ServerStorage.ArtOverrides`, named `EggStand` or `Converter`.
- **Spirits and Stormlings:** put a Model named after the spirit or pet id in `ReplicatedStorage.Art.Creatures`.

Icons are emoji placeholders in `Theme.Icons`.

## Test commands (Studio, or `Config.Security.AdminUserIds`)

`/charge 1e9`, `/tokens 20`, `/storm Blizzard` (or `/storm off`), `/pass VIP`, `/unlockall`, `/pet Voltling 2`, `/potion LuckPotion`

## Status

- **Done:** every system in the brief is implemented. All code passes strict type-checking and 46 unit tests (economy math, pacing targets, migrations, quest rotation, pass rewards, schedules).
- **Not yet done:**
  - Play-testing in Studio. None of the code has run in the Roblox engine yet, so expect a round of in-engine fixes.
  - Final art and audio.
