# Storm Chaser Simulator: Design Doc

Every number below comes from `src/shared/Config.luau`, which is the single source of truth. If you change the numbers there, update this doc. `lune run scripts/simulate 7 -v` prints the pacing timeline for the current Config.

## 1. Pitch

You chase living weather spirits (sparks, gusts, hailstones, fog wisps, rainbow sprites) with a vacuum called the **Storm Jar**. You carry them home to your floating sky island and convert them into **Charge**. Charge buys a bigger jar, faster boots, a quicker catch rod, luck, more range, new sky zones and island decorations. You can also hatch spirits into **Stormlings**, companion pets that multiply your Charge. Three identical Stormlings fuse into a stronger one.

What sets it apart from other simulators:

| Pillar | What it does | Why it retains |
|---|---|---|
| Dynamic weather | A server-wide storm starts every 10 minutes, on a fixed UTC schedule (:00, :10, :20…). It adds storm spirits, boosts Charge and can drop Legendary Stormlings | Players have a reason to log in at storm times, and the countdown is always real |
| Island building | You decorate and expand your own island on a grid. Some decorations give passive boosts | Players feel they own something |
| Stormling fusion | 3 identical Stormlings of the same tier become 1 of the next tier (Base, Charged, Supercharged, Tempest) | Gives duplicate hatches value, and gives the pet system depth |

### Game feel: "size simulator"

Your progress should be visible from across the map. Things grow as you progress:
- Spirits, props and gates get bigger in later zones (`Theme.zoneScale`, +12% per zone).
- The Storm Jar on your back grows with its capacity level (`Config.SizeFeel`).
- Your avatar grows 8% per Ascension, up to 2.2×. This is cosmetic only and can be turned off with `Config.SizeFeel.Enabled`.
- Numbers are big and loud: a stroked, bold font, floating `+Charge` popups and suffixes such as K, M, B, T and Qa.

## 2. Core loop

```
catch spirits (tap / hold) → jar fills with Static → go home (1 tap) → converter turns Static into Charge
   ↑                                                                               ↓
   └────── new zone ← gate (Charge) ← upgrades (5 tracks) ← eggs → pets → fusion ←┘
                                   Ascend: reset Charge + upgrades → permanent ×, Tokens → tree
```

- **Catch:** tap or click a spirit, or tap anywhere to vacuum the nearest one in range. At Catch Rod level 2 you can hold to keep catching. The Auto-Catch pass catches without any input.
- **Sell:** tap Home to teleport onto your converter pad, which sells automatically, then tap Back. The Auto-Sell pass sells whenever the jar is full. The tutorial teaches catch → sell → upgrade in under 60 seconds.

## 3. Economy formulas (`EconomyMath.luau`)

| Quantity | Formula |
|---|---|
| Upgrade cost (next level from L) | `floor(baseCost · costGrowth^L)` |
| Jar capacity | `floor(30 · 1.55^L · (1 + DeepJar + JarRack))` |
| Catch cooldown | `max(0.12, 0.7 · 0.93^L) · (1 − QuickRod) / speedPotion` |
| Walk speed | `min(44, 18 + 1.3·L) · speedPotion` |
| Catch range | `min(48, 16 + 1.6·L)` studs |
| Catch luck | `(1 + 0.1·L + asc/decor/VIP) · potion · storm` |
| Shiny chance | `min(0.5, luck / 150)`, shiny value ×5 |
| Static per catch | `round(spirit.value · zone.valueMult · M)`, ×5 if shiny |
| Charge multiplier M | `(1 + 0.6·Asc) · (1 + Σ equipped pet power) · (1 + tree + decor + index + friend + premium) · 2x pass · potion · storm · event` |
| Pet power | `RarityPower[rarity] · 2.4^(zone−1) · fusionTierMult` (tiers: 1, 3.5, 12.25, 43) |
| Egg odds with luck | Weights of Rare-or-better pets ×luck, then renormalised. The UI shows both base and current odds |
| Ascension cost | `2e8 · 4.5^n` Charge |
| Ascension tokens | `3 + n + min(5, floor(log2(charge / cost)))` |
| "N minutes of income" rewards | `(1/cooldown) · 3.3 · bestZoneMult · M · 0.55 · 60 · N` |
| Offline earnings | `min(away, capHours) · income/s · 15%`. The cap is 8h, plus Sky Cellar and Rain Barrels. Nothing is paid if you were away less than 5 minutes |
| Storm Pass XP for tier t | `400 + 20·(t−1)` (44,500 XP for all 50 tiers) |

"N minutes of income" rewards (quests, gifts, Charge packs) scale with your progress, so they stay useful and never become trivial or game-breaking.

### Pacing (idealised free player, `tests/Pacing.spec.luau`)

| Milestone | Target | Simulated (seed 7) |
|---|---|---|
| First purchase | ≤ 30 s | 14 s (the tutorial bonus of +25 Charge after the first sell pays for it) |
| Zone 2 | ≤ 5 min | 4.1 min |
| Zone 3 / 4 / 5 / 6 | n/a | 11.6 / 18 / 23.5 / 31 min |
| First Ascension | 45–60 min | median ≈ 55 min over 9 seeds (range 47–61) |

These are enforced by a test, so a Config change that breaks pacing fails CI.

## 4. Zones

| # | Zone | Gate (Charge) | Value × | Egg | Egg cost |
|---|---|---|---|---|---|
| 1 | Drizzle Meadows | free | 1 | Drizzle Egg | 60 |
| 2 | Breezy Bluffs | 200 | 4 | Breeze Egg | 250 |
| 3 | Thunder Peaks | 2,500 | 17 | Thunder Egg | 1.5K |
| 4 | Hailstone Hollow | 30K | 75 | Hail Egg | 9K |
| 5 | Frozen Squall | 300K | 330 | Frost Egg | 55K |
| 6 | Monsoon Marsh | 4M | 1,450 | Monsoon Egg | 500K |
| 7 | Sandstorm Dunes | 150M | 6,400 | Dune Egg | 20M |
| 8 | Aurora Rift | 2B | 28K | Aurora Egg | 250M |
| 9 | Cyclone Canyon | 30B | 124K | Cyclone Egg | 3.5B |
| 10 | Eye of the Storm | 450B | 550K | Eye Egg | 50B |
| VIP | Rainbow Lagoon | VIP pass | 1.15 × your best zone | – | – |

Each zone is worth about 4.3× the one before. The VIP zone is a side zone: it is never needed to progress, and it is only slightly better than your best zone. Zones stay unlocked after you Ascend.

Each zone spawns 4 spirits with weights 70 / 22 / 6.5 / 1.5 and base values 2 / 4 / 10 / 28. Spawn caps are `min(maxSpirits, 8 per player in zone)`, and spirits are pooled on the client.

## 5. Rarity odds

Zone eggs (zone 1–2 eggs have no Mythic):

| Rarity | Weight | Chance | Base power |
|---|---|---|---|
| Common | 60 | 60% | 0.10 |
| Uncommon | 27.5 (28) | 27.5% | 0.18 |
| Rare | 9 | 9% | 0.35 |
| Epic | 3 (2.5) | 3% | 0.8 |
| Legendary | 0.49 (0.5) | 0.49% | 2.0 |
| Mythic | 0.01 | 1 in 10,000 | 6 |
| Secret (Eye Egg only) | 0.0001 | 1 in 1,000,000 | 25 |

Special eggs:
- **Storm Egg.** Costs Charge and can only be hatched during a storm: Storm Pup 70%, Cloud Cub 27%, and 0.75% for each storm Legendary.
- **Streak Egg.** Free on day 7 of the login streak: Rare 70%, Epic 25%, Legendary 5%.
- **Tempest Egg.** Robux, paid random item: Epic 75%, Legendary 23%, Mythic 2%. It deliberately has no Secret pets.

Storm spirits also have a 1/400 × luck chance to drop their storm's Legendary Stormling directly.

Luck multiplies the weights of Rare-or-better pets. Egg luck comes from the Lucky Hatch pass (×1.5), VIP (+20%), luck potions (×2), the Aurora storm (×2) and events.

## 6. Retention systems

| System | Summary |
|---|---|
| Daily streak | 7-day cycle shown on the HUD with a flame counter. Rewards: 3 min Charge, Luck potion, 8 min Charge + 100 XP, 2x potion, 15 min Charge, 2 Speed potions + fusion skip, then on day 7 a **Streak Egg** (Rare+ guaranteed) + 20 min Charge. Missing a UTC day resets the streak to day 1 |
| Session gifts | Unlock at 5 / 10 / 15 / 30 / 60 minutes of playtime in a session. Their timers are always visible |
| Quests | 3 daily and 5 weekly quests, picked per player from template pools with a date seed. Kinds: catch, shiny, storm catch, hatch, fuse, earn, sell, explore a zone, upgrade, play time |
| Achievements | 11 stat families, 39 tiers. Rewards include Charge minutes, Pass XP and Tokens at high tiers |
| Index | Collection log of every Stormling. Discovering all pets from an egg gives +5% permanent Charge + reward |
| Leaderboards | Global OrderedDataStores for Lifetime Charge (log-encoded), Ascensions and Rarest Stormling, plus in-server `leaderstats` |
| Live events | Add an entry to `Config.LiveEvents` (start/end UTC, multipliers, extra spirits, event egg). No code needed |
| Trading | Two-sided Ready → 3 s delay → Confirm flow. Any change resets both sides. Changed items are highlighted and there is a change log. Locked pets can't be offered. Both players need 20 min of total playtime. Pets from paid eggs follow `PolicyService.IsPaidItemTradingAllowed` |
| Friend boost | +10% Charge while a friend is in the server |
| Group reward | One-time Group Gust pet + 10 min Charge for group members |
| Offline earnings | See formula. A "while you were away" popup appears on join |
| Storm Pass | 50 tiers, 30-day season, free and premium tracks. XP comes from catches, hatches and quests (see the table in section 3) |

## 7. Monetization

These are ethical and follow the Roblox rules. Most of the audience is under 13.

**Game Passes:** 2x Charge (299), Auto-Catch (249), Auto-Sell (199), +3 Pet Slots (349), VIP (399: chat tag, Rainbow Lagoon, +20% luck), Lucky Hatch (199), Faster Hatch (149).

**Developer Products:**
- Charge packs of 30 min, 3 h and 12 h of *current* income. The exact amount is shown before purchase.
- Luck, Speed and 2x Charge potions (15 min each).
- Tempest Egg ×1 / ×3.
- Storm Pass skip-a-tier, Storm Pass premium (per season).
- Instant Fusion.
- Starter Pack.

**Paid random items:**
- Every pet and its exact % is shown in the egg UI before purchase, for both base and luck-adjusted odds.
- Players for whom `PolicyService:GetPolicyInfoForPlayerAsync().ArePaidRandomItemsRestricted` is true never see the Robux egg purchase button. The server also refuses to prompt it. If a receipt still arrives, they get a fixed, non-random pet instead.

**Premium Payouts:** Premium members get +10% Charge and a daily Premium gift. The benefits panel can show `PromptPremiumPurchase`, but only when the player taps it.

**Starter Pack:**
- Offered once, 3 minutes after the tutorial. It is then available in the shop until bought.
- The "worth" line is computed from the live prices of the matching individual products. It is hidden if any price is unavailable.

**Purchase safety:**
- Every receipt goes through `ProcessReceipt`, which works like this:
  1. It waits for the player's profile.
  2. If the `PurchaseId` is already recorded, it returns `PurchaseGranted`.
  3. Otherwise it grants the purchase and records the `PurchaseId`.
  4. It forces a save and returns `PurchaseGranted` only if the save succeeded. Otherwise it returns `NotProcessedYet`, and Roblox retries.
- The last 200 receipt ids are kept.

**Things we deliberately don't do:**
- No fake timers. The only countdowns are real storm and event times.
- No "only N left" messages or pop-ups that interrupt play. The shop is one tap away and never opens itself; the only automatic offer is the Starter Pack, shown once.
- No Secret pets in paid eggs.
- Every zone can be reached for free. Passes only save time.

## 8. Technical architecture

- **Rojo:** `src/shared` → `ReplicatedStorage.Shared`, `src/server` → `ServerScriptService.Server`, `src/client` → `StarterPlayerScripts.Client`, `tests` → `ServerStorage.Tests`.
- **Data:** `SessionStore` is a session-locked wrapper around `UpdateAsync`, written for this project in the ProfileService style:
  - Lock with job id + timestamp, and steal stale locks after retries.
  - Auto-save every 60 s. Saves check the lock is still ours, and the player is kicked if the session was stolen.
  - Exponential-backoff retries and a `BindToClose` flush.
  - Falls back to an in-memory store in Studio when API access is off.
- **Versioning:** `DataVersion` plus ordered `Migrations` (tested), then reconcile against `DataTemplate`.
- **Server authority:**
  - Catches check the spirit exists, the zone is unlocked, `distance ≤ range + 6`, the cooldown (80% tolerance) and that the jar is not full.
  - Hatches check the distance to the egg stand and the Charge cost.
  - Sells check the player is standing on their own converter.
  - Every remote has a per-player rate limit.
- **Networking:** `Net.luau` declares every remote with a runtime payload schema and a rate limit. Invalid payloads are dropped and logged.
- **Services:** `DataService`, `CurrencyService`, `UpgradeService`, `ZoneService` (spirits), `PetService` (eggs, equip, fusion), `WeatherEventService` (storms + live events), `QuestService` (quests, daily, gifts, achievements, index), `ShopService` (passes, products, receipts, policy), `TradeService`, `RebirthService`, `LeaderboardService`, `IslandService`, `StormPassService`, `AnalyticsService`, `SocialService` (friends, group, premium).
- **Performance:**
  - Spirits are logical server entities and replicate only as id + position + type.
  - Clients render them from a model pool, and pets are rendered on the client.
  - `StreamingEnabled` is on and spawn caps are per zone.

## 9. Art direction ("chunky storm-toy")

See `src/shared/Theme.luau`. Every placeholder part carries the `Placeholder` CollectionService tag and an `ArtistNote` attribute that describes what should replace it.

- **World:**
  - Stepped block islands (12-stud blocks, 4-stud terraces) in SmoothPlastic, with Neon trims in each zone's accent colour.
  - Clouds are stacked white cubes.
  - Gates are 44 studs tall with a glowing frame and a giant price sign.
- **Spirits:** chunky primitive bodies (ball, block, wedge or cylinder) with a neon core, two block eyes and a bob-and-spin motion. Their size grows with zone.
- **Stormlings:** the same kit as spirits plus ears or fins and rarity aura particles. Fusion tiers scale them 1 / 1.25 / 1.5 / 1.8× and add glow.
- **UI:**
  - Bright "toy plastic" panels with thick 4px dark outlines and 14px corners.
  - Each main button has its own saturated colour with a top-light gradient.
  - FredokaOne font with stroked text.
  - Buttons squash to 90% when pressed and bounce back.
  - Mobile first: the main bar has 76px buttons at the bottom, and `UIScale` adapts from 0.55× to 1.35×.
- **HUD:**
  - Currencies at top left and the storm banner with a real countdown at top centre.
  - The quest tracker and gift timer on the right.
  - The jar bar above the main bar, with active boosts beside it.

## 10. Analytics

`AnalyticsService` events are logged by `AnalyticsService` (server):
- Onboarding funnel: join → first catch → first sell → first upgrade → tutorial done.
- Economy events for every Charge source and sink.
- Progression events for zone unlocks and Ascensions.
- Custom events: first purchase (with product), session length, D1/D7 retention markers (from `FirstJoin`), storm participation.
