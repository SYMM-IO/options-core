import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { basename, dirname, extname, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));
const repository = dirname(root);
const problems = [];
const ids = new Map();
const contents = new Map();
const ignoredDirectories = new Set(["node_modules", ".git", ".cache", ".hardhat", ".diffstory"]);
const generatedRootDirectories = new Set(["artifacts", "cache", "types", "coverage", "dist", "build"]);
const instructionNames = new Set(["agents.md", "claude.md"]);
const markdown = file => /\.(?:md|markdown|mdx)$/i.test(file) && !instructionNames.has(basename(file).toLowerCase());
const label = file => relative(repository, file);
const read = file => {
	if (!contents.has(file)) contents.set(file, readFileSync(file, "utf8"));
	return contents.get(file);
};
const decode = text =>
	text.replace(/&(?:amp|quot|apos|lt|gt|#\d+|#x[\da-f]+);/gi, entity => {
		const named = { "&amp;": "&", "&quot;": '"', "&apos;": "'", "&lt;": "<", "&gt;": ">" };
		if (named[entity.toLowerCase()]) return named[entity.toLowerCase()];
		const numeric = entity.slice(2, -1);
		const value = numeric[0].toLowerCase() === "x" ? parseInt(numeric.slice(1), 16) : parseInt(numeric, 10);
		return value <= 0x10ffff ? String.fromCodePoint(value) : entity;
	});

function walk(directory) {
	return readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
		const path = resolve(directory, entry.name);
		if (entry.isDirectory()) {
			const excluded = ignoredDirectories.has(entry.name) || (directory === repository && generatedRootDirectories.has(entry.name));
			return excluded ? [] : walk(path);
		}
		return entry.isFile() ? [path] : [];
	});
}

// Read attributes on real tags, excluding comments and script/style bodies. This also
// keeps literal HTML shown inside escaped code examples out of the link/ID checks.
function tags(html) {
	const source = html.replace(/<!--[\s\S]*?-->/g, "").replace(/<(script|style)\b([^>]*)>[\s\S]*?<\/\1\s*>/gi, "<$1$2></$1>");
	return [...source.matchAll(/<([a-z][\w:-]*)\b([^>]*)>/gi)].map(match => ({
		name: match[1].toLowerCase(),
		attributes: [...match[2].matchAll(/(?:^|\s)([^\s=/'">]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`/]+))/g)].map(attribute => [
			attribute[1].toLowerCase(),
			decode(attribute[2] ?? attribute[3] ?? attribute[4]),
		]),
	}));
}
function documentIds(file) {
	if (!ids.has(file)) {
		const entries = tags(read(file)).flatMap(tag => tag.attributes.filter(([name]) => name === "id").map(([, value]) => value));
		const unique = new Set(entries);
		if (unique.size !== entries.length) problems.push(`${label(file)}: duplicate HTML IDs`);
		ids.set(file, unique);
	}
	return ids.get(file);
}

const repositoryFiles = walk(repository);
for (const file of repositoryFiles.filter(markdown)) problems.push(`${label(file)}: Markdown documentation file remains`);
const files = repositoryFiles.filter(
	file => extname(file).toLowerCase() === ".html" && (file.startsWith(`${root}/`) || dirname(file) === repository),
);
for (const required of ["README.html", "implementation_proposal.html", "impl_proposal_add.html", "docs/index.html"]) {
	if (!existsSync(resolve(repository, required))) problems.push(`${required}: missing HTML document`);
}
for (const file of files) {
	const html = read(file);
	documentIds(file);
	if (tags(html).filter(tag => tag.name === "h1").length !== 1) problems.push(`${label(file)}: expected one page title`);
	if (/\[\[[^\]]+\]\]|\[!(?:info|note|warning|tip|abstract)\]/.test(html)) problems.push(`${label(file)}: unresolved Markdown extension`);
	for (const tag of tags(html)) {
		for (const [, value] of tag.attributes.filter(([name]) => name === "href" || name === "src")) {
			if (/^(?:\/\/|[a-z][a-z\d+.-]*:)/i.test(value) && !/^file:/i.test(value)) continue;
			try {
				const url = new URL(value, pathToFileURL(file));
				const target = fileURLToPath(url);
				if (markdown(target)) problems.push(`${label(file)}: Markdown document link ${value}`);
				if (!existsSync(target)) problems.push(`${label(file)}: missing target ${value}`);
				else if (url.hash && statSync(target).isFile() && extname(target).toLowerCase() === ".html") {
					if (!documentIds(target).has(decodeURIComponent(url.hash.slice(1)))) problems.push(`${label(file)}: missing anchor ${value}`);
				}
			} catch (error) {
				problems.push(`${label(file)}: invalid local link ${value} (${error.message})`);
			}
		}
	}
}

// Only canonical chapter pages belong to the catalog. Standalone research, assets,
// proposals, and other first-party HTML still receive the document checks above.
const catalogPath = resolve(root, "index.html");
const manifestPath = resolve(root, "assets/chapters.js");
if (existsSync(catalogPath) && existsSync(manifestPath)) {
	try {
		const catalogSlugs = [...read(catalogPath).matchAll(/href="pages\/([^"#]+)\.html"[^>]*data-catalog-item/g)].map(match => match[1]);
		const manifest = JSON.parse(read(manifestPath).split(" = ")[1].replace(/;\s*$/, ""));
		const pageSlugs = files.filter(file => dirname(file) === resolve(root, "pages")).map(file => basename(file, ".html"));
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
			const page = resolve(root, `pages/${slug}.html`);
			if (!existsSync(page)) continue;
			const escaped = title.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
			if (!read(page).includes(`<h1>${escaped}</h1>`)) problems.push(`${slug}: title differs from the manifest`);
		}
	} catch (error) {
		problems.push(`Chapter manifest could not be checked: ${error.message}`);
	}
} else if (!existsSync(manifestPath)) problems.push("docs/assets/chapters.js: missing chapter manifest");

if (problems.length) {
	console.error([...new Set(problems)].join("\n"));
	process.exitCode = 1;
} else console.log(`Checked ${files.length} HTML documents: catalog, titles, assets, local links, anchors, and HTML-only documentation agree.`);
