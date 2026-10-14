# Roll Brainrot: Monster Arena

**ROLL** ridiculous Brainrots → **COLLECT** them → put them in your **ZOO** for passive income → take your strongest into a **GIANT STADIUM** → fight waves of monsters and a boss 50× their size → **EARN** rewards → roll better Brainrots → repeat.

This is a self-contained Rojo project inside the repo (the Storm Chaser Simulator game in the repo root is separate). The design, loop and numbers are in [DESIGN.md](DESIGN.md).

## Run it

- **Quick look:** `rojo build -o RollBrainrot.rbxlx` (run inside this folder), open the file in Roblox Studio and press Play. The server builds the whole world on start (hub, zoo plots, roll machine and the stadium). Building takes a second or two.
- **Live development:** run `rokit install` in the repo root, then `rojo serve` in this folder, and connect the Rojo plugin.
- **Saving in Studio:** turn on *Game Settings → Security → Enable Studio Access to API Services*. If it's off, data stays in memory for the session.

Test commands (in Studio, or for `GameConfig.Security.AdminUserIds`):
`/coins 1e6`, `/gems 500`, `/tokens 50`, `/essence 999`, `/level 20`, `/give CosmocornoBrainrot Rainbow`, `/event GiantInvasion`, `/unlockarenas`

## Checks

`./scripts/check.sh` runs three steps:
1. Strict `luau-lsp` type-checking against the Roblox API types.
2. `selene`. This step is skipped when the Roblox API dump can't be downloaded.
3. The Lune unit tests.

| Command | What it does |
|---|---|
| `lune run scripts/run-tests [filter]` | 21 tests: config cross-references, roll odds and pity, stat maths, and headless combat simulations (a starter team clears a wave, a strong team beats a boss, respawns, snapshot packet sizes) |
| `lune run scripts/smoke` | Runs the real world builders, every creature model in every mutation, and every UI window. It uses a fake DataModel that checks each property write against Roblox's API reflection database: the property must exist, be writable, and get the right type or enum. It also prints part counts per area |
| `lune run scripts/simulate-arena GreenFields 3 BananiniBongo Cactoboom …` | Balance check. Plays a whole arena with the team you give it, and prints each wave's time, the team's DPS and how many Brainrots died |

## Layout

```
src/shared  → ReplicatedStorage.Modules
  BrainrotConfig  RarityConfig  MutationConfig  AbilityConfig  MonsterConfig  ArenaConfig  GameConfig
  Registry (validated lookups)  BrainrotMath  RollMath  Net (remotes + schemas + rate limits)
  Models/  ModelKit  BrainrotModels  MonsterModels  Animator
src/server  → ServerScriptService.Server
  Services/  Data  Inventory  Roll  Zoo  Upgrade  Reward  Combat  Monster  Arena  Player
             DailyReward  Shop  Event  Dev
  Combat/    Battle (simulation)  Abilities (handlers)  BossAttacks (telegraphed specials)
  World/     WorldBuilder  HubBuilder  RollMachineBuilder  ZooPlotBuilder  ArenaBuilder  Props  BuildKit
  Util/      SessionStore (session-locked DataStore wrapper)
src/client  → StarterPlayerScripts.Client
  Controllers/  ClientState  Effects  CameraController  RollController  UnitRenderer  CombatFx
                CombatController  ZooController  FollowController  AmbientController
                CrowdController  EventController  PromptController  MusicController
  UI/           UIKit  Windows  HUD  RollUI  CollectionUI  ZooUI  BattleUI  ArenaUI
                StandWindows  Notifications  BrainrotInfo  Viewport  Bus
```

## Adding content (config only)

| To add | Edit |
|---|---|
| A Brainrot | Add a row to `BrainrotConfig`. Pick a rarity, an ability, speed and range tiers, a habitat, and a model `builder` with colours |
| A rarity | Append a row to `RarityConfig`. Weights, colours and the reveal effect tier come from that row |
| A mutation | Add a row to `MutationConfig`. It sets chance, stat and income multipliers, tint, material, rainbow and sparkles |
| An ability | Add a row to `AbilityConfig`. If it reuses an existing handler and VFX, that's all. A brand-new mechanic needs one handler function in `Combat/Abilities` |
| A monster or boss | Add a row to `MonsterConfig`. Bosses list their `attacks`; new attack shapes go in `MonsterConfig.BossAttacks` |
| An arena or its waves | Edit `ArenaConfig` |
| Upgrades, habitats, decorations, daily rewards, events, shop items | Edit `GameConfig` |

`Registry.validate()` runs at server start and in the tests. It catches typos in cross-references, such as an unknown ability, habitat, monster or drop.

## Replacing placeholder art

All models are built from parts, so the project needs no assets. To swap in real art without changing code:
- **Brainrots:** add a `Model` named after the Brainrot id to `ReplicatedStorage.Art.Brainrots`.
- **Monsters:** add a `Model` named after the monster id to `ReplicatedStorage.Art.Monsters`.

The Model needs a `PrimaryPart` at its feet, facing −Z. Monsters are scaled automatically to the `height` set in their config.

### UI art (Higgsfield)

The HUD currency icons, menu buttons, roll button, logo and the Zoo window's habitat banners can use 24 images generated with Higgsfield. Until an image is uploaded, each spot falls back to an emoji or a gradient, so the game works either way. To use the art, follow [assets/UI_ART.md](assets/UI_ART.md): download one zip, then run one command that uploads the images to Roblox and fills in `GameConfig.UIImages`.

Sounds use built-in `rbxasset://` sounds. Music ids are empty until you upload your own. Set both in `GameConfig.Sounds`.

## Before publishing

- Put Game Pass and Developer Product ids in `GameConfig.GamePasses` and `GameConfig.Products`. An item whose id is 0 shows "Coming soon".
- Turn on API services and complete the experience questionnaire. The game has paid random items: the Auto Roll pass and roll tokens.
- Play-test in Studio. Every module type-checks and passes the smoke test and simulations, but nothing has run inside the actual Roblox engine yet, so expect a round of in-engine tuning. The likely areas are camera shots, model proportions and UI layout on phones.
