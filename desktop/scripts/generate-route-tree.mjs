#!/usr/bin/env node
/**
 * Regenerate src/app/routeTree.gen.ts (includes virtual routes from src/app/routes.ts).
 * Use when `tsr generate` or Vite was started before a new virtual route was added.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Generator, getConfig } from "@tanstack/router-generator";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const config = getConfig(undefined, root);
await new Generator({ config, root }).run();
const treePath = path.join(root, "src/app/routeTree.gen.ts");
const text = fs.readFileSync(treePath, "utf8");
const count = (text.match(/scenarios/g) ?? []).length;
if (count === 0) {
  console.error(
    "routeTree.gen.ts has no /scenarios entries; check src/app/routes.ts",
  );
  process.exit(1);
}
console.log(`Wrote ${treePath} (${count} scenarios references)`);
