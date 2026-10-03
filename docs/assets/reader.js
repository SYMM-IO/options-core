(() => {
	const root = document.documentElement;
	// Assets are resolved against this script rather than the page, so pages at any
	// depth (and the release indexes) reach the same shared vendor bundle.
	const scriptUrl = document.currentScript?.src || document.querySelector('script[src$="reader.js"]')?.src || window.location.href;
	const assetUrl = path => new URL(path, scriptUrl).href;
	const themeStorage = {
		get() {
			try {
				return window.localStorage ? localStorage.getItem("options-docs-theme") : null;
			} catch (_error) {
				return null;
			}
		},
		set(value) {
			try {
				if (window.localStorage) localStorage.setItem("options-docs-theme", value);
			} catch (_error) {
				// File URLs and embedded browsers can deny storage; the visible toggle still works for this page load.
			}
		},
	};
	const themeButtons = Array.from(document.querySelectorAll("[data-theme-toggle]"));
	const icons = {
		check: '<svg class="control-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m20 6-11 11-5-5"/></svg>',
		copy: '<svg class="control-icon" viewBox="0 0 24 24" aria-hidden="true"><rect width="14" height="14" x="8" y="8" rx="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>',
		expand: '<svg class="control-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M15 3h6v6"/><path d="m21 3-7 7"/><path d="M9 21H3v-6"/><path d="m3 21 7-7"/></svg>',
		moon: '<svg class="control-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M20.5 14.5A8.5 8.5 0 0 1 9.5 3.5 7 7 0 1 0 20.5 14.5"/></svg>',
		sun: '<svg class="control-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.9 4.9 1.4 1.4"/><path d="m17.7 17.7 1.4 1.4"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.3 17.7-1.4 1.4"/><path d="m19.1 4.9-1.4 1.4"/></svg>',
		wrap: '<svg class="control-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 7h14a4 4 0 0 1 0 8H7"/><path d="m10 12-3 3 3 3"/></svg>',
	};
	const setIconLabel = (element, icon, label) => {
		element.innerHTML = `${icon}<span>${label}</span>`;
	};
	const swapThemeWithoutTransitions = apply => {
		const guard = document.createElement("style");
		guard.textContent = "*,*::before,*::after{transition:none!important}";
		document.head.append(guard);
		apply();
		void root.offsetHeight;
		window.requestAnimationFrame(() => guard.remove());
	};

	const syncThemeButtons = () => {
		const isDark = root.dataset.theme === "dark";
		themeButtons.forEach(button => {
			setIconLabel(button, isDark ? icons.sun : icons.moon, isDark ? "Light" : "Dark");
			const actionLabel = isDark ? "Switch to light theme" : "Switch to dark theme";
			button.setAttribute("aria-label", actionLabel);
			button.setAttribute("title", actionLabel);
			button.removeAttribute("aria-pressed");
		});
	};
	const savedTheme = themeStorage.get();
	// Dark is the canonical Symmio surface; light is opt-in via the toggle.
	root.dataset.theme = savedTheme === "light" ? "light" : "dark";
	syncThemeButtons();

	themeButtons.forEach(button => {
		button.addEventListener("click", () => {
			const next = root.dataset.theme === "dark" ? "light" : "dark";
			swapThemeWithoutTransitions(() => {
				root.dataset.theme = next;
				themeStorage.set(next);
				syncThemeButtons();
			});
			window.dispatchEvent(new CustomEvent("options-docs:themechange", { detail: { theme: next } }));
		});
	});

	const escapeHtml = value =>
		value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");

	const detectDiagramType = source => {
		const first = source.trim().split(/\n/)[0] || "";
		if (/^sequenceDiagram/i.test(first)) return "sequence";
		if (/^(flowchart|graph)\b/i.test(first)) return "flow";
		if (/^stateDiagram/i.test(first)) return "state";
		if (/^gantt/i.test(first)) return "gantt";
		return "diagram";
	};

	const cleanNodeLabel = value => {
		const trimmed = value
			.replace(/["'`]/g, "")
			.replace(/<br\s*\/?>/gi, " / ")
			.replace(/\s+/g, " ")
			.trim();
		const bracket = trimmed.match(/^[\w.-]*[\[\(\{]([^()[\]{}]+)[\]\)\}]/);
		return (bracket ? bracket[1] : trimmed.replace(/^[\w.-]+$/, match => match)).replace(/&amp;/g, "&");
	};

	const parseSequence = source =>
		source
			.split("\n")
			.map(line => line.trim())
			.map(line => line.match(/^(.+?)(?:--)?->>[\+ -]*(.+?):\s*(.+)$/))
			.filter(Boolean)
			.map(match => ({
				from: cleanNodeLabel(match[1]),
				to: cleanNodeLabel(match[2]),
				label: cleanNodeLabel(match[3]),
			}));

	const parseFlow = source => {
		const nodeLabels = new Map();
		const lines = source
			.split("\n")
			.map(line => line.trim())
			.filter(line => line && !/^(flowchart|graph|subgraph|end\b|%%)/i.test(line));
		lines.forEach(line => {
			for (const match of line.matchAll(/\b([A-Za-z][\w.-]*)[\[\(\{]([^()[\]{}]+)[\]\)\}]/g)) {
				nodeLabels.set(match[1], cleanNodeLabel(match[2]));
			}
		});
		const labelFor = value => {
			const id = value.trim().match(/^([A-Za-z][\w.-]*)\b/)?.[1];
			return id && nodeLabels.has(id) ? nodeLabels.get(id) : cleanNodeLabel(value);
		};
		return lines
			.map(line => {
				const label = (line.match(/-->\|([^|]+)\|/) || line.match(/--\s*([^->]+?)\s*-->/) || [])[1] || "";
				const parts = line.replace(/-->\|[^|]+\|/, "-->").split(/-->|---|==>/);
				if (parts.length < 2) return null;
				return {
					from: labelFor(parts[0]),
					to: labelFor(parts[1]),
					label: cleanNodeLabel(label),
				};
			})
			.filter(Boolean);
	};

	const parseState = source =>
		source
			.split("\n")
			.map(line => line.trim())
			.filter(line => line.includes("-->"))
			.map(line => {
				const [from, rest] = line.split("-->");
				const [to, label = ""] = rest.split(":");
				return { from: cleanNodeLabel(from), to: cleanNodeLabel(to), label: cleanNodeLabel(label) };
			});

	const parseGantt = source =>
		source
			.split("\n")
			.map(line => line.trim())
			.filter(line => line.includes(":") && !/^(title|dateFormat|axisFormat|section)\b/i.test(line))
			.map(line => {
				const [label, timing = ""] = line.split(":");
				return { label: cleanNodeLabel(label), timing: cleanNodeLabel(timing) };
			});

	/* The text fallback stands in for a diagram that could not be drawn, so it may
	   not quietly end early. Long diagrams collapse past a readable length and say
	   exactly how many rows are hidden, with the full source one click away. */
	const FALLBACK_VISIBLE_ROWS = 18;
	const appendFallbackOverflow = (target, hidden, source) => {
		if (hidden <= 0) return;
		const notice = document.createElement("div");
		notice.className = "diagram-overflow";
		const count = document.createElement("span");
		count.textContent = `${hidden} more ${hidden === 1 ? "row" : "rows"} not shown`;
		const reveal = document.createElement("button");
		reveal.type = "button";
		reveal.textContent = "Show diagram source";
		reveal.addEventListener("click", () => {
			const existing = target.querySelector(".diagram-source");
			if (existing) {
				existing.remove();
				reveal.textContent = "Show diagram source";
				return;
			}
			const block = document.createElement("pre");
			block.className = "diagram-source";
			block.textContent = source.trim();
			target.append(block);
			reveal.textContent = "Hide diagram source";
		});
		notice.append(count, reveal);
		target.append(notice);
	};

	const fillFallbackDiagram = (target, source) => {
		const type = detectDiagramType(source);
		target.className = `diagram-fallback diagram-fallback-${type}`;
		target.replaceChildren();

		if (type === "sequence") {
			const steps = parseSequence(source);
			steps.slice(0, FALLBACK_VISIBLE_ROWS).forEach((step, index) => {
				const row = document.createElement("div");
				row.className = "diagram-step";
				row.innerHTML = `<span class="diagram-count">${String(index + 1).padStart(2, "0")}</span><span class="diagram-node">${step.from}</span><span class="diagram-arrow">to</span><span class="diagram-node">${step.to}</span><span class="diagram-message">${step.label}</span>`;
				target.append(row);
			});
			appendFallbackOverflow(target, steps.length - FALLBACK_VISIBLE_ROWS, source);
			return;
		}

		if (type === "gantt") {
			const tasks = parseGantt(source);
			tasks.slice(0, FALLBACK_VISIBLE_ROWS).forEach((task, index) => {
				const row = document.createElement("div");
				row.className = "diagram-task";
				row.innerHTML = `<span style="--bar:${(index % 5) + 4}"></span><strong>${task.label}</strong><small>${task.timing}</small>`;
				target.append(row);
			});
			appendFallbackOverflow(target, tasks.length - FALLBACK_VISIBLE_ROWS, source);
			return;
		}

		const edges = type === "state" ? parseState(source) : parseFlow(source);
		edges.slice(0, FALLBACK_VISIBLE_ROWS).forEach(edge => {
			const row = document.createElement("div");
			row.className = "diagram-edge";
			row.innerHTML = `<span class="diagram-node">${edge.from}</span><span class="diagram-arrow">${edge.label || "to"}</span><span class="diagram-node">${edge.to}</span>`;
			target.append(row);
		});
		appendFallbackOverflow(target, edges.length - FALLBACK_VISIBLE_ROWS, source);
	};

	let activeDiagramModal = null;
	const openDiagramViewer = (frame, title) => {
		if (activeDiagramModal) activeDiagramModal.remove();

		const source = frame.querySelector(".mermaid, .diagram-fallback");
		if (!source) return;
		const returnFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;

		const modal = document.createElement("div");
		modal.className = "diagram-modal";
		modal.setAttribute("role", "dialog");
		modal.setAttribute("aria-modal", "true");
		modal.setAttribute("aria-label", `${title} diagram viewer`);
		modal.innerHTML = `
			<div class="diagram-modal-bar">
				<strong>${title}</strong>
				<span class="diagram-modal-help">Scroll to zoom, drag to pan</span>
				<div class="diagram-modal-actions">
					<button type="button" data-diagram-zoom="out" aria-label="Zoom out">-</button>
					<button type="button" data-diagram-zoom="reset" aria-label="Fit diagram to readable width">Fit 100%</button>
					<button type="button" data-diagram-zoom="in" aria-label="Zoom in">+</button>
					<button type="button" data-diagram-close aria-label="Close diagram">Close</button>
				</div>
			</div>
			<div class="diagram-modal-stage">
				<div class="diagram-modal-canvas"></div>
			</div>
		`;

		const stage = modal.querySelector(".diagram-modal-stage");
		const canvas = modal.querySelector(".diagram-modal-canvas");
		const modalSource = source.cloneNode(true);
		const modalSvg = modalSource.matches?.("svg") ? modalSource : modalSource.querySelector?.("svg");
		if (modalSvg) namespaceSvgIds(modalSvg, `diagram-modal-${Date.now()}`);
		canvas.append(modalSource);
		document.body.append(modal);
		document.body.classList.add("has-diagram-modal");
		activeDiagramModal = modal;

		let scale = 1;
		let x = 0;
		let y = 0;
		let dragging = false;
		let startX = 0;
		let startY = 0;
		let originX = 0;
		let originY = 0;
		let dragMoved = false;
		let lastDragEndedAt = 0;
		let backdropClickCandidate = false;
		let backdropStartX = 0;
		let backdropStartY = 0;
		const backdropClickThreshold = 6;
		const diagramContentSelector = ".diagram-modal-canvas > .mermaid, .diagram-modal-canvas > .diagram-fallback";
		const zoomLabel = modal.querySelector("[data-diagram-zoom='reset']");
		const minScale = 0.35;
		const maxScale = 4;
		const fitPadding = 40;
		const applyTransform = () => {
			canvas.style.transform = `translate(${x}px, ${y}px) scale(${scale})`;
			if (zoomLabel) zoomLabel.textContent = `Fit ${Math.round(scale * 100)}%`;
		};
		const clampScale = value => Math.min(maxScale, Math.max(minScale, Number(value.toFixed(3))));
		const fitToStage = () => {
			const stageRect = stage.getBoundingClientRect();
			const contentWidth = canvas.offsetWidth;
			const contentHeight = canvas.offsetHeight;
			if (!contentWidth || !contentHeight) return;
			const availableWidth = Math.max(1, stageRect.width - fitPadding * 2);
			const availableHeight = Math.max(1, stageRect.height - fitPadding * 2);
			// Fit to readable width. Tall flowcharts may extend below the viewport and
			// can be panned; fitting their full height made labels illegible.
			scale = clampScale(Math.min(1, availableWidth / contentWidth));
			x = (stageRect.width - contentWidth * scale) / 2;
			y = contentHeight * scale <= availableHeight ? (stageRect.height - contentHeight * scale) / 2 : fitPadding;
			applyTransform();
		};
		const stageCenter = () => {
			const rect = stage.getBoundingClientRect();
			return {
				clientX: rect.left + rect.width / 2,
				clientY: rect.top + rect.height / 2,
			};
		};
		const zoomTo = (nextScale, anchor = stageCenter()) => {
			nextScale = clampScale(nextScale);
			if (nextScale === scale) return;
			const stageRect = stage.getBoundingClientRect();
			const anchorX = anchor.clientX - stageRect.left;
			const anchorY = anchor.clientY - stageRect.top;
			const localX = (anchorX - canvas.offsetLeft - x) / scale;
			const localY = (anchorY - canvas.offsetTop - y) / scale;
			x = anchorX - canvas.offsetLeft - localX * nextScale;
			y = anchorY - canvas.offsetTop - localY * nextScale;
			scale = nextScale;
			applyTransform();
		};
		const zoomBy = (factor, anchor) => zoomTo(scale * factor, anchor);
		const reset = () => fitToStage();
		const focusableSelector = "button, [href], input, select, textarea, [tabindex]:not([tabindex='-1'])";
		const close = () => {
			modal.remove();
			document.body.classList.remove("has-diagram-modal");
			if (activeDiagramModal === modal) activeDiagramModal = null;
			document.removeEventListener("keydown", onKeydown);
			window.removeEventListener("resize", fitToStage);
			if (returnFocus && document.contains(returnFocus)) returnFocus.focus();
		};
		const onKeydown = event => {
			if (event.key === "Escape") close();
			if (event.key === "Tab") {
				const focusable = Array.from(modal.querySelectorAll(focusableSelector)).filter(
					element => !element.hasAttribute("disabled") && element instanceof HTMLElement,
				);
				if (!focusable.length) return;
				const first = focusable[0];
				const last = focusable[focusable.length - 1];
				if (event.shiftKey && document.activeElement === first) {
					event.preventDefault();
					last.focus();
				} else if (!event.shiftKey && document.activeElement === last) {
					event.preventDefault();
					first.focus();
				}
			}
		};

		modal.querySelector("[data-diagram-close]").addEventListener("click", close);
		modal.querySelector("[data-diagram-zoom='in']").addEventListener("click", () => zoomBy(1.18));
		modal.querySelector("[data-diagram-zoom='out']").addEventListener("click", () => zoomBy(1 / 1.18));
		modal.querySelector("[data-diagram-zoom='reset']").addEventListener("click", reset);
		modal.addEventListener("click", event => {
			const target = event.target;
			if (!(target instanceof Element)) return;
			if (Date.now() - lastDragEndedAt < 200) return;
			if (target.closest(`${diagramContentSelector}, .diagram-modal-actions`)) return;
			close();
		});
		stage.addEventListener(
			"wheel",
			event => {
				event.preventDefault();
				const normalizedDelta = event.deltaMode === WheelEvent.DOM_DELTA_LINE ? event.deltaY * 16 : event.deltaY;
				const boundedDelta = Math.max(-220, Math.min(220, normalizedDelta));
				const factor = Math.exp(-boundedDelta * 0.0007);
				zoomBy(factor, { clientX: event.clientX, clientY: event.clientY });
			},
			{ passive: false },
		);
		stage.addEventListener("pointerdown", event => {
			if (event.button !== 0) return;
			event.preventDefault();
			backdropClickCandidate = event.target instanceof Element && !event.target.closest(diagramContentSelector);
			backdropStartX = event.clientX;
			backdropStartY = event.clientY;
			dragMoved = false;
			dragging = true;
			stage.setPointerCapture(event.pointerId);
			startX = event.clientX;
			startY = event.clientY;
			originX = x;
			originY = y;
			stage.classList.add("is-dragging");
		});
		stage.addEventListener("pointermove", event => {
			if (!dragging) return;
			event.preventDefault();
			const dragDistance = Math.hypot(event.clientX - backdropStartX, event.clientY - backdropStartY);
			if (dragDistance > backdropClickThreshold) {
				dragMoved = true;
				backdropClickCandidate = false;
			}
			x = originX + event.clientX - startX;
			y = originY + event.clientY - startY;
			applyTransform();
		});
		const stopDragging = event => {
			const shouldCloseFromBackdrop = backdropClickCandidate && !dragMoved;
			if (dragMoved) lastDragEndedAt = Date.now();
			backdropClickCandidate = false;
			dragMoved = false;
			dragging = false;
			stage.classList.remove("is-dragging");
			if (stage.hasPointerCapture(event.pointerId)) stage.releasePointerCapture(event.pointerId);
			if (shouldCloseFromBackdrop) close();
		};
		stage.addEventListener("pointerup", stopDragging);
		stage.addEventListener("pointercancel", stopDragging);
		document.addEventListener("keydown", onKeydown);
		window.addEventListener("resize", fitToStage);
		modal.querySelector("[data-diagram-close]").focus();
		fitToStage();
	};

	const namespaceSvgIds = (svg, namespace) => {
		const idMap = new Map();
		svg.querySelectorAll("[id]").forEach((node, index) => {
			if (node === svg) return;
			const previous = node.id;
			const next = `${namespace}-${index}-${previous}`;
			idMap.set(previous, next);
			node.id = next;
		});
		if (!idMap.size) return;
		const referenceAttributes = [
			"aria-describedby",
			"aria-labelledby",
			"clip-path",
			"fill",
			"filter",
			"href",
			"marker-end",
			"marker-mid",
			"marker-start",
			"mask",
			"stroke",
			"xlink:href",
		];
		svg.querySelectorAll("*").forEach(node => {
			referenceAttributes.forEach(attribute => {
				const value = node.getAttribute(attribute);
				if (!value) return;
				let nextValue = value;
				idMap.forEach((next, previous) => {
					nextValue = nextValue.replaceAll(`url(#${previous})`, `url(#${next})`);
					if (nextValue === `#${previous}`) nextValue = `#${next}`;
					if (attribute.startsWith("aria-")) {
						nextValue = nextValue
							.split(/\s+/)
							.map(token => (token === previous ? next : token))
							.join(" ");
					}
				});
				if (nextValue !== value) node.setAttribute(attribute, nextValue);
			});
		});
	};

	const enhanceMermaidSvg = (svg, namespace) => {
		if (!svg) return;
		namespaceSvgIds(svg, namespace);
		const softenRect = (rect, radius) => {
			const rx = rect.getAttribute("rx");
			const ry = rect.getAttribute("ry");
			if (!rx || rx === "0") rect.setAttribute("rx", radius);
			if (!ry || ry === "0") rect.setAttribute("ry", radius);
		};
		svg.dataset.styled = "true";
		svg.querySelectorAll(".node, .state, .actor").forEach(node => {
			node.querySelectorAll("rect").forEach(rect => softenRect(rect, "6"));
		});
		svg.querySelectorAll(".cluster rect, .note, .labelBox, .edgeLabel rect").forEach(rect => softenRect(rect, "5"));
	};

	const TYPE_LABELS = { sequence: "Sequence", flow: "Flow", state: "State", gantt: "Timeline", diagram: "Diagram" };

	/* A caption names what the figure shows, not which Mermaid grammar drew it.
	   An authored `data-diagram-title` wins; otherwise the section the diagram sits
	   in supplies the subject, and the grammar becomes a trailing qualifier. */
	const describeDiagram = (pre, code, source) => {
		const type = detectDiagramType(source);
		const typeLabel = TYPE_LABELS[type] || TYPE_LABELS.diagram;
		const authored = (code.dataset.diagramTitle || pre?.dataset.diagramTitle || "").trim();
		if (authored) return { type, text: authored };

		let node = pre;
		while (node && node !== document.body) {
			let sibling = node.previousElementSibling;
			while (sibling) {
				if (/^H[2-6]$/.test(sibling.tagName)) {
					const heading = sibling.cloneNode(true);
					heading.querySelectorAll(".heading-anchor").forEach(button => button.remove());
					const title = (heading.textContent || "")
						.replace(/#$/, "")
						.replace(/^\d+(\.\d+)*\.?\s*/, "")
						.trim();
					// An unrecognised grammar adds nothing to the caption, so drop the qualifier.
					if (title) return { type, text: type === "diagram" ? title : `${title}: ${typeLabel.toLowerCase()}` };
				}
				sibling = sibling.previousElementSibling;
			}
			node = node.parentElement;
		}
		return { type, text: typeLabel };
	};

	/* Mermaid ships with the docs rather than loading from a CDN, so diagrams also
	   draw offline, from a file:// checkout, and behind a proxy. Loaded once, lazily,
	   and only on pages that actually contain a diagram. */
	let mermaidPromise = null;
	const loadMermaid = () => {
		if (window.mermaid) return Promise.resolve(window.mermaid);
		if (mermaidPromise) return mermaidPromise;
		mermaidPromise = new Promise((resolve, reject) => {
			const script = document.createElement("script");
			script.src = assetUrl("vendor/mermaid.min.js");
			script.addEventListener("load", () =>
				window.mermaid ? resolve(window.mermaid) : reject(new Error("mermaid bundle loaded but exported nothing")),
			);
			script.addEventListener("error", () => reject(new Error("mermaid bundle could not be loaded")));
			document.head.append(script);
		});
		return mermaidPromise;
	};

	const installMermaidDiagrams = async () => {
		const blocks = Array.from(document.querySelectorAll(".doc-article pre > code.language-mermaid"));
		if (!blocks.length) return;

		const diagrams = blocks.map((code, index) => {
			const source = code.textContent || "";
			const pre = code.closest("pre");
			const frame = document.createElement("figure");
			frame.className = "mermaid-frame";
			const caption = document.createElement("figcaption");
			const captionText = describeDiagram(pre, code, source).text;
			const captionLabel = document.createElement("span");
			captionLabel.textContent = captionText;
			const openButton = document.createElement("button");
			openButton.type = "button";
			openButton.className = "diagram-open-button";
			setIconLabel(openButton, icons.expand, "Full screen");
			openButton.setAttribute("aria-label", `Open ${captionText} diagram full screen`);
			const openDiagram = () => openDiagramViewer(frame, captionText);
			openButton.addEventListener("click", openDiagram);
			caption.append(captionLabel, openButton);
			const canvas = document.createElement("div");
			canvas.className = "diagram-fallback";
			canvas.dataset.diagramIndex = String(index);
			canvas.setAttribute("role", "button");
			canvas.setAttribute("tabindex", "0");
			canvas.setAttribute("aria-label", `Open ${captionText} diagram full screen`);
			canvas.addEventListener("click", event => {
				if (event.target.closest("button, a")) return;
				openDiagram();
			});
			canvas.addEventListener("keydown", event => {
				if (event.key !== "Enter" && event.key !== " ") return;
				event.preventDefault();
				openDiagram();
			});
			fillFallbackDiagram(canvas, source);
			frame.append(caption, canvas);
			if (pre) pre.replaceWith(frame);
			return { frame, canvas, source };
		});

		try {
			const mermaid = await loadMermaid();
			const mermaidTheme =
				root.dataset.theme === "dark"
					? {
							fontFamily: "Manrope, ui-sans-serif, system-ui, sans-serif",
							background: "#050505",
							mainBkg: "#1c100e",
							primaryColor: "#1c100e",
							primaryBorderColor: "#ff7c70",
							primaryTextColor: "#f2eded",
							secondaryColor: "#141010",
							secondaryBorderColor: "#807b7b",
							secondaryTextColor: "#f2eded",
							tertiaryColor: "#131010",
							tertiaryBorderColor: "#807b7b",
							tertiaryTextColor: "#f2eded",
							lineColor: "#8f8a8a",
							textColor: "#f2eded",
							nodeTextColor: "#f2eded",
							clusterBkg: "#121010",
							clusterBorder: "#4a4646",
							edgeLabelBackground: "#141010",
							actorBkg: "#1c100e",
							actorBorder: "#ff7c70",
							actorTextColor: "#f2eded",
							actorLineColor: "#8f8a8a",
							noteBkgColor: "#141010",
							noteTextColor: "#f2eded",
							noteBorderColor: "#4a4646",
							labelBoxBkgColor: "#141010",
							labelBoxBorderColor: "#4a4646",
							labelTextColor: "#f2eded",
							loopTextColor: "#f2eded",
						}
					: {
							fontFamily: "Manrope, ui-sans-serif, system-ui, sans-serif",
							background: "#ffffff",
							mainBkg: "#fff1ef",
							primaryColor: "#fff1ef",
							primaryBorderColor: "#e0483a",
							primaryTextColor: "#0a0a0a",
							secondaryColor: "#fff1ef",
							secondaryBorderColor: "#ff6f61",
							secondaryTextColor: "#0a0a0a",
							tertiaryColor: "#fff7dc",
							tertiaryBorderColor: "#9d6b00",
							tertiaryTextColor: "#0a0a0a",
							lineColor: "#6f6f6f",
							textColor: "#0a0a0a",
							nodeTextColor: "#0a0a0a",
							clusterBkg: "#fafafa",
							clusterBorder: "#bdbdbd",
							edgeLabelBackground: "#ffffff",
							actorBkg: "#f5f5f5",
							actorBorder: "#bdbdbd",
							actorTextColor: "#0a0a0a",
							actorLineColor: "#6f6f6f",
							noteBkgColor: "#fff7dc",
							noteTextColor: "#0a0a0a",
							noteBorderColor: "#9d6b00",
							labelBoxBkgColor: "#fff7dc",
							labelBoxBorderColor: "#9d6b00",
							labelTextColor: "#0a0a0a",
							loopTextColor: "#0a0a0a",
						};
			mermaid.initialize({
				startOnLoad: false,
				securityLevel: "loose",
				theme: "base",
				themeVariables: mermaidTheme,
				flowchart: { htmlLabels: true },
			});
			const staging = document.createElement("div");
			staging.className = "mermaid-staging";
			document.body.append(staging);
			const renderNodes = diagrams.map(({ source }, index) => {
				const node = document.createElement("div");
				node.className = "mermaid";
				node.id = `mermaid-render-${Date.now()}-${index}`;
				node.textContent = source;
				staging.append(node);
				return node;
			});
			await mermaid.run({ nodes: renderNodes, suppressErrors: true });
			renderNodes.forEach((node, index) => {
				const { frame, canvas, source } = diagrams[index];
				const svg = node.querySelector("svg");
				if (svg) {
					const renderedSvg = svg.cloneNode(true);
					enhanceMermaidSvg(renderedSvg, `diagram-${index}`);
					canvas.className = "mermaid";
					canvas.replaceChildren(renderedSvg);
					frame.classList.add("is-rendered");
				} else {
					frame.classList.add("is-fallback");
					fillFallbackDiagram(canvas, source);
				}
			});
			staging.remove();
		} catch (_error) {
			diagrams.forEach(({ frame }) => frame.classList.add("is-fallback"));
		}
	};

	installMermaidDiagrams();

	const formatAmount = value =>
		new Intl.NumberFormat("en-US", { maximumFractionDigits: 6, minimumFractionDigits: Number.isInteger(value) ? 0 : 2 }).format(value);
	const readNumber = (rootElement, selector) => {
		const input = rootElement.querySelector(selector);
		const value = input ? Number(input.value) : 0;
		return Number.isFinite(value) ? value : 0;
	};
	const formatDuration = seconds => {
		const rounded = Math.max(0, Math.round(seconds));
		const hours = Math.floor(rounded / 3600);
		const minutes = Math.floor((rounded % 3600) / 60);
		const remainingSeconds = rounded % 60;
		const parts = [];
		if (hours) parts.push(`${hours}h`);
		if (minutes) parts.push(`${minutes}m`);
		if (remainingSeconds || !parts.length) parts.push(`${remainingSeconds}s`);
		return parts.join(" ");
	};
	const installExpressFundingTool = mount => {
		mount.innerHTML = `
			<div class="tool-heading">
				<div>
					<p class="eyebrow">Context helper</p>
					<h3>Offer Eligibility & Funding</h3>
				</div>
				<p>Enter the user's request, pool balances, and credit config to see which offers the bot can sign and where capital is drawn from.</p>
			</div>
			<div class="tool-input-groups">
				<div class="tool-input-group">
					<strong>Request</strong>
					<div class="tool-grid tool-grid-compact">
						<label>User requested amount<input type="number" min="0" step="0.01" value="500" data-request-amount></label>
						<label>Risk check<select data-risk-check>
							<option value="LOW">LOW RISK</option>
							<option value="HIGH">HIGH RISK</option>
						</select></label>
						<label>Min validator signatures<input type="number" min="0" step="1" value="2" data-validator-count></label>
					</div>
				</div>
				<div class="tool-input-group">
					<strong>Available liquidity</strong>
					<div class="tool-grid tool-grid-compact">
						<label>Affiliate pool free<input type="number" min="0" step="0.01" value="120" data-affiliate-pool></label>
						<label>General pool free<input type="number" min="0" step="0.01" value="300" data-general-pool></label>
						<label>Muon eligible base<input type="number" min="0" step="0.01" value="2000" data-eligible-base></label>
					</div>
				</div>
				<div class="tool-input-group">
					<strong>Credit line config</strong>
					<div class="tool-grid tool-grid-compact">
						<label>Current debt<input type="number" min="0" step="0.01" value="300" data-current-debt></label>
						<label>Protocol max debt<input type="number" min="0" step="0.01" value="1000" data-protocol-max-debt></label>
						<label>Affiliate max debt<input type="number" min="0" step="0.01" value="700" data-affiliate-max-debt></label>
						<label>Protocol max bps<input type="number" min="0" max="10000" step="1" value="5000" data-protocol-max-bps></label>
						<label>Affiliate max bps<input type="number" min="0" max="10000" step="1" value="3000" data-affiliate-max-bps></label>
						<label>Credit blocked?<select data-credit-blocked>
							<option value="NO">No</option>
							<option value="PAUSED">Paused</option>
							<option value="BLACKLISTED">User blacklisted</option>
						</select></label>
					</div>
				</div>
				<div class="tool-input-group">
					<strong>Fees</strong>
					<div class="tool-grid tool-grid-compact">
						<label>Affiliate fee bps<input type="number" min="0" max="10000" step="1" value="80" data-fee-bps></label>
						<label>Operator fee<input type="number" min="0" step="0.01" value="1" data-operator-fee></label>
					</div>
				</div>
			</div>
			<div class="tool-result" aria-live="polite"></div>
		`;
		const result = mount.querySelector(".tool-result");
		const cappedLimit = values => {
			const positive = values.filter(value => value > 0);
			return positive.length ? Math.min(...positive) : Infinity;
		};
		const describeLimit = value => (Number.isFinite(value) ? formatAmount(value) : "uncapped by config");
		const allocateFastFunding = (amount, affiliatePool, generalPool, creditCapacity, allowCredit = true) => {
			const affiliateAmount = Math.min(amount, affiliatePool);
			let remaining = Math.max(0, amount - affiliateAmount);
			const creditAmount = allowCredit ? Math.min(remaining, creditCapacity) : 0;
			remaining = Math.max(0, remaining - creditAmount);
			const generalAmount = Math.min(remaining, generalPool);
			remaining = Math.max(0, remaining - generalAmount);
			return { affiliateAmount, creditAmount, generalAmount, unfunded: remaining };
		};
		const optionCard = option => `
			<article class="option-card ${option.available ? "is-available" : "is-unavailable"}">
				<div class="option-card-title">
					<span>${escapeHtml(option.type)}</span>
					<strong>${option.available ? "Available" : "Not available"}</strong>
				</div>
				<p>${escapeHtml(option.reason)}</p>
				<div class="option-spend-grid">
					<span><small>Affiliate pool</small><strong>${formatAmount(option.allocation.affiliateAmount)}</strong></span>
					<span><small>Credit advance</small><strong>${formatAmount(option.allocation.creditAmount)}</strong></span>
					<span><small>General pool</small><strong>${formatAmount(option.allocation.generalAmount)}</strong></span>
				</div>
			</article>
		`;
		const update = () => {
			const requestAmount = readNumber(mount, "[data-request-amount]");
			const riskCheck = mount.querySelector("[data-risk-check]").value;
			const validatorCount = readNumber(mount, "[data-validator-count]");
			const affiliatePool = readNumber(mount, "[data-affiliate-pool]");
			const generalPool = readNumber(mount, "[data-general-pool]");
			const eligibleBase = readNumber(mount, "[data-eligible-base]");
			const currentDebt = readNumber(mount, "[data-current-debt]");
			const protocolMaxDebt = readNumber(mount, "[data-protocol-max-debt]");
			const affiliateMaxDebt = readNumber(mount, "[data-affiliate-max-debt]");
			const protocolMaxBps = readNumber(mount, "[data-protocol-max-bps]");
			const affiliateMaxBps = readNumber(mount, "[data-affiliate-max-bps]");
			const creditBlocked = mount.querySelector("[data-credit-blocked]").value;
			const feeBps = readNumber(mount, "[data-fee-bps]");
			const operatorFee = readNumber(mount, "[data-operator-fee]");

			const protocolBpsLimit = protocolMaxBps > 0 ? (eligibleBase * protocolMaxBps) / 10000 : Infinity;
			const affiliateBpsLimit = affiliateMaxBps > 0 ? (eligibleBase * affiliateMaxBps) / 10000 : Infinity;
			const effectiveDebtLimit = cappedLimit([protocolMaxDebt, affiliateMaxDebt, protocolBpsLimit, affiliateBpsLimit]);
			const creditBlockedReason =
				creditBlocked === "PAUSED" ? "credit line is paused" : creditBlocked === "BLACKLISTED" ? "user is blacklisted for credit" : "";
			const rawCreditCapacity = Number.isFinite(effectiveDebtLimit) ? Math.max(0, effectiveDebtLimit - currentDebt) : requestAmount;
			const creditCapacity = creditBlocked === "NO" ? rawCreditCapacity : 0;
			const fastAllocation = allocateFastFunding(requestAmount, affiliatePool, generalPool, creditCapacity);
			const standardAllocation = { affiliateAmount: 0, creditAmount: 0, generalAmount: 0, unfunded: 0 };

			const feeAmount = (requestAmount * feeBps) / 10000;
			const totalFee = feeAmount + operatorFee;
			const userFee = totalFee;
			const netUserAmount = Math.max(0, requestAmount - userFee);
			const poolDraw = fastAllocation.affiliateAmount + fastAllocation.generalAmount;
			const validatorsReady = validatorCount > 0;
			const fastFundingAvailable = requestAmount > 0 && fastAllocation.unfunded <= 0;

			const sameTxReasons = [];
			if (!validatorsReady) sameTxReasons.push("validator signatures are not configured");
			if (!fastFundingAvailable) sameTxReasons.push(`${formatAmount(fastAllocation.unfunded)} remains unfunded after pools and credit`);
			if (creditBlockedReason && fastAllocation.unfunded > 0) sameTxReasons.push(creditBlockedReason);
			const windowedReasons = [];
			if (riskCheck !== "LOW") windowedReasons.push("risk check is high, so the bot should not sign the fast path");
			if (!fastFundingAvailable) windowedReasons.push(`${formatAmount(fastAllocation.unfunded)} remains unfunded after pools and credit`);
			if (creditBlockedReason && fastAllocation.unfunded > 0) windowedReasons.push(creditBlockedReason);

			const options = [
				{
					type: "SAME_TX",
					available: validatorsReady && fastFundingAvailable,
					reason: sameTxReasons.length
						? sameTxReasons.join("; ")
						: "Same-transaction payout can be signed because validators are configured and the request can be fully funded.",
					allocation: fastAllocation,
				},
				{
					type: "WINDOWED",
					available: riskCheck === "LOW" && fastFundingAvailable,
					reason: windowedReasons.length
						? windowedReasons.join("; ")
						: "The request can be processed after the security window using the computed pool and credit split.",
					allocation: fastAllocation,
				},
				{
					type: "STANDARD",
					available: requestAmount > 0,
					reason:
						requestAmount > 0
							? "Always available as the cooldown path; Express does not front pools or credit for STANDARD."
							: "Enter a positive request amount.",
					allocation: standardAllocation,
				},
			];
			const recommended = options.find(option => option.available) || options[2];
			const warnings = [];
			if (creditBlockedReason) warnings.push(`Credit capacity is zero because ${creditBlockedReason}.`);
			if (requestAmount > 0 && fastAllocation.unfunded > 0)
				warnings.push(
					"Fast options cannot cover the full request with the current pools and credit capacity; STANDARD remains the fallback.",
				);
			if (!validatorsReady) warnings.push("SAME_TX requires minValidatorSignatures above zero.");
			if (riskCheck !== "LOW") warnings.push("WINDOWED should not be signed while the risk check is high.");
			result.innerHTML = `
				<div class="result-metrics">
					<span><small>Recommended offer</small><strong>${escapeHtml(recommended.type)}</strong></span>
					<span><small>Fast pool draw</small><strong>${formatAmount(poolDraw)}</strong></span>
					<span><small>Credit capacity</small><strong>${formatAmount(creditCapacity)}</strong></span>
					<span><small>User receives after fees</small><strong>${formatAmount(netUserAmount)}</strong></span>
				</div>
				<div class="option-card-grid">${options.map(optionCard).join("")}</div>
				<p>Effective credit cap is <strong>${describeLimit(effectiveDebtLimit)}</strong>; current debt is <strong>${formatAmount(currentDebt)}</strong>; usable credit for this request is <strong>${formatAmount(creditCapacity)}</strong>.</p>
				<p>Fee is <strong>${formatAmount(feeAmount)}</strong> plus operator fee <strong>${formatAmount(operatorFee)}</strong>; user pays <strong>${formatAmount(userFee)}</strong>.</p>
				${warnings.length ? `<ul class="tool-warnings">${warnings.map(warning => `<li>${escapeHtml(warning)}</li>`).join("")}</ul>` : '<p class="tool-ok">Current config supports a fast offer and a standard fallback.</p>'}
			`;
		};
		mount.querySelectorAll("input, select").forEach(control => {
			control.addEventListener("input", update);
			control.addEventListener("change", update);
		});
		update();
	};

	const installExpressTimingTool = mount => {
		mount.innerHTML = `
			<div class="tool-heading">
				<div>
					<p class="eyebrow">Context helper</p>
					<h3>Processing Timeline</h3>
				</div>
				<p>Model operator, permissionless, and STANDARD finalization windows.</p>
			</div>
			<div class="tool-grid tool-grid-compact">
				<label>Security window (seconds)<input type="number" min="0" step="1" value="20" data-security-window></label>
				<label>Tolerance period (seconds)<input type="number" min="0" step="1" value="60" data-tolerance-period></label>
				<label>STANDARD cooldown (hours)<input type="number" min="0" step="0.25" value="12" data-standard-cooldown></label>
			</div>
			<div class="timeline-track" aria-live="polite"></div>
		`;
		const result = mount.querySelector(".timeline-track");
		const update = () => {
			const securityWindow = readNumber(mount, "[data-security-window]");
			const tolerancePeriod = readNumber(mount, "[data-tolerance-period]");
			const cooldown = readNumber(mount, "[data-standard-cooldown]") * 3600;
			const permissionless = securityWindow + tolerancePeriod;
			result.innerHTML = `
				<div class="timeline-item"><span>Accept</span><strong>T + 0s</strong><small>Request enters ExpressProvider state.</small></div>
				<div class="timeline-item"><span>Operator</span><strong>T + ${formatDuration(securityWindow)}</strong><small>Operator can process WINDOWED if not locked.</small></div>
				<div class="timeline-item"><span>Fallback</span><strong>T + ${formatDuration(permissionless)}</strong><small>Anyone can process after tolerance expires.</small></div>
				<div class="timeline-item"><span>STANDARD</span><strong>T + ${formatDuration(cooldown)}</strong><small>SYMMIO cooldown target before finalization.</small></div>
			`;
		};
		mount.querySelectorAll("input").forEach(control => control.addEventListener("input", update));
		update();
	};
	const ADJUSTMENT_SCALE = 1000000000000000000n;

	const parseScaledFactor = raw => {
		const text = String(raw == null ? "" : raw).trim();
		if (!/^\d*\.?\d*$/.test(text) || text === "" || text === ".") return null;
		const [whole, fraction = ""] = text.split(".");
		if (fraction.length > 18) return null;
		const padded = (fraction + "000000000000000000").slice(0, 18);
		const value = BigInt(whole || "0") * ADJUSTMENT_SCALE + BigInt(padded);
		return value > 0n ? value : null;
	};

	const parseSignedInteger = raw => {
		const text = String(raw == null ? "" : raw)
			.trim()
			.replace(/[_,\s]/g, "");
		if (!/^-?\d+$/.test(text)) return null;
		return BigInt(text);
	};

	const parseUnsignedInteger = raw => {
		const value = parseSignedInteger(raw);
		return value == null || value < 0n ? null : value;
	};

	const formatFactor = value => {
		const whole = value / ADJUSTMENT_SCALE;
		const fraction = (value % ADJUSTMENT_SCALE).toString().padStart(18, "0").replace(/0+$/, "");
		return fraction ? `${whole}.${fraction}` : `${whole}`;
	};

	const formatBigInt = value => {
		const negative = value < 0n;
		const digits = (negative ? -value : value).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
		return negative ? `-${digits}` : digits;
	};

	const scaleDown = (amount, factor) => (amount * factor) / ADJUSTMENT_SCALE;

	const convertAmountPricePair = (amount, price, factor, adjustedAmount = scaleDown(amount, factor)) => {
		if (adjustedAmount === 0n) return { adjustedAmount, adjustedPrice: 0n, oldNotional: amount * price, newNotional: 0n, dust: 0n };
		const adjustedPrice = price === 0n ? 0n : (amount * price) / adjustedAmount;
		const oldNotional = amount * price;
		const newNotional = adjustedAmount * adjustedPrice;
		return { adjustedAmount, adjustedPrice, oldNotional, newNotional, dust: oldNotional - newNotional };
	};

	const installSymbolAdjustmentTool = mount => {
		mount.innerHTML = `
			<div class="tool-heading">
				<div>
					<p class="eyebrow">Context helper</p>
					<h3>Factor and quote conversion</h3>
				</div>
				<p>Describe one venue event and one stored quote. The panel shows the price Muon must publish on the adjusted-price route, and the rewritten fields, rounding dust, and rejection rules on the physical route.</p>
			</div>
			<div class="tool-input-groups">
				<div class="tool-input-group">
					<strong>Venue event</strong>
					<div class="tool-grid tool-grid-compact">
						<label>Active factor<input type="text" inputmode="decimal" value="1" data-active-factor></label>
						<label>This event's factor<input type="text" inputmode="decimal" value="4" data-event-factor></label>
						<label>Raw venue price after event<input type="text" inputmode="numeric" value="100" data-venue-price></label>
					</div>
				</div>
				<div class="tool-input-group">
					<strong>Quote as stored, in raw amount units</strong>
					<div class="tool-grid tool-grid-compact">
						<label>quantity<input type="text" inputmode="numeric" value="100" data-quantity></label>
						<label>openedPrice<input type="text" inputmode="numeric" value="400" data-opened-price></label>
						<label>closedAmount<input type="text" inputmode="numeric" value="0" data-closed-amount></label>
						<label>avgClosedPrice<input type="text" inputmode="numeric" value="0" data-avg-closed-price></label>
						<label>quantityToClose<input type="text" inputmode="numeric" value="0" data-quantity-to-close></label>
						<label>requestedClosePrice<input type="text" inputmode="numeric" value="0" data-requested-close-price></label>
					</div>
				</div>
				<div class="tool-input-group">
					<strong>Funding</strong>
					<div class="tool-grid tool-grid-compact">
						<label>Current rate per old unit<input type="text" inputmode="numeric" value="8" data-funding-rate></label>
					</div>
				</div>
			</div>
			<div class="tool-result" aria-live="polite"></div>
		`;
		const result = mount.querySelector(".tool-result");
		const readField = (selector, parser) => parser(mount.querySelector(selector).value);
		const row = (label, before, after, note) =>
			`<tr><td><code>${escapeHtml(label)}</code></td><td>${before}</td><td>${after}</td><td>${note}</td></tr>`;

		const update = () => {
			const activeFactor = readField("[data-active-factor]", parseScaledFactor);
			const eventFactor = readField("[data-event-factor]", parseScaledFactor);
			const venuePrice = readField("[data-venue-price]", parseUnsignedInteger);
			const quantity = readField("[data-quantity]", parseUnsignedInteger);
			const openedPrice = readField("[data-opened-price]", parseUnsignedInteger);
			const closedAmount = readField("[data-closed-amount]", parseUnsignedInteger);
			const avgClosedPrice = readField("[data-avg-closed-price]", parseUnsignedInteger);
			const quantityToClose = readField("[data-quantity-to-close]", parseUnsignedInteger);
			const requestedClosePrice = readField("[data-requested-close-price]", parseUnsignedInteger);
			const fundingRate = readField("[data-funding-rate]", parseSignedInteger);

			const missing = [
				activeFactor == null && "active factor",
				eventFactor == null && "this event's factor",
				venuePrice == null && "raw venue price",
				quantity == null && "quantity",
				openedPrice == null && "openedPrice",
				closedAmount == null && "closedAmount",
				avgClosedPrice == null && "avgClosedPrice",
				quantityToClose == null && "quantityToClose",
				requestedClosePrice == null && "requestedClosePrice",
				fundingRate == null && "funding rate",
			].filter(Boolean);
			if (missing.length) {
				result.innerHTML = `<ul class="tool-warnings"><li>Enter a valid value for ${escapeHtml(missing.join(", "))}. Factors are positive decimals; amounts and prices are whole numbers; the funding rate may be negative.</li></ul>`;
				return;
			}
			if (quantity === 0n) {
				result.innerHTML = `<ul class="tool-warnings"><li>A stored quote has a nonzero <code>quantity</code>.</li></ul>`;
				return;
			}
			if (closedAmount > quantity) {
				result.innerHTML = `<ul class="tool-warnings"><li><code>closedAmount</code> cannot exceed <code>quantity</code>.</li></ul>`;
				return;
			}

			const prospectiveFactor = (activeFactor * eventFactor) / ADJUSTMENT_SCALE;
			if (prospectiveFactor === 0n) {
				result.innerHTML = `<ul class="tool-warnings"><li>The two factors compound to zero: <code>floor(${escapeHtml(formatFactor(activeFactor))} &times; ${escapeHtml(formatFactor(eventFactor))})</code> floors away entirely. Confirmation, direct start, and preview all reject this product.</li></ul>`;
				return;
			}

			// Adjusted-price route: external prices are lifted onto the stored quote basis.
			const adjustedMark = scaleDown(venuePrice, prospectiveFactor);
			const storedOpenAmount = quantity - closedAmount;
			const venueOpenAmount = scaleDown(storedOpenAmount, prospectiveFactor);
			const venueClosedAmount = scaleDown(closedAmount, prospectiveFactor);
			const venueQuantity = venueOpenAmount + venueClosedAmount;
			const legacyVenueQuantity = scaleDown(quantity, prospectiveFactor);
			const legacyVenueOpenAmount = legacyVenueQuantity - venueClosedAmount;
			const upnlRaw = storedOpenAmount * (venuePrice - openedPrice);
			const upnlAdjusted = storedOpenAmount * (adjustedMark - openedPrice);

			// Physical route: a direct restatement converts by the prospective factor.
			const position = convertAmountPricePair(quantity, openedPrice, prospectiveFactor, venueQuantity);
			const closed = convertAmountPricePair(closedAmount, avgClosedPrice, prospectiveFactor);
			const closeRequest = convertAmountPricePair(quantityToClose, requestedClosePrice, prospectiveFactor);

			const rejections = [];
			if (position.adjustedAmount === 0n)
				rejections.push(
					`The whole position vanishes: converted open amount plus converted closed amount is <code>0</code>. Core will not store a zero-quantity position.`,
				);
			if (closedAmount > 0n && closed.adjustedAmount === 0n)
				rejections.push(
					`Recorded closed quantity vanishes: <code>floor(${escapeHtml(formatBigInt(closedAmount))} &times; factor) = 0</code>. Core will not erase closed history.`,
				);
			if (venueOpenAmount === 0n)
				rejections.push(
					`No open quantity survives: <code>floor((${escapeHtml(formatBigInt(quantity))} - ${escapeHtml(formatBigInt(closedAmount))}) &times; factor) = 0</code>. Core will not manufacture open size from total-quantity rounding.`,
				);
			if (quantityToClose > 0n && closeRequest.adjustedAmount === 0n)
				rejections.push(
					`The pending close request vanishes: <code>floor(${escapeHtml(formatBigInt(quantityToClose))} &times; factor) = 0</code>. Core will not keep a close request for zero quantity.`,
				);

			const restatable = rejections.length === 0;
			const totalDust = position.dust + closed.dust + closeRequest.dust;
			const rateMagnitude = fundingRate < 0n ? -fundingRate : fundingRate;
			const restoredMagnitude = (rateMagnitude * ADJUSTMENT_SCALE) / prospectiveFactor;
			const restoredRate = fundingRate < 0n ? -restoredMagnitude : restoredMagnitude;
			const fundingBefore = storedOpenAmount * fundingRate;
			const fundingAfter = venueOpenAmount * restoredRate;

			const notes = [];
			if (legacyVenueOpenAmount !== venueOpenAmount)
				notes.push(
					`The old independent-total method would produce open amount <code>${escapeHtml(formatBigInt(legacyVenueOpenAmount))}</code>. Core instead scales the actual stored open amount to <code>${escapeHtml(formatBigInt(venueOpenAmount))}</code> and reconstructs quantity, preventing that ${escapeHtml(formatBigInt(legacyVenueOpenAmount - venueOpenAmount))}-wei carry from changing position size.`,
				);
			if (restatable && totalDust > 0n)
				notes.push(
					`Integer division discards <code>${escapeHtml(formatBigInt(totalDust))}</code> of notional across the converted pairs. Each pair's dust is <code>oldNotional % adjustedAmount</code>, always smaller than the converted amount.`,
				);
			if (restatable && fundingBefore !== fundingAfter)
				notes.push(
					`Flooring the restored rate moves the funding amount from <code>${escapeHtml(formatBigInt(fundingBefore))}</code> to <code>${escapeHtml(formatBigInt(fundingAfter))}</code>.`,
				);
			if (activeFactor !== ADJUSTMENT_SCALE)
				notes.push(
					`A direct restatement converts by the prospective factor shown. A restatement opened later, after <code>confirmPriceAdjusted</code>, would instead convert by the active factor <code>${escapeHtml(formatFactor(activeFactor))}</code>.`,
				);

			result.innerHTML = `
				<div class="result-metrics">
					<span><small>Prospective factor</small><strong>${escapeHtml(formatFactor(prospectiveFactor))}x</strong></span>
					<span><small>Adjusted mark Muon publishes</small><strong>${escapeHtml(formatBigInt(adjustedMark))}</strong></span>
					<span><small>Physical conversion</small><strong>${restatable ? "Accepted" : "Rejected"}</strong></span>
					<span><small>Notional dust</small><strong>${restatable ? escapeHtml(formatBigInt(totalDust)) : "n/a"}</strong></span>
				</div>
				<p class="eyebrow">Adjusted-price route &mdash; storage untouched</p>
				<p>
					Muon multiplies the raw venue price by the factor: <code>floor(${escapeHtml(formatBigInt(venuePrice))} &times; ${escapeHtml(formatFactor(prospectiveFactor))}) = ${escapeHtml(formatBigInt(adjustedMark))}</code>.
					Feeding Core the raw <code>${escapeHtml(formatBigInt(venuePrice))}</code> instead would report a price UPNL of
					<code>${escapeHtml(formatBigInt(upnlRaw))}</code> on this long, against the correct
					<code>${escapeHtml(formatBigInt(upnlAdjusted))}</code>.
					<code>getQuoteInVenueUnits</code> reports quantity <code>${escapeHtml(formatBigInt(venueQuantity))}</code>,
					closed amount <code>${escapeHtml(formatBigInt(venueClosedAmount))}</code>, and open amount
					<code>${escapeHtml(formatBigInt(venueOpenAmount))}</code> for display only.
				</p>
				<p class="eyebrow">Physical route &mdash; storage rewritten</p>
				<div class="table-wrap">
					<table>
						<thead><tr><th>Field</th><th>Stored</th><th>Rewritten</th><th>Notional</th></tr></thead>
						<tbody>
							${row("quantity / openedPrice", `${escapeHtml(formatBigInt(quantity))} @ ${escapeHtml(formatBigInt(openedPrice))}`, `${escapeHtml(formatBigInt(position.adjustedAmount))} @ ${escapeHtml(formatBigInt(position.adjustedPrice))}`, `${escapeHtml(formatBigInt(position.oldNotional))} &rarr; ${escapeHtml(formatBigInt(position.newNotional))}${position.dust > 0n ? ` (dust ${escapeHtml(formatBigInt(position.dust))})` : ""}`)}
							${closedAmount > 0n ? row("closedAmount / avgClosedPrice", `${escapeHtml(formatBigInt(closedAmount))} @ ${escapeHtml(formatBigInt(avgClosedPrice))}`, `${escapeHtml(formatBigInt(closed.adjustedAmount))} @ ${escapeHtml(formatBigInt(closed.adjustedPrice))}`, `${escapeHtml(formatBigInt(closed.oldNotional))} &rarr; ${escapeHtml(formatBigInt(closed.newNotional))}${closed.dust > 0n ? ` (dust ${escapeHtml(formatBigInt(closed.dust))})` : ""}`) : row("closedAmount / avgClosedPrice", "0", "0", "not converted while zero")}
							${quantityToClose > 0n ? row("quantityToClose / requestedClosePrice", `${escapeHtml(formatBigInt(quantityToClose))} @ ${escapeHtml(formatBigInt(requestedClosePrice))}`, `${escapeHtml(formatBigInt(closeRequest.adjustedAmount))} @ ${escapeHtml(formatBigInt(closeRequest.adjustedPrice))}`, `${escapeHtml(formatBigInt(closeRequest.oldNotional))} &rarr; ${escapeHtml(formatBigInt(closeRequest.newNotional))}${closeRequest.dust > 0n ? ` (dust ${escapeHtml(formatBigInt(closeRequest.dust))})` : ""}`) : row("quantityToClose / requestedClosePrice", "0", "0", "not converted while zero")}
							${row("current funding rate", `${escapeHtml(formatBigInt(fundingRate))} per old unit`, `${escapeHtml(formatBigInt(restoredRate))} per new unit`, `${escapeHtml(formatBigInt(fundingBefore))} &rarr; ${escapeHtml(formatBigInt(fundingAfter))}`)}
						</tbody>
					</table>
				</div>
				${rejections.length ? `<ul class="tool-warnings">${rejections.map(entry => `<li>${entry}</li>`).join("")}</ul>` : `<p class="tool-ok">Every amount survives the conversion, so <code>applyAdjustment</code> would rewrite this quote. The dust exception does not apply.</p>`}
				${notes.length ? `<ul class="tool-warnings">${notes.map(entry => `<li>${entry}</li>`).join("")}</ul>` : ""}
			`;
		};
		mount.querySelectorAll("input").forEach(control => control.addEventListener("input", update));
		update();
	};

	const installExpressTools = () => {
		document.querySelectorAll("[data-express-funding-tool]").forEach(installExpressFundingTool);
		document.querySelectorAll("[data-express-timing-tool]").forEach(installExpressTimingTool);
		document.querySelectorAll("[data-symbol-adjustment-tool]").forEach(installSymbolAdjustmentTool);
	};

	installExpressTools();

	const solidityKeywords = new Set([
		"abstract",
		"after",
		"anonymous",
		"as",
		"assembly",
		"break",
		"calldata",
		"catch",
		"constant",
		"constructor",
		"continue",
		"contract",
		"delete",
		"do",
		"else",
		"emit",
		"enum",
		"error",
		"event",
		"external",
		"fallback",
		"for",
		"from",
		"function",
		"if",
		"immutable",
		"import",
		"indexed",
		"inherited",
		"interface",
		"internal",
		"is",
		"library",
		"mapping",
		"memory",
		"modifier",
		"new",
		"override",
		"payable",
		"pragma",
		"private",
		"public",
		"pure",
		"receive",
		"returns",
		"revert",
		"storage",
		"struct",
		"try",
		"type",
		"unchecked",
		"using",
		"view",
		"virtual",
		"while",
	]);
	const solidityTypes = new Set([
		"address",
		"bool",
		"byte",
		"bytes",
		"bytes1",
		"bytes2",
		"bytes3",
		"bytes4",
		"bytes8",
		"bytes16",
		"bytes20",
		"bytes32",
		"int",
		"int8",
		"int16",
		"int32",
		"int64",
		"int128",
		"int256",
		"string",
		"uint",
		"uint8",
		"uint16",
		"uint24",
		"uint32",
		"uint64",
		"uint128",
		"uint160",
		"uint256",
	]);
	const highlightSolidity = source => {
		let html = "";
		let index = 0;
		const tokenPattern =
			/(\/\/[^\n]*|\/\*[\s\S]*?\*\/|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\b0x[a-fA-F0-9]+\b|\b\d+(?:_\d+)*(?:\.\d+)?\b|\b[A-Za-z_][A-Za-z0-9_]*\b)/g;
		for (const match of source.matchAll(tokenPattern)) {
			const token = match[0];
			html += escapeHtml(source.slice(index, match.index));
			let className = "";
			if (token.startsWith("//") || token.startsWith("/*")) className = "tok-comment";
			else if (token.startsWith('"') || token.startsWith("'")) className = "tok-string";
			else if (/^(0x[a-fA-F0-9]+|\d)/.test(token)) className = "tok-number";
			else if (solidityKeywords.has(token)) className = "tok-keyword";
			else if (solidityTypes.has(token)) className = "tok-type";
			else if (/^[A-Z][A-Za-z0-9_]*$/.test(token)) className = "tok-symbol";
			html += className ? `<span class="${className}">${escapeHtml(token)}</span>` : escapeHtml(token);
			index = match.index + token.length;
		}
		html += escapeHtml(source.slice(index));
		return html;
	};

	const looksLikeSolidity = source => {
		const trimmed = source.trim();
		if (!trimmed) return false;
		const firstLine = trimmed.split("\n").find(Boolean) || "";
		if (
			/^(Scenario|Example|Bot sees|On withdrawal request|if user(?:-requested|\s+requested)|reserveDebt|activateDebt|settleDebt)\b/i.test(
				firstLine,
			)
		)
			return false;
		if (/[─→►]/.test(trimmed)) return false;

		const strongSignals = [
			/\b(function|struct|enum|event|error|modifier|mapping|contract|interface|library|pragma|import)\b/,
			/\b(external|public|internal|private|payable|view|pure|returns|calldata|memory|storage|immutable|override)\b/,
			/\b(uint(?:8|16|24|32|64|128|160|256)?|int(?:8|16|32|64|128|256)?|address|bytes(?:2|3|4|8|16|20|32)?|bool|string)\b/,
			/\b(abi\.encode|abi\.decode|keccak256|msg\.sender|msg\.value|onlyRole|require|revert|emit)\b/,
			/\b[A-Z][A-Za-z0-9_]*\s*\([^)]*(?:address|uint|bytes|bool|string)\b/,
		];
		if (strongSignals.some(pattern => pattern.test(trimmed))) return true;

		const codeLines = trimmed
			.split("\n")
			.map(line => line.trim())
			.filter(Boolean);
		if (!codeLines.length || codeLines.length > 12) return false;
		const assignmentLike = codeLines.filter(line => /^[A-Za-z_][\w.]*\s*=\s*[\w.()+\-*/\s]+$/.test(line)).length;
		return assignmentLike >= Math.max(1, Math.ceil(codeLines.length * 0.6));
	};

	document.querySelectorAll(".doc-article pre > code").forEach(code => {
		if (code.classList.contains("language-mermaid")) return;
		const hasLanguage = Array.from(code.classList).some(item => item.startsWith("language-"));
		const source = code.textContent || "";
		if (code.classList.contains("language-solidity") || (!hasLanguage && looksLikeSolidity(source))) {
			code.classList.add("language-solidity");
			code.dataset.detectedLanguage = "solidity";
			code.innerHTML = highlightSolidity(source);
		}
	});

	// Inline identifiers read like miniature code blocks: call name, args, punctuation.
	// A single pass so member access (a.b), indexing (a[b]) and operators get the
	// same treatment as calls -- not just the fn(args) shape.
	const escapeCode = value => value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
	const codeToken = /([A-Za-z_$][\w$]*)|(\d+(?:\.\d+)?)|([(),.[\]=<>;:]+)|([\s\S])/g;

	const tokenizeInlineCode = text => {
		let depth = 0;
		let html = "";
		let match;
		codeToken.lastIndex = 0;
		while ((match = codeToken.exec(text))) {
			const [raw, identifier, number, punctuation] = match;
			if (identifier) {
				// Only a following "(" proves this is a call; inside brackets it is an argument.
				const cls = text[codeToken.lastIndex] === "(" ? "tok-fn" : depth > 0 ? "tok-arg" : "";
				html += cls ? '<span class="' + cls + '">' + escapeCode(raw) + "</span>" : escapeCode(raw);
			} else if (number) {
				html += '<span class="tok-num">' + escapeCode(raw) + "</span>";
			} else if (punctuation) {
				for (const char of raw) {
					if (char === "(" || char === "[") depth += 1;
					else if (char === ")" || char === "]") depth = Math.max(0, depth - 1);
				}
				html += '<span class="tok-punct">' + escapeCode(raw) + "</span>";
			} else {
				html += escapeCode(raw);
			}
		}
		return html;
	};

	document.querySelectorAll(".doc-article :not(pre) > code, .reader-hero :not(pre) > code").forEach(node => {
		if (node.querySelector("span")) return;
		const text = node.textContent || "";
		if (!/[(),.[\]=<>]/.test(text)) return;
		node.innerHTML = tokenizeInlineCode(text);
	});

	document.querySelectorAll(".doc-article pre").forEach(pre => {
		if (pre.closest(".mermaid-frame")) return;
		if (pre.closest(".code-frame")) return;
		const code = pre.querySelector("code");
		const frame = document.createElement("div");
		frame.className = "code-frame";
		if (code && code.classList.contains("language-solidity")) frame.classList.add("code-frame-solidity");
		const toolbar = document.createElement("div");
		toolbar.className = "code-toolbar";
		const langMatch = code && /language-([a-z0-9+#-]+)/i.exec(code.className || "");
		const langLabel = document.createElement("span");
		langLabel.className = "code-lang";
		langLabel.textContent = langMatch ? langMatch[1] : "text";
		toolbar.append(langLabel);
		const actions = document.createElement("div");
		actions.className = "code-actions";
		const wrap = document.createElement("button");
		wrap.type = "button";
		setIconLabel(wrap, icons.wrap, "Wrap");
		wrap.addEventListener("click", () => {
			frame.classList.toggle("is-wrapped");
			setIconLabel(wrap, icons.wrap, frame.classList.contains("is-wrapped") ? "Unwrap" : "Wrap");
		});
		const copy = document.createElement("button");
		copy.type = "button";
		setIconLabel(copy, icons.copy, "Copy");
		copy.addEventListener("click", async () => {
			try {
				await navigator.clipboard.writeText(pre.textContent || "");
				setIconLabel(copy, icons.check, "Copied");
				window.setTimeout(() => {
					setIconLabel(copy, icons.copy, "Copy");
				}, 1200);
			} catch (_error) {
				const selection = window.getSelection();
				if (selection) {
					const range = document.createRange();
					range.selectNodeContents(pre);
					selection.removeAllRanges();
					selection.addRange(range);
				}
				setIconLabel(copy, icons.check, selection ? "Selected" : "Copy unavailable");
				window.setTimeout(() => {
					setIconLabel(copy, icons.copy, "Copy");
				}, 1200);
			}
		});
		actions.append(wrap, copy);
		toolbar.append(actions);
		pre.before(frame);
		frame.append(toolbar, pre);
	});

	/* Every wide table needs its own scroll container or it pushes the article
	   sideways on narrow screens. v0.8.6 pages author the wrapper; older pages do
	   not, so add it wherever it is missing. */
	const installTableScrollers = () => {
		document.querySelectorAll(".doc-article table").forEach(table => {
			if (table.parentElement?.classList.contains("table-wrap")) return;
			const wrapper = document.createElement("div");
			wrapper.className = "table-wrap";
			table.before(wrapper);
			wrapper.append(table);
		});
	};

	installTableScrollers();

	const installHeadingLinks = () => {
		document.querySelectorAll(".doc-article h2[id], .doc-article h3[id]").forEach(heading => {
			if (heading.querySelector(".heading-anchor")) return;
			const title = (heading.textContent || "section").trim();
			// The button is a child of the heading, so its label would otherwise fold
			// into the heading's accessible name and be announced twice. Naming the
			// heading from its own text keeps the two separate.
			const text = document.createElement("span");
			text.className = "heading-text";
			text.id = `${heading.id}-text`;
			while (heading.firstChild) text.append(heading.firstChild);
			heading.append(text);
			heading.setAttribute("aria-labelledby", text.id);

			const anchor = document.createElement("button");
			anchor.type = "button";
			anchor.className = "heading-anchor";
			anchor.textContent = "#";
			anchor.setAttribute("aria-label", `Copy link to ${title}`);
			const defaultLabel = anchor.getAttribute("aria-label");
			anchor.addEventListener("click", async () => {
				const url = `${window.location.href.split("#")[0]}#${heading.id}`;
				try {
					await navigator.clipboard.writeText(url);
					anchor.textContent = "✓";
					anchor.setAttribute("aria-label", "Section link copied");
					window.setTimeout(() => {
						anchor.textContent = "#";
						anchor.setAttribute("aria-label", defaultLabel);
					}, 1100);
				} catch (_error) {
					window.location.hash = heading.id;
				}
			});
			heading.append(anchor);
		});
	};

	installHeadingLinks();
})();
