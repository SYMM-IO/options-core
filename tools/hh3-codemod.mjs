// One-off Hardhat 2 → 3 rewrite. Deleted at the end of Task 7.
// Usage: node tools/hh3-codemod.mjs [--extensions-only] <dir-or-file>...
// Requires `npx hardhat compile` first: it resolves imports against the generated types/ and artifacts/.
import fs from "node:fs"
import path from "node:path"

const argv = process.argv.slice(2)
const extensionsOnly = argv.includes("--extensions-only")
const targets = argv.filter(a => !a.startsWith("--"))
const ROOT = process.cwd()
const CONNECTION = path.join(ROOT, "tests", "connection.ts")
const flags = []
const changed = []

function walk(p) {
	if (fs.statSync(p).isFile()) return p.endsWith(".ts") ? [p] : []
	return fs.readdirSync(p).flatMap(name => walk(path.join(p, name)))
}

function relativeTo(fromFile, toTsFile) {
	const r = path.relative(path.dirname(fromFile), toTsFile).split(path.sep).join("/").replace(/\.ts$/, ".js")
	return r.startsWith(".") ? r : "./" + r
}

// Relative specifiers get an explicit .js; TypeChain's types/contracts/<x> flattens to types/<x>.
function fixSpecifier(file, rel, spec) {
	if (!spec.startsWith(".")) return spec
	const abs = path.resolve(path.dirname(file), spec)
	if (spec.endsWith(".json")) {
		if (!fs.existsSync(abs)) flags.push(`${rel}: JSON import "${spec}" does not exist`)
		return spec
	}
	if (spec.endsWith(".js")) return spec
	const flat = spec.replace(/\/types\/contracts\//, "/types/")
	const flatAbs = path.resolve(path.dirname(file), flat)
	if (fs.existsSync(flatAbs + ".ts")) return flat + ".js"
	if (fs.existsSync(path.join(flatAbs, "index.ts"))) return flat + "/index.js"
	flags.push(`${rel}: cannot resolve "${spec}"`)
	return spec
}

function rewriteSpecifiers(file, rel, src) {
	return src.replace(/(\bfrom\s+|^import\s+)"(\.[^"]*)"/gm, (_, kw, spec) => `${kw}"${fixSpecifier(file, rel, spec)}"`)
}

function rewriteTest(rel, src) {
	const need = new Set()

	const hh = src.match(/^import \{([^}]*)\} from "hardhat"[ \t]*\n/m)
	if (hh) {
		for (const name of hh[1].split(",").map(s => s.trim()).filter(Boolean)) {
			if (name === "ethers") need.add("ethers")
			else if (name === "upgrades") need.add("upgradesApi as upgrades")
			else flags.push(`${rel}: unsupported import "${name}" from "hardhat"`)
		}
		src = src.replace(hh[0], "")
	}
	if (/from "hardhat"/.test(src)) flags.push(`${rel}: another import from "hardhat" remains`)

	const nh = src.match(/^import \{([^}]*)\} from "@nomicfoundation\/hardhat-network-helpers"[ \t]*\n/m)
	if (nh) {
		const names = nh[1].split(",").map(s => s.trim()).filter(Boolean)
		src = src.replace(nh[0], "")
		for (const name of names) {
			if (name === "loadFixture") src = src.replace(/(?<![.\w])loadFixture\(/g, "networkHelpers.loadFixture(")
			else if (name === "time") src = src.replace(/(?<![.\w])time\./g, "networkHelpers.time.")
			else if (name === "setBalance") src = src.replace(/(?<![.\w])setBalance\(/g, "networkHelpers.setBalance(")
			else flags.push(`${rel}: unsupported network-helpers import "${name}"`)
		}
		if (src.includes("networkHelpers.")) need.add("networkHelpers")
	}

	// Property-style revert assertions become .revert(ethers). (?![A-Za-z]) keeps revertedWith* untouched.
	const before = (src.match(/\.reverted(?![A-Za-z])/g) || []).length
	src = src
		.replace(/\.not\.to\.be\.reverted(?![A-Za-z])/g, ".not.to.revert(ethers)")
		.replace(/\.to\.not\.be\.reverted(?![A-Za-z])/g, ".to.not.revert(ethers)")
		.replace(/\.to\.be\.reverted(?![A-Za-z])/g, ".to.revert(ethers)")
		.replace(/\.not\.reverted(?![A-Za-z])/g, ".not.to.revert(ethers)")
	const left = (src.match(/\.reverted(?![A-Za-z])/g) || []).length
	if (left) flags.push(`${rel}: ${left} ".reverted" left unconverted`)
	if (before > left) need.add("ethers")

	src = src.replace(
		/^import \{ SignerWithAddress \} from "@nomicfoundation\/hardhat-ethers\/signers"$/m,
		'import type { HardhatEthersSigner as SignerWithAddress } from "@nomicfoundation/hardhat-ethers/types"',
	)
	if (src.includes("hardhat-ethers/signers")) flags.push(`${rel}: other hardhat-ethers/signers import`)
	src = src.replace(/^import "@nomicfoundation\/hardhat-ethers"[ \t]*\n/m, "")

	src = src.replace(/^import \* as (\w+) from "([^"]+\.json)"$/gm, 'import $1 from "$2" with { type: "json" }')
	if (/^import \{[^}]*\} from "[^"]+\.json"/m.test(src)) flags.push(`${rel}: named JSON import needs a manual rewrite`)

	return { src, need }
}

for (const file of targets.flatMap(t => walk(path.resolve(t)))) {
	if (file === CONNECTION) continue
	const rel = path.relative(ROOT, file)
	const original = fs.readFileSync(file, "utf8")
	let src = original
	if (!extensionsOnly) {
		const result = rewriteTest(rel, src)
		src = result.src
		if (result.need.size) {
			if (/from "[^"]*connection\.js"/.test(src)) flags.push(`${rel}: already imports connection.js; merge by hand`)
			else src = `import { ${[...result.need].sort().join(", ")} } from "${relativeTo(file, CONNECTION)}"\n` + src
		}
	}
	src = rewriteSpecifiers(file, rel, src)
	if (src !== original) {
		fs.writeFileSync(file, src)
		changed.push(rel)
	}
}

console.log(`changed ${changed.length} file(s)`)
for (const f of changed) console.log(`  ${f}`)
if (flags.length) {
	console.log(`\n${flags.length} item(s) need manual attention:`)
	for (const f of flags) console.log(`  ${f}`)
	process.exitCode = 1
}
