import type { HardhatRuntimeEnvironment } from "hardhat/types/hre"
import { loadAddresses } from "../../scripts/utils/file.js"
import { requireArg } from "../utils/args.js"

export default async function ({ intentid, quantity, price }: { intentid: string; quantity: string; price: string }, hre: HardhatRuntimeEnvironment) {
	// Validate before connecting, so a missing option never reaches a live network or a keystore prompt.
	const intentId = BigInt(requireArg(intentid, "intentid"))
	const fillQuantity = BigInt(requireArg(quantity, "quantity"))
	const fillPrice = BigInt(requireArg(price, "price"))

	const { ethers } = await hre.network.getOrCreate()
	const [admin] = await ethers.getSigners()
	const partyBCloseFacet = (await ethers.getContractAt("PartyBCloseFacet", String(loadAddresses().symmioAddress))).connect(admin)
	const tx = await partyBCloseFacet.fillCloseIntent(intentId, fillQuantity, fillPrice)
	console.log("Transaction sent:", tx.hash)
	await tx.wait()
	console.log("Transaction confirmed.")
}
