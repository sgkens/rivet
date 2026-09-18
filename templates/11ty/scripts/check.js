#!/usr/bin/env node
import fs from 'node:fs';

console.log('Checking Eleventy theme integrity...');
if (!fs.existsSync('eleventy.config.js') && !fs.existsSync('.eleventy.js') && !fs.existsSync('eleventy.config.mjs')) {
  console.error('Error: eleventy configuration file not found');
  process.exit(1);
}
console.log('Integrity check passed.');
