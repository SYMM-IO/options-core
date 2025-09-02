import { task } from "hardhat/config"
import { loadAddresses } from "../../scripts/utils/file"
import { HardhatRuntimeEnvironment } from "hardhat/types"

task("send-close-intent", "Calls sendCloseIntent on the contract")
	.addParam("tradeid", "ID of the tradeId")
	.addParam("quantity", "Quantity of the quantity")
	.addParam("price", "Price of the price")
	.addParam("deadline", "deadline parameter")
	.setAction(async (args, hre: HardhatRuntimeEnvironment) => {
		const { ethers } = hre
		const admin = (await ethers.getSigners())[0]
		const symmioAddress = loadAddresses().symmioAddress

		const partyACloseFacet = (await ethers.getContractAt("PartyACloseFacet", String(symmioAddress))).connect(admin)
		const { tradeid, quantity, price, deadline } = args

		const tx = await partyACloseFacet.sendCloseIntent(BigInt(tradeid), BigInt(quantity), BigInt(price), BigInt(deadline))
		console.log("Transaction sent:", tx.hash)
		await tx.wait()
		console.log("Transaction confirmed.")
	})
