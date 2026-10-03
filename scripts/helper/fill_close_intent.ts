import hre from "hardhat"

async function main() {
	const intentId = "1"
	const quantity = "10"
	const price = "1000"

	await hre.tasks.getTask("fill-close-intent").run({
		intentid: intentId,
		quantity: quantity,
		price: price,
	})
}

main().catch(error => {
	console.error("Error:", error)
	process.exit(1)
})
