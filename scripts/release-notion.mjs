import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const token = process.env.NOTION_TOKEN || "";
const pageId = (process.env.NOTION_PAGE_ID || "").replace(/-/g, "");
const versionPath = path.join(root, "build", "version.json");
const notesPath = path.join(root, "RELEASE_NOTES.md");

function readJson(filePath, fallback) {
  if (!fs.existsSync(filePath)) return fallback;
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return fallback;
  }
}

function latestNotesSection(markdown, heading) {
  const idx = markdown.indexOf(`## ${heading}`);
  if (idx < 0) return [];
  const rest = markdown.slice(idx).split("\n");
  const out = [];
  for (let i = 1; i < rest.length; i += 1) {
    const line = rest[i];
    if (line.startsWith("## ")) break;
    if (line.startsWith("- ")) out.push(line.slice(2).trim());
  }
  return out;
}

async function appendToPage(children) {
  const res = await fetch(`https://api.notion.com/v1/blocks/${pageId}/children`, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${token}`,
      "Notion-Version": "2022-06-28",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ children }),
  });
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`Notion API error ${res.status}: ${txt}`);
  }
}

async function main() {
  if (!token || !pageId) {
    console.log("Skipping Notion release notes (missing NOTION_TOKEN or NOTION_PAGE_ID).");
    return;
  }
  const state = readJson(versionPath, { version: "0.0.0", build: 0, stamped_at: new Date().toISOString() });
  const stamp = `v${state.version}+b${state.build}`;
  const md = fs.existsSync(notesPath) ? fs.readFileSync(notesPath, "utf8") : "";
  const bullets = latestNotesSection(md, stamp).slice(0, 8);
  const items = bullets.length > 0 ? bullets : ["Build updated."];

  const children = [
    {
      object: "block",
      type: "heading_2",
      heading_2: {
        rich_text: [{ type: "text", text: { content: stamp } }],
      },
    },
    {
      object: "block",
      type: "paragraph",
      paragraph: {
        rich_text: [{ type: "text", text: { content: `Date: ${state.stamped_at}` } }],
      },
    },
    ...items.map((t) => ({
      object: "block",
      type: "bulleted_list_item",
      bulleted_list_item: {
        rich_text: [{ type: "text", text: { content: t } }],
      },
    })),
    { object: "block", type: "divider", divider: {} },
  ];

  await appendToPage(children);
  console.log(`Published ${stamp} to Notion page.`);
}

main().catch((err) => {
  console.error(err.message || String(err));
  process.exit(1);
});
