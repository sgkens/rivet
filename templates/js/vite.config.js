import { cpSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, dirname, resolve } from 'node:path';
import terser from '@rollup/plugin-terser';
import { defineConfig } from 'vite';

const projectRoot = resolve('.');
const pkg = JSON.parse(readFileSync(resolve(projectRoot, 'package.json'), 'utf8'));
const packageName = pkg.name.split('/').pop();
const configPath = resolve(projectRoot, 'repo_config.json');
const rivetConfig = existsSync(configPath)
  ? JSON.parse(readFileSync(configPath, 'utf8'))
  : {};
const jsConfig = rivetConfig.js ?? {};
const entry = resolve(projectRoot, jsConfig.entry || `src/${packageName}.js`);
const target = jsConfig.target || 'es2015';
const packageDist = resolve(projectRoot, 'dist', packageName);
const bundleDist = resolve(packageDist, 'dist');
const globalName =
  jsConfig.globalName || packageName.replace(/(?:^|[-_])(\w)/g, (_, character) => character.toUpperCase());
const banner = `/*! ${packageName} v${pkg.version} | ${pkg.homepage || ''} | ${pkg.license || ''} */`;

const outputs = [
  ['umd', `${packageName}.js`, false],
  ['umd', `${packageName}.min.js`, true],
  ['cjs', `${packageName}.cjs`, false],
  ['es', `${packageName}.mjs`, false],
  ['es', `${packageName}.esm.js`, false],
  ['es', `${packageName}.esm.min.js`, true],
].map(([format, entryFileNames, minified]) => ({
  format,
  ...(format === 'umd' ? { name: globalName } : {}),
  exports: 'named',
  dir: bundleDist,
  entryFileNames,
  banner: minified ? undefined : banner,
  plugins: minified ? [terser({ format: { comments: /^!/ }, compress: true, mangle: true })] : [],
}));

function copyWhenPresent(source, destination) {
  if (!existsSync(source)) return;
  mkdirSync(dirname(destination), { recursive: true });
  cpSync(source, destination, { recursive: true });
}

const stagePackage = {
  name: 'stage-package',
  closeBundle() {
    mkdirSync(packageDist, { recursive: true });
    const packageDocument = structuredClone(pkg);
    delete packageDocument.scripts;
    delete packageDocument.devDependencies;
    delete packageDocument.files;
    writeFileSync(resolve(packageDist, 'package.json'), `${JSON.stringify(packageDocument, null, 2)}\n`);

    copyWhenPresent(resolve(projectRoot, 'src'), resolve(packageDist, 'src'));
    copyWhenPresent(resolve(projectRoot, 'LICENSE'), resolve(packageDist, 'LICENSE'));
    copyWhenPresent(resolve(projectRoot, 'jsr.jsonc'), resolve(packageDist, 'jsr.jsonc'));
    copyWhenPresent(resolve(projectRoot, 'branding'), resolve(packageDist, 'branding'));
    const readme = existsSync(resolve(projectRoot, 'README-npm.md')) ? 'README-npm.md' : 'README.md';
    copyWhenPresent(resolve(projectRoot, readme), resolve(packageDist, 'README.md'));
  },
};

if (!existsSync(entry)) {
  throw new Error(`Configured JavaScript entry file does not exist: ${basename(entry)}`);
}

export default defineConfig({
  build: {
    outDir: packageDist,
    emptyOutDir: true,
    copyPublicDir: false,
    sourcemap: true,
    target,
    lib: { entry, name: globalName, fileName: packageName },
    minify: false,
    rollupOptions: { output: outputs },
  },
  test: {
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov'],
      include: ['src/**/*.js'],
      exclude: ['**/node_modules/**', 'tests/**'],
    },
  },
  plugins: [stagePackage],
});
