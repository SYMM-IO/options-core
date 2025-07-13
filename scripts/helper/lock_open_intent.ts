import { run } from "hardhat"

async function main() {
	const intentId = "1"

	await run("lock-open-intent", {
		intentid: intentId,
	})
}

main().catch(error => {
	console.error("Error:", error)
	process.exit(1)
})
