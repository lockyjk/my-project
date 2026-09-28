# Project notes for Claude

## Roblox game art style (the owner wants this for EVERY game)

Every Roblox game made in this repo uses the bright, cartoony "front-page simulator" look,
like *Steal a Brainrot* / *Steal an Egg*. Do this by default without being asked.

**World**
- Ground: saturated lime-green **checkerboard** tiles, built from two alternating SmoothPlastic
  shades (about RGB 126,214,52 and 112,200,44). No realistic terrain textures.
- Map edge: tall **checkered dirt walls** (orange-brown two-tone tiles) with a thick
  **bright green grass trim** on top.
- Materials: SmoothPlastic everywhere, with saturated colors. Neon for glows, Glass for gems.
  Avoid realistic materials (WoodPlanks, Slate, Cobblestone, Marble...).
- Props: wooden cross-brace fences, blocky (voxel) trees and bushes, and striped shop stalls.
- Every interactable has a **glowing yellow neon circle pad** on the ground and a **big floating
  title** (stroked FredokaOne text, for example "TRAILS SHOP", with "FREE!" tags where relevant).
- Lighting: bright and sunny, with high ambient light, light shadows, a little bloom and extra
  saturation. No heavy fog or gloomy grading on the surface.

**Guidance ("tell the player what to do")**
- A **big objective banner** at the top center ("Steal an Egg!" style) that walks new players
  through multiple steps, then keeps giving the next goal forever.
- A **red arrow trail on the ground** from the player to the current objective.

**UI**
- Cartoony: chunky gradient buttons, thick dark outlines, rounded corners, bouncy tweens,
  emoji icons, a left-side button stack, and confetti on rewards.
- Round **avatar headshot** tags over players.

**Also always include** (what makes Roblox games succeed): understandable in 10 seconds, a
tight core loop, a visible next goal, reasons to return (daily rewards, offline earnings,
quests, timed events), social hooks, mobile-friendly controls, and fair, policy-safe
monetization (no Robux-bought random items).

**Constant rewards** (the "+1 ___ Per Click" hook): every click visibly gives something (a big
"+1" popup at the cursor with a pop sound), the first free reward lands within 10 seconds,
timed free gifts keep coming every few minutes, milestone bursts pay out often, and a rebirth
gives a permanent multiplier.

## Dig Deep (`dig-deep/`)
- Two scripts: `DigDeepServer.server.luau` and `DigDeepClient.client.luau`. Build a
  ready-to-play place with `rojo build dig-deep/default.project.json -o dig-deep/DigDeepOfficial.rbxlx`.
- Keep each script's top-level `local`s at 160 or fewer. Luau's register limit is 200 per
  function, and exceeding it stops the whole script from loading. Roblox counts every local,
  even constants that other Luau compilers fold away, so count them from the source (the old
  "compiles with N extra locals" check passed at 212 while Roblox refused the script). Put
  settings in the `K` table and HUD pieces in `U`, and wrap subsystems in `do` blocks.
