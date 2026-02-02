#!/usr/bin/env node

// CI/Pre-commit Guards System
// Protects against dangerous changes and maintains system integrity

import { promises as fs } from "fs";
import path from "path";
import { execSync } from "child_process";

const ROOT = process.argv[2] || ".";
const MAX_BLAST_RADIUS = parseInt(process.argv[3]) || 15; // Max files allowed to change

// Critical PHP functions that must never disappear
const CRITICAL_PHP_FUNCTIONS = [
  'set_price\\s*\\(',
  'before_calculate_totals',
  'add_cart_item_data',
  'cart_item_removed',
  'woocommerce_add_to_cart',
  'woocommerce_cart_item_data'
];

// Files that must be kept in sync with mod-index.json
const GENERATED_FILES = [
  'MODULES.md',
  'HOOKS.md', 
  'EVENTS.md',
  'DEPS.md',
  'PROMPTS.md',
  'SYSTEM_STATUS.md'
];

let exitCode = 0;
let violations = [];

function log(level, message) {
  const timestamp = new Date().toISOString();
  const prefix = level === 'ERROR' ? '❌' : level === 'WARN' ? '⚠️' : 'ℹ️';
  console.log(`${prefix} [${timestamp}] ${message}`);
}

function addViolation(severity, message) {
  violations.push({ severity, message });
  if (severity === 'ERROR') exitCode = 1;
}

async function getGitChangedFiles() {
  try {
    // Get staged and modified files
    const staged = execSync('git diff --cached --name-only', { encoding: 'utf8', cwd: ROOT }).trim();
    const modified = execSync('git diff --name-only', { encoding: 'utf8', cwd: ROOT }).trim();
    
    const allChanged = [...new Set([
      ...staged.split('\n').filter(Boolean),
      ...modified.split('\n').filter(Boolean)
    ])];
    
    return allChanged;
  } catch (err) {
    log('WARN', 'Not a git repository or git not available - skipping git checks');
    return [];
  }
}

async function checkBlastRadius(changedFiles) {
  if (changedFiles.length === 0) return;
  
  log('INFO', `Checking blast radius: ${changedFiles.length} files changed (max: ${MAX_BLAST_RADIUS})`);
  
  if (changedFiles.length > MAX_BLAST_RADIUS) {
    addViolation('ERROR', 
      `Blast radius exceeded: ${changedFiles.length} files > ${MAX_BLAST_RADIUS} max. ` +
      `Large changes increase risk. Consider splitting into smaller commits.`
    );
    
    log('INFO', 'Changed files:');
    changedFiles.forEach(file => log('INFO', `  - ${file}`));
  }
}

async function checkModIndexSync(changedFiles) {
  const modIndexChanged = changedFiles.includes('mod-index.json');
  if (!modIndexChanged) return;
  
  log('INFO', 'mod-index.json changed - checking if generated files are updated...');
  
  // Check if any generated files are also in the changeset
  const generatedChanged = GENERATED_FILES.filter(file => changedFiles.includes(file));
  
  if (generatedChanged.length === 0) {
    addViolation('ERROR',
      'mod-index.json changed but no generated files updated. ' +
      'Run `node tools/build-universal-mapping.mjs` to regenerate mapping files.'
    );
  } else {
    log('INFO', `Generated files also updated: ${generatedChanged.join(', ')}`);
  }
}

async function checkCriticalFunctions(changedFiles) {
  log('INFO', 'Checking for removal of critical PHP functions...');
  
  const phpFiles = changedFiles.filter(file => file.endsWith('.php'));
  if (phpFiles.length === 0) return;
  
  for (const file of phpFiles) {
    try {
      const filePath = path.join(ROOT, file);
      
      // Get the diff for this file
      const diff = execSync(`git diff HEAD -- "${file}"`, { 
        encoding: 'utf8', 
        cwd: ROOT 
      });
      
      // Check for removed lines (lines starting with -)
      const removedLines = diff.split('\n')
        .filter(line => line.startsWith('-') && !line.startsWith('---'))
        .map(line => line.substring(1)); // Remove the - prefix
      
      // Check if any critical functions were removed
      for (const criticalFunc of CRITICAL_PHP_FUNCTIONS) {
        const regex = new RegExp(criticalFunc, 'i');
        const removedCritical = removedLines.some(line => regex.test(line));
        
        if (removedCritical) {
          addViolation('ERROR',
            `Critical function pattern "${criticalFunc}" removed from ${file}. ` +
            `This may break core pricing/cart functionality.`
          );
        }
      }
      
    } catch (err) {
      log('WARN', `Could not check ${file}: ${err.message}`);
    }
  }
}

async function checkFileIntegrity() {
  log('INFO', 'Checking core file integrity...');
  
  const criticalFiles = [
    'wc-ai-product-customizer/wc-ai-product-customizer.php',
    'wc-ai-product-customizer/includes/class-wc-ai-product-customizer.php'
  ];
  
  for (const file of criticalFiles) {
    try {
      const filePath = path.join(ROOT, file);
      await fs.access(filePath);
    } catch (err) {
      addViolation('ERROR', `Critical file missing: ${file}`);
    }
  }
}

async function checkGeneratedFilesAge() {
  log('INFO', 'Checking if generated files are recent...');
  
  try {
    const modIndexPath = path.join(ROOT, 'System_program/mod-index.json');
    const modIndexStat = await fs.stat(modIndexPath);
    
    for (const genFile of GENERATED_FILES) {
      try {
        const genPath = path.join(ROOT, 'System_program', genFile);
        const genStat = await fs.stat(genPath);
        
        // Generated file should be newer than or same age as mod-index.json
        if (genStat.mtime < modIndexStat.mtime) {
          addViolation('WARN',
            `${genFile} is older than mod-index.json. Consider regenerating mapping files.`
          );
        }
      } catch (err) {
        addViolation('WARN', `Generated file missing: ${genFile}`);
      }
    }
  } catch (err) {
    log('WARN', 'Could not check file ages - mod-index.json missing');
  }
}

async function checkCodeQuality(changedFiles) {
  // Optional quality check - only warnings, never blocks
  const enableQualityCheck = process.env.ENABLE_QUALITY_CHECK === '1';
  
  if (!enableQualityCheck) {
    return;
  }
  
  log('INFO', 'Running optional code quality checks...');
  
  // Filter JS/PHP files
  const jsFiles = changedFiles.filter(file => 
    /\.(js|jsx|ts|tsx|mjs)$/.test(file) && !file.includes('node_modules')
  );
  const phpFiles = changedFiles.filter(file => 
    file.endsWith('.php') && !file.includes('vendor')
  );
  
  const filesToCheck = [...jsFiles, ...phpFiles].slice(0, 5); // Limit to 5 files
  
  if (filesToCheck.length === 0) {
    return;
  }
  
  for (const file of filesToCheck) {
    try {
      const toolPath = path.join(ROOT, 'System_program/tools/analyze-quality.mjs');
      const result = execSync(
        `node "${toolPath}" "${file}"`,
        { encoding: 'utf8', cwd: ROOT }
      );
      
      const analysis = JSON.parse(result);
      
      if (analysis.summary && analysis.summary.total > 0) {
        const { total, errors, warnings, byCategory } = analysis.summary;
        
        // Only warn if there are errors or high complexity
        const hasHighComplexity = (byCategory.complexity || 0) > 3;
        const hasSecurity = (byCategory.security || 0) > 0;
        
        if (errors > 0 || hasHighComplexity || hasSecurity) {
          let message = `Quality issues in ${file}: ${total} total (${errors} errors, ${warnings} warnings)`;
          
          if (hasSecurity) {
            message += ` - ⚠️ SECURITY ISSUES FOUND`;
          }
          
          addViolation('WARN', message);
          log('WARN', `  Run: node System_program/tools/analyze-quality.mjs "${file}" for details`);
        }
      }
    } catch (err) {
      // Quality check failed - just log, don't block
      log('INFO', `Could not check quality for ${file}: ${err.message}`);
    }
  }
}

async function runAllChecks() {
  log('INFO', '🛡️  Starting CI/Pre-commit Guards...');
  
  const changedFiles = await getGitChangedFiles();
  
  // Run all checks
  await Promise.all([
    checkBlastRadius(changedFiles),
    checkModIndexSync(changedFiles),
    checkCriticalFunctions(changedFiles),
    checkFileIntegrity(),
    checkGeneratedFilesAge(),
    checkCodeQuality(changedFiles)
  ]);
  
  // Report results
  log('INFO', '📊 Guard Results:');
  
  if (violations.length === 0) {
    log('INFO', '✅ All checks passed - commit is safe');
  } else {
    const errors = violations.filter(v => v.severity === 'ERROR');
    const warnings = violations.filter(v => v.severity === 'WARN');
    
    if (errors.length > 0) {
      log('ERROR', `${errors.length} blocking error(s):`);
      errors.forEach(v => log('ERROR', `  ${v.message}`));
    }
    
    if (warnings.length > 0) {
      log('WARN', `${warnings.length} warning(s):`);
      warnings.forEach(v => log('WARN', `  ${v.message}`));
    }
    
    if (errors.length > 0) {
      log('ERROR', '❌ Commit blocked by errors. Fix issues above and try again.');
    }
  }
  
  return exitCode;
}

// Self-contained guard runner
if (import.meta.url === `file://${process.argv[1]}`) {
  runAllChecks()
    .then(code => process.exit(code))
    .catch(err => {
      log('ERROR', `Guard system error: ${err.message}`);
      process.exit(1);
    });
}

export { runAllChecks, checkBlastRadius, checkModIndexSync, checkCriticalFunctions };