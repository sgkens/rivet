/** Checks the production bundle against an optional repository-configured gzip budget. */

import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { gzipSync } from 'node:zlib';

const projectRoot = resolve(import.meta.dirname, '..');
const pkg = JSON.parse(readFileSync(resolve(projectRoot, 'package.json'), 'utf8'));
const packageName = pkg.name.split('/').pop();
const configPath = resolve(projectRoot, 'repo_config.json');
const rivetConfig = existsSync(configPath)
  ? JSON.parse(readFileSync(configPath, 'utf8'))
  : {};
const maxGzipBytes = Number(rivetConfig.js?.bundleSize?.maxGzipBytes || 0);

if (maxGzipBytes <= 0) {
  console.log('Bundle size check skipped: js.bundleSize.maxGzipBytes is not configured.');
  process.exit(0);
}

const bundlePath = resolve(projectRoot, 'dist', packageName, 'dist', `${packageName}.min.js`);
const bundle = readFileSync(bundlePath);
const gzipBytes = gzipSync(bundle).byteLength;

console.log(`${bundlePath}: ${bundle.byteLength} bytes, ${gzipBytes} bytes gzip`);
if (gzipBytes > maxGzipBytes) {
  throw new Error(`Bundle exceeds the configured ${maxGzipBytes}-byte gzip budget.`);
}
