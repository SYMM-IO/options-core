import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));
const files = [
	"index.html",
	...readdirSync(resolve(root, "pages"))
		.filter(file => file.endsWith(".html"))
		.map(file => `pages/${file}`),
];
const problems = [];
const ids = new Map();
const read = file => readFileSync(resolve(root, file), "utf8");
const decode = text => text.replace(/&amp;/g, "&").replace(/&quot;/g, '"');
for (const file of files) {
	const html = read(file);
	const entries = [...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
	const unique = new Set(entries);
	if (unique.size !== entries.length) problems.push(`${file}: duplicate HTML IDs`);
	ids.set(resolve(root, file), unique);
	if ((html.match(/<h1[\s>]/g) || []).length !== 1) problems.push(`${file}: expected one page title`);
	if (/\[\[[^\]]+\]\]|\[!(?:info|note|warning|tip|abstract)\]/.test(html)) problems.push(`${file}: unresolved Markdown extension`);
}
for (const file of files) {
	for (const match of read(file).matchAll(/\b(?:href|src)="([^"]+)"/g)) {
		const value = decode(match[1]);
		if (/^(?:https?:|mailto:|data:)/.test(value)) continue;
		const [target, anchor] = value.split("#");
		const path = target ? resolve(root, dirname(file), decodeURIComponent(target)) : resolve(root, file);
		if (!existsSync(path)) problems.push(`${file}: missing target ${value}`);
		else if (anchor && ids.has(path) && !ids.get(path).has(decodeURIComponent(anchor))) problems.push(`${file}: missing anchor ${value}`);
	}
}
const catalog = read("index.html");
const catalogSlugs = [...catalog.matchAll(/href="pages\/([^"#]+)\.html"[^>]*data-catalog-item/g)].map(match => match[1]);
const manifest = JSON.parse(read("assets/chapters.js").split(" = ")[1].replace(/;\s*$/, ""));
const pageSlugs = files.slice(1).map(file => file.replace(/^pages\//, "").replace(/\.html$/, ""));
if (manifest.map(([slug]) => slug).join("|") !== catalogSlugs.join("|")) problems.push("Catalog order differs from the chapter manifest");
if (
	[...pageSlugs].sort().join("|") !==
	manifest
		.map(([slug]) => slug)
		.sort()
		.join("|")
)
	problems.push("Chapter files differ from the manifest");
for (const [slug, , title] of manifest) {
	if (
		!read(`pages/${slug}.html`).includes(
			`<h1>${title.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")}</h1>`,
		)
	)
		problems.push(`${slug}: title differs from the manifest`);
}
if (problems.length) {
	console.error(problems.join("\n"));
	process.exitCode = 1;
} else console.log(`Checked ${files.length} HTML pages: catalog, titles, assets, local links, and anchors agree.`);
