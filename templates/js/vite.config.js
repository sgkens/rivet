import { defineConfig } from 'vite';
import copy from 'rollup-plugin-copy';
import { resolve } from 'node:path';
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync } from 'node:fs';
import terser from '@rollup/plugin-terser';

const pkg = JSON.parse(readFileSync(resolve('package.json'), 'utf8'));
const packageName = pkg.name.split('/').pop();
const packageDist = `dist/${packageName}`;
const bundleDist = `${packageDist}/dist`;
const globalName = packageName.replace(/(?:^|[-_])(\w)/g, (_, c) => c.toUpperCase());

const banner = `/*! ${packageName} v${pkg.version} | ${pkg.homepage} | ${pkg.license} */`;

/**
 * Creates the Vite plugin that stages generated bundles and documentation assets.
 * @returns {{name: string, closeBundle: () => void}} Vite staging plugin.
 */
function stageWebUtilityAssets() {
  return {
    name: 'stage-web-utility-assets',
    closeBundle() {
      const destination = resolve('docs/static/webutil/libs');
      rmSync(destination, { recursive: true, force: true });
      mkdirSync(destination, { recursive: true });
      if (existsSync(resolve(bundleDist))) {
        cpSync(resolve(bundleDist), destination, { recursive: true });
      }
      const brandingDestination = resolve('docs/static/webutil/assets/branding');
      mkdirSync(brandingDestination, { recursive: true });
      if (existsSync(resolve(`branding/${packageName}-logo.svg`))) {
        cpSync(resolve(`branding/${packageName}-logo.svg`), resolve(brandingDestination, `${packageName}-logo.svg`));
      }
      const docsData = resolve('docs/data');
      mkdirSync(docsData, { recursive: true });
      cpSync(resolve('package.json'), resolve(docsData, 'package.json'));
    },
  };
}

export default defineConfig({
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    copyPublicDir: false,
    sourcemap: true,
    target: 'es2015',
    lib: {
      entry: resolve(`src/${packageName}.js`),
      name: globalName,
      fileName: packageName,
    },
    minify: false,
    rollupOptions: {
      output: [
        {
          format: 'umd',
          name: globalName,
          dir: bundleDist,
          entryFileNames: `${packageName}.js`,
          exports: 'named',
          plugins: [terser({ format: { comments: true, preamble: banner } })],
        },
        {
          format: 'umd',
          name: globalName,
          dir: bundleDist,
          entryFileNames: `${packageName}.min.js`,
          exports: 'named',
          plugins: [terser({ format: { comments: /^!/ }, compress: true, mangle: true })],
        },
        {
          format: 'umd',
          name: globalName,
          dir: bundleDist,
          entryFileNames: `${packageName}.cjs`,
          exports: 'named',
          plugins: [terser({ format: { comments: true, preamble: banner } })],
        },
        {
          format: 'es',
          dir: bundleDist,
          entryFileNames: `${packageName}.mjs`,
          plugins: [terser({ format: { comments: true, preamble: banner } })],
        },
        {
          format: 'es',
          dir: bundleDist,
          entryFileNames: `${packageName}.esm.js`,
          plugins: [terser({ format: { comments: true, preamble: banner } })],
        },
        {
          format: 'es',
          dir: bundleDist,
          entryFileNames: `${packageName}.esm.min.js`,
          plugins: [terser({ format: { comments: /^!/ }, compress: true, mangle: true })],
        },
      ],
    },
  },
  test: {
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov'],
      include: ['src/**/*.js'],
      exclude: ['**/node_modules/**', 'tests/**', `src/${packageName}-metrics.js`, `src/${packageName}-debug.js`],
    },
  },
  plugins: [
    copy({
      targets: [
        { src: 'README-npm.md', dest: packageDist, rename: 'README.md' },
        {
          src: 'package.json',
          dest: packageDist,
          transform: (contents) => {
            const packageJson = JSON.parse(contents.toString());
            delete packageJson.scripts;
            delete packageJson.devDependencies;
            delete packageJson.files;
            return JSON.stringify(packageJson, null, 2);
          },
        },
        { src: 'src', dest: packageDist },
        { src: 'branding', dest: packageDist },
        { src: 'LICENSE', dest: packageDist },
        { src: 'jsr.jsonc', dest: packageDist },
      ],
      hook: 'writeBundle',
    }),
    stageWebUtilityAssets(),
  ],
});
