/**
 * @fileoverview Validates release bundles, archives, download metadata, and URLs.
 * @module scripts/validate-release
 */

import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const projectRoot = resolve(import.meta.dirname, '..');
const packageDocument = JSON.parse(readFileSync(join(projectRoot, 'package.json'), 'utf8'));
const packageName = packageDocument.name.split('/').pop();
const packageVersion = packageDocument.version;
const packageRoot = resolve(projectRoot, process.argv[2] || `dist/${packageName}`);
const bundleRoot = join(packageRoot, 'dist');

const requiredBundles = [
  `${packageName}.js`,
  `${packageName}.min.js`,
  `${packageName}.cjs`,
  `${packageName}.mjs`,
  `${packageName}.esm.js`,
];
const files = existsSync(bundleRoot) ? readdirSync(bundleRoot) : [];
const missingBundles = requiredBundles.filter((file) => !files.includes(file));
const archives = files.filter((file) => file.endsWith('.zip') || file.endsWith('.tar.gz'));

if (missingBundles.length || archives.length < 2) {
  throw new Error(
    `Release artifact validation failed: missing bundles [${missingBundles.join(', ')}], archives found ${archives.length}.`
  );
}

const downloadsPage = readFileSync(join(projectRoot, 'docs/content/downloads.md'), 'utf8');
if (!downloadsPage.includes('{{< release-downloads >}}')) {
  throw new Error('Downloads page must invoke the release-downloads shortcode.');
}

const downloadsShortcode = readFileSync(
  join(projectRoot, 'docs/layouts/shortcodes/release-downloads.html'),
  'utf8'
);
for (const marker of ['site.Data.releases', 'release_url', '.assets', '.url']) {
  if (!downloadsShortcode.includes(marker))
    throw new Error(`Downloads shortcode is missing metadata marker: ${marker}`);
}
for (const marker of ['source_url', 'data-download-tabs', 'role="tablist"', 'data-lume-title']) {
  if (!downloadsShortcode.includes(marker)) {
    throw new Error(`Downloads shortcode is missing release UI marker: ${marker}`);
  }
}

const docsLayout = readFileSync(join(projectRoot, 'docs/layouts/_default/baseof.html'), 'utf8');
const docsRuntime = readFileSync(join(projectRoot, 'docs/static/assets/docs.js'), 'utf8');
for (const source of ['data-metrics-src', 'data-debug-src']) {
  if (!docsLayout.includes(source)) throw new Error(`Documentation layout is missing ${source}.`);
}
for (const asset of ['lume.mjs', 'lume-metrics.mjs', 'lume-debug.mjs']) {
  const expected = `https://cdn.jsdelivr.net/npm/@staticcanvas/lume@latest/dist/${asset}`;
  if (!docsLayout.includes(expected)) {
    throw new Error(`Documentation layout must load the latest jsDelivr asset: ${asset}.`);
  }
}
for (const source of ['dataset.metricsSrc', 'dataset.debugSrc']) {
  if (!docsRuntime.includes(source)) throw new Error(`Documentation runtime is missing ${source}.`);
}
if (docsRuntime.includes("runtimeSrc.replace('lume.mjs'")) {
  throw new Error(
    'Optional documentation modules must use explicit URLs instead of filename inference.'
  );
}

const jsrManifest = readFileSync(join(projectRoot, 'jsr.jsonc'), 'utf8');
const jsrVersion = jsrManifest.match(/^\s*"version"\s*:\s*"([^"]+)"/m)?.[1];
if (!jsrVersion || jsrVersion !== packageVersion) {
  throw new Error(
    `Manifest version mismatch: package.json=${packageVersion}, jsr.jsonc=${jsrVersion || 'missing'}.`
  );
}

const releaseTag = process.env.CI_COMMIT_TAG;
if (releaseTag?.endsWith('-release')) {
  const tagVersion = releaseTag.replace(/^v/, '').replace(/-release$/, '');
  if (tagVersion !== packageVersion) {
    throw new Error(
      `Production tag ${releaseTag} does not match package.json version ${packageVersion}.`
    );
  }
}

const releaseDataPath = join(projectRoot, 'docs/data/releases.json');
if (existsSync(releaseDataPath)) {
  const releaseData = JSON.parse(readFileSync(releaseDataPath, 'utf8'));
  if (!Array.isArray(releaseData.versions))
    throw new Error('Release metadata must contain a versions array.');
  for (const version of releaseData.versions) {
    if (
      !version.version ||
      !version.release_url ||
      !version.source_url ||
      !Array.isArray(version.assets)
    ) {
      throw new Error(
        'Each release metadata entry requires version, release_url, source_url, and assets.'
      );
    }
    for (const asset of version.assets) {
      if (!asset.name || !/^https:\/\//.test(asset.url))
        throw new Error(`Invalid release asset URL for ${version.version}.`);
    }
  }
}

console.log(
  `Release validation passed: ${requiredBundles.length} required bundles and ${archives.length} archives.`
);
