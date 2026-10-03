import { upgrades } from "@openzeppelin/hardhat-upgrades"
import type { HardhatRuntimeEnvironment } from "hardhat/types/hre"
import { requireArg } from "../utils/args.js"
import { deployMultiAccount } from "./deploy-lib.js"

export default async function (
	{ symmioaddress, admin, tradenftaddress }: { symmioaddress: string; admin: string; tradenftaddress: string },
	hre: HardhatRuntimeEnvironment,
) {
	const connection = await hre.network.getOrCreate()
	return deployMultiAccount(
		connection.ethers,
		await upgrades(hre, connection),
		requireArg(symmioaddress, "symmioaddress"),
		requireArg(admin, "admin"),
		requireArg(tradenftaddress, "tradenftaddress"),
	)
}
