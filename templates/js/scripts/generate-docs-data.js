/**
 * @file generate-docs-data.js
 * @description Node.js script to extract preset metadata, copy source modules into static library locations, and generate JSON docs manifests.
 * @module generate-docs-data
 */

import { cp, mkdir, readFile, writeFile } from "node:fs/promises";
import asciiam from "../src/asciiam.js";

const packageMetadata = JSON.parse(await readFile(new URL("../package.json", import.meta.url), "utf8"));
const docsData = new URL("../docs/data/", import.meta.url);
const docsLibrary = new URL("../docs/static/libs/", import.meta.url);
const docsLumeLibrary = new URL("../docs/static/libs/lume/", import.meta.url);
const lumeModule = new URL("../node_modules/@staticcanvas/lume/", import.meta.url);
const docsBranding = new URL("../docs/static/branding/", import.meta.url);
const docsImages = new URL("../docs/static/images/", import.meta.url);

const sparseModes = new Set(["matrix", "snow", "sparkle", "fire", "starfield", "orbit"]);
const revealModes = new Set(["fadeIn", "fadeOut", "typewriter"]);
const spatialModes = new Set(["ripple", "vortex", "plasma", "orbit", "hoverZone", "clickZone"]);

/**
 * Maps an animation mode algorithm name to its gallery filter category.
 *
 * @param {string} mode Mode algorithm key.
 * @returns {string} Category identifier string.
 */
const categoryFor = (mode) => {
    if (mode === "image") return "image";
    if (sparseModes.has(mode)) return "particles";
    if (revealModes.has(mode)) return "reveals";
    if (spatialModes.has(mode)) return "spatial";
    return "fields";
};

const presets = Object.entries(asciiam.presets).map(([name, options]) => ({
    name,
    title: name.replace(/([a-z0-9])([A-Z])/g, "$1 $2").replace(/^./, (character) => character.toUpperCase()),
    mode: options.mode || "wave",
    category: categoryFor(options.mode || "wave"),
    previewable: options.mode !== "image" || Boolean(options.image),
    options,
}));

await Promise.all([
    mkdir(docsData, { recursive: true }),
    mkdir(docsLibrary, { recursive: true }),
    mkdir(docsLumeLibrary, { recursive: true }),
    mkdir(docsBranding, { recursive: true }),
    mkdir(docsImages, { recursive: true }),
]);
await Promise.all([
    writeFile(new URL("presets.json", docsData), `${JSON.stringify({ version: packageMetadata.version, builtInModeCount: asciiam.BUILT_IN_MODES.length, presets }, null, 2)}\n`),
    cp(new URL("../src/asciiam.js", import.meta.url), new URL("asciiam.esm.js", docsLibrary)),
    cp(new URL("../src/asciiam.js", import.meta.url), new URL("asciiam.mjs", docsLibrary)),
    cp(new URL("../src/mesh.js", import.meta.url), new URL("mesh.js", docsLibrary)),
    cp(new URL("../src/gltf.js", import.meta.url), new URL("gltf.js", docsLibrary)),
    cp(new URL("../branding/asciiam-logo.svg", import.meta.url), new URL("asciiam-logo.svg", docsBranding)),
    cp(new URL("../docs/static/webutil/assets/images/domitian-tunnel-5122424_1920.jpg", import.meta.url), new URL("domitian-tunnel-5122424_1920.jpg", docsImages)),
    // Vendor the tooltip engine used site-wide, rather than pulling it from a CDN at runtime.
    cp(new URL("dist/lume.mjs", lumeModule), new URL("lume.mjs", docsLumeLibrary)),
    cp(new URL("dist/lume.mjs.map", lumeModule), new URL("lume.mjs.map", docsLumeLibrary)),
    cp(new URL("src/lume.css", lumeModule), new URL("lume.css", docsLumeLibrary)),
]);

console.log(`Documentation data: v${packageMetadata.version}; ${presets.length} preset(s)`);
