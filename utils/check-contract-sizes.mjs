#!/usr/bin/env node

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

export const EIP170_LIMIT = 24_576;
export const RELEASE_LIMIT = 23_552;
export const WARNING_LIMIT = 22_528;

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const artifactsRoot = path.join(projectRoot, "artifacts", "contracts");
const reportPath = path.join(projectRoot, "artifacts", "contract-sizes.json");

function collectArtifacts(directory, files = []) {
	for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
		const entryPath = path.join(directory, entry.name);
		if (entry.isDirectory()) collectArtifacts(entryPath, files);
		else if (entry.name.endsWith(".json") && !entry.name.endsWith(".dbg.json")) files.push(entryPath);
	}
	return files;
}

export function readContractSizes(root = artifactsRoot) {
	if (!fs.existsSync(root)) throw new Error(`Artifacts not found at ${root}. Run Hardhat compile first.`);
	return collectArtifacts(root)
		.map(artifactPath => JSON.parse(fs.readFileSync(artifactPath, "utf-8")))
		.filter(artifact => typeof artifact.deployedBytecode === "string" && artifact.deployedBytecode.length > 2)
		.map(artifact => {
			const bytes = (artifact.deployedBytecode.length - 2) / 2;
			return {
				contract: artifact.contractName,
				source: artifact.sourceName,
				bytes,
				headroom: EIP170_LIMIT - bytes,
				status:
					bytes > EIP170_LIMIT ? "eip170-failure" : bytes > RELEASE_LIMIT ? "release-failure" : bytes > WARNING_LIMIT ? "warning" : "ok",
			};
		})
		.sort((left, right) => right.bytes - left.bytes || left.source.localeCompare(right.source));
}

export function checkContractSizes(entries) {
	return {
		entries,
		warnings: entries.filter(entry => entry.status === "warning"),
		failures: entries.filter(entry => entry.status === "release-failure" || entry.status === "eip170-failure"),
	};
}

function printReport(result) {
	console.log("\nProduction contract size report");
	console.log(
		`Release budget: ${RELEASE_LIMIT.toLocaleString()} bytes (${(EIP170_LIMIT - RELEASE_LIMIT).toLocaleString()} bytes EIP-170 reserve)\n`,
	);
	console.log(`${"Bytes".padStart(7)}  ${"Headroom".padStart(8)}  Status    Contract`);
	for (const entry of result.entries) {
		if (entry.status === "ok" && entry.bytes <= WARNING_LIMIT) continue;
		console.log(
			`${String(entry.bytes).padStart(7)}  ${String(entry.headroom).padStart(8)}  ${entry.status.padEnd(8)}  ${entry.contract} (${entry.source})`,
		);
	}
	console.log(
		`\nChecked ${result.entries.length} deployable artifacts; ${result.warnings.length} warning(s), ${result.failures.length} failure(s).`,
	);
}

function main() {
	const result = checkContractSizes(readContractSizes());
	fs.writeFileSync(
		reportPath,
		JSON.stringify(
			{
				generatedAt: new Date().toISOString(),
				eip170Limit: EIP170_LIMIT,
				releaseLimit: RELEASE_LIMIT,
				warningLimit: WARNING_LIMIT,
				...result,
			},
			null,
			2,
		),
	);
	printReport(result);
	if (result.failures.length > 0) process.exitCode = 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
