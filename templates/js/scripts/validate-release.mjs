/** Validates package outputs using package metadata and optional Rivet rules. */

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { resolve, sep } from 'node:path';

const projectRoot = resolve(import.meta.dirname, '..');
const packageDocument = JSON.parse(readFileSync(resolve(projectRoot, 'package.json'), 'utf8'));
const packageName = packageDocument.name.split('/').pop();
const packageRoot = resolve(projectRoot, process.argv[2] || `dist/${packageName}`);
const configPath = resolve(projectRoot, 'repo_config.json');
const rivetConfig = existsSync(configPath)
  ? JSON.parse(readFileSync(configPath, 'utf8'))
  : {};
const validation = rivetConfig.releaseValidation ?? {};

function collectPackageFiles(value, files = new Set()) {
  if (typeof value === 'string' && value.startsWith('./')) files.add(value.slice(2));
  else if (Array.isArray(value)) value.forEach((item) => collectPackageFiles(item, files));
  else if (value && typeof value === 'object') {
    Object.values(value).forEach((item) => collectPackageFiles(item, files));
  }
  return files;
}

function resolveInside(root, relativePath) {
  const resolved = resolve(root, relativePath);
  if (resolved !== root && !resolved.startsWith(`${root}${sep}`)) {
    throw new Error(`Release validation path escapes its root: ${relativePath}`);
  }
  return resolved;
}

const configuredFiles = Array.isArray(validation.requiredFiles)
  ? validation.requiredFiles.filter(Boolean)
  : [];
const metadataFiles = collectPackageFiles({
  main: packageDocument.main,
  module: packageDocument.module,
  browser: packageDocument.browser,
  exports: packageDocument.exports,
});
const requiredFiles = configuredFiles.length ? configuredFiles : [...metadataFiles];
const missingFiles = requiredFiles.filter(
  (file) => !existsSync(resolveInside(packageRoot, file.replaceAll('{packageName}', packageName)))
);
if (missingFiles.length) {
  throw new Error(`Release artifact validation failed: missing files [${missingFiles.join(', ')}].`);
}

const bundleRoot = resolve(packageRoot, 'dist');
const bundleFiles = existsSync(bundleRoot) ? readdirSync(bundleRoot) : [];
const archives = bundleFiles.filter((file) => file.endsWith('.zip') || file.endsWith('.tar.gz'));
const minimumArchiveCount = Number(validation.minimumArchiveCount || 0);
if (archives.length < minimumArchiveCount) {
  throw new Error(
    `Release artifact validation failed: expected ${minimumArchiveCount} archive(s), found ${archives.length}.`
  );
}

for (const rule of Array.isArray(validation.textFiles) ? validation.textFiles : []) {
  if (!rule?.path) throw new Error('Each releaseValidation.textFiles rule requires a path.');
  const filePath = resolveInside(projectRoot, rule.path);
  if (!existsSync(filePath)) throw new Error(`Release validation text file not found: ${rule.path}`);
  const content = readFileSync(filePath, 'utf8');
  for (const marker of rule.requiredMarkers ?? []) {
    if (!content.includes(marker)) throw new Error(`${rule.path} is missing required marker: ${marker}`);
  }
  for (const marker of rule.forbiddenMarkers ?? []) {
    if (content.includes(marker)) throw new Error(`${rule.path} contains forbidden marker: ${marker}`);
  }
}

const jsrPath = resolve(projectRoot, 'jsr.jsonc');
if (existsSync(jsrPath)) {
  const jsrVersion = readFileSync(jsrPath, 'utf8').match(/^\s*"version"\s*:\s*"([^"]+)"/m)?.[1];
  if (!jsrVersion || jsrVersion !== packageDocument.version) {
    throw new Error(
      `Manifest version mismatch: package.json=${packageDocument.version}, jsr.jsonc=${jsrVersion || 'missing'}.`
    );
  }
}

const releaseTag = process.env.CI_COMMIT_TAG;
if (releaseTag?.endsWith('-release')) {
  const tagVersion = releaseTag.replace(/^v/, '').replace(/-release$/, '');
  if (tagVersion !== packageDocument.version) {
    throw new Error(
      `Production tag ${releaseTag} does not match package.json version ${packageDocument.version}.`
    );
  }
}

console.log(
  `Release validation passed: ${requiredFiles.length} required file(s), ${archives.length} archive(s), ${(validation.textFiles ?? []).length} text rule(s).`
);
