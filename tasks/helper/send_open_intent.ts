import { task } from "hardhat/config"
import { loadAddresses } from "../../scripts/utils/file"
import { HardhatRuntimeEnvironment } from "hardhat/types"

task("send-open-intent", "Calls sendOpenIntent on the contract")
	.addParam("symbolid", "ID of the symbol") // <-- lowercase param name
	.addParam("price", "Price of the trade")
	.addParam("quantity", "Quantity of the trade")
	.addParam("strikeprice", "Strike price")
	.addParam("expiration", "Expiration timestamp")
	.addParam("mm", "Minimum margin")
	.addParam("tradeside", "Trade side (0=Buy, 1=Sell)")
	.addParam("margintype", "Margin type (0=Isolated, 1=Cross)")
	.addParam("exercisefeerate", "Basis points of exercise fee (e.g. 500 = 5%)")
	.addParam("exercisefeecap", "Cap of exercise fee")
	.addParam("deadline", "Deadline timestamp")
	.addParam("feetoken", "Address of the token used to pay fees")
	.addParam("affiliate", "Address of the affiliate")
	.addParam("userdata", "User-specific data in hex")
	.addOptionalParam("whitelist", "Comma-separated partyB addresses")
	.setAction(async (args, hre: HardhatRuntimeEnvironment) => {
		const { ethers } = hre
		const admin = (await ethers.getSigners())[0]
		const symmioAddress = loadAddresses().symmioAddress

		const partyAOpenFacet = (await ethers.getContractAt("PartyAOpenFacet", String(symmioAddress))).connect(admin)
		const {
			symbolid,
			price,
			quantity,
			strikeprice,
			expiration,
			mm,
			tradeside,
			margintype,
			exercisefeerate,
			exercisefeecap,
			deadline,
			feetoken,
			affiliate,
			userdata,
			whitelist,
		} = args

		const exerciseFee = {
			rate: BigInt(exercisefeerate),
			cap: BigInt(exercisefeecap),
		}

		const partyBsWhiteList = whitelist ? whitelist.split(",").map((addr: string) => addr.trim()) : []

		const tx = await partyAOpenFacet.sendOpenIntent(
			partyBsWhiteList,
			BigInt(symbolid),
			BigInt(price),
			BigInt(quantity),
			BigInt(strikeprice),
			BigInt(expiration),
			BigInt(mm),
			Number(tradeside),
			Number(margintype),
			exerciseFee,
			BigInt(deadline),
			feetoken,
			affiliate,
			userdata,
		)

		console.log("Transaction sent:", tx.hash)
		await tx.wait()
		console.log("Transaction confirmed.")
	})
