import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const docs = resolve(root, "docs");
const check = process.argv.includes("--check");
const escape = value => value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const plain = value =>
	value
		.replace(/<[^>]+>/g, "")
		.replace(/&#39;/g, "'")
		.replace(/&amp;/g, "&")
		.replace(/&quot;/g, '"');
const slug = value =>
	plain(value)
		.toLowerCase()
		.replace(/[^\p{L}\p{N}\s_-]/gu, "")
		.replace(/\s/g, "-");

// Canonical HTML chapters; this list drives the catalog and reader navigation.
// Article content is edited in docs/pages, never generated from another format.
export const chapters = [
	["pages/overview.html", "Start here"],
	["pages/architecture.html", "Architecture"],
	["pages/development-standards.html", "Development"],
	["pages/testing.html", "Development"],
	["pages/deployment-and-operations.html", "Development"],
	["pages/account-balances.html", "Flows"],
	["pages/native-buckets.html", "Flows"],
	["pages/open-intents.html", "Flows"],
	["pages/close-and-settlement.html", "Flows"],
	["pages/instant-actions.html", "Flows"],
	["pages/liquidation-and-force-actions.html", "Flows"],
	["pages/glossary.html", "Concepts"],
	["pages/margin-modes.html", "Concepts"],
	["pages/fee-model.html", "Concepts"],
	["pages/oracle-and-signatures.html", "Concepts"],
	["pages/scheduled-release.html", "Concepts"],
	["pages/facets.html", "Reference"],
	["pages/events.html", "Reference"],
	["pages/errors.html", "Reference"],
	["pages/types-and-storage.html", "Reference"],
	["pages/roles-and-pauses.html", "Reference"],
	["pages/security.html", "Security"],
].map(([source, category]) => {
	const html = readFileSync(resolve(docs, source), "utf8");
	const title = plain(/<h1(?:\s[^>]*)?>([\s\S]*?)<\/h1>/.exec(html)?.[1] || "").trim();
	const summary = /<meta\s+name="description"\s+content="([^"]*)"/.exec(html)?.[1];
	if (!title || !summary) throw new Error(`Missing title or description in ${source}`);
	return { source, category, summary: plain(summary), title, slug: basename(source, ".html"), html };
});

const outputs = new Map();
const put = (name, content) => outputs.set(name, content);

function refreshOutline(chapter) {
	const article = /<article\b[^>]*\bid="full-document"[^>]*>([\s\S]*?)<\/article>/.exec(chapter.html)?.[1];
	if (article === undefined) throw new Error(`Missing canonical article in ${chapter.source}`);
	const headings = [...article.matchAll(/<h([23])\b([^>]*)>([\s\S]*?)<\/h\1>/g)].map(([, depth, attributes, text]) => {
		const id = /\bid="([^"]+)"/.exec(attributes)?.[1];
		if (!id) throw new Error(`Heading lacks a stable HTML id in ${chapter.source}: ${plain(text)}`);
		return { depth, text, id };
	});
	const outline = headings.map(({ depth, text, id }) => `<a class="toc-link level-${depth}" href="#${escape(id)}">${text}</a>`).join("\n");
	const rail = /(<div\b[^>]*\bdata-rail-sections[^>]*>)[\s\S]*?(<\/div>)/;
	if (!rail.test(chapter.html)) throw new Error(`Missing reader outline in ${chapter.source}`);
	// Replace only the derived rail. The article and page chrome remain the editable HTML source.
	return chapter.html.replace(rail, (_match, open, close) => `${open}\n${outline}\n${close}`);
}

function head(title, summary, prefix) {
	return `<!doctype html>\n<html lang="en" data-theme="dark"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="${escape(summary)}"><title>${escape(title)} | Options Core</title>
<link rel="icon" type="image/svg+xml" href="${prefix}assets/symmio-mark.svg">
<script>try { if (localStorage.getItem("options-docs-theme") === "light") document.documentElement.dataset.theme = "light"; } catch (_) {}</script>
<link rel="stylesheet" href="${prefix}assets/reader.css"><link rel="stylesheet" href="${prefix}assets/docs-portal.css">
<script src="${prefix}assets/chapters.js" defer></script><script src="${prefix}assets/reader.js" defer></script><script src="${prefix}assets/docs-portal.js" defer></script>
</head>`;
}
function header(prefix, reader) {
	return `<header class="docs-header"><div class="doc-topbar"><nav class="docs-trail" aria-label="Breadcrumb">
<a class="brand" href="${prefix}index.html"><span class="brand-mark" aria-hidden="true"></span><span class="brand-name">Options Core</span></a>
${reader ? `<span class="trail-sep" aria-hidden="true">/</span><a class="trail-release" href="${prefix}index.html">Documentation</a>` : '<span class="trail-sep" aria-hidden="true">/</span><span class="trail-current" aria-current="page">Documentation</span>'}
</nav><nav class="top-actions" aria-label="Page actions"><button class="button ghost" type="button" data-theme-toggle aria-label="Toggle color theme">Theme</button></nav></div></header>`;
}
const footer = '<footer class="site-footer"><span>Options Core documentation.</span></footer></body></html>\n';
for (const chapter of chapters) put(chapter.source, refreshOutline(chapter));

put(
	"assets/chapters.js",
	`// Generated by scripts/build-docs.mjs.\nwindow.OPTIONS_DOCS_CHAPTERS = ${JSON.stringify(
		chapters.map(({ slug, category, title }) => [slug, category, title]),
		null,
		"\t",
	)};\n`,
);
const categories = [...new Set(chapters.map(chapter => chapter.category))];
put(
	"index.html",
	`${head("Documentation", "Architecture, trading flows, development guides, and contract references for Options Core.", "")}
<body class="index-page version-catalog-page" data-version="current"><a class="skip-link" href="#docs">Skip to chapters</a>${header("", false)}
<header class="site-hero"><div class="index-hero-content"><div class="hero-layout hero-layout-single"><div class="hero-intro"><p class="eyebrow">Protocol documentation</p><h1>Options Core</h1><p class="hero-copy">The options trade lifecycle, collateral accounting, settlement, and contract interfaces.</p><p class="hero-copy">Start with <a href="pages/overview.html">reading paths</a> or <a href="pages/architecture.html">architecture</a>. Developers can use <a href="pages/development-standards.html">development standards</a> for commands and release checks.</p></div></div></div></header>
<main class="index-shell version-catalog-shell" id="docs"><div class="catalog-toolbar" role="search"><label class="catalog-search-wrap"><span class="visually-hidden">Search chapters</span><input class="catalog-search" type="search" placeholder="Search chapters" data-catalog-search autocomplete="off" aria-describedby="catalog-result-count"><kbd class="catalog-search-hint" aria-hidden="true" data-search-hint>Ctrl K</kbd></label><span class="catalog-count" id="catalog-result-count" data-catalog-count>${chapters.length} chapters</span></div>
<div class="catalog-empty" data-catalog-empty hidden><strong>No chapters found</strong><span>Try another term or clear the current search.</span><button class="button" type="button" data-catalog-clear>Clear search</button></div><div class="doc-browser">
${categories
	.map(
		category =>
			`<section class="version-catalog-group" data-catalog-group aria-labelledby="${slug(category)}"><div class="section-heading"><p class="eyebrow" data-catalog-group-count></p><h2 id="${slug(category)}">${escape(category)}</h2></div><div class="doc-list">${chapters
				.filter(chapter => chapter.category === category)
				.map(
					chapter =>
						`<a class="doc-list-item" href="pages/${chapter.slug}.html" data-catalog-item><span class="doc-list-index">${String(chapters.indexOf(chapter) + 1).padStart(2, "0")}</span><span class="doc-list-main"><span class="category">${escape(category)}</span><strong>${escape(chapter.title)}</strong><span>${escape(chapter.summary)}</span></span></a>`,
				)
				.join("\n")}</div></section>`,
	)
	.join("\n")}
</div></main>${footer}`,
);

const stale = [];
for (const [name, content] of outputs) {
	const path = resolve(docs, name);
	if (check) {
		if (!existsSync(path) || readFileSync(path, "utf8") !== content) stale.push(name);
	} else {
		mkdirSync(dirname(path), { recursive: true });
		writeFileSync(path, content);
	}
}
if (stale.length) throw new Error(`Stale documentation navigation: ${stale.join(", ")}. Run npm run docs:build.`);
console.log(`${check ? "Verified" : "Built"} ${chapters.length} chapters and the documentation catalog.`);
