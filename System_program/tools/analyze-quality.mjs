#!/usr/bin/env node

/**
 * Quality Analysis Tool for Magenta Plugin
 * 
 * Analyzes code quality and reports issues in JSON format.
 * Supports JavaScript/TypeScript (ESLint) and PHP (PHPCS).
 * 
 * Usage:
 *   node analyze-quality.mjs <file-path>
 *   node analyze-quality.mjs --all-js
 *   node analyze-quality.mjs --all-php
 * 
 * Output: JSON with quality issues (complexity, code smells, etc.)
 */

import { promises as fs } from 'fs';
import { exec } from 'child_process';
import { promisify } from 'util';
import path from 'path';
import { fileURLToPath } from 'url';

const execAsync = promisify(exec);
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PROJECT_ROOT = path.resolve(__dirname, '../..');

// Configuration
const ESLINT_CONFIG = path.join(PROJECT_ROOT, 'eslint.config.js');
const PHPCS_CONFIG = path.join(PROJECT_ROOT, 'phpcs.xml');

/**
 * Analyze JavaScript/TypeScript file with ESLint
 */
async function analyzeJavaScript(filePath) {
  try {
    const { stdout, stderr } = await execAsync(
      `npx eslint --format json --config "${ESLINT_CONFIG}" "${filePath}"`,
      { cwd: PROJECT_ROOT }
    );
    
    const results = JSON.parse(stdout);
    const issues = [];
    
    if (results && results.length > 0) {
      const fileResult = results[0];
      
      for (const message of fileResult.messages || []) {
        issues.push({
          type: 'eslint',
          severity: message.severity === 2 ? 'error' : 'warning',
          rule: message.ruleId || 'unknown',
          message: message.message,
          line: message.line,
          column: message.column,
          category: categorizeESLintRule(message.ruleId)
        });
      }
    }
    
    return issues;
  } catch (error) {
    // ESLint exits with code 1 when issues are found
    if (error.stdout) {
      try {
        const results = JSON.parse(error.stdout);
        const issues = [];
        
        if (results && results.length > 0) {
          const fileResult = results[0];
          
          for (const message of fileResult.messages || []) {
            issues.push({
              type: 'eslint',
              severity: message.severity === 2 ? 'error' : 'warning',
              rule: message.ruleId || 'unknown',
              message: message.message,
              line: message.line,
              column: message.column,
              category: categorizeESLintRule(message.ruleId)
            });
          }
        }
        
        return issues;
      } catch (parseError) {
        return [{
          type: 'eslint',
          severity: 'error',
          rule: 'tool-error',
          message: `ESLint execution failed: ${error.message}`,
          category: 'tool-error'
        }];
      }
    }
    
    return [{
      type: 'eslint',
      severity: 'error',
      rule: 'tool-error',
      message: `ESLint execution failed: ${error.message}`,
      category: 'tool-error'
    }];
  }
}

/**
 * Analyze PHP file with PHPCS
 */
async function analyzePHP(filePath) {
  try {
    const { stdout } = await execAsync(
      `npx phpcs --standard="${PHPCS_CONFIG}" --report=json "${filePath}"`,
      { cwd: PROJECT_ROOT }
    );
    
    const results = JSON.parse(stdout);
    const issues = [];
    
    const fileResults = results.files[filePath];
    if (fileResults && fileResults.messages) {
      for (const message of fileResults.messages) {
        issues.push({
          type: 'phpcs',
          severity: message.type.toLowerCase(),
          rule: message.source || 'unknown',
          message: message.message,
          line: message.line,
          column: message.column,
          category: categorizePHPCSRule(message.source)
        });
      }
    }
    
    return issues;
  } catch (error) {
    // PHPCS exits with code 1 when issues are found
    if (error.stdout) {
      try {
        const results = JSON.parse(error.stdout);
        const issues = [];
        
        const fileResults = results.files[filePath];
        if (fileResults && fileResults.messages) {
          for (const message of fileResults.messages) {
            issues.push({
              type: 'phpcs',
              severity: message.type.toLowerCase(),
              rule: message.source || 'unknown',
              message: message.message,
              line: message.line,
              column: message.column,
              category: categorizePHPCSRule(message.source)
            });
          }
        }
        
        return issues;
      } catch (parseError) {
        // No PHPCS available or parse error
        return [];
      }
    }
    
    // PHPCS not available
    return [];
  }
}

/**
 * Categorize ESLint rule into quality categories
 */
function categorizeESLintRule(ruleId) {
  if (!ruleId) return 'other';
  
  const complexityRules = ['complexity', 'max-depth', 'max-nested-callbacks', 'max-lines', 'max-lines-per-function', 'max-params', 'max-statements'];
  const codeSmellRules = ['no-unused-vars', 'no-unreachable', 'no-duplicate-imports', 'no-magic-numbers'];
  const securityRules = ['no-eval', 'no-implied-eval', 'no-new-func'];
  const bestPracticeRules = ['eqeqeq', 'no-var', 'prefer-const', 'no-console'];
  
  if (complexityRules.some(rule => ruleId.includes(rule))) return 'complexity';
  if (codeSmellRules.some(rule => ruleId.includes(rule))) return 'code-smell';
  if (securityRules.some(rule => ruleId.includes(rule))) return 'security';
  if (bestPracticeRules.some(rule => ruleId.includes(rule))) return 'best-practice';
  
  return 'other';
}

/**
 * Categorize PHPCS rule into quality categories
 */
function categorizePHPCSRule(source) {
  if (!source) return 'other';
  
  if (source.includes('Complexity')) return 'complexity';
  if (source.includes('UnusedVariable') || source.includes('UnreachableCode')) return 'code-smell';
  if (source.includes('Security')) return 'security';
  if (source.includes('BestPractice')) return 'best-practice';
  
  return 'other';
}

/**
 * Generate quality summary statistics
 */
function generateSummary(issues) {
  const summary = {
    total: issues.length,
    errors: issues.filter(i => i.severity === 'error').length,
    warnings: issues.filter(i => i.severity === 'warning').length,
    byCategory: {},
    topIssues: []
  };
  
  // Count by category
  for (const issue of issues) {
    if (!summary.byCategory[issue.category]) {
      summary.byCategory[issue.category] = 0;
    }
    summary.byCategory[issue.category]++;
  }
  
  // Find most common issues
  const issueCounts = {};
  for (const issue of issues) {
    const key = `${issue.rule}: ${issue.message}`;
    issueCounts[key] = (issueCounts[key] || 0) + 1;
  }
  
  summary.topIssues = Object.entries(issueCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([issue, count]) => ({ issue, count }));
  
  return summary;
}

/**
 * Main execution
 */
async function main() {
  const args = process.argv.slice(2);
  
  if (args.length === 0) {
    console.error('Usage: node analyze-quality.mjs <file-path>');
    console.error('       node analyze-quality.mjs --all-js');
    console.error('       node analyze-quality.mjs --all-php');
    process.exit(1);
  }
  
  const target = args[0];
  
  // Check if file exists
  const filePath = path.resolve(PROJECT_ROOT, target);
  
  try {
    await fs.access(filePath);
  } catch (error) {
    console.error(JSON.stringify({
      error: 'File not found',
      file: target,
      issues: []
    }, null, 2));
    process.exit(1);
  }
  
  // Determine file type
  const ext = path.extname(filePath).toLowerCase();
  let issues = [];
  
  if (['.js', '.jsx', '.ts', '.tsx', '.mjs'].includes(ext)) {
    issues = await analyzeJavaScript(filePath);
  } else if (ext === '.php') {
    issues = await analyzePHP(filePath);
  } else {
    console.error(JSON.stringify({
      error: 'Unsupported file type',
      file: target,
      supportedTypes: ['.js', '.jsx', '.ts', '.tsx', '.mjs', '.php'],
      issues: []
    }, null, 2));
    process.exit(1);
  }
  
  // Generate output
  const output = {
    file: path.relative(PROJECT_ROOT, filePath),
    analyzed: new Date().toISOString(),
    summary: generateSummary(issues),
    issues: issues
  };
  
  console.log(JSON.stringify(output, null, 2));
  
  // Exit with code 0 (always success - AI should parse the JSON)
  process.exit(0);
}

main().catch(error => {
  console.error(JSON.stringify({
    error: 'Analysis failed',
    message: error.message,
    stack: error.stack,
    issues: []
  }, null, 2));
  process.exit(1);
});
