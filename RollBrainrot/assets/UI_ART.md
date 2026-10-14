# UI art (Higgsfield)

There are 24 images for the HUD, menu buttons, roll button, logo and Zoo window banners. They were generated with Higgsfield (`gpt_image_2_5`, transparent backgrounds for icons) in a chunky, glossy cartoon style that matches the game.

Every image spot is optional. The UI reads `GameConfig.UIImages[key]`. While a key is `""`, that spot shows the old emoji or gradient instead. You can upload some images and not others.

## 1. Download

**One zip, already prepared for Roblox:** [RollBrainrot_UI_Art.zip](https://d2ol7oe51mr4n9.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/f29a6a5e-082c-43ec-8a3e-cb406677193c.zip), about 5 MB.

The zip contains the following:
- Icons are trimmed and resized to 256×256 with transparency.
- Habitat banners are cropped to 768×430.
- The logo is trimmed and resized to 768 px wide.
- Files are named by key, e.g. `menu_Zoo.png`.

Unzip it into `RollBrainrot/assets/ui/`.

## 2. Upload and wire up

### Automatic (recommended)

1. Create an Open Cloud API key with these settings:
   - Go to create.roblox.com → Open Cloud → API Keys.
   - Add the **Assets** API with Read and Write.
   - Allow your IP.
2. Run this command from `RollBrainrot/`:

   ```sh
   ROBLOX_API_KEY=... ROBLOX_USER_ID=<your user id> lune run scripts/upload-ui-art
   # group game: ROBLOX_GROUP_ID=<group id> instead of ROBLOX_USER_ID
   ```

   The script uploads each `assets/ui/<key>.png` and writes `rbxassetid://…` into `GameConfig.UIImages`. Keys that are already set are skipped, so you can safely re-run it.
3. If you use `rojo serve`, the change syncs into Studio straight away.

### Manual

1. In Studio, open **View → Asset Manager → Bulk Import** and select the PNGs.
2. Right-click each image → **Copy Asset ID**.
3. Paste it into `GameConfig.UIImages` as `"rbxassetid://123…"`.

Either way, new uploads may show as blank for a few minutes while Roblox moderation reviews them.

## Images

| Key | Used for | Picture | Full-res original |
|---|---|---|---|
| `coins` | HUD coin counter | stack of gold coins | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014323_719484c5-050b-48cc-bbf1-c7c0992f3d2e.png) |
| `gems` | HUD gem counter | blue diamond | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014323_f29588a2-d2b7-4cad-aaaf-8a6300b08bea.png) |
| `tokens` | HUD roll tokens | pink star ticket | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014234_877a4bd5-6170-4d88-9f56-1df7d618a1a6.png) |
| `essence` | HUD essence | green bubbling potion | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014233_6f29908f-c9d7-48ee-9e2f-e31cf715a7c8.png) |
| `bossTokens` | HUD boss tokens | red devil medallion | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014233_19e3ab3d-ece2-43f7-a823-4aa02de94690.png) |
| `roll` | Roll button | cracking rainbow egg | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014322_a5336818-3809-4faa-bd3f-528cfd38dfd1.png) |
| `star` | Zoo rating stars | smiling gold star | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014635_39708eca-f93e-415c-9e02-03f42ec66568.png) |
| `heart` | Spare (petting) | pink paw heart | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014635_44ba9556-712a-41b6-b00e-2acffa3f9ab4.png) |
| `menu_Collection` | Menu: Collection | card album | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014233_38dfd99e-d888-4e85-85d1-497dcedde82b.png) |
| `menu_Zoo` | Menu: Zoo | zoo gate | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014234_0cd3e9c9-5f33-4c9a-8551-e007e6ada242.png) |
| `menu_Upgrades` | Menu: Upgrades | green arrow + wrench | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014233_9f5535da-c914-4968-8301-459665471582.png) |
| `menu_Shop` | Menu: Shop | market stall | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014323_ab3ec9a7-5c2a-4248-975d-312d9b6a196a.png) |
| `menu_Daily` | Menu: Daily | gift on a calendar | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014322_cb622208-e043-4a6e-9bae-d0f9c1912ebe.png) |
| `menu_Events` | Menu: Events | storm cloud + lightning | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014232_77e0b8ff-cd88-4d90-8e3b-b521b85de199.png) |
| `menu_Arena` | Menu: Arena | crossed swords + castle | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014232_0a57c5b7-3a4e-4cbe-8f8e-58c7a5a1a47c.png) |
| `menu_Settings` | Menu: Settings | gear | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014323_30e1e0e3-3889-4f88-9ed8-a89f256ba0c3.png) |
| `habitat_Grass` | Zoo card banner | meadow pen + pond | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014618_edc25b02-444a-4726-88b4-c698c772f304.png) |
| `habitat_Forest` | Zoo card banner | pine forest + cave | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014334_b7d02300-1ee4-43f8-8862-20a706e2db81.png) |
| `habitat_Desert` | Zoo card banner | canyon + oasis | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014618_19a52db4-2f70-4319-a6ca-5124b6bd6244.png) |
| `habitat_Ice` | Zoo card banner | ice crystals + glacier pool | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014618_bc8e0909-e265-413c-9d4f-f1e5b911808d.png) |
| `habitat_Volcano` | Zoo card banner | volcano + lava rivers | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014627_da695459-0877-4a8a-bd6b-cda0851abfea.png) |
| `habitat_Alien` | Zoo card banner | crystal crater + UFO | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014334_776277d7-887a-48a3-b8ca-a91ca27135d4.png) |
| `habitat_Giant` | Zoo card banner | giant jungle + golden fence | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014626_b3177c9f-36f6-4b99-975a-7f5f73ec8aa2.png) |
| `logo` | Top-centre HUD logo | ROLL BRAINROT wordmark | [png](https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/hf_20261014_014627_340c0b34-b1c1-4399-ae4e-56c700100d86.png) |

The original links are Higgsfield's CDN copies (1024², or 1344×752 for banners). The same images are also in your Higgsfield library under 14 Oct 2026.
