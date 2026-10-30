// Vex's Lab: TikTok LIVE comments -> Claude (in character) -> ElevenLabs voices -> OBS overlay.
//   npm start          connect to your TikTok LIVE
//   npm run test-chat  type fake comments in the terminal instead of going live
//   npm run demo       same, with canned replies and no API keys needed
import { createInterface } from "node:readline";
import { createBrain } from "./brain.js";
import { createVoice, clearAudio } from "./voice.js";
import { startOverlay } from "./overlay.js";
import { createShow } from "./show.js";

const args = new Set(process.argv.slice(2));
const testMode = args.has("--test");
const mock = args.has("--mock");
const env = process.env;

if (!mock && !env.ANTHROPIC_API_KEY) {
  console.error("Missing ANTHROPIC_API_KEY. Copy .env.example to .env and fill it in, or run `npm run demo`.");
  process.exit(1);
}
if (!testMode && !env.TIKTOK_USERNAME) {
  console.error("Missing TIKTOK_USERNAME in .env (or run `npm run test-chat` to try it without going live).");
  process.exit(1);
}

await clearAudio();
const brain = await createBrain({ apiKey: env.ANTHROPIC_API_KEY, model: env.CLAUDE_MODEL || "claude-opus-5-5", mock });
const voice = mock ? null : createVoice({
  apiKey: env.ELEVENLABS_API_KEY,
  voices: { vex: env.VEX_VOICE_ID, pip: env.PIP_VOICE_ID },
});
if (!voice) console.log("[voice] no ElevenLabs key: subtitles only");
const overlay = startOverlay(Number(env.PORT) || 5077);
const show = createShow({ brain, voice, overlay, idleSeconds: Number(env.IDLE_SECONDS) || 25 });

if (testMode) {
  console.log(`Test mode. Type comments as "name: message". Also:
  !gift name Rose 5      a gift (name, gift, count)
  !follow name           a follow
  !likes 1000            total likes`);
  createInterface({ input: process.stdin }).on("line", (line) => {
    const [cmd, ...rest] = line.trim().split(/\s+/);
    if (cmd === "!gift") return show.gift(rest[0] ?? "viewer", rest[1] ?? "Rose", Number(rest[2]) || 1, (Number(rest[2]) || 1) * 5);
    if (cmd === "!follow") return show.follow(rest[0] ?? "viewer");
    if (cmd === "!likes") return show.likes(Number(rest[0]) || 0);
    const m = line.match(/^\s*([^:]{1,30}):\s*(.+)$/);
    if (m) show.chat(m[1].trim(), m[2]);
    else if (line.trim()) show.chat("viewer", line);
  });
} else {
  const { TikTokLiveConnection, WebcastEvent, ControlEvent, SignConfig } = await import("tiktok-live-connector");
  if (env.EULER_API_KEY) SignConfig.apiKey = env.EULER_API_KEY;
  const connection = new TikTokLiveConnection(env.TIKTOK_USERNAME, { enableExtendedGiftInfo: true });
  const nameOf = (data) => data.user?.nickname || data.user?.uniqueId || "someone";

  connection.on(WebcastEvent.CHAT, (data) => show.chat(nameOf(data), data.comment ?? ""));
  connection.on(WebcastEvent.GIFT, (data) => {
    // Streakable gifts fire repeatedly; only react once the streak ends.
    if (data.giftDetails?.giftType === 1 && !data.repeatEnd) return;
    const count = data.repeatCount || 1;
    const diamonds = (data.giftDetails?.diamondCount ?? data.extendedGiftInfo?.diamond_count ?? 1) * count;
    show.gift(nameOf(data), data.giftDetails?.giftName ?? "a gift", count, diamonds);
  });
  connection.on(WebcastEvent.FOLLOW, (data) => show.follow(nameOf(data)));
  connection.on(WebcastEvent.LIKE, (data) => show.likes(data.totalLikeCount ?? 0));
  connection.on(WebcastEvent.STREAM_END, () => {
    console.log("Stream ended.");
    process.exit(0);
  });
  connection.on(ControlEvent.DISCONNECTED, () => console.warn("[tiktok] disconnected"));

  try {
    const state = await connection.connect();
    console.log(`[tiktok] connected to @${env.TIKTOK_USERNAME} (room ${state.roomId}). Waiting for comments...`);
  } catch (err) {
    console.error(`[tiktok] could not connect to @${env.TIKTOK_USERNAME}. Are you live right now?`, err.message ?? err);
    process.exit(1);
  }
}
