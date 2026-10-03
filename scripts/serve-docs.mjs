import { spawn } from "node:child_process";
import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const host = "127.0.0.1";
const portFlag = process.argv.indexOf("--port");
const port = portFlag === -1 ? 4173 : Number(process.argv[portFlag + 1]);
const shouldOpen = !process.argv.includes("--no-open");
const docsRoot = resolve(fileURLToPath(new URL("../docs/", import.meta.url)));
const mimeTypes = {
	".css": "text/css; charset=utf-8",
	".html": "text/html; charset=utf-8",
	".js": "text/javascript; charset=utf-8",
	".json": "application/json; charset=utf-8",
	".png": "image/png",
	".svg": "image/svg+xml",
};

if (!Number.isInteger(port) || port < 1 || port > 65535) {
	console.error("Usage: npm run docs -- --port 4173");
	process.exit(1);
}

const send = (response, status, message) => {
	response.writeHead(status, { "Content-Type": "text/plain; charset=utf-8" });
	response.end(message);
};

const server = createServer(async (request, response) => {
	let pathname;
	try {
		pathname = decodeURIComponent(new URL(request.url || "/", `http://${host}`).pathname);
	} catch (_error) {
		send(response, 400, "Bad request");
		return;
	}

	const relativePath = pathname === "/" ? "index.html" : pathname.replace(/^\/+/, "");
	let filePath = resolve(docsRoot, relativePath);
	if (filePath !== docsRoot && !filePath.startsWith(`${docsRoot}${sep}`)) {
		send(response, 403, "Forbidden");
		return;
	}

	try {
		const fileStat = await stat(filePath);
		if (fileStat.isDirectory()) filePath = resolve(filePath, "index.html");
		await stat(filePath);
	} catch (_error) {
		send(response, 404, "Not found");
		return;
	}

	response.writeHead(200, {
		"Cache-Control": "no-cache",
		"Content-Type": mimeTypes[extname(filePath).toLowerCase()] || "application/octet-stream",
	});
	createReadStream(filePath).pipe(response);
});

server.on("error", error => {
	if (error.code === "EADDRINUSE") console.error(`Port ${port} is already in use. Try: npm run docs -- --port ${port + 1}`);
	else console.error(error);
	process.exit(1);
});

server.listen(port, host, () => {
	const url = `http://${host}:${port}/`;
	console.log(`Documentation: ${url}`);
	console.log("Browser zoom now persists across every docs page on this origin.");
	if (shouldOpen && process.platform === "darwin") spawn("open", [url], { detached: true, stdio: "ignore" }).unref();
});

process.on("SIGINT", () => server.close(() => process.exit(0)));
