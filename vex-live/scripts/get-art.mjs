// Downloads the Higgsfield art and promo skits into the right folders: `npm run get-art`.
import { mkdir, writeFile } from "node:fs/promises";

const CDN = "https://d8j0ntlcm91z4.cloudfront.net/user_3FI3atLqvNU7ytGi1dslHTMQo8J/";
const FILES = {
  "overlay/avatars/vex.png": "hf_20261030_105956_dfe94647-ce70-496d-a27d-2165bad371de.png",
  "overlay/avatars/pip.png": "hf_20261030_105954_842f5822-2402-413d-9cb4-6fb7ef99d0a0.png",
  "art/lab-background.png": "hf_20261030_105419_076c8667-8847-4aa0-8911-ed999cdcd8b9.png",
  "art/poster.png": "hf_20261030_105416_113a8b1e-2066-4b0b-84d1-50614fa99ac7.png",
  "art/promo-1-gloop.mp4": "hf_20261030_110102_9c3e3e6b-13a7-443e-8cd5-b745880567c9.mp4",
  "art/promo-2-regret-o-matic.mp4": "hf_20261030_110102_b1bd7c1f-9df1-40cf-889b-e901adfa2fdf.mp4",
  "art/promo-3-genius.mp4": "hf_20261030_110102_c7046dae-6f03-4312-918e-b43d497c28f9.mp4",
};

const root = new URL("..", import.meta.url);
await mkdir(new URL("art/", root), { recursive: true });
for (const [dest, file] of Object.entries(FILES)) {
  const res = await fetch(CDN + file);
  if (!res.ok) {
    console.error(`x ${dest}: HTTP ${res.status}`);
    continue;
  }
  await writeFile(new URL(dest, root), Buffer.from(await res.arrayBuffer()));
  console.log(`saved ${dest}`);
}
