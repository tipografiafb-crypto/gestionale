import globals from "globals";

export default [
  {
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: {
        ...globals.browser,
        ...globals.node,
        ...globals.jquery,
        wp: "readonly",
        jQuery: "readonly",
        ajaxurl: "readonly",
        fabric: "readonly"
      }
    },
    rules: {
      'complexity': ['warn', 10],
      'max-depth': ['warn', 4],
      'max-nested-callbacks': ['warn', 3],
      'max-lines-per-function': ['warn', { max: 50, skipBlankLines: true, skipComments: true }],
      'max-params': ['warn', 4],
      'max-statements': ['warn', 20],
      'no-unused-vars': ['warn', { vars: 'all', args: 'none' }],
      'no-unreachable': 'error',
      'no-duplicate-imports': 'error',
      'no-magic-numbers': ['warn', { ignore: [0, 1, -1], ignoreArrayIndexes: true }],
      'no-eval': 'error',
      'no-implied-eval': 'error',
      'no-new-func': 'error',
      'eqeqeq': ['warn', 'always'],
      'no-var': 'warn',
      'prefer-const': 'warn',
      'no-console': 'off'
    }
  }
];
