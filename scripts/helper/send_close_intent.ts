import { run } from "hardhat"

async function main() {
	const tradeId = "1"
	const quantity = "10"
	const price = "1000"
	const deadline = "1700000000"

	await run("send-close-intent", {
		tradeid: tradeId,
		quantity: quantity,
		price: price,
		deadline: deadline,
	})
}

main().catch(error => {
	console.error("Error:", error)
	process.exit(1)
})
