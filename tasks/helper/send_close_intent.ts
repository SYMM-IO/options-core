import type { HardhatRuntimeEnvironment } from "hardhat/types/hre"
import { loadAddresses } from "../../scripts/utils/file.js"
import { requireArg } from "../utils/args.js"

export default async function (
	{ tradeid, quantity, price, deadline }: { tradeid: string; quantity: string; price: string; deadline: string },
	hre: HardhatRuntimeEnvironment,
) {
	// Validate before connecting, so a missing option never reaches a live network or a keystore prompt.
	const tradeId = BigInt(requireArg(tradeid, "tradeid"))
	const closeQuantity = BigInt(requireArg(quantity, "quantity"))
	const closePrice = BigInt(requireArg(price, "price"))
	const closeDeadline = BigInt(requireArg(deadline, "deadline"))

	const { ethers } = await hre.network.getOrCreate()
	const [admin] = await ethers.getSigners()
	const partyACloseFacet = (await ethers.getContractAt("PartyACloseFacet", String(loadAddresses().symmioAddress))).connect(admin)
	const tx = await partyACloseFacet.sendCloseIntent(tradeId, closeQuantity, closePrice, closeDeadline)
	console.log("Transaction sent:", tx.hash)
	await tx.wait()
	console.log("Transaction confirmed.")
}
