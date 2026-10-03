import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Marked } from "marked";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const docs = resolve(root, "docs");
const check = process.argv.includes("--check");
const escape = value => value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const plain = value =>
	value
		.replace(/<[^>]+>/g, "")
		.replace(/&#39;/g, "'")
		.replace(/&amp;/g, "&")
		.replace(/&quot;/g, '"')
		.replace(/[`*_]/g, "");
const slug = value =>
	plain(value)
		.toLowerCase()
		.replace(/[^\p{L}\p{N}\s_-]/gu, "")
		.replace(/\s/g, "-");

// This list drives the catalog, reader navigation, and generated pages.
export const chapters = [
	["README.md", "Start here", "Reading paths, chapter map, and documentation maintenance."],
	["architecture.md", "Architecture", "Diamond routing, domain libraries, storage, and helper contracts."],
	["development-standards.md", "Development", "Contract conventions, lint rules, release checks, and Git hooks."],
	["testing.md", "Development", "Mocha behavior groups, fixtures, assertions, and coverage."],
	["deployment-and-operations.md", "Development", "Deployment tasks, configuration, networks, and post-deploy setup."],
	["flows/account-balances.md", "Flows", "Deposits, withdrawals, allocation, reserves, and transfers."],
	["flows/open-intents.md", "Flows", "Create, lock, fill, and cancel intents, including deferred sell escrow."],
	["flows/close-and-settlement.md", "Flows", "Close intents, settlement, exercise, trade transfers, and NFTs."],
	["flows/instant-actions.md", "Flows", "Party binding, helper accounts, and signed InstantLayer batches."],
	["flows/liquidation-and-force-actions.md", "Flows", "Forced cancellations, liquidation, confiscation, and distribution."],
	["concepts/glossary.md", "Concepts", "Protocol terms, actors, quantities, and units."],
	["concepts/margin-modes.md", "Concepts", "Cross and isolated margin, collateral reservation, and restrictions."],
	["concepts/fee-model.md", "Concepts", "Open, close, and exercise fees, affiliates, and fee collectors."],
	["concepts/oracle-and-signatures.md", "Concepts", "Muon verification, gateway signatures, ERC-1271, and EIP-712."],
	["concepts/scheduled-release.md", "Concepts", "Delayed isolated releases, synchronization, and liquidation."],
	["reference/facets.md", "Reference", "Facet selectors, modifiers, preconditions, and accounting effects."],
	["reference/events.md", "Reference", "Diamond and helper events with declaration and emission sites."],
	["reference/errors.md", "Reference", "Custom errors, trigger conditions, and call sites."],
	["reference/types-and-storage.md", "Reference", "Structs, enums, storage layouts, and units."],
	["reference/roles-and-pauses.md", "Reference", "Roles, pause flags, gated operations, and operational consequences."],
	["security.md", "Security", "Trust assumptions, invariants, upgrade authority, and known limits."],
].map(([source, category, summary]) => {
	const markdown = readFileSync(resolve(docs, source), "utf8").replace(/^---\n[\s\S]*?\n---\n/, "");
	const title = /^# (.+)$/m.exec(markdown)?.[1];
	if (!title) throw new Error(`Missing title in ${source}`);
	return { source, category, summary, title, slug: source === "README.md" ? "overview" : basename(source, ".md"), markdown };
});

const bySource = new Map(chapters.map(chapter => [resolve(docs, chapter.source), chapter]));
const bySlug = new Map(chapters.map(chapter => [chapter.slug, chapter]));
bySlug.set("README", chapters[0]);
const outputs = new Map();
const put = (name, content) => outputs.set(name, content);

function link(href, chapter) {
	if (/^(https?:|mailto:|data:)/.test(href)) return href;
	if (href.startsWith("#")) return href;
	const [path, anchor] = href.split("#");
	const target = bySource.get(resolve(docs, dirname(chapter.source), path));
	if (target) return `${target.slug}.html${anchor ? `#${slug(decodeURIComponent(anchor))}` : ""}`;
	if (["flows", "concepts", "reference"].some(folder => resolve(docs, dirname(chapter.source), path) === resolve(docs, folder)))
		return `../index.html#${basename(path)}`;
	if (path === "./index.html" && chapter.source === "README.md") return "../index.html";
	throw new Error(`Unresolved local link ${href} in ${chapter.source}`);
}

function render(chapter) {
	const headings = [];
	const ids = new Map();
	const parser = new Marked({ gfm: true });
	parser.use({
		renderer: {
			heading({ tokens, depth }) {
				const text = this.parser.parseInline(tokens);
				const base = slug(text);
				const count = ids.get(base) || 0;
				ids.set(base, count + 1);
				const id = count ? `${base}-${count}` : base;
				if (depth >= 2 && depth <= 3) headings.push({ depth, text, id });
				return `<h${depth} id="${escape(id)}">${text}</h${depth}>\n`;
			},
			link({ href, tokens }) {
				return `<a href="${escape(link(href, chapter))}">${this.parser.parseInline(tokens)}</a>`;
			},
		},
	});
	let markdown = chapter.markdown.replace(/^# .+\n/m, "");
	markdown = markdown.replace(/\[\[([^\]]+)\]\]/g, (_match, value) => {
		const [destination, label] = value.split("|");
		const [name, anchor] = destination.split("#");
		const target = bySlug.get(name || chapter.slug);
		if (!target) throw new Error(`Unknown chapter ${name} in ${chapter.source}`);
		const relative = target.slug + ".html" + (anchor ? "#" + slug(anchor) : "");
		// Raw HTML avoids re-resolving this already-normalized wiki link.
		return `<a href="${escape(relative)}">${escape(label || destination)}</a>`;
	});
	markdown = markdown.replace(/^> \[!([^\]]+)\](.*)$/gm, (_match, type, label) => `> **${label.trim() || type[0].toUpperCase() + type.slice(1)}**`);
	const article = parser.parse(markdown);
	return { article, headings };
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
for (const chapter of chapters) {
	const { article, headings } = render(chapter);
	put(
		`pages/${chapter.slug}.html`,
		`${head(chapter.title, chapter.summary, "../")}
<body class="doc-page" data-version="current"><a class="skip-link" href="#full-document">Skip to document</a>
${header("../", true)}<div class="reader-shell"><div data-rail-sections hidden>
${headings.map(({ depth, text, id }) => `<a class="toc-link level-${depth}" href="#${escape(id)}">${text}</a>`).join("\n")}
</div><main class="reader-main"><header class="reader-hero"><div class="reader-title-row"><div><h1>${escape(chapter.title)}</h1><p class="hero-copy">${escape(chapter.summary)}</p></div></div></header>
<article class="doc-article" id="full-document">${article}</article></main></div>${footer}`,
	);
}
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
if (stale.length) throw new Error(`Stale generated docs: ${stale.join(", ")}. Run npm run docs:build.`);
console.log(`${check ? "Verified" : "Built"} ${chapters.length} chapters and the documentation catalog.`);
