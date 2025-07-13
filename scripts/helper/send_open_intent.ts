import { run } from "hardhat"

async function main() {
	const symbolId = "1"
	const price = "1000"
	const quantity = "10"
	const strikePrice = "900"
	const expiration = "1700000000"
	const mm = "500"
	const tradeSide = "0"
	const marginType = "0"
	const exerciseFeeRate = "500"
	const exerciseFeeCap = "10000"
	const deadline = "1700000000"
	const feeToken = "0x3333333333333333333333333333333333333333"
	const affiliate = "0x4444444444444444444444444444444444444444"
	const userdata = "0x1234abcd"
	const whitelist = "0x1111111111111111111111111111111111111111,0x2222222222222222222222222222222222222222"

	await run("send-open-intent", {
		symbolid: symbolId,
		price: price,
		quantity: quantity,
		strikeprice: strikePrice,
		expiration: expiration,
		mm: mm,
		tradeside: tradeSide,
		margintype: marginType,
		exercisefeerate: exerciseFeeRate,
		exercisefeecap: exerciseFeeCap,
		deadline: deadline,
		feetoken: feeToken,
		affiliate: affiliate,
		userdata: userdata,
		whitelist: whitelist,
	})
}

main().catch(error => {
	console.error("Error:", error)
	process.exit(1)
})
