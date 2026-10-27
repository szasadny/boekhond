// Library API, not the CLI: the packaged dogescript bin throws on any input.
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
