# Roll Brainrot: Monster Arena — Design

The numbers below are first-pass values. They live in `src/shared/*Config.luau`. `lune run scripts/simulate-arena` checks the combat pacing.

## 1. Core loop

```
JOIN (starter Bananini Bongo + 5 free Roll Tokens + $500)
  → ROLL at the giant machine (tokens first, then $250 a roll)
  → reveal → EQUIP or SEND TO ZOO
  → zoo earns coins every minute, even offline (50%, up to 12h) → WELCOME BACK popup
  → ENTER ARENA through the stadium gate → 10 waves → GIANT BOSS cinematic → victory
  → coins, XP, Rot Essence, Roll Tokens, Boss Tokens, boss-exclusive drops
  → roll more, level Brainrots (coins + Essence), buy upgrades, unlock habitats
  → next arena (level requirement + previous boss beaten) → repeat
```

The player should keep thinking: *"I need to roll a stronger Brainrot so I can beat the next monster."*

## 2. World layout (studs)

| Place | Where | Notes |
|---|---|---|
| Spawn + welcome arch | (0, 175) | From the spawn you look north, through the arch, at the machine and the stadium |
| Plaza + ROLL machine | (0, 0) | Plaza radius 78. Eight reward pedestals stand in an arc behind the machine |
| Stands | ±120 / ±130 around the plaza | Shop, Upgrades, Daily Rewards, Events (the Events stand has a live board) |
| Zoo plots ×6 | x = ±330 | Each plot is 190×170: 6 themed pens plus a long Giant pen, a collector pad, decoration spots and an owner sign |
| Pond, meadow, forests, hills | around the edges | The meadow is the landing zone for Giant Invasions |
| Monster Arena | (0, −1320) | 540-radius battlefield, 6 tiers of stands, a 175-stud facade, floodlights, giant screens, a south tunnel and a north boss gate |

The battlefield (Ø1,080) plus the stands (Ø1,400) is bigger than the hub (1,120 × 1,060). The stadium shell streams as *Persistent*, so you can always see it from the hub. A 520-stud road leads there. The HUD's travel buttons skip the walk.

## 3. Rolling

- **Odds** (`RarityConfig`): Common 60%, Uncommon 25%, Rare 10%, Epic 4%, Legendary 0.8%, Mythic 0.19%, Secret 0.01%.
  - Luck multiplies the weights of Rare and above, then all weights are normalised.
- **Luck** = Luck upgrade (1 + 0.1/level) × Luck Boost (2×) × Golden Hour (2×).
- **Mutations** are rolled separately from rarity (`MutationConfig`):
  - Golden 7% (×2), Diamond 2% (×5), Rainbow 0.8% (×10), Shadow 0.25% (×15), Cosmic 0.05% (×25).
  - Luck raises mutation odds by √luck.
- **Pity**: every 100 rolls without a Legendary or better forces one. Rolling one naturally also resets the counter. The machine shows "PITY 73/100".
- **Reveal**:
  1. Camera close-up.
  2. The machine shakes while the rarity lights strobe.
  3. The capsule drops down the chute.
  4. Names flash past, slowing down.
  5. The capsule cracks open and the Brainrot pops out.

  The effects scale with rarity (`fxTier`):

  | Rarity | Effects |
  |---|---|
  | Common | Simple white burst |
  | Rare | Blue rings |
  | Epic | Purple pillar and confetti |
  | Legendary | Gold, screen shake and a flash |
  | Mythic | Red/pink double ring and a blast |
  | Secret | Blackout build-up, a star burst, a 400-stud pillar, rainbow lights, a huge shake and 220 confetti |

- **Speeding it up**: Skip unlocks after your first roll. The Fast Roll pass and the Quick Rolls upgrade shorten the animation. Auto Roll (a pass) loops rolls.

## 4. Brainrots (`BrainrotConfig`)

| Brainrot | Rarity | Role | HP / ATK / DEF | Ability | Zoo $/min |
|---|---|---|---|---|---|
| 🍌 Bananini Bongo | Common | Speed | 100 / 12 / 4 | Banana Bonk (3 quick hits) | 5 |
| 🍕 Pizzarino Mozzarino | Common | AoE | 140 / 10 / 6 | Cheese Burst (exploding pizza) | 8 |
| 🌵 Cactoboom | Uncommon | Tank | 400 / 18 / 20 | Thorn Shield (−50% damage, 30% reflect, taunt) | 20 |
| 🐸 Froggolino Gelatino | Rare | Support | 260 / 24 / 12 | Sticky Splash (slow + heal) | 50 |
| 🐊 Bombardiro Gatoro | Epic | Ranged DPS | 450 / 65 / 14 | Gator Missile (hits the strongest enemy) | 150 |
| 🦈 Sharkalero Jetto | Legendary | Assassin | 700 / 110 / 22 | Shark Rush (piercing dash) | 500 |
| 🐘 Volcanico Elefanto | Mythic | Boss DPS | 3,500 / 300 / 60 | Volcano Stomp (lava shockwave + burn); immune to burn | 2,500 |
| 🌌 Cosmocorno Brainrot | Secret | Ultimate | 15,000 / 1,500 / 120 | Cosmic Collapse (black hole); Cosmic Aura (+20% attack speed) | 15,000 |

- **Combat Power** = DPS × 5 + HP / 6 + DEF × 1.5. Mutations and levels multiply it.
- **Levels** run 1–30. Each level adds 12% to stats and 10% to income. A level costs coins plus Rot Essence (essence is earned in the arena).
- **Ability handlers** (`Combat/Abilities`): MultiHit, AoEProjectile, SelfShield, AreaSlowHeal, Dash, GroundSlam, BlackHole and Chain.
  - The generic Fireball, Freeze, Taunt, Chain Lightning and Heal abilities are already defined for future Brainrots.

## 5. Zoo

- **Ownership**: one plot per player, assigned on join. The owner sign shows the player's name.
- **Habitats**: Grass (free), Forest $3K, Desert $20K, Ice $100K, Volcano $600K, Alien $3M, Giant $15M.
  - The last three also need an arena boss beaten.
  - Each habitat has 3 slots, plus 1 per upgrade level (levels 1–6).
  - Each upgrade level adds 10% income.
- **Favourite habitat**: a Brainrot placed in its favourite habitat earns +25%.
- **Income**: Σ placed income × Zoo Income upgrade × (1 + decorations) × VIP × Coin Boost.
  - Income goes into a bank. You collect it at your plot's pad or from the Zoo window.
- **Equipped vs in the zoo**: a Brainrot copy is either equipped or in the zoo, not both, so duplicates are useful.
- **What players see**: each client draws every zoo's Brainrots wandering their pens, with idle quirks (Bananini slips over, Froggolino hops, …). NPC visitors stroll the plots of players who are in the server.

## 6. Arena & combat

- **Server-authoritative simulation** (`Combat/Battle`), running at 10 Hz:
  - Units are plain tables: no physics, no server models.
  - Targeting: nearest enemy. Monsters prefer Brainrots over the trainer, and a taunt overrides everything.
  - Brainrots stay on a leash near their trainer.
  - Separation uses a 16-stud spatial hash.
  - Statuses: Shield, Slow, Burn, Taunt, Pulled, Haste and Rally.
  - Brainrots respawn 8 s after dying.
- **Damage** = atk² / (atk + def) × crit (10% chance, ×1.75) × Rally.
  - This formula works the same at every scale, from tier 1 to tier 6.
  - Monsters hit trainers using their *unscaled* attack × tier factor, because trainers don't grow ×4,000.
- **Networking**:
  - Reliable `CombatEvents` arrive batched once per tick.
  - Unreliable `CombatSnap` sends 8 bytes per unit, up to 100 units per packet (well under the 900-byte limit).
  - Clients smooth the positions and animate the models.
  - Only players within 650 studs receive a battle's traffic.
- **Waves**:

  | Wave | Contents |
  |---|---|
  | 1 | 10 small |
  | 2 | 20 mixed |
  | 3 | Elite (Rock Brute) |
  | 4 | 30 mixed |
  | 5 | MINI BOSS (King Goober) |
  | 6 | 24 mixed |
  | 7 | 3 elites |
  | 8 | 30 mixed |
  | 9 | Final stand |
  | 10 | GIANT BOSS |

  - Non-boss monsters gain +8% per wave. Bosses are tuned as listed.
  - Monsters spawn 70–120 studs from the fighters, mostly from the far side.
  - At most 36 monsters are alive at once; the rest of the wave trickles in.
- **Bosses**:
  - Four attack shapes: Circle slam, Ring shockwave, Line charge and Multi barrage.
  - Every attack is telegraphed with a red zone that fills up first. There is also a Summon.
  - Bosses enrage at 40–50% HP: 25% faster windups and +35% attack speed.
  - Entrance: the north doors slide open and the boss strides in while invulnerable. A WARNING sequence and a two-shot camera cinematic play, the crowd roars, and the name card appears.
- **Trainer actions**:

  | Action | Key | What it does |
  |---|---|---|
  | Attack | click / R2 | Cleaves up to 3 enemies |
  | Dodge | Q | Dash with i-frames |
  | Heal | E | Heals 35% and revives fallen Brainrots |
  | Rally | R | ×1.5 attack for 8 s |
  | Ultimate | F | Meteor dealing 10× the team's average attack; charged by team hits and kills |

- **Arenas**:

  | Arena | Stats | Rewards | Level |
  |---|---|---|---|
  | Green Fields | ×1 | ×1 | 1 |
  | Desert Colosseum | ×6 | ×5 | 8 |
  | Frozen Wasteland | ×30 | ×22 | 16 |
  | Volcanic Arena | ×150 | ×100 | 25 |
  | Void Arena | ×800 | ×450 | 35 |
  | Ancient Titan Arena | ×4,000 | ×2,000 | 50 |

  - Each arena also needs the previous boss beaten.
  - Picking an arena re-themes the battlefield (terrain material, fog and sky tint).
- **Co-op**: everyone who joins a run fights the same waves. Every fighter gets the full reward for every kill. Rewards are paid as you go, so dying or leaving keeps them.
- **Crowd**: 3,000 client-side fans, built only when you're near the stadium. They bounce with "hype" from big hits and kills. Everyone stands for the boss entrance, and they do a stadium-wide Mexican wave when the boss falls. Only fans whose pose changes are moved (one `BulkMoveTo` call).

**Pacing** (`simulate-arena`, Brainrots only, without the trainer's damage or heals):

| Team | Green Fields run | Boss fight |
|---|---|---|
| Starter 3 commons (power 352) | ~12 min | ~2.7 min |
| 4 commons/rare (power 513) | ~7 min | ~1.5 min |
| Desert Colosseum, Epic + Legendary team (power 2,307) | ~6 min | ~1.3 min |

## 7. Rewards & progression

- **Kills** pay coins × arena rewards × Coin Boost × VIP, and XP × √(reward multiplier).
  - Elites and bosses also drop Essence (× tier), Tokens and Boss Tokens.
  - Any monster has a tiny chance of dropping a Roll Token or 5 Gems.
- **Boss-exclusive drops** (examples):
  - Forest Titan: Golden Cactoboom 25%, Froggolino 8%, Bombardiro 2%.
  - Volcano Titan: **Volcanico Elefanto 2%**.
  - Void Monster: Cosmocorno 0.2%.
- **Clearing a wave** pays 20 × wave × the reward multiplier, plus XP.
- **Player level**: XP to the next level = 100 × level^1.5. Each level gives +15 HP, +3 attack and 5 Gems.
- **Upgrades**:
  - Luck (×1→×3)
  - Equip Slots (3→8; +2 with the pass, so 10)
  - Zoo Income (×1→×3.5)
  - Storage (+25 per level)
  - Trainer Power
  - Quick Rolls (paid in gems)
- **Daily rewards** (7-day cycle; missing more than 48h resets the streak): Coins → Tokens → XP Boost → Luck Boost → Rare Brainrot → 50 Gems → Golden Epic Brainrot.

## 8. World events

One event starts every 8 minutes and lasts 2.5–4 minutes:

| Event | Effect |
|---|---|
| Meteor Shower | Strikes hit monsters for 8% of max HP; visual meteors cross the sky; rewards ×1.25 |
| Storm | Lightning strikes, rain and a darker sky |
| Blood Moon | Night with a red sky; monsters ×1.5, rewards ×2 |
| Golden Hour | Sunset; roll luck ×2 |
| Giant Monster Invasion | The Giant Mutant lands in the hub meadow. Walk in to fight it. Its HP scales with the player count and its tier with the best arena any player online has beaten |

## 9. Monetization (optional, nothing pay-to-win)

| Kind | Items |
|---|---|
| Passes | +2 Equip Slots, Auto Roll, Fast Roll, +300 Storage, VIP (decorations, +10% coins, gold name) |
| Products | Luck, Coin and XP boosts; Roll Tokens; Gems |

- Receipts are idempotent: the last 60 purchase ids are saved in the profile.
- **Free alternatives**: the Gem Shop sells boosts and tokens for gems earned from levels and daily rewards. A Boss Crate (10 Boss Tokens) gives a random Epic.

## 10. Saving

`SessionStore` is a session-locked DataStore wrapper:
- Only one server can own a profile at a time.
- Every call is retried with backoff and waits for request budget.
- Autosave runs every 60 s. Profiles are released on leave and saved on shutdown.
- If another server takes the lock, the player is kicked rather than risking an overwrite.
- In Studio without API access it falls back to an in-memory store.

The template is reconciled on every load, so new fields appear in old saves. Every cross-reference is cleaned on load: Brainrots removed from the config, and stale uids in the equipped list or the zoo.

## 11. Performance notes

- **World**: about 11,000 parts in total.
  - Hub ~4.3k, zoos ~3.7k, stadium ~3k.
  - Flowers are 2 parts each. Fences have sparse posts.
  - Streaming is on. Only the stadium shell and the machine are persistent.
- **Creatures**: everything that moves is client-side (zoo creatures, followers, battle units, NPCs, crowd).
  - Each creature moves with one Root CFrame write per frame (welded parts follow).
  - Far zoos update at a quarter rate and are culled beyond 520 studs.
- **Server**: no per-NPC Heartbeat. One fixed 10 Hz loop runs all battles.
