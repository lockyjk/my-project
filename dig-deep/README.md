# ⛏ Dig Deep

*Dig down. Find treasure. Go deeper.*

A Roblox mining game made of two scripts. The server script builds the whole world when the game starts, so there are no models or assets to import.

## Play it

Open **`DigDeep.rbxlx`** in Roblox Studio and press Play. The place file already contains both scripts, Future lighting, and a kill floor set low enough for the 500m mine.

## Or put the scripts in your own place (2 minutes)

1. In Roblox Studio, create a new **Baseplate** place. The script removes the baseplate and spawn for you.
2. **ServerScriptService** → Insert Object → **Script**. Name it `DigDeepServer` and paste in [`DigDeepServer.server.luau`](DigDeepServer.server.luau).
3. **StarterPlayer → StarterPlayerScripts** → Insert Object → **LocalScript**. Name it `DigDeepClient` and paste in [`DigDeepClient.client.luau`](DigDeepClient.client.luau).
4. Set **Workspace → FallenPartsDestroyHeight** to `-4000`, because the mine goes 3000 studs down. Also set **Lighting → Technology** to **Future** for the intended look.
5. Press **Play**.

To keep progress between sessions, turn on **Game Settings → Security → Enable Studio Access to API Services**. Without it the game still works, but progress resets when you stop.

## How it plays

| | |
|---|---|
| **Dig** | Hold left click (or hold your finger on a phone) on a block within reach. |
| **Sell** | Tap **⬆ SURFACE** (or press **R**). It teleports you onto the gold sell pad, which sells your bag. |
| **Upgrade** | Walk up to a pickaxe or backpack on the market stalls and press **E** to buy it. Prices turn green when you can afford them. |
| **Go deeper** | Topsoil → Stone (20m) → Deepstone (60m) → Magma Rock (120m) → Crystal Caves (200m) → The Void (300m) → The Core (420m) → bedrock at 500m. Each layer has richer ore and harder blocks. |
| **Ascend** | Once you've reached bedrock, use the Ascension Shrine next to the museum. It resets your coins, gear and depth but keeps your treasures, and gives +50% ore value forever each time. |
| **Elevator** | Takes you straight to your deepest 25m checkpoint. |

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
- **Cartoony UI:** a button stack on the left (Shop, Pets, Spin, Codes, Offer), chunky gradient buttons, bouncy windows, confetti, and a level-up burst.

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
- **Earthquakes:** every 30 minutes, or when the mine gets too big, there's a 20-second warning with screen shake. Then the mine resets with fresh ore and everyone underground is sent back up.
- **Geodes:** purple glowing blocks with lots of health. *Everyone* who hits one gets the full reward, so strangers team up.
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
- The server was run headlessly on an emulated Roblox instance tree. The run covered: world build, two players joining, digging 30 rows, a full bag, the anti-cheat rejecting out-of-reach and malformed hits, selling, buying, the daily chest, the elevator, a treasure find, a shared geode, an earthquake reset and a player leaving.
- The client ran against that server with every server event triggered, including real hold-to-dig input and the R key to surface. It had no errors.
- This has **not** been played in the real Roblox engine yet. Things like animation feel, lighting and camera can only be judged in Studio.
