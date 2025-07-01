import { ethers } from "hardhat";
import fs from "fs";
import { loadAddresses } from "./utils/file";

async function main() {
	const configFile = "scripts/config/setup.json";
	const symmioAddress = loadAddresses().symmioAddress;

	if (!configFile || !symmioAddress) {
		console.error("Error: Configuration file or Symmio contract address is inaccessible.");
		process.exit(1);
	}

	const config = JSON.parse(fs.readFileSync(configFile, "utf8"));

	const controlFacetFactory = await ethers.getContractFactory("ControlFacet");
	const controlFacet = controlFacetFactory.attach(symmioAddress) as any;

	const owner = (await ethers.getSigners())[0];

	const viewFacetFactory = await ethers.getContractFactory("ViewFacet");
	const viewFacet = viewFacetFactory.attach(symmioAddress) as any;

	// Helper function to execute a transaction and wait for confirmation
	async function executeAndWait(txPromise: any, actionDescription: string) {
		try {
			console.log(`Initiating: ${actionDescription}...`);
			const tx = await txPromise;
			console.log(`Transaction submitted: ${tx.hash}`);
			const receipt = await tx.wait();
			if (receipt.status === 1) {
				console.log(`Success: ${actionDescription}. Gas used: ${receipt.gasUsed.toString()}`);
				return true;
			} else {
				console.error(`Failed: ${actionDescription}. Transaction reverted.`);
				return false;
			}
		} catch (error) {
			console.error(`Error during ${actionDescription}:`, error);
			return false;
		}
	}

	async function executeViewCall(viewCall: any, actionDescription: string) {
		try {
			console.log(`Calling: ${actionDescription}...`);
			const result = await viewCall;
			console.log(`Success: ${actionDescription}.`);
			return result;
		} catch (error) {
			console.error(`Error during ${actionDescription}:`, error);
			return null;
		}
	}


	if (config.admin) {
		await executeAndWait(controlFacet.connect(owner).setAdmin(config.admin), `Admin configuration. Assigned admin: ${config.admin}`);
	}

	if (config.grantRoles) {
		for (const { roleUser, role } of config.grantRoles) {
			if (roleUser && role) {
				await executeAndWait(controlFacet.connect(owner).grantRole(roleUser, role), `Role grant. User: ${roleUser}, Role: ${role}`);
			}
		}
	}

	if (config.revokeRoles) {
		for (const { roleUser, role } of config.revokeRoles) {
			if (roleUser && role) {
				await executeAndWait(controlFacet.connect(owner).revokeRole(roleUser, role), `Role revocation. User: ${roleUser}, Role: ${role}`);
			}
		}
	}

	if (config.collateral) {
		await executeAndWait(controlFacet.connect(owner).whiteListCollateral(config.collateral), `Collateral token setting. Address: ${config.collateral}`);
	}

	if (config.maxCloseOrdersLength) {
		await executeAndWait(
			controlFacet.connect(owner).setMaxCloseOrdersLength(config.maxCloseOrdersLength),
			`Max Close Orders Length. Amount: ${config.maxCloseOrdersLength}`,
		);
	}

	if (config.maxTradePerPartyA) {
		await executeAndWait(
			controlFacet.connect(owner).setMaxTradePerPartyA(config.maxTradePerPartyA),
			`Max Trade Per PartyA. Amount: ${config.maxTradePerPartyA}`,
		);
	}

	if (config.balanceLimitPerUser) {
		for (const { collateral, limit } of config.balanceLimitPerUser) {
			await executeAndWait(controlFacet.connect(owner).setBalanceLimitPerUser(collateral, limit), `Balance Limit Per User configuration. Collateral: ${collateral}, Limit: ${limit}`);
		}
	}

	if (config.timingParameters) {
		await executeAndWait(
			controlFacet.connect(owner).setTimingParameters(config.timingParameters.partyADeallocateCooldown, config.timingParameters.partyBDeallocateCooldown, config.timingParameters.forceCancelOpenTimeout, config.timingParameters.forceCancelCloseTimeout, config.timingParameters.settlementPriceSigValidTime, config.timingParameters.upnlSigValidTime, config.timingParameters.partyBExclusiveWindow, config.timingParameters.unbindingCooldown, config.timingParameters.deactiveInstantActionModeCooldown),
			`Timing Parameters. partyADeallocateCooldown: ${config.timingParameters.partyADeallocateCooldown}, partyBDeallocateCooldown: ${config.timingParameters.partyBDeallocateCooldown}, forceCancelOpenTimeout: ${config.timingParameters.forceCancelOpenTimeout}, forceCancelCloseTimeout: ${config.timingParameters.forceCancelCloseTimeout}, settlementPriceSigValidTime: ${config.timingParameters.settlementPriceSigValidTime}, upnlSigValidTime: ${config.timingParameters.upnlSigValidTime}, partyBExclusiveWindow: ${config.timingParameters.partyBExclusiveWindow}, unbindingCooldown: ${config.timingParameters.unbindingCooldown}, deactiveInstantActionModeCooldown: ${config.timingParameters.deactiveInstantActionModeCooldown}`,
		);
	}

	if (config.partyBReleaseInterval) {
		await executeAndWait(
			controlFacet.connect(owner).setPartyBReleaseInterval(config.partyBReleaseInterval.partyB, config.partyBReleaseInterval.interval),
			`partyB Release Interval. partyB: ${config.partyBReleaseInterval.partyB}, interval: ${config.partyBReleaseInterval.interval}`,
		);
	}

	if (config.defaultReleaseInterval) {
		await executeAndWait(
			controlFacet.connect(owner).setDefaultReleaseInterval(config.defaultReleaseInterval),
			`defaultReleaseInterval. Amount: ${config.defaultReleaseInterval}`,
		);
	}

	if (config.maxConnectedCounterParties) {
		await executeAndWait(
			controlFacet.connect(owner).setMaxConnectedCounterParties(config.maxConnectedCounterParties),
			`maxConnectedCounterParties. Amount: ${config.maxConnectedCounterParties}`,
		);
	}

	if (config.defaultFeeCollector) {
		await executeAndWait(
			controlFacet.connect(owner).setDefaultFeeCollector(config.defaultFeeCollector),
			`defaultFeeCollector. Amount: ${config.defaultFeeCollector}`,
		);
	}

	if (config.oracle) {
		await executeAndWait(
			controlFacet.connect(owner).addOracle(config.oracle.name, config.oracle.address),
			`Oracle. name: ${config.oracle.name}, address: ${config.oracle.address}`,
		);
	}

	if (config.priceOracleAddress) {
		await executeAndWait(
			controlFacet.connect(owner).setPriceOracleAddress(config.priceOracleAddress),
			`priceOracleAddress. Amount: ${config.priceOracleAddress}`,
		);
	}

	if (config.symbols) {
		let old_symbols = await executeViewCall(viewFacet.getSymbols(0, 1000), `Getting old symbols`);

		// Build a Set of existing symbol names for fast lookup
		const oldSymbolNames = new Set(old_symbols.map((symbol: { name: any }) => symbol.name));

		// Filter and clean symbols from config
		const symbolsForAdd = config.symbols
			.filter((symbol: { name: unknown }) => !oldSymbolNames.has(symbol.name)); // Keep only new symbols

		// Define batch size for pagination
		const BATCH_SIZE = 100;

		// Process symbols in batches if there are many
		if (symbolsForAdd.length > BATCH_SIZE) {
			console.log(`Adding ${symbolsForAdd.length} symbols in batches of ${BATCH_SIZE}...`);
			let symbols_added_success = true;

			// Split symbols into batches
			for (let i = 0; i < symbolsForAdd.length; i += BATCH_SIZE) {
				const batch = symbolsForAdd.slice(i, i + BATCH_SIZE);
				console.log(`Processing batch ${Math.floor(i / BATCH_SIZE) + 1}/${Math.ceil(symbolsForAdd.length / BATCH_SIZE)}`);
				console.log(batch[0]);
				// Add the current batch of symbols
				symbols_added_success = symbols_added_success && await executeAndWait(controlFacet.connect(owner).addSymbols(batch), `Symbol batch addition. Batch size: ${batch.length}`);
			}

			if (symbols_added_success) console.log(`All ${symbolsForAdd.length} symbols added successfully in ${Math.ceil(symbolsForAdd.length / BATCH_SIZE)} batches`);
			else console.log(`Failed to add all symbols`);
		} else {
			// Add all symbols at once if the list is not too long
			await executeAndWait(controlFacet.connect(owner).addSymbols(symbolsForAdd), `Symbol batch addition. Total symbols: ${symbolsForAdd.length}`);
		}
	}

	if (config.affiliates) {
		for (const { address, status, feesCollector, affiliateFees } of config.affiliates) {
			await executeAndWait(
				controlFacet.connect(owner).setAffiliateStatus(address, status),
				`affiliateStatus. affiliate: ${address}, status: ${status}`,
			);
			await executeAndWait(
				controlFacet.connect(owner).setAffiliateFeesCollector(address, feesCollector),
				`affiliateFeesCollector. affiliate: ${address}, collector: ${feesCollector}`,
			);
			await executeAndWait(
				controlFacet.connect(owner).batchSetAffiliateFees(address, affiliateFees.symbolIds, affiliateFees.fees),
				`batchAffiliateFees. affiliate: ${address}, symbolIds: ${affiliateFees.symbolIds}, fees: ${affiliateFees.fees}`,
			);
		}
	}

	if (config.partyB) {
		for (const { partyB, isActive, lossCoverage, oracleId, symbolType } of config.partyB) {
			const partyBConfig = {
				isActive: isActive,
				lossCoverage: lossCoverage,
				oracleId: oracleId,
				symbolType: symbolType,
			};
			await executeAndWait(
				controlFacet.connect(owner).setPartyBConfig(partyB, partyBConfig),
				`PartyB Config. partyB: ${partyB}, isActive: ${isActive}, lossCoverage: ${lossCoverage}, oracleId: ${oracleId}, symbolType: ${symbolType}`,
			);
		}
	}

	if (config.signatureVerifier) {
		await executeAndWait(
			controlFacet.connect(owner).setSignatureVerifier(config.signatureVerifier),
			`signatureVerifier. Amount: ${config.signatureVerifier}`,
		);
	}

	if (config.bridgeValidationState) {
		await executeAndWait(
			controlFacet.connect(owner).setBridgeValidationState(config.bridgeValidationState.bridgeAddress, config.bridgeValidationState.bridgeAddress),
			`bridgeValidationState Release Interval. bridgeAddress: ${config.bridgeValidationState.state}, state: ${config.bridgeValidationState.state}`,
		);
	}

	if (config.invalidBridgedAmountsPool) {
		await executeAndWait(
			controlFacet.connect(owner).setInvalidBridgedAmountsPool(config.invalidBridgedAmountsPool),
			`invalidBridgedAmountsPool. Amount: ${config.invalidBridgedAmountsPool}`,
		);
	}

	console.log("ControlFacet initialization process completed successfully.");
}

main().catch(error => {
	console.error("Initialization process failed with error:", error);
	process.exit(1);
});