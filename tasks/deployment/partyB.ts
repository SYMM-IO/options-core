import { upgrades } from "@openzeppelin/hardhat-upgrades"
import type { HardhatRuntimeEnvironment } from "hardhat/types/hre"
import { requireArg } from "../utils/args.js"
import { deploySymmioPartyB } from "./deploy-lib.js"

export default async function ({ symmioaddress, admin }: { symmioaddress: string; admin: string }, hre: HardhatRuntimeEnvironment) {
	const connection = await hre.network.getOrCreate()
	return deploySymmioPartyB(connection.ethers, await upgrades(hre, connection), requireArg(symmioaddress, "symmioaddress"), requireArg(admin, "admin"))
}
