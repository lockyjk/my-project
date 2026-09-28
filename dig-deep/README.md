# ⛏ Dig Deep

*Dig down. Find treasure. Go deeper.*

A Roblox mining game made of two scripts. The server script builds the whole world when the game starts, so there are no models or assets to import.

## Play it

Open **`DigDeepOfficial.rbxlx`** in Roblox Studio and press Play. There are 9 mines, so set **Game Settings → Places → Max Players** to 9 when you publish. The place file already contains both scripts, ShadowMap lighting, and a kill floor set low enough for the 500m mine.

## Keep your game up to date (no new files)

Install **Dig Deep Sync** once: in Studio, open the **Plugins** tab, click **Plugins Folder**, put [`DigDeepSync.lua`](DigDeepSync.lua) in that folder, and restart Studio. From then on, whenever you open your Dig Deep game it downloads the newest scripts from this repository into that same game. You can also click **Update Dig Deep** on the Plugins tab. The first time, allow the two permissions Studio asks for: web requests to raw.githubusercontent.com, and changing scripts.

## Or put the scripts in your own place (2 minutes)

1. In Roblox Studio, create a new **Baseplate** place. The script removes the baseplate and spawn for you.
2. **ServerScriptService** → Insert Object → **Script**. Name it `DigDeepServer` and paste in [`DigDeepServer.server.luau`](DigDeepServer.server.luau).
3. **StarterPlayer → StarterPlayerScripts** → Insert Object → **LocalScript**. Name it `DigDeepClient` and paste in [`DigDeepClient.client.luau`](DigDeepClient.client.luau).
4. Set **Workspace → FallenPartsDestroyHeight** to `-4000`, because the mine goes 3000 studs down. Also set **Lighting → Technology** to **ShadowMap** for the intended look.
5. Press **Play**.

To keep progress between sessions, turn on **Game Settings → Security → Enable Studio Access to API Services**. Without it the game still works, but progress resets when you stop.

## How it plays

| | |
|---|---|
| **Dig** | Every player gets **their own mine**: a shaft with your name on it. Jump in and click (or hold) anywhere. Each click hits the one big block you're standing on. When it breaks you drop onto the next one, and the walls change colour as you reach new layers. |
| **Sell** | Tap **⬆ SURFACE** (or press **R**). It teleports you onto the gold sell pad, which sells your bag. |
| **Upgrade** | Walk up to a pickaxe or backpack on the market stalls and press **E** to buy it. Prices turn green when you can afford them. |
| **Go deeper** | Topsoil → Stone (20m) → Deepstone (60m) → Magma Rock (120m) → Crystal Caves (200m) → The Void (300m) → The Core (420m) → bedrock at 500m. Each layer has richer ore and harder blocks. |
| **Ascend** | Once you've reached bedrock, use the Ascension Shrine next to the museum. It resets your coins, gear and depth but keeps your treasures, and gives +50% ore value forever each time. |
| **Elevator** | Takes you straight back down to the bottom of your mine. |

## +1 Strength every click

The core loop borrows from *+1 Mine Per Click*, one of the biggest mining games on Roblox right now.

- **💪 Strength:** every swing gives Strength, even a click at thin air. A big **+1 💪** pops up at your cursor with a pop sound that climbs in pitch as you keep clicking. Strength multiplies your pickaxe damage (x(1 + √Strength × 0.1)). Deeper layers are much tougher, so you need Strength to get down.
- **🏋️ Training Area:** four rocks west of the mine. Stand on a rock's glowing pad and your character trains by itself (x1 free, then x3, x10 and x25, unlocked by rebirths).
- **Milestones:** 25, 50, 100, 250, 500, 1K Strength and so on. Each one pays coins on the spot with a big burst and confetti.
- **🔁 Rebirth:** reach the Strength goal (250, then x2.6 each time) to reset your Strength for **+1 Strength per click** and **+20% cash**, forever (+1, +2, +3... per click). Milestones pay out again on every run.
- **🎁 Free Gifts:** the first gift unlocks after **10 seconds**, then more at 30s, 1m, 2m, 3m, 5m, 7m, 10m, 13m, 16m, 20m and 25m of play: Strength, coins, potions and a free egg. The GIFTS button counts down to the next one.
- **Offline:** Strength keeps training while you're away, as well as coins.
- **First steps:** the objective banner now starts with "Click to train Strength" and later sends you to the free training rock.

## Rock Cave, accessories and TNT

- **🪨 Rock Cave:** once you break the first block in your mine, a tunnel in the right-hand wall opens into your own cave. It holds 7 boulders: grey Pebble Rocks (4 clicks, 1 🪨), Gold Rocks (8 clicks, 6 🪨) and glowing Gem Rocks (15 clicks, 30 🪨). Broken rocks grow back after 15 seconds. A ladder at the far end climbs out to the surface, so you can always come back, even from deep down.
- **✨ Accessory shop** east of the mine: spend 🪨 Rocks on a Party Hat, Miner Helmet (with a working head lamp), Cool Shades, Gold Crown, Angel Wings, Halo, Dragon Wings or a Rainbow Aura. You wear one per slot (head, face, back, aura), and each one adds coin value (3% to 35%).
- **💣 TNT stand** beside the sell pad: TNT costs a lot (25 minutes of digging with your current pickaxe, at least 💰 2,500). Stand in your mine and press the TNT button to blast through 5 blocks at once, and everything it blows up is sold on the spot.
- **Pickaxes:** new models with a banded handle, a wrapped grip and pommel, and a curved head with two points and a gem. High tiers glow and sparkle. A new top tier, the **Rainbow Pick**, sits after the Core Breaker.

## Making money (Game Passes and Developer Products)

Everything is already built. You only need to create the items on Roblox and paste their IDs in:

1. Publish the place (**File → Publish to Roblox**).
2. On the [Creator Dashboard](https://create.roblox.com/dashboard/creations), open the experience. Create each **Pass** under *Monetization → Passes* and each **Developer Product** under *Monetization → Developer Products*.
3. Put each item's ID into the `PASSES` / `PRODUCTS` tables at the top of `DigDeepServer`, replacing the `id = 0`.

While an ID is `0`, the item shows **"Soon"** in the live game. **In Studio, buying it gives it to you for free** for that session, so you can test everything before publishing.

| Game Pass | Suggested price | What it does |
|---|---|---|
| 👑 VIP | 399 | +25% ore value, 👑 VIP tag over your head, sparkling pickaxe |
| 💰 2x Coins | 349 | Everything you sell is worth double |
| 🤖 Auto Mine | 299 | Toggle button: digs automatically |
| 🛒 Sell Anywhere | 249 | SELL button on screen, no trip to the surface |
| 🍀 Lucky Miner | 299 | 2x treasure luck, better egg odds |
| ⚡ Fast Swings | 249 | 25% faster pickaxe |
| ♾️ Infinite Backpack | 799 | Backpack never fills |
| 🐾 +2 Pet Slots | 349 | Equip 5 pets instead of 3 |

| Developer Product | Suggested price | What it gives |
|---|---|---|
| 🎁 Starter Pack | 99 | Exclusive Starter Pup pet, 15 min of every potion, coins |
| 🪙 / 💰 / 🏦 Coin packs | 49 / 199 / 599 | 20 min / 2 h / 8 h worth of digging at your current pickaxe |
| 🧪 🍀 ⚡ Potions | 39 each | 15 min of 2x Coins / 2x Luck / faster swings (stack up to 3 h) |
| ⛏ Instant Pickaxe | 149 | Skip straight to your next pickaxe |

**Policy-safe by design:** eggs and spins can't be bought with Robux, so there are no paid random items. Every Robux purchase gives a fixed, stated reward. Receipts are tracked so a purchase is never granted twice, and one is never lost if the player leaves mid-purchase.

## Simulator features

- **Pets:** 16 pets from 4 eggs, each hand-built with glossy eyes, blush and idle animations (wings flap, tails wag, slimes squish) in the 🥚 Pet Shop next to the museum (coins only, odds shown on each egg), plus the exclusive Starter Pup. Pets follow you and boost your coins. New pets equip themselves if they're better, and the Pets window has Equip, Delete and Equip Best.
- **Miner Level:** XP for every block (deeper layers give more). Each level gives +1% ore value and a coin reward. Your level shows over your head.
- **🎡 Spin wheel:** a free spin every 20 minutes (coins, potions, a free egg, or a 💎 jackpot).
- **🎟️ Codes:** `RELEASE`, `DIGDEEP`, `GOLDRUSH`, `THANKYOU`. Add more in the `CODES` table and post them on your group or socials.
- **Potions:** timers show under your coins.
- **Cartoony UI:** a button stack on the left (Shop, Pets, Spin, Codes, Offer, Quests, Settings), chunky 3D buttons with a bevelled lip and gloss, bouncy windows with a big header bar and a red **X**, confetti, and a level-up burst.
- **Shop:** wide, colourful offer cards like the top sims. Each has a slowly turning 3D model of the item (crown, coin piles, potions, robot, money bag, backpack, pickaxe, pets), a big title, and a green Robux price button. Some have tags such as ONE TIME!, POPULAR or BEST VALUE.

## Look and guidance

- **Cartoony front-page style:** a lime checkerboard grass map inside checkered dirt walls with a bright green trim, flat saturated plastic, wooden cross-brace fences, blocky trees, a cartoon pond, and glowing yellow circle pads with big floating titles (⛏ PICKAXES, 🥚 PET SHOP, FREE!, and so on).
- **Objective banner** at the top center that walks new players through 7 steps: dig, fill your bag, sell, buy a pickaxe, buy a backpack, hatch a pet, reach 20m and open the daily chest. After that it always shows the next goal (next pickaxe, next layer, or Ascend).
- **Red arrow trail** on the ground from you to the current objective.
- **Avatar headshot tags** over every player, with name, level, 👑 VIP and ⭐ Ascension.

- **Big, spread-out map** (about 550 × 590 studs): the mine yard with 9 shafts sits in the middle, the pickaxe and backpack stalls line the main road, and the spawn plaza, museum, pet shop, Ascension shrine, training rocks and pond each have their own space.
- **Themed eggs:** the Dirt Egg has a grassy top with flowers, the Cave Egg has glowing orange crystals and cracks, the Crystal Egg is see-through glass with a pink crystal inside, and the Void Egg is dark with neon cracks and orbiting moons. The pets inside each egg float above its stand, and hatching shows the real 3D egg shaking.
- **Pets:** a round, mossy Rock Golem with a glowing crystal heart, dragons with belly plates, wing bones and tail spikes, brighter Void pets, and a little gold crown on every Legendary and Exclusive pet.

## Sound and music

- **Music:** licensed APM tracks (*Happy Song*, *Breezy Days*, *Relaxed Scene*) that play on a loop and get quieter underground.
- **Ambience:** forest wind on the surface fades into an eerie cave hum as you dig.
- **Sound effects:** pickaxe hits, block breaks, ore dings, cash register, level-up, egg cracks, and UI pops and clicks.
- **Fallbacks:** every sound lists fallback IDs, ending with Roblox's built-in sounds. If an ID can't load, the game switches to the next one and prints a warning in Output. To swap a sound, edit `SOUNDS`, `MUSIC` or `AMBIENCE` at the top of `DigDeepClient`.
- **⚙️ Settings** (saved per player): music on/off and volume, sound effects on/off and volume, ambience, other players' pets, screen shake.

## Retention features

- **Welcome back:** your pets keep digging while you're offline (15% of your normal rate, up to 8 h), and a popup reminds you when your daily chest is ready.
- **📜 Daily Quests:** three per day, the same for everyone, reset at midnight UTC. Finish all three for a free egg and a Luck potion. The Quests window has an Invite Friends button.
- **Next-goal bar** above your bag, showing progress to your next pickaxe (or to Ascension).
- **🏆 Top Miners board** by spawn: a global leaderboard where Ascensions outrank depth. It needs API access; in Studio without it, it ranks the current server.
- **Pet Index:** "📖 5/17" collection counter in the Pets window.
- **Guide beams** lead new players to their first pet and to the daily chest.

## What keeps players coming back

- **Treasures:** 8 rare finds, from an Old Boot near the surface to the Crown of the Deep below 360m, plus a 1-in-40,000 Rubber Duck anywhere. Each find gets a big reveal and is announced to the whole server. First finds and rare treasures are announced to the server. Repeat finds of common ones show as a small popup. Each one goes into the **Museum of the Deep**, which shows silhouettes for the ones you haven't found. Every unique treasure gives **+10% ore value forever**.
- **Gold Rush:** every 12 minutes on the UTC clock (the same moment in every server), ore is 3× more common for 90 seconds. The countdown sits under your coins.
- **Geodes:** now and then your next block is a glowing purple geode with lots of health and a big coin reward.
- **Daily chest:** a streak reward that grows each day, with triple on day 7. The reward scales with your pickaxe tier.
- **Friend bonus:** +10% ore value while a friend is in your server.
- Your **Depth** and **Coins** show on the player list.

## UI

The HUD has four things: coins (top), your bag (bottom), a depth gauge (right, only underground) and the Surface button (only underground). Shops, prices, the museum, the daily chest and the elevator are all physical objects in the world with floating labels. New players get one-line hints. When they can afford their first pickaxe, a golden beam leads them to it.

## Tuning

Every number is at the top of `DigDeepServer`: ores, layers, pickaxes, bags, treasures, event timings and mine size. The client reads them from the server, so you only change them in one place.

Sounds use built-in Roblox sounds. To use your own, replace the ids in the `SOUNDS` table at the top of `DigDeepClient`.

## How it was checked

- Both scripts type-check with **zero warnings** against the Roblox API (luau-lsp 1.70, in the same non-strict mode Studio uses).
- The server was run headlessly on an emulated Roblox instance tree. The run covered: world build, two players each getting their own mine, breaking slabs row by row, a full bag, the anti-cheat rejecting hits on someone else's slab, from outside the shaft and malformed hits, trespassers being sent back, selling, buying, the elevator, a treasure find, a geode, Strength, gifts, rebirth, training rocks, Ascension (a fresh mine) and a player leaving (their mine is freed).
- The client ran against that server with every server event triggered, including real hold-to-dig input and the R key to surface. It had no errors.
- This has **not** been played in the real Roblox engine yet. Things like animation feel, lighting and camera can only be judged in Studio.
