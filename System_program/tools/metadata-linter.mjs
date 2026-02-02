#!/usr/bin/env node

// Metadata Linter for MODULE Headers
// Validates MODULE header completeness and standardization

import { promises as fs } from "fs";
import path from "path";

const ROOT = process.argv[2] || ".";

// Required fields for MODULE headers
const REQUIRED_FIELDS = ['module', 'path', 'domain', 'feature', 'purpose'];
const OPTIONAL_FIELDS = ['exports', 'consumes', 'events', 'touches', 'owner', 'risk', 'tests', 'capabilities', 'deps_internal', 'deps_external', 'hooks', 'contracts', 'severity', 'stability'];
const VALID_RISK_LEVELS = ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'];
const VALID_SEVERITY_LEVELS = ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'];
const VALID_STABILITY_LEVELS = ['LOW', 'MEDIUM', 'HIGH'];

const isCodeFile = (p) => /\.(js|jsx|ts|php|css|scss|vue)$/i.test(p);

async function walkDirectory(dir) {
  const files = [];
  try {
    const items = await fs.readdir(dir, { withFileTypes: true });
    for (const item of items) {
      const fullPath = path.join(dir, item.name);
      if (item.name.startsWith('.') || ['node_modules', 'vendor', 'lib'].includes(item.name)) continue;
      if (item.isDirectory()) {
        files.push(...await walkDirectory(fullPath));
      } else if (item.isFile() && isCodeFile(fullPath)) {
        files.push(fullPath);
      }
    }
  } catch (err) {
    // Skip inaccessible directories
  }
  return files;
}

function parseModuleHeader(content) {
  const match = content.match(/\/\*\s*MODULE([\s\S]*?)\*\//);
  if (!match) return null;
  
  const headerBody = match[1];
  const fields = {};
  const lines = headerBody.split("\n");
  
  for (const rawLine of lines) {
    const line = rawLine.trim();
    const keyValue = line.match(/^@([a-zA-Z0-9_-]+)\s*:\s*(.+)$/);
    if (!keyValue) continue;
    
    const key = keyValue[1].toLowerCase();
    let value = keyValue[2].trim();
    
    // Parse arrays for specific fields
    if (["domain", "exports", "consumes", "events", "touches", "tests", "capabilities", "deps_internal", "deps_external", "hooks", "contracts"].includes(key)) {
      value = value.split(",").map(s => s.trim()).filter(Boolean);
    }
    
    fields[key] = value;
  }
  return fields;
}

function lintModuleHeader(moduleData, filePath) {
  const issues = [];
  
  // Check for missing required fields
  for (const field of REQUIRED_FIELDS) {
    if (!moduleData[field] || (Array.isArray(moduleData[field]) && moduleData[field].length === 0)) {
      issues.push({
        type: 'missing_required',
        field,
        severity: 'error',
        message: `Missing required field: @${field}`,
        file: filePath
      });
    }
  }
  
  // Check for empty values
  for (const [field, value] of Object.entries(moduleData)) {
    if (value === '' || (Array.isArray(value) && value.length === 0)) {
      issues.push({
        type: 'empty_value',
        field,
        severity: 'warning',
        message: `Empty value for field: @${field}`,
        file: filePath
      });
    }
  }
  
  // Validate specific field values
  if (moduleData.risk && !VALID_RISK_LEVELS.includes(moduleData.risk)) {
    issues.push({
      type: 'invalid_value',
      field: 'risk',
      severity: 'error',
      message: `Invalid risk level: "${moduleData.risk}". Valid values: ${VALID_RISK_LEVELS.join(', ')}`,
      file: filePath,
      suggestion: `Use one of: ${VALID_RISK_LEVELS.join(', ')}`
    });
  }
  
  if (moduleData.severity && !VALID_SEVERITY_LEVELS.includes(moduleData.severity)) {
    issues.push({
      type: 'invalid_value',
      field: 'severity',
      severity: 'error',
      message: `Invalid severity level: "${moduleData.severity}". Valid values: ${VALID_SEVERITY_LEVELS.join(', ')}`,
      file: filePath,
      suggestion: `Use one of: ${VALID_SEVERITY_LEVELS.join(', ')}`
    });
  }
  
  if (moduleData.stability && !VALID_STABILITY_LEVELS.includes(moduleData.stability)) {
    issues.push({
      type: 'invalid_value',
      field: 'stability',
      severity: 'error',
      message: `Invalid stability level: "${moduleData.stability}". Valid values: ${VALID_STABILITY_LEVELS.join(', ')}`,
      file: filePath,
      suggestion: `Use one of: ${VALID_STABILITY_LEVELS.join(', ')}`
    });
  }
  
  // Check purpose length (should be descriptive but not too long)
  if (moduleData.purpose && moduleData.purpose.length < 10) {
    issues.push({
      type: 'insufficient_description',
      field: 'purpose',
      severity: 'warning',
      message: `Purpose too short: "${moduleData.purpose}". Provide more detail.`,
      file: filePath
    });
  }
  
  if (moduleData.purpose && moduleData.purpose.length > 200) {
    issues.push({
      type: 'excessive_description',
      field: 'purpose',
      severity: 'warning',
      message: `Purpose too long (${moduleData.purpose.length} chars). Consider shortening.`,
      file: filePath
    });
  }
  
  // Validate module name format (should be PascalCase or camelCase)
  if (moduleData.module && !/^[A-Z][a-zA-Z0-9]*$/.test(moduleData.module)) {
    issues.push({
      type: 'naming_convention',
      field: 'module',
      severity: 'warning',
      message: `Module name "${moduleData.module}" should use PascalCase`,
      file: filePath,
      suggestion: 'Use PascalCase for module names (e.g., MyModuleName)'
    });
  }
  
  // Check for unknown fields
  const allValidFields = [...REQUIRED_FIELDS, ...OPTIONAL_FIELDS];
  for (const field of Object.keys(moduleData)) {
    if (!allValidFields.includes(field)) {
      issues.push({
        type: 'unknown_field',
        field,
        severity: 'info',
        message: `Unknown field: @${field}`,
        file: filePath,
        suggestion: `Valid fields: ${allValidFields.join(', ')}`
      });
    }
  }
  
  return issues;
}

function generateLintReport(allIssues) {
  const errors = allIssues.filter(i => i.severity === 'error');
  const warnings = allIssues.filter(i => i.severity === 'warning');
  const infos = allIssues.filter(i => i.severity === 'info');
  
  let report = `# MODULE METADATA LINT REPORT\n\n`;
  report += `> Generated: ${new Date().toISOString()}\n\n`;
  report += `## Summary\n`;
  report += `- **Errors**: ${errors.length} (blocking)\n`;
  report += `- **Warnings**: ${warnings.length} (recommended fixes)\n`;
  report += `- **Info**: ${infos.length} (suggestions)\n\n`;
  
  if (allIssues.length === 0) {
    report += `✅ **All MODULE headers are properly formatted!**\n`;
    return report;
  }
  
  // Group issues by file
  const issuesByFile = allIssues.reduce((acc, issue) => {
    if (!acc[issue.file]) acc[issue.file] = [];
    acc[issue.file].push(issue);
    return acc;
  }, {});
  
  for (const [file, issues] of Object.entries(issuesByFile)) {
    report += `## 📁 ${file}\n\n`;
    
    const fileErrors = issues.filter(i => i.severity === 'error');
    const fileWarnings = issues.filter(i => i.severity === 'warning');
    const fileInfos = issues.filter(i => i.severity === 'info');
    
    if (fileErrors.length > 0) {
      report += `### ❌ Errors (${fileErrors.length})\n`;
      fileErrors.forEach(issue => {
        report += `- **${issue.field}**: ${issue.message}\n`;
        if (issue.suggestion) {
          report += `  💡 *Suggestion: ${issue.suggestion}*\n`;
        }
      });
      report += `\n`;
    }
    
    if (fileWarnings.length > 0) {
      report += `### ⚠️  Warnings (${fileWarnings.length})\n`;
      fileWarnings.forEach(issue => {
        report += `- **${issue.field}**: ${issue.message}\n`;
        if (issue.suggestion) {
          report += `  💡 *Suggestion: ${issue.suggestion}*\n`;
        }
      });
      report += `\n`;
    }
    
    if (fileInfos.length > 0) {
      report += `### ℹ️  Info (${fileInfos.length})\n`;
      fileInfos.forEach(issue => {
        report += `- **${issue.field}**: ${issue.message}\n`;
        if (issue.suggestion) {
          report += `  💡 *Suggestion: ${issue.suggestion}*\n`;
        }
      });
      report += `\n`;
    }
  }
  
  // Quick fix suggestions
  report += `## 🔧 Quick Fix Template\n\n`;
  report += `\`\`\`\n`;
  report += `/* MODULE\n`;
  REQUIRED_FIELDS.forEach(field => {
    report += `@${field}: [${field.toUpperCase()}_VALUE]\n`;
  });
  report += `@risk: [LOW|MEDIUM|HIGH|CRITICAL]\n`;
  report += `@stability: [LOW|MEDIUM|HIGH]\n`;
  report += `@severity: [LOW|MEDIUM|HIGH|CRITICAL]\n`;
  report += `*/\n`;
  report += `\`\`\`\n\n`;
  
  return report;
}

async function lintAllModules() {
  console.log('🧹 Linting MODULE headers...');
  
  const files = await walkDirectory(ROOT);
  const allIssues = [];
  let modulesChecked = 0;
  let filesWithoutModuleHeader = 0;
  
  for (const filePath of files) {
    try {
      const content = await fs.readFile(filePath, 'utf-8');
      const relativePath = path.relative(ROOT, filePath);
      
      const moduleData = parseModuleHeader(content);
      if (moduleData) {
        modulesChecked++;
        const issues = lintModuleHeader(moduleData, relativePath);
        allIssues.push(...issues);
      } else {
        filesWithoutModuleHeader++;
      }
      
    } catch (err) {
      console.warn(`Warning: Could not process ${filePath}: ${err.message}`);
    }
  }
  
  console.log(`✓ Checked ${modulesChecked} modules`);
  console.log(`ℹ️  ${filesWithoutModuleHeader} files without MODULE headers`);
  
  const errors = allIssues.filter(i => i.severity === 'error');
  const warnings = allIssues.filter(i => i.severity === 'warning');
  
  if (allIssues.length === 0) {
    console.log('✅ All MODULE headers are properly formatted!');
  } else {
    if (errors.length > 0) {
      console.log(`❌ Found ${errors.length} error(s) that need fixing`);
    }
    if (warnings.length > 0) {
      console.log(`⚠️  Found ${warnings.length} warning(s) - recommended fixes`);
    }
  }
  
  return { allIssues, modulesChecked, filesWithoutModuleHeader };
}

// Self-contained runner
if (import.meta.url === `file://${process.argv[1]}`) {
  lintAllModules()
    .then(result => {
      const report = generateLintReport(result.allIssues);
      console.log('\n' + report);
      
      const errors = result.allIssues.filter(i => i.severity === 'error');
      process.exit(errors.length > 0 ? 1 : 0);
    })
    .catch(err => {
      console.error('Metadata linter error:', err.message);
      process.exit(1);
    });
}

export { lintAllModules, generateLintReport, lintModuleHeader };