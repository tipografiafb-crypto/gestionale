#!/usr/bin/env node

/**
 * File Size Guard - Pre-screening per Quality Workflow
 * 
 * Identifica file lunghi che richiedono refactoring focalizzato.
 * Si integra con ENTERPRISE-GRADE MODULE ROUTING SYSTEM.
 * 
 * @feature: quality
 * @domain: tools
 * 
 * Usage:
 *   node check-file-length.mjs --feature=canvas
 *   node check-file-length.mjs --all
 *   node check-file-length.mjs --threshold=500
 *   node check-file-length.mjs --feature=canvas --threshold=800
 * 
 * Output: JSON con file lunghi per targeting chirurgico
 */

import { promises as fs } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PROJECT_ROOT = path.resolve(__dirname, '../..');
const PLUGIN_ROOT = path.join(PROJECT_ROOT, 'magenta-product-customizer');
const SCOPE_DIR = path.join(PROJECT_ROOT, 'System_program/scope');

// Default configuration
const DEFAULT_THRESHOLD = 500;
const SUPPORTED_EXTENSIONS = ['.js', '.jsx', '.ts', '.tsx', '.mjs', '.php', '.css', '.scss'];

/**
 * Parse command line arguments
 */
function parseArgs() {
  const args = process.argv.slice(2);
  const config = {
    feature: null,
    threshold: DEFAULT_THRESHOLD,
    all: false,
    help: false
  };

  for (const arg of args) {
    if (arg === '--help' || arg === '-h') {
      config.help = true;
    } else if (arg === '--all') {
      config.all = true;
    } else if (arg.startsWith('--feature=')) {
      config.feature = arg.split('=')[1];
    } else if (arg.startsWith('--threshold=')) {
      config.threshold = parseInt(arg.split('=')[1]);
    }
  }

  return config;
}

/**
 * Show help message
 */
function showHelp() {
  console.log(`
File Size Guard - Pre-screening per Quality Workflow

Usage:
  node check-file-length.mjs [options]

Options:
  --feature=<name>     Analizza solo file della feature specificata
                       (usa scope/<feature>.allow per filtering)
  
  --threshold=<lines>  Soglia minima di righe (default: ${DEFAULT_THRESHOLD})
  
  --all                Analizza tutti i file del plugin
  
  --help, -h           Mostra questo messaggio

Examples:
  # Trova file lunghi nella feature canvas
  node check-file-length.mjs --feature=canvas

  # Trova tutti i file oltre 800 righe
  node check-file-length.mjs --all --threshold=800

  # Usa soglia personalizzata per una feature
  node check-file-length.mjs --feature=ai --threshold=600

Output:
  JSON strutturato con file lunghi per AI targeting chirurgico
`);
}

/**
 * Read scope file and get allowed files for a feature
 */
async function readScopeFile(feature) {
  try {
    const scopePath = path.join(SCOPE_DIR, `${feature}.allow`);
    const content = await fs.readFile(scopePath, 'utf8');
    
    // Parse scope file (lines starting with + are allowed)
    const allowedPatterns = content
      .split('\n')
      .filter(line => line.trim().startsWith('+'))
      .map(line => line.trim().substring(1).trim());
    
    return allowedPatterns;
  } catch (err) {
    return null;
  }
}

/**
 * Check if file matches any pattern
 */
function matchesPattern(filePath, patterns) {
  if (!patterns || patterns.length === 0) return true;
  
  const relativePath = filePath.replace(PLUGIN_ROOT + '/', '');
  
  return patterns.some(pattern => {
    // Convert glob-like pattern to regex
    const regexPattern = pattern
      .replace(/\./g, '\\.')
      .replace(/\*/g, '.*')
      .replace(/\?/g, '.');
    
    const regex = new RegExp(`^${regexPattern}$`);
    return regex.test(relativePath);
  });
}

/**
 * Count lines in a file
 */
async function countLines(filePath) {
  try {
    const content = await fs.readFile(filePath, 'utf8');
    return content.split('\n').length;
  } catch (err) {
    return 0;
  }
}

/**
 * Recursively scan directory for files
 */
async function scanDirectory(dir, patterns = null) {
  const results = [];
  
  try {
    const entries = await fs.readdir(dir, { withFileTypes: true });
    
    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name);
      
      // Skip common ignore directories
      if (entry.isDirectory()) {
        if (['node_modules', 'vendor', '.git', 'legacy'].includes(entry.name)) {
          continue;
        }
        
        // Recurse into subdirectory
        const subResults = await scanDirectory(fullPath, patterns);
        results.push(...subResults);
      } else if (entry.isFile()) {
        const ext = path.extname(entry.name);
        
        // Check if file has supported extension
        if (SUPPORTED_EXTENSIONS.includes(ext)) {
          // Check if file matches patterns (if provided)
          if (!patterns || matchesPattern(fullPath, patterns)) {
            results.push(fullPath);
          }
        }
      }
    }
  } catch (err) {
    // Ignore permission errors
  }
  
  return results;
}

/**
 * Analyze files and identify long ones
 */
async function analyzeFiles(files, threshold) {
  const longFiles = [];
  
  for (const filePath of files) {
    const lineCount = await countLines(filePath);
    
    if (lineCount >= threshold) {
      const relativePath = filePath.replace(PROJECT_ROOT + '/', '');
      const ext = path.extname(filePath);
      
      longFiles.push({
        file: relativePath,
        lines: lineCount,
        extension: ext,
        category: categorizeFile(filePath)
      });
    }
  }
  
  // Sort by line count (descending)
  longFiles.sort((a, b) => b.lines - a.lines);
  
  return longFiles;
}

/**
 * Categorize file by type
 */
function categorizeFile(filePath) {
  const ext = path.extname(filePath);
  
  if (['.js', '.jsx', '.ts', '.tsx', '.mjs'].includes(ext)) {
    return 'javascript';
  } else if (ext === '.php') {
    return 'php';
  } else if (['.css', '.scss'].includes(ext)) {
    return 'stylesheet';
  }
  
  return 'other';
}

/**
 * Generate recommendations based on analysis
 */
function generateRecommendations(longFiles, threshold) {
  if (longFiles.length === 0) {
    return `No files exceed ${threshold} lines. Great job maintaining file size!`;
  }
  
  const top3 = longFiles.slice(0, 3);
  const recommendations = [];
  
  if (longFiles.length === 1) {
    recommendations.push(`Focus refactoring on: ${top3[0].file} (${top3[0].lines} lines)`);
  } else if (longFiles.length <= 3) {
    recommendations.push(`Refactor these ${longFiles.length} files one at a time for deep surgical fixes:`);
    top3.forEach((file, idx) => {
      recommendations.push(`  ${idx + 1}. ${file.file} (${file.lines} lines)`);
    });
  } else {
    recommendations.push(`Found ${longFiles.length} long files. Start with top 3 for maximum impact:`);
    top3.forEach((file, idx) => {
      recommendations.push(`  ${idx + 1}. ${file.file} (${file.lines} lines)`);
    });
    recommendations.push(`\nAfter completing top 3, address remaining ${longFiles.length - 3} files.`);
  }
  
  return recommendations.join('\n');
}

/**
 * Main execution
 */
async function main() {
  const config = parseArgs();
  
  if (config.help) {
    showHelp();
    process.exit(0);
  }
  
  let files = [];
  let scopePatterns = null;
  
  // Determine which files to scan
  if (config.feature) {
    scopePatterns = await readScopeFile(config.feature);
    
    if (!scopePatterns) {
      console.error(JSON.stringify({
        status: 'error',
        message: `Feature "${config.feature}" not found. Check System_program/scope/${config.feature}.allow exists.`,
        available_features: await getAvailableFeatures()
      }, null, 2));
      process.exit(1);
    }
    
    files = await scanDirectory(PLUGIN_ROOT, scopePatterns);
  } else if (config.all) {
    files = await scanDirectory(PLUGIN_ROOT, null);
  } else {
    showHelp();
    process.exit(1);
  }
  
  // Analyze files
  const longFiles = await analyzeFiles(files, config.threshold);
  
  // Generate output
  const output = {
    status: longFiles.length > 0 ? 'warning' : 'ok',
    feature: config.feature || 'all',
    threshold: config.threshold,
    total_files_scanned: files.length,
    long_files_count: longFiles.length,
    long_files: longFiles,
    recommendation: generateRecommendations(longFiles, config.threshold),
    workflow_suggestion: longFiles.length > 0 
      ? `Use: node System_program/tools/analyze-quality.mjs "${longFiles[0].file}" for detailed quality analysis`
      : null
  };
  
  console.log(JSON.stringify(output, null, 2));
  
  // Exit with status code
  process.exit(longFiles.length > 0 ? 0 : 0); // Always success, just informational
}

/**
 * Get available features from scope directory
 */
async function getAvailableFeatures() {
  try {
    const files = await fs.readdir(SCOPE_DIR);
    return files
      .filter(f => f.endsWith('.allow'))
      .map(f => f.replace('.allow', ''));
  } catch (err) {
    return [];
  }
}

// Run if called directly
if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch(err => {
    console.error(JSON.stringify({
      status: 'error',
      message: err.message,
      stack: err.stack
    }, null, 2));
    process.exit(1);
  });
}

export { analyzeFiles, countLines, scanDirectory };
