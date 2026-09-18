/** Generate original synthetic fixtures against a separately supplied Probably 0.1 runtime.
 * No upstream implementation or hosted model recordings are included in this repo.
 * Usage: bun scripts/generate-oracle-fixtures.ts /absolute/path/to/upstream/src/runtime.ts
 */
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
const source = process.argv[2];
if (!source) throw new Error('Supply the separately downloaded upstream src/runtime.ts path.');
const { run } = await import(pathToFileURL(resolve(source)).href);
const provider = {
  async write(prompt: string, value: unknown) { return `Edited: ${value ?? prompt}`; },
  async judge(value: unknown, labels: string[]) {
    const text = String(value);
    const first = text === 'ambiguous' ? 0.6 : text.startsWith('Edited:') || text === 'no' ? 0.1 : 0.9;
    return Object.fromEntries(labels.map((label, i) => [label, i === 0 ? first : (1 - first) / (labels.length - 1)]));
  }
};
const branch = 'if input() feels "ready" with confidence 80% { print("go") } otherwise maybe { print("ask") } else { print("wait") }';
const programs: [string, string][] = [
  ['print("Hello, doubt.") print(4.5) print(false)', ''],
  ['let value=input() print(value)', '🦆 exact input'],
  [branch, 'yes'], [branch, 'no'], [branch, 'ambiguous'],
  ['chaos { ' + branch + ' }', 'yes'],
  ['chaos { ' + branch + ' }', 'ambiguous'],
  ['let draft=llm "simplify" using input() print(draft)', 'verbose'],
  ['let draft=write "simplify" print(draft)', ''],
  ['let draft=input() while draft feels "verbose" { draft=llm "simplify" using draft } print(draft)', 'verbose'],
  ['match input() { "first" => { print("1") } "second" => { print("2") } "third" => { print("3") } }', 'no'],
  ['let x="outer" repeat 2 { let local="new" x=local } print(x)', ''],
  ['let x="outer" repeat 1 { let x="inner" print(x) } print(x)', ''],
  ['// comments and source lines\nlet message="one\\ntwo";\nprint(message);', ''],
  ['if input() feels "ready" with confidence 80% { print("yes") } else { print("no") }', 'ambiguous'],
  ['print(0.000001) print(0.0000001) print(100000000000000000000) print(1000000000000000000000)', ''],
  ['match input() { "" => {print("empty")} "other" => {print("other")} }', 'yes']
];
const success = [];
for (const [source, input] of programs) success.push(await run(source, provider, { input, random: () => 0.95 }));
const rejected = [
  'print(process.env)', 'let x = fetch("url")', 'let if = "x"',
  'repeat 0 {}', 'repeat 6 {}', 'match "x" {"one" => {}}',
  'if input() feels "ready" with confidence 49% {}',
  'print("unterminated)', 'let x=llm "a" using llm "b"',
  'print(missing)', 'let x=1 let x=2', 'print("x") }',
  'repeat 1 {'.repeat(13) + '}'.repeat(13)
];
for (const source of rejected) {
  let failed = false;
  try { await run(source, provider); } catch { failed = true; }
  if (!failed) throw new Error(`Reference accepted a rejected fixture: ${source}`);
}
const destination = new URL('../Tests/MaybeTests/Fixtures/oracle.json', import.meta.url);
await Bun.write(destination, JSON.stringify({ provenance: 'Original synthetic fixtures executed with Probably 0.1; no live model calls.', success, rejected }, null, 2) + '\n');
console.log(`Generated ${success.length} successful recordings and ${rejected.length} rejected programs.`);
