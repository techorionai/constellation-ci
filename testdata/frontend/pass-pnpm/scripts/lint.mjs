import { readFileSync } from "node:fs";

const source = readFileSync(new URL("../src/index.js", import.meta.url), "utf8");
if (source.includes("debugger")) {
  console.error("src/index.js has a debugger statement.");
  process.exit(1);
}
console.log("Lint passed.");
