#!/usr/bin/env node

// Contracts Checker System
// Verifies @contracts declarations against actual code implementation

import { promises as fs } from "fs";
import path from "path";

const ROOT = process.argv[2] || ".";

// Contract validation patterns
const CONTRACT_PATTERNS = {
  // Event contracts: on(event_name) => action
  event: /on\s*\(\s*([^)]+)\s*\)\s*=>\s*(.+)/g,
  // Hook contracts: hook(hook_name) => implementation  
  hook: /hook\s*\(\s*([^)]+)\s*\)\s*=>\s*(.+)/g,
  // Method contracts: method(params) => return_type
  method: /(\w+)\s*\(\s*([^)]*)\s*\)\s*=>\s*(.+)/g
};

// Implementation detection patterns
const IMPLEMENTATION_PATTERNS = {
  // JavaScript event listeners
  js_events: /\.(?:on|addEventListener|bind)\s*\(\s*['"]([^'"]+)['"]|dispatchEvent\s*\([^)]*['"]([^'"]+)['"]/g,
  // PHP hooks
  php_hooks: /add_(?:action|filter)\s*\(\s*['"]([^'"]+)['"][\s\S]*?['"]([^'"]+)['"]|add_(?:action|filter)\s*\(\s*['"]([^'"]+)['"][\s\S]*?array\s*\(\s*\$this\s*,\s*['"]([^'"]+)['"]/g,
  // Method definitions
  php_methods: /(?:public|private|protected)?\s*function\s+(\w+)\s*\(/g,
  js_methods: /(\w+)\s*[:\(]\s*function|(\w+)\s*=>\s*|(\w+)\s*:\s*\(/g
};

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
    
    if (["contracts"].includes(key)) {
      value = value.split(",").map(s => s.trim()).filter(Boolean);
    }
    
    fields[key] = value;
  }
  return fields;
}

function parseContracts(contractsArray) {
  if (!Array.isArray(contractsArray)) {
    contractsArray = [contractsArray];
  }
  
  const contracts = {
    events: [],
    hooks: [],
    methods: []
  };
  
  for (const contractStr of contractsArray) {
    // Parse event contracts
    let match;
    const eventPattern = /on\s*\(\s*([^)]+)\s*\)\s*=>\s*(.+)/g;
    while ((match = eventPattern.exec(contractStr)) !== null) {
      contracts.events.push({
        event: match[1].trim().replace(/['"`]/g, ''),
        action: match[2].trim()
      });
    }
    
    // Parse hook contracts  
    const hookPattern = /hook\s*\(\s*([^)]+)\s*\)\s*=>\s*(.+)/g;
    while ((match = hookPattern.exec(contractStr)) !== null) {
      contracts.hooks.push({
        hook: match[1].trim().replace(/['"`]/g, ''),
        implementation: match[2].trim()
      });
    }
    
    // Parse method contracts
    const methodPattern = /(\w+)\s*\(\s*([^)]*)\s*\)\s*=>\s*(.+)/g;
    while ((match = methodPattern.exec(contractStr)) !== null) {
      if (!match[0].includes('on(') && !match[0].includes('hook(')) {
        contracts.methods.push({
          method: match[1].trim(),
          params: match[2].trim(),
          returns: match[3].trim()
        });
      }
    }
  }
  
  return contracts;
}

function findImplementations(content, filePath) {
  const implementations = {
    events: [],
    hooks: [],
    methods: []
  };
  
  const isJs = /\.(js|jsx|ts)$/i.test(filePath);
  const isPhp = filePath.endsWith('.php');
  
  if (isJs) {
    // Find JS events
    let match;
    const jsEventPattern = /\.(?:on|addEventListener|bind|trigger)\s*\(\s*['"]([^'"]+)['"]|dispatchEvent\s*\([^)]*['"]([^'"]+)['"]/g;
    while ((match = jsEventPattern.exec(content)) !== null) {
      const eventName = match[1] || match[2];
      if (eventName) {
        implementations.events.push(eventName);
      }
    }
    
    // Find JS methods
    const jsMethodPattern = /(\w+)\s*:\s*function|function\s+(\w+)\s*\(|(\w+)\s*=>\s*|const\s+(\w+)\s*=\s*\(/g;
    while ((match = jsMethodPattern.exec(content)) !== null) {
      const methodName = match[1] || match[2] || match[3] || match[4];
      if (methodName && !['if', 'for', 'while', 'switch'].includes(methodName)) {
        implementations.methods.push(methodName);
      }
    }
  }
  
  if (isPhp) {
    // Find PHP hooks
    const phpHookPattern = /add_(?:action|filter)\s*\(\s*['"]([^'"]+)['"][\s\S]*?['"]([^'"]+)['"]|add_(?:action|filter)\s*\(\s*['"]([^'"]+)['"][\s\S]*?array\s*\(\s*\$this\s*,\s*['"]([^'"]+)['"]/g;
    while ((match = phpHookPattern.exec(content)) !== null) {
      const hookName = match[1] || match[3];
      if (hookName) {
        implementations.hooks.push(hookName);
      }
    }
    
    // Find PHP methods
    const phpMethodPattern = /(?:public|private|protected)?\s*function\s+(\w+)\s*\(/g;
    while ((match = phpMethodPattern.exec(content)) !== null) {
      const methodName = match[1];
      if (methodName && !['__construct', '__destruct'].includes(methodName)) {
        implementations.methods.push(methodName);
      }
    }
  }
  
  return implementations;
}

function validateContracts(contracts, implementations, filePath) {
  const violations = [];
  
  // Check event contracts
  for (const eventContract of contracts.events) {
    if (!implementations.events.includes(eventContract.event)) {
      violations.push({
        type: 'missing_event',
        contract: eventContract,
        file: filePath,
        message: `Event "${eventContract.event}" declared in contract but not found in implementation`
      });
    }
  }
  
  // Check hook contracts
  for (const hookContract of contracts.hooks) {
    if (!implementations.hooks.includes(hookContract.hook)) {
      violations.push({
        type: 'missing_hook',
        contract: hookContract,
        file: filePath,
        message: `Hook "${hookContract.hook}" declared in contract but not found in implementation`
      });
    }
  }
  
  // Check method contracts
  for (const methodContract of contracts.methods) {
    if (!implementations.methods.includes(methodContract.method)) {
      violations.push({
        type: 'missing_method',
        contract: methodContract,
        file: filePath,
        message: `Method "${methodContract.method}" declared in contract but not found in implementation`
      });
    }
  }
  
  return violations;
}

async function checkAllContracts() {
  console.log('🔍 Scanning for contract violations...');
  
  const files = await walkDirectory(ROOT);
  const allViolations = [];
  let contractsChecked = 0;
  
  for (const filePath of files) {
    try {
      const content = await fs.readFile(filePath, 'utf-8');
      const relativePath = path.relative(ROOT, filePath);
      
      const moduleData = parseModuleHeader(content);
      if (moduleData && moduleData.contracts) {
        contractsChecked++;
        
        const contracts = parseContracts(moduleData.contracts);
        const implementations = findImplementations(content, relativePath);
        const violations = validateContracts(contracts, implementations, relativePath);
        
        allViolations.push(...violations);
      }
      
    } catch (err) {
      console.warn(`Warning: Could not process ${filePath}: ${err.message}`);
    }
  }
  
  console.log(`✓ Checked ${contractsChecked} files with @contracts declarations`);
  
  if (allViolations.length === 0) {
    console.log('✅ All contracts are properly implemented');
  } else {
    console.log(`❌ Found ${allViolations.length} contract violations:`);
    
    const groupedViolations = allViolations.reduce((acc, violation) => {
      if (!acc[violation.file]) acc[violation.file] = [];
      acc[violation.file].push(violation);
      return acc;
    }, {});
    
    for (const [file, violations] of Object.entries(groupedViolations)) {
      console.log(`\n📁 ${file}:`);
      violations.forEach(v => {
        console.log(`  ❌ ${v.message}`);
      });
    }
  }
  
  return allViolations;
}

// Self-contained runner
if (import.meta.url === `file://${process.argv[1]}`) {
  checkAllContracts()
    .then(violations => {
      process.exit(violations.length > 0 ? 1 : 0);
    })
    .catch(err => {
      console.error('Contract checker error:', err.message);
      process.exit(1);
    });
}

export { checkAllContracts, parseContracts, validateContracts };