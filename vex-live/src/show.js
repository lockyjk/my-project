// The director: collects live events, picks what to answer next, and plays the replies one at a time.

const MAX_CHAT_AGE_MS = 45_000; // older comments are dropped, the moment has passed
const USER_COOLDOWN_MS = 60_000; // one answered comment per viewer per minute (gifts excepted)
const FOLLOW_BATCH_MS = 8_000; // follows within this window are welcomed together
const LIKE_MILESTONE = 1000;
const LOG_LINES = 14;

// Comments matching this are never read out or sent to the AI. Add words as you find them.
const BLOCKED = [
  /https?:\/\/|www\.|\.com\b/i,
  /\b(ignore|forget) (all|your|previous) (instructions|rules)\b/i,
  /\b(kys|kill yourself)\b/i,
  /\b\d{3}[\s.-]?\d{3}[\s.-]?\d{4}\b/, // phone numbers
];

export function createShow({ brain, voice, overlay, idleSeconds }) {
  const queue = [];
  const showLog = [];
  const lastAnswered = new Map();
  let follows = [];
  let followTimer = null;
  let nextLikeMilestone = LIKE_MILESTONE;
  let busy = false;
  let lastActivity = Date.now();

  function log(entry) {
    showLog.push(entry);
    if (showLog.length > LOG_LINES) showLog.shift();
  }

  function push(ev) {
    queue.push({ ...ev, at: Date.now() });
    pump();
  }

  const show = {
    chat(name, text) {
      text = text.trim().slice(0, 200);
      if (!text || BLOCKED.some((re) => re.test(text))) return;
      push({ type: "chat", name, text });
    },
    gift(name, gift, count, diamonds) {
      push({ type: "gift", name, gift, count, diamonds });
    },
    follow(name) {
      follows.push(name);
      followTimer ??= setTimeout(() => {
        push({ type: "follows", names: follows.slice(0, 5) });
        follows = [];
        followTimer = null;
      }, FOLLOW_BATCH_MS);
    },
    likes(total) {
      if (total < nextLikeMilestone) return;
      nextLikeMilestone = (Math.floor(total / LIKE_MILESTONE) + 1) * LIKE_MILESTONE;
      push({ type: "likes", total: Math.floor(total / LIKE_MILESTONE) * LIKE_MILESTONE });
    },
  };

  // Gifts first (biggest first), then follows and like milestones, then the newest comment,
  // preferring questions and comments that talk to Vex or Pip directly.
  function pickNext() {
    const now = Date.now();
    for (let i = queue.length - 1; i >= 0; i--) {
      const ev = queue[i];
      if (ev.type === "chat" && now - ev.at > MAX_CHAT_AGE_MS) queue.splice(i, 1);
    }
    if (!queue.length) return null;

    const score = (ev) => {
      if (ev.type === "gift") return 1000 + ev.diamonds;
      if (ev.type === "follows" || ev.type === "likes") return 500;
      const since = now - (lastAnswered.get(ev.name) ?? 0);
      let s = (ev.at - now) / 1000; // newer is better
      if (/\?/.test(ev.text)) s += 8;
      if (/\b(vex|pip|professor|gerald|toaster)\b/i.test(ev.text)) s += 10;
      if (/\broast\b|\binvent/i.test(ev.text)) s += 6;
      if (since < USER_COOLDOWN_MS) s -= 100;
      return s;
    };
    queue.sort((a, b) => score(b) - score(a));
    return queue.shift();
  }

  async function perform(ev) {
    const lines = await brain(ev, showLog);
    if (ev.type === "chat") log(`[${ev.name}] ${ev.text}`);
    else if (ev.type !== "idle") log(`[event] ${ev.type}: ${ev.name ?? ev.names?.join(", ") ?? ev.total}`);
    if (!lines?.length) return;
    if (ev.name) lastAnswered.set(ev.name, Date.now());

    // Start every voice clip at once, then play them in order.
    const clips = lines.map((l) => (voice ? voice(l.speaker, l.text) : Promise.resolve(null)));
    for (let i = 0; i < lines.length; i++) {
      const audio = await clips[i];
      console.log(`  ${lines[i].speaker.toUpperCase()}: ${lines[i].text}`);
      log(`${lines[i].speaker === "vex" ? "Vex" : "Pip"}: ${lines[i].text}`);
      await overlay.say({ ...lines[i], audio, replyTo: i === 0 && ev.type === "chat" ? `${ev.name}: ${ev.text}` : null });
    }
  }

  async function pump() {
    if (busy) return;
    busy = true;
    try {
      let ev;
      while ((ev = pickNext())) {
        lastActivity = Date.now();
        console.log(`> ${ev.type === "chat" ? `${ev.name}: ${ev.text}` : ev.type}`);
        await perform(ev);
      }
    } finally {
      busy = false;
    }
  }

  setInterval(async () => {
    if (busy || queue.length || Date.now() - lastActivity < idleSeconds * 1000) return;
    busy = true;
    lastActivity = Date.now();
    try {
      await perform({ type: "idle" });
    } finally {
      busy = false;
      pump();
    }
  }, 2000);

  return show;
}
