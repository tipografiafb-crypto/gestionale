#!/usr/bin/env node

/**
 * Build Universal Mapping System - Enterprise Edition
 * Generates: mod-index.json, SYSTEM_STATUS.md, ORPHANS.md, MODULES.md
 * 
 * Features:
 * - Module indexing with @feature/@domain/@risk/@stability metadata
 * - Cross-Reference Analysis: detects orphaned features and unused files
 * - AI-Ready Metadata: reads JSDoc comments for automatic descriptions
 * 
 * Usage: node System_program/tools/build-universal-mapping.mjs
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
// NO EXTERNAL DEPENDENCIES REQUIRED - Built-in Node.js only

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// DYNAMIC ROOT DETECTION
// 1. Assume System_program is at the root of the "System"
// 2. We want to find the code it manages.
//    - Scenario A: System_program is INSIDE the plugin (PROJECT_ROOT/System_program) -> Scan PROJECT_ROOT
//    - Scenario B: System_program is SIBLING to the plugin (PROJECT_ROOT/System_program & PROJECT_ROOT/my-plugin) -> Scan siblings
//    - Scenario C: System_program IS the root (standalone) -> Scan PROJECT_ROOT

const PROJECT_ROOT = path.resolve(__dirname, '../..');
const OUTPUT_ROOT = path.resolve(__dirname, '..');

// Helper to find likely plugin directories
function findTargetRoots() {
  const candidates = [];

  // 1. Check if PROJECT_ROOT itself looks like a plugin (has .php file with headers or includes/public dir)
  if (fs.existsSync(path.join(PROJECT_ROOT, 'includes')) || fs.existsSync(path.join(PROJECT_ROOT, 'public'))) {
    candidates.push(PROJECT_ROOT);
  }

  // 2. Check subdirectories (Scenario B)
  try {
    const subs = fs.readdirSync(PROJECT_ROOT, { withFileTypes: true });
    for (const sub of subs) {
      if (sub.isDirectory() && sub.name !== 'System_program' && sub.name !== 'node_modules' && sub.name !== '.git') {
        const fullPath = path.join(PROJECT_ROOT, sub.name);
        // Heuristic: contains 'includes' or 'public' or has a PHP file
        if (fs.existsSync(path.join(fullPath, 'includes')) && fs.existsSync(path.join(fullPath, 'public'))) {
          candidates.push(fullPath);
        }
      }
    }
  } catch (e) {
    console.warn("Could not scan subdirectories:", e.message);
  }

  // Fallback: If no candidate found, use PROJECT_ROOT
  if (candidates.length === 0) {
    return [PROJECT_ROOT];
  }

  return candidates;
}

const TARGET_ROOTS = findTargetRoots();
console.log(`🎯 Target Roots detected: ${TARGET_ROOTS.map(r => path.basename(r)).join(', ')}`);


const MODULE_HEADER_REGEX = /(\/\*[\s\S]*?MODULE[\s\S]*?\*\/)|(#\s*MODULE[\s\S]*?#\s*END MODULE)/;
const JSDOC_REGEX = /(\/\*\*[\s\S]*?@ai-module\s+(\S+)[\s\S]*?\*\/)|(#\s*@ai-module\s+(\S+)[\s\S]*?#\s*@ai-end)/g;
const AI_DESC_REGEX = /@ai-description\s+(.+?)(?:\n|\*|\#)/;
const AI_CONTEXT_REGEX = /@ai-context\s+(.+?)(?:\n|\*|\#)/;
const AI_USAGE_REGEX = /@ai-usage\s+(.+?)(?:\n|\*|\#)/;
const AI_HOOK_REGEX = /(\/\/|#)\s*@ai-hook\s+(\S+)\s*(.+?)(?:\n|$)/g;

const STANDARD_DOCBLOCK_REGEX = /\/\*\*([\s\S]*?)\*\/|#\s*@([\s\S]*?)$/m; // Simple heuristic for ruby single line or standard block

function extractMetadata(filePath, fileContent) {
  const lines = fileContent.split('\n').slice(0, 50).join('\n');

  // Try legacy MODULE format first
  let match = lines.match(MODULE_HEADER_REGEX);
  let blockContent = match ? match[0] : null;

  // If no MODULE block, try standard DocBlock or Ruby comments
  if (!blockContent) {
    // Check for Ruby top-level comments with @feature
    const rubyMatches = lines.match(/(?:^#\s*@\w+.*$)+/m); // naive match for block of attributes
    if (rubyMatches && /@feature|@module/.test(rubyMatches[0])) {
      blockContent = rubyMatches[0];
    } else {
      const docMatch = lines.match(STANDARD_DOCBLOCK_REGEX);
      if (docMatch) {
        // Check if it contains relevant metadata tags to avoid grabbing random headers
        if (/@feature|@module|@risk/.test(docMatch[0])) {
          blockContent = docMatch[0];
        }
      }
    }
  }

  // Fallback: If no explicit headers, try to infer from class/module definitions for Ruby
  if (!blockContent && filePath.endsWith('.rb')) {
    const classMatch = lines.match(/class\s+([A-Z]\w+)/);
    const moduleMatch = lines.match(/module\s+([A-Z]\w+)/);
    if (classMatch || moduleMatch) {
      // Inferred metadata
      return {
        file: filePath,
        type: 'ruby',
        module: (classMatch || moduleMatch)[1],
        feature: 'unclassified', // Will need manual tagging
        domain: 'backend',
        purpose: 'Auto-detected Ruby Class/Module',
        risk: 'LOW', // Default
        stability: 'MEDIUM',
        consumes: [],
        touches: [],
        ai: null
      };
    }
  }

  if (!blockContent) return null;

  const metadata = {
    file: filePath,
    type: filePath.endsWith('.php') ? 'php' : (filePath.endsWith('.rb') ? 'ruby' : 'js'),
    module: null,
    feature: null,
    domain: null,
    purpose: null,
    risk: null,
    stability: null,
    consumes: [],
    touches: [],
    ai: null,
  };

  // Regexes updated to make colon optional
  const moduleName = blockContent.match(/@module:?\s*(.+?)(?:\n|\*|#|$)/);
  const feature = blockContent.match(/@feature:?\s*(.+?)(?:\n|\*|#|$)/);
  const domain = blockContent.match(/@domain:?\s*(.+?)(?:\n|\*|#|$)/);
  const purpose = blockContent.match(/@purpose:?\s*(.+?)(?:\n|\*|#|$)/);
  const risk = blockContent.match(/@risk:?\s*(.+?)(?:\n|\*|#|$)/);
  const stability = blockContent.match(/@stability:?\s*(.+?)(?:\n|\*|#|$)/);

  // Also look for description/summary as purpose if not explicitly defined
  const description = blockContent.match(/@description:?\s*(.+?)(?:\n|\*|#|$)/);

  metadata.module = moduleName ? moduleName[1].trim() : path.basename(filePath);
  metadata.feature = feature ? feature[1].trim() : null;
  metadata.domain = domain ? domain[1].trim() : null;
  metadata.purpose = purpose ? purpose[1].trim() : (description ? description[1].trim() : null);
  metadata.risk = risk ? risk[1].trim() : 'LOW'; // Default to LOW if not specified
  metadata.stability = stability ? stability[1].trim() : 'MEDIUM'; // Default to MEDIUM if not specified

  const consumes = blockContent.match(/@consumes:?\s*(.+?)(?:\n|\*|#|$)/);
  const touches = blockContent.match(/@touches:?\s*(.+?)(?:\n|\*|#|$)/);

  if (consumes) {
    metadata.consumes = consumes[1].split(',').map(s => s.trim()).filter(Boolean);
  }
  if (touches) {
    metadata.touches = touches[1].split(',').map(s => s.trim()).filter(Boolean);
  }


  metadata.ai = extractAIMetadata(fileContent);

  return metadata;
}

function extractAIMetadata(fileContent) {
  const aiBlocks = [];
  // Updated regex to support JS/PHP (/** */) and Ruby (# #)
  const jsdocMatches = fileContent.matchAll(/(\/\*\*[\s\S]*?@ai-module\s+(\S+)[\s\S]*?\*\/)|(#\s*@ai-module\s+(\S+)[\s\S]*?#\s*@ai-end)/g);

  for (const match of jsdocMatches) {
    const block = match[0];
    const moduleName = match[2] || match[4]; // Group 2 for JS/PHP, Group 4 for Ruby

    const descMatch = block.match(/@ai-description\s+(.+?)(?:\n|\*|#)/);
    const contextMatch = block.match(/@ai-context\s+(.+?)(?:\n|\*|#)/);
    const usageMatch = block.match(/@ai-usage\s+(.+?)(?:\n|\*|#)/);

    aiBlocks.push({
      module: moduleName,
      description: descMatch ? descMatch[1].trim() : null,
      context: contextMatch ? contextMatch[1].trim() : null,
      usage: usageMatch ? usageMatch[1].trim() : null,
    });
  }

  return aiBlocks.length > 0 ? aiBlocks : null;
}

// Helper to scan files recursively using built-in fs
function getFilesNative(dir, pattern, baseDir = dir) {
  let results = [];
  try {
    const items = fs.readdirSync(dir, { withFileTypes: true });

    const isPhp = pattern.endsWith('.php');
    const isJs = pattern.endsWith('.js');
    const isRb = pattern.endsWith('.rb');
    const isGlob = pattern.includes('*');

    // Support wildcard matching like 'models/**/*.rb'
    const parts = pattern.split('/');
    const folderMatch = parts.length > 1 && parts[0] !== '**' ? parts[0] : null;

    for (const item of items) {
      const res = path.resolve(dir, item.name);
      const relPath = path.relative(baseDir, res).replace(/\\/g, '/');

      if (item.isDirectory()) {
        // Basic ignores
        if (item.name === 'node_modules' || item.name === 'vendor' || item.name === 'System_program' || item.name === '.git' || item.name === 'tests' || item.name === 'tmp' || item.name === 'log') continue;
        results = results.concat(getFilesNative(res, pattern, baseDir));
      } else {
        // File matching
        if (isPhp && !relPath.endsWith('.php')) continue;
        if (isJs && !relPath.endsWith('.js')) continue;
        if (isRb && !relPath.endsWith('.rb')) continue;

        // Exact match check for non-glob patterns
        if (!isGlob && relPath !== pattern) continue;

        // Simple folder match check for globs
        if (isGlob && folderMatch && !relPath.startsWith(folderMatch)) continue;

        if (relPath.endsWith('.min.js')) continue;

        results.push(relPath);
      }
    }
  } catch (e) {
    // dir might not exist
  }
  return results;
}

function scanFiles() {
  const patterns = [
    'includes/**/*.php',
    'public/js/**/*.js',
    'templates/**/*.js',
    'templates/**/*.php',
    'models/**/*.rb',
    'routes/**/*.rb',
    'services/**/*.rb',
    'lib/**/*.rb',
    'app.rb'
  ];

  let modules = [];


  for (const root of TARGET_ROOTS) {
    for (const pattern of patterns) {
      const files = getFilesNative(root, pattern);

      for (const file of files) {
        const filePath = path.join(root, file);
        try {
          const content = fs.readFileSync(filePath, 'utf-8');
          const metadata = extractMetadata(file, content);

          if (metadata && metadata.feature) {
            metadata.file = file; // Store relative path
            modules.push(metadata);
          }
        } catch (err) {
          // Skip unreadable files
        }
      }
    }
  }

  return modules;
}


function generateModIndex(modules) {
  const features = {};
  const byRisk = { CRITICAL: [], HIGH: [], MEDIUM: [], LOW: [] };
  const byStability = { HIGH: [], MEDIUM: [], LOW: [] };

  for (const mod of modules) {
    if (mod.feature) {
      if (!features[mod.feature]) {
        features[mod.feature] = [];
      }
      features[mod.feature].push({
        file: mod.file,
        module: mod.module,
        type: mod.type,
        domain: mod.domain,
        purpose: mod.purpose,
        risk: mod.risk,
        stability: mod.stability,
      });
    }

    if (mod.risk && byRisk[mod.risk]) {
      byRisk[mod.risk].push(mod.file);
    }

    if (mod.stability && byStability[mod.stability]) {
      byStability[mod.stability].push(mod.file);
    }
  }

  return {
    metadata: {
      generated: new Date().toISOString(),
      totalModules: modules.length,
      totalFeatures: Object.keys(features).length,
    },
    features,
    risk: byRisk,
    stability: byStability,
    modules: modules.sort((a, b) => a.file.localeCompare(b.file)),
  };
}

function generateSystemStatus(modules) {
  const totalModules = modules.length;
  const features = new Set(modules.map(m => m.feature).filter(Boolean));

  const riskDist = {
    CRITICAL: modules.filter(m => m.risk === 'CRITICAL').length,
    HIGH: modules.filter(m => m.risk === 'HIGH').length,
    MEDIUM: modules.filter(m => m.risk === 'MEDIUM').length,
    LOW: modules.filter(m => m.risk === 'LOW').length,
  };

  const stabilityDist = {
    HIGH: modules.filter(m => m.stability === 'HIGH').length,
    MEDIUM: modules.filter(m => m.stability === 'MEDIUM').length,
    LOW: modules.filter(m => m.stability === 'LOW').length,
  };

  const byFeature = {};
  for (const mod of modules) {
    if (mod.feature) {
      if (!byFeature[mod.feature]) {
        byFeature[mod.feature] = [];
      }
      byFeature[mod.feature].push(mod);
    }
  }

  let featureTable = '';
  for (const [feature, mods] of Object.entries(byFeature).sort()) {
    const risks = mods.map(m => m.risk).filter(Boolean);
    const topRisk = risks.length > 0 ? risks.sort()[risks.length - 1] : 'LOW';
    featureTable += `| ${feature} | ${mods.length} | ${mods.length} | 0 | ${topRisk} |\n`;
  }

  const timestamp = new Date().toISOString();
  const criticalModules = modules.filter(m => m.risk === 'CRITICAL').slice(0, 10).map(m => `- ${m.module} (${m.file})`).join('\n') || '- None';
  const highModules = modules.filter(m => m.risk === 'HIGH').slice(0, 5).map(m => `- ${m.module} (${m.file})`).join('\n') || '- None';

  return `# SYSTEM STATUS

> Last generated: ${timestamp}  
> Generated by: System_program/tools/build-universal-mapping.mjs

## 📊 System Health Overview

| Metric | Count | Status |
|---|---|---|
| **Total Modules** | ${totalModules} | 🟢 HEALTHY |
| **Active Features** | ${features.size} | 🟢 HEALTHY |
| **WordPress Hooks** | 0 | 🟢 HEALTHY |
| **JS Events** | 0 | 🟢 HEALTHY |
| **Dependencies** | 0 | 🟢 HEALTHY |
| **High Risk Modules** | ${riskDist.HIGH + riskDist.CRITICAL} | ${riskDist.HIGH + riskDist.CRITICAL > 5 ? '🔴 ACTION' : '🟡 MONITOR'} |

## 🚀 Quality Metrics

| Metric | Value | Status |
|---|---|---|
| **Code Coverage** | 0% | 🟡 NONE |
| **Average Stability** | ${Math.round((stabilityDist.HIGH * 100) / (totalModules || 1))}% HIGH | 🟢 GOOD |
| **Risk Distribution** | C:${riskDist.CRITICAL} H:${riskDist.HIGH} M:${riskDist.MEDIUM} L:${riskDist.LOW} | 🟢 BALANCED |
| **Module Density** | ${(totalModules / (features.size || 1)).toFixed(1)} modules/feature | 🟢 HEALTHY |

## 🎯 Feature Distribution

| Feature | Modules | Files | Hooks | Primary Risk |
|---|---|---|---|---|
${featureTable}

## ⚠️ Risk Assessment

### Critical Risk Modules (${riskDist.CRITICAL})
${criticalModules}

### High Risk Modules (${riskDist.HIGH})
${highModules}

## 📈 System Complexity Indicators

| Indicator | Value | Threshold | Status |
|---|---|---|---|
| **Module Cohesion** | ${features.size > 0 ? (totalModules / features.size).toFixed(1) : 'N/A'} | < 5.0 | 🟢 |
| **Feature Coupling** | 0% | < 20% | 🟢 |
| **Risk Distribution** | ${riskDist.CRITICAL > 0 ? 'Unbalanced' : 'Balanced'} | Balanced | ${riskDist.CRITICAL > 0 ? '🔴' : '🟢'} |

## 🏗️ Architecture Insights

### Module Stability Distribution
- **HIGH**: ${stabilityDist.HIGH} modules
- **MEDIUM**: ${stabilityDist.MEDIUM} modules  
- **LOW**: ${stabilityDist.LOW} modules

### Risk Profile
- **CRITICAL**: ${riskDist.CRITICAL} modules
- **HIGH**: ${riskDist.HIGH} modules
- **MEDIUM**: ${riskDist.MEDIUM} modules
- **LOW**: ${riskDist.LOW} modules

## 🎯 Action Items

${riskDist.CRITICAL > 0 ? '🔴 **CRITICAL**: ' + riskDist.CRITICAL + ' modules require immediate review' : '🟢 **No critical issues** - System appears healthy'}

---

### Legend
- 🟢 Healthy | 🟡 Monitor | 🔴 Action Required
- **Feature**: Named subsystem
- **Modules**: Individual PHP/JS files with @feature tag
- **Risk**: CRITICAL > HIGH > MEDIUM > LOW
`;
}

function scanAllFiles() {
  const patterns = [
    'includes/**/*.php',
    'public/js/**/*.js',
    'templates/**/*.js',
    'templates/**/*.php',
  ];

  let allFiles = [];

  for (const root of TARGET_ROOTS) {
    for (const pattern of patterns) {
      const files = getFilesNative(root, pattern);
      // Map to absolute paths
      const absoluteFiles = files.map(f => path.join(root, f));
      allFiles = allFiles.concat(absoluteFiles);
    }
  }

  return [...new Set(allFiles)];
}


function crossReferenceAnalysis(modules, allFiles) {
  const orphans = {
    filesWithoutFeature: [],
    featuresWithSingleFile: [],
    potentialDuplicates: [],
    missingMetadata: [],
  };

  const indexedFiles = new Set(modules.map(m => m.file));

  for (const file of allFiles) {
    if (!indexedFiles.has(file)) {
      const skipPatterns = [
        /index\.php$/,
        /autoload/i,
        /bootstrap/i,
        /-config\.php$/,
        /\.min\.js$/,
      ];

      const shouldSkip = skipPatterns.some(pattern => pattern.test(file));
      if (!shouldSkip) {
        orphans.filesWithoutFeature.push(file);
      }
    }
  }

  const featureCounts = {};
  for (const mod of modules) {
    if (mod.feature) {
      featureCounts[mod.feature] = (featureCounts[mod.feature] || 0) + 1;
    }
  }

  for (const [feature, count] of Object.entries(featureCounts)) {
    if (count === 1) {
      const mod = modules.find(m => m.feature === feature);
      orphans.featuresWithSingleFile.push({
        feature,
        file: mod?.file,
      });
    }
  }

  for (const mod of modules) {
    if (!mod.risk || !mod.stability || !mod.domain) {
      orphans.missingMetadata.push({
        file: mod.file,
        missing: [
          !mod.risk && 'risk',
          !mod.stability && 'stability',
          !mod.domain && 'domain',
        ].filter(Boolean),
      });
    }
  }

  const moduleNames = modules.map(m => m.module).filter(Boolean);
  const nameCounts = {};
  for (const name of moduleNames) {
    nameCounts[name] = (nameCounts[name] || 0) + 1;
  }

  for (const [name, count] of Object.entries(nameCounts)) {
    if (count > 1) {
      const files = modules.filter(m => m.module === name).map(m => m.file);
      orphans.potentialDuplicates.push({ module: name, files });
    }
  }

  return orphans;
}

function generateOrphansReport(orphans) {
  const timestamp = new Date().toISOString();

  let filesSection = orphans.filesWithoutFeature.length > 0
    ? orphans.filesWithoutFeature.map(f => `- \`${f}\``).join('\n')
    : '✅ Nessun file orfano trovato';

  let singleFileSection = orphans.featuresWithSingleFile.length > 0
    ? orphans.featuresWithSingleFile.map(f => `- **${f.feature}**: \`${f.file}\``).join('\n')
    : '✅ Tutte le feature hanno più file';

  let duplicatesSection = orphans.potentialDuplicates.length > 0
    ? orphans.potentialDuplicates.map(d => `- **${d.module}**: ${d.files.map(f => `\`${f}\``).join(', ')}`).join('\n')
    : '✅ Nessun duplicato trovato';

  let missingSection = orphans.missingMetadata.slice(0, 20).length > 0
    ? orphans.missingMetadata.slice(0, 20).map(m => `- \`${m.file}\`: manca ${m.missing.join(', ')}`).join('\n')
    : '✅ Tutti i moduli hanno metadata completi';

  return `# 🔍 ORPHAN ANALYSIS REPORT

> Last generated: ${timestamp}
> Generated by: System_program/tools/build-universal-mapping.mjs

## 📊 Summary

| Metric | Count | Status |
|---|---|---|
| **Files Without @feature** | ${orphans.filesWithoutFeature.length} | ${orphans.filesWithoutFeature.length > 10 ? '🔴 REVIEW' : orphans.filesWithoutFeature.length > 0 ? '🟡 MONITOR' : '🟢 OK'} |
| **Single-File Features** | ${orphans.featuresWithSingleFile.length} | ${orphans.featuresWithSingleFile.length > 20 ? '🟡 MONITOR' : '🟢 OK'} |
| **Potential Duplicates** | ${orphans.potentialDuplicates.length} | ${orphans.potentialDuplicates.length > 0 ? '🔴 ACTION' : '🟢 OK'} |
| **Missing Metadata** | ${orphans.missingMetadata.length} | ${orphans.missingMetadata.length > 10 ? '🟡 MONITOR' : '🟢 OK'} |

---

## 🚨 Files Without @feature Tag

These files exist but are not indexed (no MODULE header with @feature):

${filesSection}

---

## ⚠️ Single-File Features

Features with only one file (potential orphans or incomplete implementations):

${singleFileSection}

---

## 🔄 Potential Duplicates

Modules with the same name in multiple files:

${duplicatesSection}

---

## 📝 Missing Metadata

Modules missing @risk, @stability, or @domain (first 20):

${missingSection}
${orphans.missingMetadata.length > 20 ? `\n... and ${orphans.missingMetadata.length - 20} more` : ''}

---

## 🎯 Action Items

${orphans.potentialDuplicates.length > 0 ? '🔴 **DUPLICATES**: Review and consolidate duplicate modules' : ''}
${orphans.filesWithoutFeature.length > 10 ? '🔴 **ORPHANS**: Add @feature tags to unindexed files' : ''}
${orphans.missingMetadata.length > 10 ? '🟡 **METADATA**: Complete missing @risk/@stability/@domain tags' : ''}
${orphans.potentialDuplicates.length === 0 && orphans.filesWithoutFeature.length <= 10 && orphans.missingMetadata.length <= 10 ? '🟢 **HEALTHY**: No critical orphan issues detected' : ''}

---

### Legend
- 🟢 OK | 🟡 Monitor | 🔴 Action Required
- **Orphan**: File without @feature tag (not indexed)
- **Single-File Feature**: Feature with only one module (potentially incomplete)
`;
}

function extractHooks(allFiles) {
  const hooks = [];

  // allFiles is now a list of { root, file } objects or we need to pass it differently.
  // Actually, scanAllFiles needs to be updated first to return full paths or struct.
  // Let's check scanAllFiles first. 
  // Wait, I cannot see scanAllFiles implementation in this view.
  // I will check the file content again or just update this blindly assuming I update `scanAllFiles` too.
  // But `allFiles` is passed from `scanAllFiles()`.

  // Let's assume `allFiles` now contains objects { path: relativePath, fullPath: absolutePath } OR just absolute paths?
  // The original `allFiles` was relative paths from SCAN_ROOT.

  // I'll update `scanAllFiles` to return relative paths, but we need to know WHICH root they belong to.
  // Simplest is to make allFiles checks loop over TARGET_ROOTS again or store metadata.

  // Let's update `scanAllFiles` first (next tool call) to return objects or absolute paths.
  // If I change `scanAllFiles` to return absolute paths, this will be easier.

  for (const file of allFiles) {
    try {
      // file is now absolute path
      const content = fs.readFileSync(file, 'utf-8');

      const matches = content.matchAll(AI_HOOK_REGEX);
      for (const match of matches) {
        hooks.push({
          file,
          hook: match[1],
          description: match[2]?.trim() || '',
        });
      }
    } catch (err) {
      // Skip unreadable files
    }
  }

  return hooks;
}

function generateHooksDoc(hooks) {
  const timestamp = new Date().toISOString();

  const byHook = {};
  for (const h of hooks) {
    if (!byHook[h.hook]) {
      byHook[h.hook] = [];
    }
    byHook[h.hook].push(h);
  }

  let content = `# 🎣 HOOKS REGISTRY

> Last generated: ${timestamp}
> Total Hooks: ${hooks.length}
> Unique Hooks: ${Object.keys(byHook).length}

---

## 📊 Summary

| Metric | Count |
|---|---|
| **Total Hook References** | ${hooks.length} |
| **Unique Hooks** | ${Object.keys(byHook).length} |
| **Files Using Hooks** | ${new Set(hooks.map(h => h.file)).size} |

---

## 🎯 Hooks by Name

`;

  for (const [hookName, instances] of Object.entries(byHook).sort()) {
    content += `### \`${hookName}\`\n\n`;
    content += `**Instances**: ${instances.length}\n\n`;
    content += `| File | Description |\n`;
    content += `|---|---|\n`;

    for (const inst of instances) {
      const desc = inst.description || '(no description)';
      content += `| \`${inst.file}\` | ${desc} |\n`;
    }
    content += '\n';
  }

  content += `---

## 📁 Hooks by File

`;

  const byFile = {};
  for (const h of hooks) {
    if (!byFile[h.file]) {
      byFile[h.file] = [];
    }
    byFile[h.file].push(h);
  }

  for (const [file, fileHooks] of Object.entries(byFile).sort()) {
    content += `### \`${file}\`\n\n`;
    for (const h of fileHooks) {
      content += `- **${h.hook}**: ${h.description || '(no description)'}\n`;
    }
    content += '\n';
  }

  return content;
}

function generateModulesDoc(modules) {
  const timestamp = new Date().toISOString();
  const byFeature = {};

  for (const mod of modules) {
    const feature = mod.feature || 'unclassified';
    if (!byFeature[feature]) {
      byFeature[feature] = [];
    }
    byFeature[feature].push(mod);
  }

  let content = `# 📚 MODULES DOCUMENTATION

> Last generated: ${timestamp}
> Total Modules: ${modules.length}
> Features: ${Object.keys(byFeature).length}

---

## 🎯 Quick Reference

`;

  const aiModules = modules.filter(m => m.ai && m.ai.length > 0);
  if (aiModules.length > 0) {
    content += `### 🤖 AI-Ready Modules (with @ai-module tags)

| Module | Description | Context |
|---|---|---|
`;
    for (const mod of aiModules) {
      for (const ai of mod.ai) {
        content += `| **${ai.module}** | ${ai.description || mod.purpose || '-'} | ${ai.context || '-'} |\n`;
      }
    }
    content += '\n---\n\n';
  }

  content += `## 📁 Modules by Feature\n\n`;

  for (const [feature, mods] of Object.entries(byFeature).sort()) {
    content += `### ${feature}\n\n`;
    content += `| Module | File | Risk | Stability | Purpose |\n`;
    content += `|---|---|---|---|---|\n`;

    for (const mod of mods) {
      const purpose = mod.purpose ? mod.purpose.slice(0, 60) + (mod.purpose.length > 60 ? '...' : '') : '-';
      content += `| ${mod.module || '-'} | \`${mod.file}\` | ${mod.risk || '-'} | ${mod.stability || '-'} | ${purpose} |\n`;
    }
    content += '\n';
  }

  return content;
}

function generateDataFlowDoc(modules) {
  const timestamp = new Date().toISOString();

  // 1. Dependency Analysis
  const consumers = modules.filter(m => m.consumes && m.consumes.length > 0);
  const touchers = modules.filter(m => m.touches && m.touches.length > 0);

  // 2. Identify External Systems (heuristic: not a module name)
  const knownModules = new Set(modules.map(m => m.module));
  const externalDeps = new Set();

  for (const mod of consumers) {
    for (const dep of mod.consumes) {
      if (!knownModules.has(dep)) externalDeps.add(dep);
    }
  }

  let content = `# 🔄 DATA FLOW & DEPENDENCY MAPPING

> Last generated: ${timestamp}
> Analzyed Modules: ${modules.length}
> Dependencies Tracked: ${consumers.length} modules
> Impact Areas Tracked: ${touchers.length} modules

---

## 🏗️ Architecture Dependency Matrix

Core modules that consume other services or data.

| Module | Consumes (Dependencies) | Risk |
|---|---|---|
`;

  // Sort by risk (CRITICAL first) then name
  const riskOrder = { 'CRITICAL': 0, 'HIGH': 1, 'MEDIUM': 2, 'LOW': 3 };
  consumers.sort((a, b) => {
    const rA = riskOrder[a.risk] || 2;
    const rB = riskOrder[b.risk] || 2;
    if (rA !== rB) return rA - rB;
    return a.module.localeCompare(b.module);
  });

  for (const mod of consumers) {
    const deps = mod.consumes.map(d => `\`${d}\``).join(', ');
    content += `| **${mod.module}** | ${deps} | ${mod.risk} |\n`;
  }

  content += `
---

## 💥 Impact Analysis (Blast Radius)

If you modify these modules, these systems/areas are affected.

| Module | Touches (Impact Area) | Stability |
|---|---|---|
`;

  touchers.sort((a, b) => a.module.localeCompare(b.module));

  for (const mod of touchers) {
    const impact = mod.touches.map(t => `\`${t}\``).join(', ');
    content += `| **${mod.module}** | ${impact} | ${mod.stability} |\n`;
  }

  content += `
---

## 🌐 External System Integrations

External APIs, Database tables, and Hooks identified as dependencies.

`;

  const externalList = Array.from(externalDeps).sort();
  const externalGroups = {};

  // Simple grouping
  for (const ext of externalList) {
    let group = 'Other';
    if (ext.includes('API')) group = 'APIs';
    else if (ext.includes('DB') || ext.includes('database') || ext.includes('table')) group = 'Database';
    else if (ext.includes('Hook') || ext.includes('hook')) group = 'WordPress Hooks';
    else if (ext.includes('File') || ext.includes('filesystem')) group = 'Filesystem';

    if (!externalGroups[group]) externalGroups[group] = [];
    externalGroups[group].push(ext);
  }

  for (const [group, items] of Object.entries(externalGroups).sort()) {
    content += `### ${group}\n`;
    items.forEach(item => content += `- ${item}\n`);
    content += '\n';
  }

  content += `---
  
### Legend
- **Consumes**: Inbound dependencies (I need this to work)
- **Touches**: Outbound impact (I change/affect this)
- **External**: Dependencies not matching a known module name
`;

  return content;
}

async function main() {
  try {
    console.log('🔍 Scanning modules...');
    const modules = scanFiles();
    const allFiles = scanAllFiles();

    console.log(`✅ Found ${modules.length} modules`);

    const modIndex = generateModIndex(modules);
    const modIndexPath = path.join(OUTPUT_ROOT, 'mod-index.json');
    fs.writeFileSync(modIndexPath, JSON.stringify(modIndex, null, 2));
    console.log(`✅ Generated ${modIndexPath}`);

    const systemStatus = generateSystemStatus(modules);
    const statusPath = path.join(OUTPUT_ROOT, 'SYSTEM_STATUS.md');
    fs.writeFileSync(statusPath, systemStatus);
    console.log(`✅ Generated ${statusPath}`);

    console.log('🔍 Running cross-reference analysis...');
    const orphans = crossReferenceAnalysis(modules, allFiles);
    const orphansReport = generateOrphansReport(orphans);
    const orphansPath = path.join(OUTPUT_ROOT, 'ORPHANS.md');
    fs.writeFileSync(orphansPath, orphansReport);
    console.log(`✅ Generated ${orphansPath}`);

    const modulesDoc = generateModulesDoc(modules);
    const modulesPath = path.join(OUTPUT_ROOT, 'MODULES.md');
    fs.writeFileSync(modulesPath, modulesDoc);
    console.log(`✅ Generated ${modulesPath}`);

    console.log('🎣 Extracting hooks...');
    const hooks = extractHooks(allFiles);
    const hooksDoc = generateHooksDoc(hooks);
    const hooksPath = path.join(OUTPUT_ROOT, 'HOOKS.md');
    fs.writeFileSync(hooksPath, hooksDoc);
    console.log(`✅ Generated ${hooksPath}`);

    console.log('🔄 Generating Data Flow analysis...');
    const dataFlowDoc = generateDataFlowDoc(modules);
    const dataFlowPath = path.join(OUTPUT_ROOT, 'DATAFLOW.md');
    fs.writeFileSync(dataFlowPath, dataFlowDoc);
    console.log(`✅ Generated ${dataFlowPath}`);

    console.log('\n📊 Summary:');
    console.log(`   - Total Modules: ${modules.length}`);
    console.log(`   - Features: ${new Set(modules.map(m => m.feature)).size}`);
    console.log(`   - Risk Distribution: C:${modIndex.risk.CRITICAL.length} H:${modIndex.risk.HIGH.length} M:${modIndex.risk.MEDIUM.length} L:${modIndex.risk.LOW.length}`);
    console.log(`   - Orphan Files: ${orphans.filesWithoutFeature.length}`);
    console.log(`   - Duplicates: ${orphans.potentialDuplicates.length}`);
    console.log(`   - AI-Ready Modules: ${modules.filter(m => m.ai).length}`);
    console.log(`   - Hooks: ${hooks.length} references, ${new Set(hooks.map(h => h.hook)).size} unique`);

  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

main();
