import hre from "hardhat"

async function main() {
	const intentId = "1"

	await hre.tasks.getTask("lock-open-intent").run({
		intentid: intentId,
	})
}

main().catch(error => {
	console.error("Error:", error)
	process.exit(1)
})
