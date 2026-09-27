# ⛏ Dig Deep

*Dig down. Find treasure. Go deeper.*

A Roblox mining game made of two scripts. The server script builds the whole world when the game starts, so there are no models or assets to import.

## Put it in a place (2 minutes)

1. In Roblox Studio, create a new **Baseplate** place. The script removes the baseplate and spawn for you.
2. **ServerScriptService** → Insert Object → **Script**. Name it `DigDeepServer` and paste in [`DigDeepServer.server.luau`](DigDeepServer.server.luau).
3. **StarterPlayer → StarterPlayerScripts** → Insert Object → **LocalScript**. Name it `DigDeepClient` and paste in [`DigDeepClient.client.luau`](DigDeepClient.client.luau).
4. Press **Play**.

To keep progress between sessions, turn on **Game Settings → Security → Enable Studio Access to API Services**. Without it the game still works, but progress resets when you stop.

## How it plays

| | |
|---|---|
| **Dig** | Hold left click (or hold your finger on a phone) on a block within reach. |
| **Sell** | Tap **⬆ SURFACE** (or press **R**). It teleports you onto the gold sell pad, which sells your bag. |
| **Upgrade** | Walk up to a pickaxe or backpack on the market stalls and press **E** to buy it. Prices turn green when you can afford them. |
| **Go deeper** | Topsoil → Stone (15m) → Deepstone (40m) → Magma Rock (80m) → Crystal Caves (130m) → The Void (200m) → bedrock at 300m. Each layer has richer ore and harder blocks. |
| **Elevator** | Takes you straight to your deepest 25m checkpoint. |

## What keeps players coming back

- **Treasures:** 8 rare finds, from an Old Boot near the surface to the Crown of the Deep below 220m, plus a 1-in-40,000 Rubber Duck anywhere. Each find gets a big reveal and is announced to the whole server. It then goes into the **Museum of the Deep**, which shows silhouettes for the ones you haven't found. Every unique treasure gives **+10% ore value forever**.
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
