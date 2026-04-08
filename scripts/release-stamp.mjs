import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";

const root = process.cwd();
const pkgPath = path.join(root, "package.json");
const versionPath = path.join(root, "build", "version.json");
const backendInfoPath = path.join(root, "build", "build_info.txt");
const godotInfoPath = path.join(root, "ikaros", "build", "build_info.txt");
const releaseNotesPath = path.join(root, "RELEASE_NOTES.md");

const now = new Date();
const iso = now.toISOString();

function ensureDir(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function readJson(filePath, fallback) {
  if (!fs.existsSync(filePath)) return fallback;
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return fallback;
  }
}

const pkg = readJson(pkgPath, { version: "0.0.0" });
const state = readJson(versionPath, { build: 0 });
const build = Number(state.build || 0) + 1;
const version = String(pkg.version || "0.0.0");
const stamp = `v${version}+b${build}`;
const buildLine = `${stamp} | ${iso}`;

ensureDir(versionPath);
fs.writeFileSync(
  versionPath,
  JSON.stringify({ version, build, stamped_at: iso }, null, 2) + "\n",
  "utf8",
);

ensureDir(backendInfoPath);
fs.writeFileSync(backendInfoPath, buildLine + "\n", "utf8");

ensureDir(godotInfoPath);
fs.writeFileSync(godotInfoPath, buildLine + "\n", "utf8");

let commits = [];
try {
  const raw = execSync("git log --oneline -n 8", { encoding: "utf8" });
  commits = raw
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean)
    .map((l) => l.replace(/^[a-f0-9]+\s+/, ""));
} catch {
  commits = ["Build stamp update."];
}

const entry = [
  `## ${stamp}`,
  `- Date: ${iso}`,
  ...commits.slice(0, 5).map((c) => `- ${c}`),
  "",
].join("\n");

let existing = "";
if (fs.existsSync(releaseNotesPath)) {
  existing = fs.readFileSync(releaseNotesPath, "utf8");
}
if (!existing.startsWith("# Release Notes")) {
  existing = "# Release Notes\n\n" + existing;
}
const out = existing + (existing.endsWith("\n") ? "" : "\n") + entry;
fs.writeFileSync(releaseNotesPath, out, "utf8");

console.log(`Stamped ${stamp}`);
