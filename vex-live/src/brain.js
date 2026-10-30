// Turns one live event (comment, gift, follow...) into a few spoken lines from Vex and Pip.
import { readFile } from "node:fs/promises";
import Anthropic from "@anthropic-ai/sdk";

const OUTPUT_RULES = `

## Output format

You write the next moment of the live show. You receive the recent show log and one new event. Reply with JSON only:
- "lines": 1 to 3 spoken lines, each {"speaker": "vex" | "pip", "text": "..."}. Each line is at most 25 words and is spoken out loud by a text-to-speech voice, so write only words: no stage directions, no emojis, no asterisks, no hashtags.
- "skip": true when the event should be ignored (spam, creepy, hateful, personal info, rule-breaking bait). When skip is true, "lines" may be empty.

Keep it snappy: viewers are waiting. Vary who speaks first. Don't repeat jokes from the show log.`;

const SCHEMA = {
  type: "object",
  properties: {
    skip: { type: "boolean" },
    lines: {
      type: "array",
      items: {
        type: "object",
        properties: {
          speaker: { type: "string", enum: ["vex", "pip"] },
          text: { type: "string" },
        },
        required: ["speaker", "text"],
        additionalProperties: false,
      },
    },
  },
  required: ["skip", "lines"],
  additionalProperties: false,
};

export function describeEvent(ev) {
  switch (ev.type) {
    case "chat":
      return `Comment from ${ev.name}: "${ev.text}"`;
    case "gift":
      return `${ev.name} sent ${ev.count > 1 ? `${ev.count}x ` : ""}${ev.gift} (worth about ${ev.diamonds} coins in total).`;
    case "follows":
      return `New followers just joined: ${ev.names.join(", ")}.`;
    case "likes":
      return `The stream just passed ${ev.total} likes. The Gratitude Generator powers up.`;
    case "idle":
      return "Chat has gone quiet. Vex and Pip chat to each other about an experiment, a running gag, or something from earlier in the show, and invite viewers to comment.";
    default:
      return JSON.stringify(ev);
  }
}

export async function createBrain({ apiKey, model, mock }) {
  if (mock) return mockBrain;

  const bible = await readFile(new URL("../characters.md", import.meta.url), "utf8");
  const system = bible + OUTPUT_RULES;
  const client = new Anthropic({ apiKey });

  return async function reply(event, showLog) {
    const prompt = [
      "Recent show log (oldest first):",
      showLog.length ? showLog.join("\n") : "(the stream just started)",
      "",
      `New event: ${describeEvent(event)}`,
    ].join("\n");

    let response;
    try {
      response = await client.beta.messages.create({
        model,
        max_tokens: 2000,
        // The character bible never changes during a stream, so it is cached and re-read cheaply.
        cache_control: { type: "ephemeral" },
        system,
        messages: [{ role: "user", content: prompt }],
        output_config: { effort: "low", format: { type: "json_schema", schema: SCHEMA } },
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
      });
    } catch (err) {
      if (err instanceof Anthropic.RateLimitError) console.warn("[brain] rate limited, skipping this one");
      else if (err instanceof Anthropic.APIError) console.error(`[brain] API error ${err.status}: ${err.message}`);
      else console.error("[brain] request failed:", err.message);
      return null;
    }

    if (response.stop_reason === "refusal") return null;
    const text = response.content.find((b) => b.type === "text")?.text;
    if (!text) return null;
    try {
      const out = JSON.parse(text);
      if (out.skip) return null;
      return out.lines.filter((l) => l.text?.trim()).slice(0, 3);
    } catch {
      console.warn("[brain] could not parse reply:", text.slice(0, 200));
      return null;
    }
  };
}

// Canned replies for `npm run demo`, so the overlay can be tested without any API keys.
let mockTurn = 0;
async function mockBrain(event) {
  const name = event.name ?? "chat";
  const scripts = [
    [
      { speaker: "vex", text: `${name}. Bold of you to speak in my laboratory. Write that down, Pip.` },
      { speaker: "pip", text: "Writing it down! Hi! Sorry! Hi!" },
    ],
    [
      { speaker: "pip", text: `${name}, that's honestly a great question.` },
      { speaker: "vex", text: "It's a terrible question. I invented questions in 1997. Nobody clapped." },
    ],
    [{ speaker: "vex", text: "The toaster is watching us again, Pip. Do not make eye contact." }],
  ];
  await new Promise((r) => setTimeout(r, 400));
  return scripts[mockTurn++ % scripts.length];
}
