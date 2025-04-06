import { task } from "hardhat/config"
import { DEPLOYMENT_LOG_FILE } from "../../common/constants"
import { readData } from "../utils/fs"

task("verify:deployment", "Verifies the deployed contracts").setAction(async (_, { run }) => {
	const deployedAddresses = readData(DEPLOYMENT_LOG_FILE) as {
		name: string
		address: string
		constructorArguments: any
	}[]

	for (const { name, address, constructorArguments } of deployedAddresses) {
		try {
			console.info(`Verifying ${name} :: ${address}`)
			await run("verify:verify", {
				address,
				constructorArguments,
			})
		} catch (err) {
			console.error(err)
		}
	}
})
