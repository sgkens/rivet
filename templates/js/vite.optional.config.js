import { defineConfig } from 'vite';
import { cpSync, mkdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import terser from '@rollup/plugin-terser';

const pkg = JSON.parse(readFileSync(resolve('package.json'), 'utf8'));
const packageName = pkg.name.split('/').pop();
const packageDist = `dist/${packageName}`;
const bundleDist = `${packageDist}/dist`;
const isDebug = process.env.npm_config_mode === 'debug';
const name = isDebug ? `${packageName}-debug` : `${packageName}-metrics`;
const entry = isDebug ? `src/${packageName}-debug.js` : `src/${packageName}-metrics.js`;
const capitalizedPkg = packageName.replace(/(?:^|[-_])(\w)/g, (_, c) => c.toUpperCase());
const globalName = isDebug ? `${capitalizedPkg}Debug` : `${capitalizedPkg}Metrics`;
const external = isDebug ? ['@staticcanvas/logcad'] : [];
/** Vite plugin that copies optional bundles into the documentation web utility. */
const stageOptionalAssets = {
  name: 'stage-optional-web-assets',
  closeBundle() {
    const destination = resolve('docs/static/webutil/libs');
    mkdirSync(destination, { recursive: true });
    cpSync(resolve(bundleDist), destination, { recursive: true });
  },
};
/**
 * Builds one Rollup output configuration for an optional bundle format.
 * @param {string} format Rollup output format.
 * @param {string} fileName Generated file name.
 * @param {Array<object>} [plugins=[]] Rollup plugins.
 * @returns {object} Rollup output configuration.
 */
const output = (format, fileName, plugins = []) => ({
  format,
  ...(format === 'umd' ? { name: globalName } : {}),
  ...(format === 'umd' ? { exports: 'named' } : {}),
  dir: bundleDist,
  entryFileNames: fileName,
  plugins,
  ...(external.length ? { globals: { '@staticcanvas/logcad': 'logcad' } } : {}),
});

export default defineConfig({
  build: {
    outDir: 'dist',
    emptyOutDir: false,
    copyPublicDir: false,
    sourcemap: true,
    target: 'es2015',
    lib: { entry: resolve(entry), name: globalName, fileName: name },
    minify: false,
    rollupOptions: {
      external,
      output: [
        output('umd', `${name}.js`, [terser({ format: { comments: true, preamble: `/*! ${name} | ${pkg.license} */` } })]),
        output('umd', `${name}.min.js`, [terser({ format: { comments: /^!/ }, compress: true, mangle: true })]),
        output('umd', `${name}.cjs`, [terser({ format: { comments: true, preamble: `/*! ${name} | ${pkg.license} */` } })]),
        output('es', `${name}.mjs`, [terser({ format: { comments: true, preamble: `/*! ${name} | ${pkg.license} */` } })]),
        output('es', `${name}.esm.js`, [terser({ format: { comments: true, preamble: `/*! ${name} | ${pkg.license} */` } })]),
        output('es', `${name}.esm.min.js`, [terser({ format: { comments: /^!/ }, compress: true, mangle: true })]),
      ],
    },
  },
  plugins: [stageOptionalAssets],
});
