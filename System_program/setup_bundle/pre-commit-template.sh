#!/bin/sh

# Enterprise Agent System - Pre-commit Guard
# To install: 
# 1. Copy to .git/hooks/pre-commit
# 2. chmod +x .git/hooks/pre-commit

echo "🔍 Running Enterprise Quality Guards..."

# 1. Check feature tags
node System_program/tools/enforce-file-tags.mjs
if [ $? -ne 0 ]; then
  echo "❌ Error: Missing @feature tags. Commit aborted."
  exit 1
fi

# 2. Auto-regenerate documentation
node System_program/tools/build-universal-mapping.mjs
git add System_program/*.json System_program/*.md

echo "✅ All guards passed!"
exit 0
