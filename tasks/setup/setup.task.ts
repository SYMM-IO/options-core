import { readFileSync } from "fs"
import { task } from "hardhat/config"
import { ControlFacet } from "../../types"
import { IConfig } from "../config/config.interface"

task("setup:deployment", "Setup Deployed Facets").setAction(async ({}, { ethers, run }) => {
	console.info("Running setup:deployment")

	const configFile = "config/sample.config.json"
	const optionAddress = ""

	if (!configFile || !optionAddress) {
		console.error("Error: Configuration file or Options contract address is inaccessible.")
		process.exit(1)
	}

	const config: IConfig = JSON.parse(readFileSync(configFile, "utf8"))

	const controlFacetFactory = await ethers.getContractFactory("ControlFacet")
	const controlFacet = controlFacetFactory.attach(optionAddress) as ControlFacet

	const owner = (await ethers.getSigners())[0]

	if (config.admin) {
		await controlFacet.connect(owner).setAdmin(config.admin)
		console.log(`Admin configuration completed. Assigned admin: ${config.admin}`)
	}

	if (config.roles.grant.length !== 0) {
		for (const { address, role } of config.roles.grant) {
			if (address && role) {
				await controlFacet.connect(owner).grantRole(address, role)
				console.log(`Role granted successfully. User: ${address}, Role: ${role}`)
			}
		}
	}

	if (config.roles.revoke.length !== 0) {
		for (const { address, role } of config.roles.revoke) {
			if (address && role) {
				await controlFacet.connect(owner).revokeRole(address, role)
				console.log(`Role revoked successfully. User: ${address}, Role: ${role}`)
			}
		}
	}

	if (config.affiliates.length !== 0) {
		for (const { address, status } of config.affiliates) {
			if (address) {
				await controlFacet.connect(owner).setAffiliateStatus(address, status)
				console.log(`Affiliate registered successfully. Address: ${address}`)
			}
		}
	}

	if (config.collateral.whiteList.length !== 0) {
		for (const collateral of config.collateral.whiteList) {
			await controlFacet.connect(owner).whiteListCollateral(collateral)
			console.log(`Collateral whitelisted. Address: ${collateral}`)
		}
	}

	if (config.collateral.removeFromWhitelist.length !== 0) {
		for (const collateral of config.collateral.removeFromWhitelist) {
			await controlFacet.connect(owner).removeFromWhiteListCollateral(collateral)
			console.log(`Collateral removed from whitelist. Address: ${collateral}`)
		}
	}

	if (config.oracles.length !== 0) {
		for (const { name, address } of config.oracles) {
			await controlFacet.connect(owner).addOracle(name, address)
			console.log(`Oracle registered successfully. Address: ${name} :: ${address}`)
		}
	}

	if (config.partyB.length !== 0) {
		for (const { address, isActive, lossCoverage, oracleId, symbolType } of config.partyB) {
			await controlFacet.connect(owner).setPartyBConfig(address, {
				oracleId,
				symbolType,
				isActive,
				lossCoverage,
			})
			console.log(`partyB registered successfully. Address: ${address}`)
		}
	}

	if (config.deactiveInstantActionModeCooldown) {
		await controlFacet.connect(owner).setDeactiveInstantActionModeCooldown(config.deactiveInstantActionModeCooldown)
		console.log(`deactiveInstantActionModeCooldown set successfully. Cooldown: ${config.deactiveInstantActionModeCooldown}`)
	}

	if (config.maxConnectedPartyBs) {
		await controlFacet.connect(owner).setDeactiveInstantActionModeCooldown(config.maxConnectedPartyBs)
		console.log(`maxConnectedPartyBs set successfully. Max_connection: ${config.maxConnectedPartyBs}`)
	}

	if (config.priceOracleAddress) {
		await controlFacet.connect(owner).setPriceOracleAddress(config.priceOracleAddress)
		console.log(`priceOracleAddress set successfully. Address: ${config.priceOracleAddress}`)
	}

	if (config.unbindingCooldown) {
		await controlFacet.connect(owner).setUnbindingCooldown(config.unbindingCooldown)
		console.log(`unbindingCooldown set successfully. Cooldown: ${config.unbindingCooldown}`)
	}

	if (config.pause.global) {
		if (config.pause.global !== undefined && config.pause.global) {
			await controlFacet.connect(owner).pauseGlobal()
			console.log(`pauseGlobal successfully. pause: ${config.pause.global}`)
		}

		if (config.pause.global !== undefined && !config.pause.global) {
			await controlFacet.connect(owner).unpauseGlobal()
			console.log(`unpauseGlobal successfully. pause: ${config.pause.global}`)
		}
	}

	console.log("Initialization process completed successfully.")
})
