(() => {
	const body = document.body;
	if (!body) return;

	const normalize = value => value.toLowerCase().normalize("NFKD").replace(/\s+/g, " ").trim();
	const escapeHtml = value =>
		value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
	const pad2 = value => String(value).padStart(2, "0");
	const store = {
		get(key) {
			try {
				return window.localStorage ? localStorage.getItem(key) : null;
			} catch (_error) {
				return null;
			}
		},
		set(key, value) {
			try {
				if (window.localStorage) localStorage.setItem(key, value);
			} catch (_error) {
				// File URLs and embedded browsers can deny storage; controls still work for this page load.
			}
		},
		remove(key) {
			try {
				if (window.localStorage) localStorage.removeItem(key);
			} catch (_error) {
				// File URLs and embedded browsers can deny storage; controls still work for this page load.
			}
		},
	};

	const icons = {
		rail: '<svg class="control-icon" viewBox="0 0 24 24" aria-hidden="true"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="M9 3v18"/></svg>',
		close: '<svg class="control-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>',
		up: '<svg class="control-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m18 15-6-6-6 6"/></svg>',
	};

	/* --- Chapter manifest ----------------------------------------------------
	   One ordered list per release. It drives the chapter rail, the
	   "Chapter NN of NN" kicker, and the previous/next pager, so those three
	   never disagree. Every chapter is its own `<slug>.html` reader page.

	   Titles here must match the chapter page's own <h1> and its catalog card
	   verbatim: one chapter, one name, on every surface. `npm run docs:check`
	   fails the build when they drift. */
	const MANIFESTS = { current: window.OPTIONS_DOCS_CHAPTERS || [] };
	const COMPANIONS = {};

	const version = body.dataset.version || "";
	const manifest = (MANIFESTS[version] || []).map(([slug, category, title], index) => ({
		slug,
		category,
		title,
		number: index + 1,
	}));
	const companions = COMPANIONS[version] || {};
	const currentSlug = decodeURIComponent((location.pathname.split("/").pop() || "").replace(/\.html?$/i, ""));

	/* --- Rail ---------------------------------------------------------------
	   A reader only needs its local outline here. Release-wide navigation lives
	   in the catalog and the previous/next pager, so the rail remains one clear
	   "On this page" region instead of introducing a competing tab model. */
	const buildRail = ({ id, label, title }) => {
		const rail = document.createElement("aside");
		rail.className = "chapter-rail is-single-panel";
		rail.id = id;
		rail.setAttribute("aria-label", label);

		rail.innerHTML =
			'<div class="rail-inner">' +
			'<div class="rail-tabs">' +
			`<p class="rail-title" id="${id}-title">${escapeHtml(title)}</p>` +
			'<button type="button" class="rail-collapse" data-rail-collapse aria-controls="' +
			id +
			'" aria-label="Hide navigation" title="Hide navigation">' +
			icons.rail +
			"</button>" +
			"</div>" +
			`<div class="rail-panel" role="region" id="${id}-panel" aria-labelledby="${id}-title">` +
			'<div class="rail-list" data-rail-list="sections"></div>' +
			"</div>" +
			"</div>";

		return {
			rail,
			list: rail.querySelector('[data-rail-list="sections"]'),
		};
	};

	/* Compact drawer + desktop collapse, shared by every rail. */
	const wireRailChrome = (rail, { trigger }) => {
		const compact = window.matchMedia("(max-width: 980px)");
		const collapse = rail.querySelector("[data-rail-collapse]");
		const resizer = document.createElement("div");
		resizer.className = "rail-resizer";
		resizer.tabIndex = 0;
		resizer.setAttribute("role", "separator");
		resizer.setAttribute("aria-orientation", "vertical");
		resizer.setAttribute("aria-label", "Resize page navigation");
		resizer.setAttribute("aria-keyshortcuts", "ArrowLeft ArrowRight Home End Enter");
		resizer.setAttribute("title", "Drag or use arrow keys to resize. Double-click or press Enter to reset.");
		rail.append(resizer);

		const railWidthKey = "docs-rail-width";
		const minimumRailWidth = 180;
		const minimumReaderWidth = 320;
		const defaultRailWidth = () => (window.innerWidth <= 1180 ? 280 : 304);
		const maximumRailWidth = () => Math.max(minimumRailWidth, window.innerWidth - minimumReaderWidth);
		const savedRailWidth = Number.parseFloat(store.get(railWidthKey) || "");
		let preferredRailWidth = Number.isFinite(savedRailWidth) ? savedRailWidth : null;

		const applyRailWidth = width => {
			const maximum = maximumRailWidth();
			const next = Math.round(Math.min(maximum, Math.max(minimumRailWidth, width)));
			body.style.setProperty("--rail-expanded", `${next}px`);
			resizer.setAttribute("aria-valuemin", String(minimumRailWidth));
			resizer.setAttribute("aria-valuemax", String(maximum));
			resizer.setAttribute("aria-valuenow", String(next));
			resizer.setAttribute("aria-valuetext", `${next} pixels wide`);
			return next;
		};

		const applyPreferredRailWidth = () => applyRailWidth(preferredRailWidth ?? defaultRailWidth());
		const resetRailWidth = () => {
			preferredRailWidth = null;
			store.remove(railWidthKey);
			applyPreferredRailWidth();
		};
		applyPreferredRailWidth();

		resizer.addEventListener("pointerdown", event => {
			if (compact.matches || event.button !== 0) return;
			event.preventDefault();
			body.classList.add("rail-is-resizing");
			resizer.setPointerCapture(event.pointerId);

			const updateFromPointer = pointerEvent => {
				const rightToLeft = getComputedStyle(body).direction === "rtl";
				preferredRailWidth = applyRailWidth(rightToLeft ? window.innerWidth - pointerEvent.clientX : pointerEvent.clientX);
			};
			const finishResize = pointerEvent => {
				if (pointerEvent.type === "pointerup") updateFromPointer(pointerEvent);
				body.classList.remove("rail-is-resizing");
				if (resizer.hasPointerCapture(pointerEvent.pointerId)) resizer.releasePointerCapture(pointerEvent.pointerId);
				if (preferredRailWidth !== null) store.set(railWidthKey, String(preferredRailWidth));
				resizer.removeEventListener("pointermove", updateFromPointer);
				resizer.removeEventListener("pointerup", finishResize);
				resizer.removeEventListener("pointercancel", finishResize);
			};

			resizer.addEventListener("pointermove", updateFromPointer);
			resizer.addEventListener("pointerup", finishResize);
			resizer.addEventListener("pointercancel", finishResize);
		});

		resizer.addEventListener("keydown", event => {
			if (compact.matches) return;
			if (event.key === "Enter") {
				event.preventDefault();
				resetRailWidth();
				return;
			}
			const rightToLeft = getComputedStyle(body).direction === "rtl";
			const current = Number.parseFloat(resizer.getAttribute("aria-valuenow") || "") || defaultRailWidth();
			const step = event.shiftKey ? 48 : 16;
			let next = null;
			if (event.key === "Home") next = minimumRailWidth;
			else if (event.key === "End") next = maximumRailWidth();
			else if (event.key === "ArrowLeft") next = current + (rightToLeft ? step : -step);
			else if (event.key === "ArrowRight") next = current + (rightToLeft ? -step : step);
			if (next === null) return;
			event.preventDefault();
			preferredRailWidth = applyRailWidth(next);
			store.set(railWidthKey, String(preferredRailWidth));
		});

		resizer.addEventListener("dblclick", resetRailWidth);

		let resizeFrame = 0;
		window.addEventListener("resize", () => {
			if (resizeFrame) return;
			resizeFrame = window.requestAnimationFrame(() => {
				resizeFrame = 0;
				applyPreferredRailWidth();
			});
		});
		const focusableSelector = "a[href], button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex='-1'])";
		const backdrop = document.createElement("button");
		backdrop.type = "button";
		backdrop.className = "rail-backdrop";
		backdrop.setAttribute("aria-label", "Close navigation");
		body.append(backdrop);
		const background = [
			document.querySelector(".docs-header"),
			...Array.from(rail.parentElement?.children || []).filter(element => element !== rail),
			document.querySelector(".site-footer"),
		].filter(Boolean);

		let returnFocus = null;
		let lockedScrollY = 0;
		const setOpen = (open, restoreAfterLayout = false) => {
			const shouldOpen = compact.matches && open;
			const wasOpen = body.classList.contains("rail-is-open");
			if (shouldOpen && !wasOpen) {
				returnFocus = document.activeElement instanceof HTMLElement ? document.activeElement : trigger;
				lockedScrollY = window.scrollY;
				body.style.top = `-${lockedScrollY}px`;
			}
			body.classList.toggle("rail-is-open", shouldOpen);
			background.forEach(element => element.toggleAttribute("inert", shouldOpen));
			if (!shouldOpen && wasOpen) {
				const restoreScrollY = lockedScrollY;
				body.style.removeProperty("top");
				window.scrollTo(0, restoreScrollY);
				if (restoreAfterLayout) window.requestAnimationFrame(() => window.scrollTo(0, restoreScrollY));
			}
			rail.toggleAttribute("inert", compact.matches && !shouldOpen);
			if (trigger) trigger.setAttribute("aria-expanded", String(shouldOpen));
			describeCollapse();
			if (shouldOpen) {
				window.requestAnimationFrame(() => {
					const first = rail.querySelector("[data-rail-collapse], .toc-link");
					if (first) first.focus();
				});
			} else if (returnFocus && document.contains(returnFocus)) {
				returnFocus.focus({ preventScroll: true });
				returnFocus = null;
			}
		};

		// The same control closes the drawer at compact widths and collapses the
		// rail on wide screens, so the rail only ever needs one dismiss affordance.
		const describeCollapse = () => {
			if (!collapse) return;
			const drawer = compact.matches;
			const collapsed = body.classList.contains("rail-is-collapsed");
			const label = drawer ? "Close navigation" : collapsed ? "Show navigation" : "Hide navigation";
			collapse.innerHTML = drawer ? icons.close : icons.rail;
			collapse.setAttribute("aria-label", label);
			collapse.setAttribute("title", label);
			collapse.setAttribute("aria-expanded", String(drawer ? body.classList.contains("rail-is-open") : !collapsed));
		};

		const setCollapsed = (collapsed, persist = true) => {
			if (compact.matches) {
				describeCollapse();
				return;
			}
			body.classList.toggle("rail-is-collapsed", collapsed);
			describeCollapse();
			if (persist) store.set("docs-rail-collapsed", String(collapsed));
		};

		if (trigger) {
			trigger.addEventListener("click", () => {
				const closing = body.classList.contains("rail-is-open");
				setOpen(!closing, closing);
			});
		}
		if (collapse) {
			collapse.addEventListener("click", () => {
				if (compact.matches) setOpen(false, true);
				else setCollapsed(!body.classList.contains("rail-is-collapsed"));
			});
		}
		backdrop.addEventListener("click", () => setOpen(false, true));
		rail.addEventListener("click", event => {
			if (event.target instanceof Element && event.target.closest("a")) setOpen(false);
		});
		window.addEventListener("keydown", event => {
			if (!body.classList.contains("rail-is-open")) return;
			if (event.key === "Escape") {
				setOpen(false, true);
				return;
			}
			if (event.key !== "Tab") return;
			const focusable = Array.from(rail.querySelectorAll(focusableSelector)).filter(
				element => element instanceof HTMLElement && element.getClientRects().length > 0,
			);
			if (!focusable.length) return;
			const first = focusable[0];
			const last = focusable[focusable.length - 1];
			if (!rail.contains(document.activeElement)) {
				event.preventDefault();
				(event.shiftKey ? last : first).focus();
			} else if (event.shiftKey && document.activeElement === first) {
				event.preventDefault();
				last.focus();
			} else if (!event.shiftKey && document.activeElement === last) {
				event.preventDefault();
				first.focus();
			}
		});
		compact.addEventListener("change", () => {
			setOpen(false, true);
			if (compact.matches) body.classList.remove("rail-is-collapsed");
			else {
				applyPreferredRailWidth();
				setCollapsed(store.get("docs-rail-collapsed") === "true", false);
			}
		});
		setOpen(false);
		setCollapsed(store.get("docs-rail-collapsed") === "true", false);
	};

	/* The compact-width rail trigger, added to whatever top bar the page has. */
	const installRailTrigger = (railId, label) => {
		const actions = document.querySelector(".docs-header .top-actions");
		if (!actions) return null;
		const trigger = document.createElement("button");
		trigger.type = "button";
		trigger.className = "button ghost rail-trigger";
		trigger.dataset.railTrigger = "true";
		trigger.setAttribute("aria-controls", railId);
		trigger.setAttribute("aria-expanded", "false");
		trigger.innerHTML = `${icons.rail}<span>${escapeHtml(label)}</span>`;
		actions.prepend(trigger);
		return trigger;
	};

	/* A breadcrumb reads ancestor to current. The release crumb stays a link to the
	   catalog it names, and the page the reader is actually on becomes the final,
	   non-link crumb — previously the trail ended in a link pointing back up and
	   never named the current page at all. */
	const installTrailCurrent = title => {
		const trail = document.querySelector(".docs-header .docs-trail");
		if (!trail || !title || trail.querySelector("[data-trail-current]")) return;
		const separator = document.createElement("span");
		separator.className = "trail-sep";
		separator.setAttribute("aria-hidden", "true");
		separator.textContent = "/";
		const current = document.createElement("span");
		current.className = "trail-current trail-chapter";
		current.dataset.trailCurrent = "true";
		current.setAttribute("aria-current", "page");
		current.textContent = title;
		trail.append(separator, current);
	};

	/* Tracks which heading the reader is inside and mirrors it in the rail. */
	const trackSections = (listHost, headings) => {
		if (!headings.length) return;
		const links = new Map();
		listHost.querySelectorAll(".toc-link").forEach(link => {
			let id = "";
			try {
				id = decodeURIComponent((link.getAttribute("href") || "").replace(/^#/, ""));
			} catch (_error) {
				id = "";
			}
			if (id) links.set(id, link);
		});
		if (!links.size) return;
		const trackedHeadings = headings.filter(heading => links.has(heading.id));
		if (!trackedHeadings.length) return;
		const scrollHost = listHost.closest(".rail-panel") || listHost;

		let activeId = "";
		let frame = 0;
		const apply = () => {
			frame = 0;
			const marker = headerHeight() + 24;
			const documentHeight = Math.max(document.documentElement.scrollHeight, document.body?.scrollHeight || 0);
			const atDocumentEnd = window.scrollY + window.innerHeight >= documentHeight - 2;
			let current = atDocumentEnd ? trackedHeadings.at(-1) : trackedHeadings[0];
			if (!atDocumentEnd) {
				for (const heading of trackedHeadings) {
					if (heading.getBoundingClientRect().top <= marker) current = heading;
					else break;
				}
			}
			if (!current || current.id === activeId) return;
			const previous = links.get(activeId);
			if (previous) {
				previous.classList.remove("is-active");
				previous.removeAttribute("aria-current");
			}
			activeId = current.id;
			const link = links.get(activeId);
			if (!link) return;
			link.classList.add("is-active");
			link.setAttribute("aria-current", "location");
			if (scrollHost.scrollHeight > scrollHost.clientHeight) {
				const hostRect = scrollHost.getBoundingClientRect();
				const linkRect = link.getBoundingClientRect();
				if (linkRect.top < hostRect.top + 12) scrollHost.scrollTop += linkRect.top - hostRect.top - 18;
				else if (linkRect.bottom > hostRect.bottom - 12) scrollHost.scrollTop += linkRect.bottom - hostRect.bottom + 18;
			}
		};
		const schedule = () => {
			if (!frame) frame = window.requestAnimationFrame(apply);
		};
		window.addEventListener("scroll", schedule, { passive: true });
		window.addEventListener("resize", schedule);
		window.addEventListener("hashchange", schedule);
		apply();
	};

	/* Turns authored numbered headings into a quieter, reference-style contents
	   list without asking every page to duplicate presentation markup. Top-level
	   section numbers get their own gutter; consecutive subsections share one
	   visual spine. The original link text remains the accessible name. */
	const formatSectionMenu = listHost => {
		const links = Array.from(listHost.children).filter(child => child.classList?.contains("toc-link"));
		let subsectionGroup = null;
		let subsectionLabel = "Subsections";

		links.forEach(link => {
			if (link.classList.contains("level-2")) {
				subsectionGroup = null;
				subsectionLabel = `${(link.textContent || "Section").trim()} subsections`;
				const match = (link.textContent || "").trim().match(/^(\d+)\.\s+(.+)$/);
				if (!match) return;

				const index = document.createElement("span");
				index.className = "toc-section-index";
				index.setAttribute("aria-hidden", "true");
				index.textContent = match[1];
				const label = document.createElement("span");
				label.className = "toc-section-label";
				label.textContent = match[2];
				link.classList.add("has-section-index");
				link.setAttribute("aria-label", `${match[1]}. ${match[2]}`);
				link.replaceChildren(index, label);
				return;
			}

			if (!link.classList.contains("level-3")) return;
			if (!subsectionGroup) {
				subsectionGroup = document.createElement("div");
				subsectionGroup.className = "toc-sublist";
				subsectionGroup.setAttribute("role", "group");
				subsectionGroup.setAttribute("aria-label", subsectionLabel);
				link.before(subsectionGroup);
			}
			subsectionGroup.append(link);
		});
	};

	const headerHeight = () => {
		const header = document.querySelector(".docs-header");
		return header ? Math.ceil(header.getBoundingClientRect().height) : 0;
	};

	const readingMinutes = article => {
		const words = (article.textContent || "").trim().split(/\s+/).filter(Boolean).length;
		return Math.max(1, Math.round(words / 220));
	};

	const installReadingProgress = () => {
		const header = document.querySelector(".docs-header");
		if (!header || header.querySelector("[data-reading-progress]")) return;

		const progress = document.createElement("div");
		progress.className = "reading-progress";
		progress.dataset.readingProgress = "true";
		progress.setAttribute("role", "progressbar");
		progress.setAttribute("aria-label", "Reading progress");
		progress.setAttribute("aria-valuemin", "0");
		progress.setAttribute("aria-valuemax", "100");
		progress.setAttribute("aria-valuenow", "0");
		progress.innerHTML = '<span aria-hidden="true"></span>';
		header.append(progress);

		let frame = 0;
		let previousValue = -1;
		const update = () => {
			frame = 0;
			const scrollable = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
			const ratio = Math.min(1, Math.max(0, window.scrollY / scrollable));
			const value = Math.round(ratio * 100);
			progress.style.setProperty("--reading-progress", String(ratio));
			if (value !== previousValue) {
				progress.setAttribute("aria-valuenow", String(value));
				previousValue = value;
			}
		};
		const schedule = () => {
			if (!frame) frame = window.requestAnimationFrame(update);
		};
		window.addEventListener("scroll", schedule, { passive: true });
		window.addEventListener("resize", schedule);
		window.addEventListener("load", schedule, { once: true });
		update();
	};

	/* --- Chapter pages ------------------------------------------------------ */
	const installReaderShell = () => {
		if (!body.classList.contains("doc-page")) return;
		const shell = document.querySelector(".reader-shell");
		const main = document.querySelector(".reader-main");
		const hero = document.querySelector(".reader-hero");
		const article = document.querySelector(".doc-article");
		if (!shell || !main || !hero || !article) return;

		const authored = document.querySelector("[data-rail-sections]");
		const entry = manifest.find(item => item.slug === currentSlug);
		const companion = companions[currentSlug];

		const { rail, list: sectionList } = buildRail({
			id: "docs-rail",
			label: "On this page",
			title: "On this page",
		});

		if (authored) {
			Array.from(authored.children).forEach(child => sectionList.append(child));
			authored.remove();
		}
		formatSectionMenu(sectionList);
		if (!sectionList.querySelector(".toc-link")) {
			const empty = document.createElement("p");
			empty.className = "rail-empty";
			empty.textContent = "This page has no subsections.";
			sectionList.append(empty);
		}

		shell.prepend(rail);
		installTrailCurrent(entry?.title || companion?.[1] || (document.querySelector(".reader-hero h1")?.textContent || "").trim());
		wireRailChrome(rail, { trigger: installRailTrigger(rail.id, "Contents") });

		// One kicker replaces the old breadcrumb, whose last crumb named the
		// category rather than the page the reader was on. A page that authors
		// its own kicker keeps it.
		let kicker = hero.querySelector(".topic-kicker");
		if (!kicker) {
			kicker = document.createElement("p");
			kicker.className = "topic-kicker";
			if (entry) {
				kicker.innerHTML = `<span>${escapeHtml(entry.category)}</span><span>${pad2(entry.number)} of ${pad2(manifest.length)}</span>`;
			} else if (companion) {
				kicker.innerHTML = `<span>${escapeHtml(companion[0])}</span><span>Companion guide</span>`;
			} else {
				kicker.innerHTML = "<span>Reference</span>";
			}
			hero.prepend(kicker);
		}
		if (!kicker.querySelector("[data-reading-time]")) {
			const minutes = readingMinutes(article);
			const readingTime = document.createElement("span");
			readingTime.dataset.readingTime = "true";
			readingTime.textContent = `${minutes} min read`;
			kicker.append(readingTime);
		}

		if (entry) {
			const previous = manifest[entry.number - 2];
			const next = manifest[entry.number];
			if (previous || next) {
				const pager = document.createElement("nav");
				pager.className = "chapter-pager";
				pager.setAttribute("aria-label", "Previous and next pages");
				if (previous)
					pager.innerHTML += `<a href="${previous.slug}.html"><small>Previous</small><span>${escapeHtml(previous.title)}</span></a>`;
				if (next) pager.innerHTML += `<a href="${next.slug}.html"><small>Next</small><span>${escapeHtml(next.title)}</span></a>`;
				main.append(pager);
			}
		}

		trackSections(sectionList, Array.from(article.querySelectorAll("h2[id], h3[id], h4[id]")));
		installReadingProgress();
	};

	/* Both search fields answer to the same keys, so the shortcut a reader learns on
	   the portal still works on the release catalog. */
	const wireSearchShortcuts = (input, apply) => {
		window.addEventListener("keydown", event => {
			if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
				event.preventDefault();
				input.focus();
				input.select();
			} else if (event.key === "Escape" && document.activeElement === input && input.value) {
				input.value = "";
				apply();
			}
		});
	};

	/* The hint reflects the platform's own modifier rather than always showing ⌘. */
	const labelSearchShortcut = () => {
		const isApple = /mac|iphone|ipad|ipod/i.test(navigator.platform || navigator.userAgent || "");
		document.querySelectorAll("[data-search-hint]").forEach(hint => {
			hint.textContent = isApple ? "⌘K" : "Ctrl K";
		});
	};

	/* --- Release catalogs --------------------------------------------------- */
	const installCatalog = () => {
		const input = document.querySelector("[data-catalog-search]");
		if (!input) return;
		// Items carry `data-catalog-item` where the markup was updated for it, and
		// fall back to the two catalog row shapes so a release index that predates
		// the attribute still filters instead of hiding everything.
		const items = Array.from(document.querySelectorAll("[data-catalog-item]"));
		const rows = items.length ? items : Array.from(document.querySelectorAll(".doc-list-item, .minor-improvement-item"));
		if (!rows.length) return;
		const groups = Array.from(document.querySelectorAll("[data-catalog-group]"));
		const count = document.querySelector("[data-catalog-count]");
		const empty = document.querySelector("[data-catalog-empty]");
		const clear = document.querySelector("[data-catalog-clear]");
		const groupCounts = new Map(groups.map(group => [group, group.querySelector("[data-catalog-group-count]")]));
		const total = rows.length;
		if (count) {
			if (!count.id) count.id = "catalog-result-count";
			count.setAttribute("role", "status");
			count.setAttribute("aria-live", "polite");
			count.setAttribute("aria-atomic", "true");
			input.setAttribute("aria-describedby", count.id);
		}

		const describe = value => {
			const unit = count?.dataset.catalogUnit || "chapter";
			return `${value} ${value === 1 ? unit : `${unit}s`}`;
		};

		const apply = () => {
			const query = normalize(input.value);
			let shown = 0;
			rows.forEach(row => {
				const match = !query || normalize(row.textContent || "").includes(query);
				row.hidden = !match;
				if (match) shown += 1;
			});
			groups.forEach(group => {
				const groupRows = rows.filter(row => group.contains(row));
				const visible = groupRows.filter(row => !row.hidden).length;
				group.hidden = groupRows.length > 0 && visible === 0;
				const label = groupCounts.get(group);
				if (label) label.textContent = describe(visible);
			});
			if (count) count.textContent = query ? `${describe(shown)} of ${total}` : describe(total);
			if (empty) empty.hidden = shown !== 0;
		};

		groups.forEach(group => {
			const label = groupCounts.get(group);
			if (label) label.textContent = describe(rows.filter(row => group.contains(row)).length);
		});
		if (count) count.textContent = describe(total);
		input.addEventListener("input", apply);
		clear?.addEventListener("click", () => {
			input.value = "";
			apply();
			input.focus();
		});
		wireSearchShortcuts(input, apply);
	};

	/* --- Version portal search --------------------------------------------- */
	// A search field, a live count and a keyboard shortcut are worth their space
	// only once the list is long enough to be worth filtering. Below that the
	// controls stay in the markup but out of the way.
	const VERSION_SEARCH_MIN_ITEMS = 6;

	const installVersionSearch = () => {
		const input = document.querySelector("[data-version-search]");
		if (!input) return;
		const items = Array.from(document.querySelectorAll("[data-version-item]"));
		if (!items.length) return;
		if (items.length < VERSION_SEARCH_MIN_ITEMS) {
			input.closest(".portal-search")?.remove();
			document.querySelector("[data-version-count]")?.remove();
			return;
		}
		const count = document.querySelector("[data-version-count]");
		const empty = document.querySelector("[data-version-empty]");
		if (count) {
			count.setAttribute("role", "status");
			count.setAttribute("aria-live", "polite");
		}
		const describe = value => `${value} ${value === 1 ? "version" : "versions"}`;

		const apply = () => {
			const query = normalize(input.value);
			let shown = 0;
			items.forEach(item => {
				const searchableText = `${item.textContent || ""} ${item.getAttribute("aria-label") || ""}`;
				const match = !query || normalize(searchableText).includes(query);
				item.hidden = !match;
				if (match) shown += 1;
			});
			if (count) count.textContent = query ? `${describe(shown)} of ${items.length}` : describe(items.length);
			if (empty) empty.hidden = shown !== 0;
		};

		input.addEventListener("input", apply);
		wireSearchShortcuts(input, apply);
	};

	/* --- Back to top -------------------------------------------------------- */
	const installBackToTop = () => {
		let button = document.querySelector("[data-back-to-top]");
		if (!button && body.classList.contains("doc-page")) {
			button = document.createElement("button");
			button.type = "button";
			button.className = "back-to-top";
			button.dataset.backToTop = "true";
			button.setAttribute("aria-label", "Back to top");
			button.innerHTML = icons.up;
			body.append(button);
		}
		if (!button) return;
		if (!button.querySelector("svg")) button.innerHTML = icons.up;
		const sync = () => button.classList.toggle("is-visible", window.scrollY > 900);
		window.addEventListener("scroll", sync, { passive: true });
		button.addEventListener("click", () => {
			const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
			window.scrollTo({ top: 0, behavior: reducedMotion ? "auto" : "smooth" });
		});
		sync();
	};

	/* --- Deep links --------------------------------------------------------- */
	// Diagrams and code frames land after first paint, so a hash target moves.
	// Re-align it a few times instead of leaving the reader mid-chapter.
	const initialHash = decodeURIComponent(window.location.hash.replace(/^#/, ""));
	const alignInitialHash = () => {
		if (!initialHash) return;
		const target = document.getElementById(initialHash);
		if (!target) return;
		const root = document.documentElement;
		const previousBehavior = root.style.scrollBehavior;
		root.style.scrollBehavior = "auto";
		target.scrollIntoView({ block: "start" });
		root.style.scrollBehavior = previousBehavior;
	};

	installReaderShell();
	installCatalog();
	installVersionSearch();
	labelSearchShortcut();
	installBackToTop();

	// Reader pages can need delayed realignment as diagrams settle into place.
	if (initialHash) {
		window.addEventListener(
			"load",
			() => {
				alignInitialHash();
				[300, 1200, 2400].forEach(delay => window.setTimeout(alignInitialHash, delay));
			},
			{ once: true },
		);
	}
})();
