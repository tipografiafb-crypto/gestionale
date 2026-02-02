/**
 * Enforce @feature tags on changed JS/PHP files.
 * Reads staged files and fails if a changed file lacks a @feature or @domain tag
 * in its leading comment block (first 50 lines).
 */
import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from 'url';

// Get current directory in ES modules
const __dirname = path.dirname(fileURLToPath(import.meta.url));

const exts = new Set([".js", ".jsx", ".ts", ".tsx", ".php"]);
// Use git to find root, which is reliable
const root = execSync("git rev-parse --show-toplevel").toString().trim();

function getStagedFiles() {
  const out = execSync("git diff --cached --name-only").toString();
  return out.split("\n").filter(Boolean);
}

function hasFeatureTag(filePath) {
  try {
    // Read first 50 lines only
    const data = fs.readFileSync(filePath, "utf8").split(/\r?\n/).slice(0, 50).join("\n");
    // Accept both @feature and @domain tags
    const re = /@feature\s*:\s*([\w-.,/]+)|@domain\s*:\s*([\w-.,/]+)/i;
    return re.test(data);
  } catch (e) {
    return false;
  }
}

const staged = getStagedFiles();
let errors = [];

for (const rel of staged) {
  const abs = path.join(root, rel);
  const ext = path.extname(rel);
  if (!exts.has(ext)) continue;
  
  try {
    if (!fs.existsSync(abs) || fs.statSync(abs).isDirectory()) continue;

    if (!hasFeatureTag(abs)) {
        errors.push(rel);
    }
  } catch (e) {
    // Ignore errors for deleted files or other issues
    continue;
  }
}

if (errors.length) {
  console.error("\n[enforce-file-tags] Missing @feature/@domain tag in files:");
  for (const f of errors) console.error("  - " + f);
  console.error("\nAdd a header like:");
  console.error("  /**");
  console.error("   * @feature: canvas-export");
  console.error("   * @owner: team/Paolo");
  console.error("   * @stability: stable");
  console.error("   */");
  process.exit(1);
}
