# Vex's Lab: AI TikTok LIVE

Professor Vex Quill (a burnt-out, sarcastic inventor) and Pip (his nervous apprentice) answer your TikTok LIVE comments out loud, in character:

```
TikTok LIVE comments, gifts, follows, likes
        → Claude writes Vex and Pip's reply (characters.md is their personality)
        → ElevenLabs speaks each line in that character's voice
        → overlay page shows subtitles and bounces whoever is talking
        → OBS captures it and streams it to TikTok
```

This runs on **your PC**, next to OBS.

## What's in here

| File | What it is |
|---|---|
| `characters.md` | The character bible: personalities, catchphrases, running gags, and the rules that keep the stream TikTok-safe. Edit it to change how they talk. |
| `src/index.js` | Connects to your live (or a fake chat for testing) and wires everything together. |
| `src/show.js` | The director: picks which comment to answer (gifts first, then questions and comments that talk to Vex or Pip), drops stale and blocked comments, has them chat when chat is quiet. |
| `src/brain.js` | Asks Claude for 1–3 short lines in character. |
| `src/voice.js` | ElevenLabs text-to-speech, one voice per character. |
| `overlay/index.html` | The OBS browser source: subtitles, the comment being answered, and the two characters. |
| `overlay/avatars/` | Put `vex.png` and `pip.png` here (transparent PNGs). Until then, coloured placeholders are shown. |

## Setup (Windows)

1. Install [Node.js](https://nodejs.org) 22 LTS or newer, and [OBS Studio](https://obsproject.com).
2. Get the code onto your PC (in Git Bash, PowerShell or a terminal):

   ```bash
   git clone -b claude/zealous-rubin-w0th4k https://github.com/lockyjk/my-project.git
   ```

   ```bash
   cd my-project/vex-live
   ```

   ```bash
   npm install
   ```

3. Try it with no keys at all. This uses canned replies:

   ```bash
   npm run demo
   ```

   Open http://localhost:5077 in Chrome, click once to allow sound, then type comments in the terminal like `kenny: vex what's your best invention?`.

4. Make your `.env`: copy `.env.example` to `.env` and fill it in:
   - `ANTHROPIC_API_KEY`: create one at https://platform.claude.com under API keys. It's pay-as-you-go: you need to add credit, and every reply costs a little.
   - `ELEVENLABS_API_KEY`, `VEX_VOICE_ID`, `PIP_VOICE_ID`: in ElevenLabs, pick or design two voices (Voice Library or Voice Design). For example, a dry, raspy older British man for Vex and a quick, squeaky, nervous young guy for Pip. Copy each voice's ID. Use designed or library voices; don't clone a real person's voice without their permission.
   - `TIKTOK_USERNAME`: your TikTok handle, without the @.

5. Test the real AI and voices without going live:

   ```bash
   npm run test-chat
   ```

   Extra test commands: `!gift kenny Rose 5`, `!follow kenny`, `!likes 1000`.

## Going live

1. In OBS, set the canvas to **1080×1920** (Settings → Video) for a portrait stream.
2. Add sources, bottom to top:
   - **Image or video**: your lab background.
   - **Browser**: URL `http://localhost:5077`, width 1080, height 1920. Tick **Control audio via OBS** so the voices go into the stream.
3. Stream from OBS to TikTok. You need TikTok LIVE access, and to stream from a PC you need TikTok LIVE Studio or a stream key; TikTok decides who gets a stream key. If you use TikTok LIVE Studio, add the same browser source there instead of OBS.
4. Go live, then start the bot:

   ```bash
   npm start
   ```

   It connects to your live and starts answering. Close it with Ctrl+C.

## Tuning

- **Faster or cheaper replies:** set `CLAUDE_MODEL=claude-haiku-5-5` in `.env`. The default is Claude Opus 5.5, which gives the best jokes.
- **More or less chatter when it's quiet:** `IDLE_SECONDS` in `.env`.
- **Who gets answered:** see the top of `src/show.js` (comment age limit, per-viewer cooldown, like milestones, and the `BLOCKED` patterns for comments that are never read out).
- **Refusals:** the Claude request has server-side fallbacks turned on, so if a reply is declined it is retried on another model automatically. Anything still declined is silently skipped.

## Stay on TikTok's good side

- Turn on TikTok's **AI-generated content** label for the live and the clips.
- The characters are told never to beg for gifts. TikTok punishes that, so keep it that way.
- Keep an eye on the terminal during the first few streams, and add anything nasty you see to `BLOCKED` in `src/show.js`.
