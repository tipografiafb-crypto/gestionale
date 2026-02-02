// tools/build-mod-index.mjs
// Generates mod-index.json and MODULES.md from MODULE header blocks in code files

import { promises as fs } from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Scan from plugin directory, write to System_program
const SCAN_ROOT = process.argv[2] || path.resolve(__dirname, '../../wc-ai-product-customizer');
const OUTPUT_ROOT = path.resolve(__dirname, '..');
const OUT_JSON = path.join(OUTPUT_ROOT, "mod-index.json");
const OUT_MD   = path.join(OUTPUT_ROOT, "MODULES.md");

const isCode = (p) => /\.(js|jsx|ts|php|css|scss|vue)$/i.test(p);

async function walk(dir) {
  const out = [];
  try {
    const items = await fs.readdir(dir, { withFileTypes: true });
    for (const it of items) {
      const full = path.join(dir, it.name);
      if (it.name.startsWith('.') || it.name === 'node_modules' || it.name === 'vendor') continue;
      if (it.isDirectory()) out.push(...await walk(full));
      else if (it.isFile() && isCode(full)) out.push(full);
    }
  } catch (err) {
    // Skip inaccessible directories
  }
  return out;
}

function parseModuleHeader(src) {
  const m = src.match(/\/\*\s*MODULE([\s\S]*?)\*\//);
  if (!m) return null;
  const body = m[1];
  const fields = {};
  const lines = body.split("\n");
  for (let raw of lines) {
    const line = raw.trim();
    const kv = line.match(/^@([a-zA-Z0-9_-]+)\s*:\s*(.+)$/);
    if (!kv) continue;
    const key = kv[1].toLowerCase();
    let val = kv[2].trim();
    // Split by comma into array for some keys
    if (["domain","exports","consumes","events","touches","tests"].includes(key)) {
      val = val.split(",").map(s => s.trim()).filter(Boolean);
    }
    fields[key] = val;
  }
  return fields;
}

function toMarkdown(mods) {
  if (mods.length === 0) {
    return `# MODULES

> Generated automatically by \`tools/build-mod-index.mjs\`

No modules found with MODULE header blocks.
`;
  }

  const rows = mods.map(m =>
`| ${m.module || ""} | \`${m.path || ""}\` | ${Array.isArray(m.domain)?m.domain.join(", "):m.domain||""} | ${m.feature||""} | ${m.purpose||""} | ${m.risk||""} |`).join("\n");
  
  return `# MODULES

> Generated automatically by \`tools/build-mod-index.mjs\`

| Module | Path | Domain | Feature | Purpose | Risk |
|---|---|---|---|---|---|
${rows}

## Usage

Use this index to quickly locate modules by domain or feature:

### By Domain
${[...new Set(mods.flatMap(m => Array.isArray(m.domain) ? m.domain : [m.domain]).filter(Boolean))].sort().map(domain => 
  `- **${domain}**: ${mods.filter(m => (Array.isArray(m.domain) ? m.domain : [m.domain]).includes(domain)).map(m => m.module).join(", ")}`
).join("\n")}

### By Risk Level
${["HIGH", "MEDIUM", "LOW"].map(risk => 
  `- **${risk}**: ${mods.filter(m => m.risk === risk).map(m => m.module).join(", ") || "None"}`
).join("\n")}
`;
}

async function main() {
  console.log(`Scanning ${SCAN_ROOT} for MODULE headers...`);
  console.log(`Output will be written to ${OUTPUT_ROOT}`);
  const files = await walk(SCAN_ROOT);
  const modules = [];
  
  for (const fp of files) {
    try {
      const src = await fs.readFile(fp, "utf8");
      const meta = parseModuleHeader(src);
      if (meta) {
        // Fallback: put real path if not specified
        if (!meta.path) meta.path = path.relative(SCAN_ROOT, fp);
        modules.push(meta);
      }
    } catch (err) {
      // Skip files that can't be read
      console.warn(`Warning: Could not read ${fp}`);
    }
  }
  
  await fs.writeFile(OUT_JSON, JSON.stringify(modules, null, 2), "utf8");
  await fs.writeFile(OUT_MD, toMarkdown(modules), "utf8");
  console.log(`✓ Wrote ${OUT_JSON} and ${OUT_MD} (${modules.length} modules)`);
  
  if (modules.length === 0) {
    console.log("No MODULE headers found. Add /* MODULE ... */ blocks to your code files.");
  }
}

main().catch(e => { 
  console.error("Error:", e.message); 
  process.exit(1); 
});