import js from '@eslint/js';
import globals from 'globals';
import prettierConfig from 'eslint-config-prettier';

export default [
  js.configs.recommended,
  {
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: {
        // ... (Your manual globals kept as requested)
        console: 'readonly',
        document: 'readonly',
        window: 'readonly',
        fetch: 'readonly',
        Promise: 'readonly',
        Array: 'readonly',
        Object: 'readonly',
        String: 'readonly',
        Number: 'readonly',
        Boolean: 'readonly',
        Date: 'readonly',
        Error: 'readonly',
        RegExp: 'readonly',
        Map: 'readonly',
        Set: 'readonly',
        JSON: 'readonly',
        Math: 'readonly',
        ...globals.browser,
        ...globals.node,
      },
      parserOptions: {
        ecmaVersion: 2022,
        sourceType: 'module',
      },
    },
    rules: {
      // --- LOGIC RULES (Keep these!) ---
      'no-unused-vars': [
        'warn',
        {
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
        },
      ],
      'no-console': 'off',
      'no-undef': 'error',
      'no-redeclare': 'warn',
      'prefer-const': 'warn',
      'no-var': 'error',
      eqeqeq: ['error', 'always'],
      curly: ['error', 'all'], // Prettier respects this

      // --- STYLING RULES (HANDLED BY PRETTIER NOW) ---
      // I have commented these out because Prettier overrides them.
      // If you keep them, ESLint might yell at Prettier.

      // 'brace-style': ['error', '1tbs'],
      // 'semi': ['error', 'always'],
      // 'quotes': ['warn', 'single', { avoidEscape: true }],
      // 'comma-dangle': ['warn', 'never'],
      // 'indent': ['warn', 4, { SwitchCase: 1 }],
      // 'no-trailing-spaces': 'warn',
      // 'eol-last': ['warn', 'always']
    },
  },
  {
    files: ['src/**/*.js'],
    rules: {
      // Source-specific rules
    },
  },
  {
    files: ['**/*.test.js', '**/*.spec.js'],
    rules: {
      'no-unused-vars': 'off',
    },
  },
  {
    ignores: [
      'node_modules/**',
      'dist/**',
      'public/**',
      'docs/**',
      'coverage/**',
      'editors/zed-lirl/grammar.js',
      '*.min.js',
    ],
  },

  // <--- 2. Add Prettier Config LAST
  // This turns off any rule above that would conflict with Prettier formatting.
  prettierConfig,
];
