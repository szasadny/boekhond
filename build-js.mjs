// Boekhond asset build: compile every static/djs/*.djs to static/js/*.js.
//
// We call the dogescript *library API* deliberately: the packaged `dogescript`
// CLI bin is broken in 2.4.3 (it throws its own bundle on any input). The library
// entrypoint is reliable. Dogescript passes plain JS through unchanged, so the
// .djs sources are mostly plain DOM JS (its keyword syntax mis-compiles real DOM
// code) with `shh` line-comments — the "gaps -> plain JS" rule.
import dogescript from "dogescript";
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from "node:fs";
import { join } from "node:path";

const SRC = "static/djs";
const OUT = "static/js";

mkdirSync(OUT, { recursive: true });

const sources = readdirSync(SRC).filter((f) => f.endsWith(".djs"));
if (sources.length === 0) {
  console.error(`geen .djs bronnen in ${SRC}/`);
  process.exit(1);
}

for (const src of sources) {
  const inPath = join(SRC, src);
  const outPath = join(OUT, src.replace(/\.djs$/, ".js"));
  const js = dogescript(readFileSync(inPath, "utf8"), { beautify: true, es6: true });
  writeFileSync(outPath, js);
  console.log(`${inPath} -> ${outPath} (${js.length} bytes)`);
}
