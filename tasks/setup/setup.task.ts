import { readFileSync } from "fs"
import { task } from "hardhat/config"
import { ControlFacet } from "../../types"
import { IConfig } from "../config/config.interface"

task("setup:deployment", "Setup Deployed Facets").setAction(async ({}, { ethers }) => {
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

	if (config.roles?.grant?.length) {
		for (const { address, role } of config.roles.grant) {
			if (address && role) {
				await controlFacet.connect(owner).grantRole(address, role)
				console.log(`Role granted successfully. User: ${address}, Role: ${role}`)
			}
		}
	}

	if (config.roles?.revoke?.length) {
		for (const { address, role } of config.roles.revoke) {
			if (address && role) {
				await controlFacet.connect(owner).revokeRole(address, role)
				console.log(`Role revoked successfully. User: ${address}, Role: ${role}`)
			}
		}
	}

	if (config.affiliates?.length) {
		for (const { address, status } of config.affiliates) {
			if (address !== undefined) {
				await controlFacet.connect(owner).setAffiliateStatus(address, status)
				console.log(`Affiliate registered successfully. Address: ${address}`)
			}
		}
	}

	if (config.collateral?.whiteList?.length) {
		for (const collateral of config.collateral.whiteList) {
			await controlFacet.connect(owner).whiteListCollateral(collateral)
			console.log(`Collateral whitelisted. Address: ${collateral}`)
		}
	}

	if (config.collateral?.removeFromWhitelist?.length) {
		for (const collateral of config.collateral.removeFromWhitelist) {
			await controlFacet.connect(owner).removeFromWhiteListCollateral(collateral)
			console.log(`Collateral removed from whitelist. Address: ${collateral}`)
		}
	}

	if (config.oracles?.length) {
		for (const { name, address } of config.oracles) {
			await controlFacet.connect(owner).addOracle(name, address)
			console.log(`Oracle registered successfully. Address: ${name} :: ${address}`)
		}
	}

	if (config.partyB?.length) {
		for (const { address, isActive, lossCoverage, oracleId, symbolType } of config.partyB) {
			if (address !== undefined) {
				await controlFacet.connect(owner).setPartyBConfig(address, {
					oracleId,
					symbolType,
					isActive,
					lossCoverage,
				})
				console.log(`partyB registered successfully. Address: ${address}`)
			}
		}
	}

	if (config.deactiveInstantActionModeCooldown !== undefined) {
		await controlFacet.connect(owner).setDeactiveInstantActionModeCooldown(config.deactiveInstantActionModeCooldown)
		console.log(`deactiveInstantActionModeCooldown set successfully. Cooldown: ${config.deactiveInstantActionModeCooldown}`)
	}

	if (config.maxConnectedPartyBs !== undefined) {
		await controlFacet.connect(owner).setDeactiveInstantActionModeCooldown(config.maxConnectedPartyBs)
		console.log(`maxConnectedPartyBs set successfully. Max_connection: ${config.maxConnectedPartyBs}`)
	}

	if (config.priceOracleAddress) {
		await controlFacet.connect(owner).setPriceOracleAddress(config.priceOracleAddress)
		console.log(`priceOracleAddress set successfully. Address: ${config.priceOracleAddress}`)
	}

	if (config.unbindingCooldown !== undefined) {
		await controlFacet.connect(owner).setUnbindingCooldown(config.unbindingCooldown)
		console.log(`unbindingCooldown set successfully. Cooldown: ${config.unbindingCooldown}`)
	}

	if (config.affiliateFeeCollector?.length) {
		for (const { affiliate, collector } of config.affiliateFeeCollector) {
			await controlFacet.connect(owner).setAffiliateFeeCollector(affiliate, collector)
			console.log(`affiliate Fee Collector set successfully. affiliate: ${affiliate} :: collector: ${collector}`)
		}
	}

	if (config.balanceLimitPerUser !== undefined) {
		await controlFacet.connect(owner).setBalanceLimitPerUser(config.balanceLimitPerUser)
		console.log(`balanceLimitPerUser set successfully. limit: ${config.balanceLimitPerUser}`)
	}

	if (config.defaultFeeCollector) {
		await controlFacet.connect(owner).setDefaultFeeCollector(config.defaultFeeCollector)
		console.log(`default Fee Collector set successfully. collector: ${config.defaultFeeCollector}`)
	}

	if (config.emergencyMode !== undefined) {
		if (config.emergencyMode) {
			await controlFacet.connect(owner).activeEmergencyMode()
			console.log(`active emergency mode successfully: ${config.emergencyMode}`)
		} else {
			await controlFacet.connect(owner).deactiveEmergencyMode()
			console.log(`deactive emergency mode successfully: ${config.emergencyMode}`)
		}
	}

	if (config.partyBEmergencyStatus?.length) {
		for (const { address, active } of config.partyBEmergencyStatus) {
			if (address !== undefined && active !== undefined) {
				if (active) {
					await controlFacet.connect(owner).activePartyBEmergencyStatus(address)
					console.log(`active partyB emergency mode successfully: ${address}`)
				} else {
					await controlFacet.connect(owner).deactivePartyBEmergencyStatus(address)
					console.log(`deactive partyB emergency mode successfully: ${address}`)
				}
			}
		}
	}

	if (config.forceCancelCloseIntentTimeout !== undefined) {
		await controlFacet.connect(owner).setForceCancelCloseIntentTimeout(config.forceCancelCloseIntentTimeout)
		console.log(`force cancel close intent timeout set successfully. timeout: ${config.forceCancelCloseIntentTimeout}`)
	}

	if (config.forceCancelOpenIntentTimeout !== undefined) {
		await controlFacet.connect(owner).setForceCancelOpenIntentTimeout(config.forceCancelOpenIntentTimeout)
		console.log(`force cancel open intent timeout set successfully. timeout: ${config.forceCancelOpenIntentTimeout}`)
	}

	if (config.instantActionsMode?.length) {
		for (const { address, active } of config.instantActionsMode) {
			await controlFacet.connect(owner).setInstantActionsMode(address, active)
			console.log(`instant Actions Mode set successfully. address: ${address} :: active: ${active}`)
		}
	}

	if (config.instantActionsModeDeactivateTime?.length) {
		for (const { address, time } of config.instantActionsModeDeactivateTime) {
			await controlFacet.connect(owner).setInstantActionsModeDeactivateTime(address, time)
			console.log(`instant Actions Mode Deactivate Time set successfully. address: ${address} :: time: ${time}`)
		}
	}

	if (config.liquidationSigValidTime !== undefined) {
		await controlFacet.connect(owner).setLiquidationSigValidTime(config.liquidationSigValidTime)
		console.log(`liquidation Sig Valid Time set successfully. time: ${config.liquidationSigValidTime}`)
	}

	if (config.maxCloseOrdersLength !== undefined) {
		await controlFacet.connect(owner).setMaxCloseOrdersLength(config.maxCloseOrdersLength)
		console.log(`max Close Orders Length set successfully. max: ${config.maxCloseOrdersLength}`)
	}

	if (config.partyADeallocateCooldown !== undefined) {
		await controlFacet.connect(owner).setPartyADeallocateCooldown(config.partyADeallocateCooldown)
		console.log(`partyA Deallocate Cooldown set successfully. coolDown: ${config.partyADeallocateCooldown}`)
	}

	if (config.partyBDeallocateCooldown !== undefined) {
		await controlFacet.connect(owner).setPartyBDeallocateCooldown(config.partyBDeallocateCooldown)
		console.log(`partyB Deallocate Cooldown set successfully. coolDown: ${config.partyBDeallocateCooldown}`)
	}

	if (config.partyBReleaseInterval?.length) {
		for (const { address, time } of config.partyBReleaseInterval) {
			await controlFacet.connect(owner).setPartyBReleaseInterval(address, time)
			console.log(`partyB Release Interval set successfully. address: ${address} :: time: ${time}`)
		}
	}

	if (config.settlementPriceSigValidTime !== undefined) {
		await controlFacet.connect(owner).setSettlementPriceSigValidTime(config.settlementPriceSigValidTime)
		console.log(`settlement Price Sig Valid Time set successfully. time: ${config.settlementPriceSigValidTime}`)
	}

	if (config.suspendAddress?.length) {
		for (const { address, suspend } of config.suspendAddress) {
			await controlFacet.connect(owner).suspendAddress(address, suspend)
			console.log(`suspend Address set successfully. address: ${address} :: suspend: ${suspend}`)
		}
	}

	if (config.suspendWithdrawal?.length) {
		for (const { withdrawId, suspend } of config.suspendWithdrawal) {
			await controlFacet.connect(owner).suspendWithdrawal(withdrawId, suspend)
			console.log(`suspend withdrawal set successfully. withdrawId: ${withdrawId} :: suspend: ${suspend}`)
		}
	}

	if (config.unbindingCooldown !== undefined) {
		await controlFacet.connect(owner).setUnbindingCooldown(config.unbindingCooldown)
		console.log(`unbinding cooldown set successfully. cooldown: ${config.unbindingCooldown}`)
	}

	// Pause config
	if (config.pause) {
		const p = config.pause

		if (p.global !== undefined) {
			await controlFacet.connect(owner)[p.global ? "pauseGlobal" : "unpauseGlobal"]()
			console.log(`${p.global ? "pauseGlobal" : "unpauseGlobal"} successfully.`)
		}
		if (p.deposit !== undefined) {
			await controlFacet.connect(owner)[p.deposit ? "pauseDeposit" : "unpauseDeposit"]()
			console.log(`${p.deposit ? "pauseDeposit" : "unpauseDeposit"} successfully.`)
		}
		if (p.liquidating !== undefined) {
			await controlFacet.connect(owner)[p.liquidating ? "pauseLiquidating" : "unpauseLiquidating"]()
			console.log(`${p.liquidating ? "pauseLiquidating" : "unpauseLiquidating"} successfully.`)
		}
		if (p.partyAActions !== undefined) {
			await controlFacet.connect(owner)[p.partyAActions ? "pausePartyAActions" : "unpausePartyAActions"]()
			console.log(`${p.partyAActions ? "pausePartyAActions" : "unpausePartyAActions"} successfully.`)
		}
		if (p.partyBActions !== undefined) {
			await controlFacet.connect(owner)[p.partyBActions ? "pausePartyBActions" : "unpausePartyBActions"]()
			console.log(`${p.partyBActions ? "pausePartyBActions" : "unpausePartyBActions"} successfully.`)
		}
		if (p.withdraw !== undefined) {
			await controlFacet.connect(owner)[p.withdraw ? "pauseWithdraw" : "unpauseWithdraw"]()
			console.log(`${p.withdraw ? "pauseWithdraw" : "unpauseWithdraw"} successfully.`)
		}
	}

	console.log("Initialization process completed successfully.")
})
