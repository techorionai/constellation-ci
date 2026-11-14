import { copyFileSync, mkdirSync } from "node:fs";

mkdirSync(new URL("../dist", import.meta.url), { recursive: true });
copyFileSync(new URL("../src/index.js", import.meta.url), new URL("../dist/index.js", import.meta.url));
console.log("Build passed.");
