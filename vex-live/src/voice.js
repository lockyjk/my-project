// ElevenLabs text-to-speech: one voice per character, saved as an mp3 the overlay plays.
import { writeFile, readdir, unlink } from "node:fs/promises";

const AUDIO_DIR = new URL("../audio/", import.meta.url);

export function createVoice({ apiKey, voices }) {
  if (!apiKey) return null;
  let counter = 0;

  return async function speak(speaker, text) {
    const voiceId = voices[speaker];
    if (!voiceId) return null;
    try {
      const res = await fetch(
        `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=mp3_44100_128`,
        {
          method: "POST",
          headers: { "xi-api-key": apiKey, "content-type": "application/json" },
          body: JSON.stringify({ text, model_id: "eleven_flash_v2_5" }),
        },
      );
      if (!res.ok) {
        console.error(`[voice] ElevenLabs ${res.status}: ${(await res.text()).slice(0, 200)}`);
        return null;
      }
      const file = `${Date.now()}-${counter++}.mp3`;
      await writeFile(new URL(file, AUDIO_DIR), Buffer.from(await res.arrayBuffer()));
      return `/audio/${file}`;
    } catch (err) {
      console.error("[voice] request failed:", err.message);
      return null;
    }
  };
}

// Old clips are deleted when the bot starts so the folder doesn't grow forever.
export async function clearAudio() {
  for (const f of await readdir(AUDIO_DIR)) if (f.endsWith(".mp3")) await unlink(new URL(f, AUDIO_DIR));
}
