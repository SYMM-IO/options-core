import type { HardhatRuntimeEnvironment } from "hardhat/types/hre"
import { requireArg } from "../utils/args.js"
import { deployInstantLayer } from "./deploy-lib.js"

export default async function ({ symmioaddress, admin }: { symmioaddress: string; admin: string }, hre: HardhatRuntimeEnvironment) {
	const { ethers } = await hre.network.getOrCreate()
	return deployInstantLayer(ethers, requireArg(symmioaddress, "symmioaddress"), requireArg(admin, "admin"))
}
