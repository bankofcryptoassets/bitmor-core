// This script patches the bignumber.js package to add an "exports" field in its package.json.
import { readFileSync, writeFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BIGNUMBER_PKG_PATH = join(
  __dirname,
  'node_modules',
  'bignumber.js',
  'package.json'
);

try {
  const pkgJson = JSON.parse(readFileSync(BIGNUMBER_PKG_PATH, 'utf8'));

  if (pkgJson.exports) {
    console.log('bignumber.js already patched');
    process.exit(0);
  }

  pkgJson.exports = {
    '.': {
      import: './bignumber.mjs',
      require: './bignumber.js'
    }
  };

  writeFileSync(BIGNUMBER_PKG_PATH, JSON.stringify(pkgJson, null, 2) + '\n');

  console.log('Successfully patched bignumber.js package.json');
} catch (error) {
  console.warn('Failed to patch bignumber.js:', error.message);
  process.exit(0);
}
