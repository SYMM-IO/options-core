import type { HardhatRuntimeEnvironment } from "hardhat/types/hre"
import { loadAddresses } from "../../scripts/utils/file.js"

export default async function (
	{ tradeid, quantity, price, deadline }: { tradeid: string; quantity: string; price: string; deadline: string },
	hre: HardhatRuntimeEnvironment,
) {
	const { ethers } = await hre.network.getOrCreate()
	const [admin] = await ethers.getSigners()
	const partyACloseFacet = (await ethers.getContractAt("PartyACloseFacet", String(loadAddresses().symmioAddress))).connect(admin)
	const tx = await partyACloseFacet.sendCloseIntent(BigInt(tradeid), BigInt(quantity), BigInt(price), BigInt(deadline))
	console.log("Transaction sent:", tx.hash)
	await tx.wait()
	console.log("Transaction confirmed.")
}
