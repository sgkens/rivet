import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = resolve(fileURLToPath(new URL('..', import.meta.url)));
const hugoArguments = [
  '--source',
  'docs',
  '--destination',
  '../public',
  '--cleanDestinationDir',
  '--minify',
];

const localBuild = spawnSync('hugo', hugoArguments, {
  cwd: projectRoot,
  stdio: 'inherit',
});

let buildStatus;
if (!localBuild.error) buildStatus = localBuild.status ?? 1;

if (localBuild.error && localBuild.error.code !== 'ENOENT') throw localBuild.error;

if (localBuild.error?.code === 'ENOENT') {
  console.log('Hugo was not found on PATH; using ghcr.io/gohugoio/hugo:v0.164.0.');
  const containerBuild = spawnSync(
    'docker',
    [
      'run',
      '--rm',
      '-v',
      `${projectRoot}:/src`,
      'ghcr.io/gohugoio/hugo:v0.164.0',
      '--source',
      '/src/docs',
      '--destination',
      '/src/public',
      '--cleanDestinationDir',
      '--minify',
    ],
    {
      cwd: projectRoot,
      stdio: 'inherit',
    }
  );

  if (containerBuild.error?.code === 'ENOENT') {
    console.error('Documentation build requires Hugo Extended or Docker.');
    process.exit(1);
  }
  if (containerBuild.error) throw containerBuild.error;
  buildStatus = containerBuild.status ?? 1;
}

if (buildStatus !== 0) process.exit(buildStatus);

// One content-derived revision prevents a deployment from combining new HTML
// controls with cached utility/runtime JavaScript from an earlier build. This
// covers both the Web Utility playground and the main docs site's own script
// tags/module imports (docs.js, gallery.js, examples.js, home.js,
// asciiam-animations.js) — every one of them ends up importing the same
// core asciiam bundle, so a stale cached copy of any of them can keep
// serving a fixed bug indefinitely even after a fresh deployment.
const revisionSources = [
  'public/webutil/index.html',
  'public/webutil/js/webutil.js',
  'public/webutil/js/webutil-code.js',
  'public/webutil/js/webutil-sequence.js',
  'public/webutil/libs/asciiam.js',
];
const sourceContents = await Promise.all(revisionSources.map((file) => readFile(resolve(projectRoot, file), 'utf8')));
const assetRevision = createHash('sha256').update(sourceContents.join('\0')).digest('hex').slice(0, 12);

// The docs.js script tag lives in baseof.html, which every generated page
// extends, and js/docs.js itself carries the placeholder too (its import of
// asciiam-animations.js) — rather than hand-list every page, walk every
// generated .html and public/js/*.js file and substitute wherever the
// placeholder actually appears.
const publicDir = resolve(projectRoot, 'public');
const entries = await readdir(publicDir, { recursive: true, withFileTypes: true });
const substitutionTargets = entries
  .filter((entry) => entry.isFile() && (entry.name.endsWith('.html') || entry.name.endsWith('.js')))
  .map((entry) => resolve(entry.parentPath ?? entry.path, entry.name));
await Promise.all(substitutionTargets.map(async (path) => {
  const source = await readFile(path, 'utf8');
  if (!source.includes('__ASSET_REVISION__')) return;
  await writeFile(path, source.replaceAll('__ASSET_REVISION__', assetRevision));
}));
console.log(`Asset revision: ${assetRevision}`);
