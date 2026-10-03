import { verifyContract } from "@nomicfoundation/hardhat-verify/verify"
import type { HardhatRuntimeEnvironment } from "hardhat/types/hre"
import { DEPLOYMENT_LOG_FILE } from "../../common/constants.js"
import { readData } from "../utils/fs.js"

export default async function (_: Record<string, unknown>, hre: HardhatRuntimeEnvironment) {
	const deployedAddresses = readData(DEPLOYMENT_LOG_FILE) as {
		name: string
		address: string
		constructorArguments: unknown[]
	}[]
	for (const { name, address, constructorArguments } of deployedAddresses) {
		try {
			console.info(`Verifying ${name} :: ${address}`)
			await verifyContract({ address, constructorArgs: constructorArguments }, hre)
		} catch (err) {
			console.error(err)
		}
	}
}
