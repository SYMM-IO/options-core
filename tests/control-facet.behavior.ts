import { ethers, networkHelpers } from "./connection.js"
import { expect } from "chai"
import { ZeroAddress, toUtf8Bytes } from "ethers"
import { e } from "../utils/e.js"
import { initializeTestFixture } from "./initialize-test.fixture.js"
import { OptionType } from "./option-enums.js"
import { PartyA } from "./models/partyA.model.js"
import { RunContext } from "./run-context.js"

const role = (name: string) => ethers.keccak256(toUtf8Bytes(name))

export function shouldBehaveLikeControlFacet(): void {
	let context: RunContext

	beforeEach(async function () {
		context = await networkHelpers.loadFixture(initializeTestFixture)
	})

	it("gates role administration to DEFAULT_ADMIN_ROLE and emits role events", async function () {
		const setterRole = role("SETTER_ROLE")
		const newSetter = context.signers.others[0]
		const nonAdmin = context.signers.partyA1

		await expect(context.controlFacet.connect(nonAdmin).grantRole(newSetter.address, setterRole))
			.to.be.revertedWithCustomError(context.controlFacet, "MissingRole")
			.withArgs(nonAdmin.address, role("DEFAULT_ADMIN_ROLE"))

		await expect(context.controlFacet.grantRole(newSetter.address, setterRole))
			.to.emit(context.controlFacet, "RoleGranted")
			.withArgs(setterRole, newSetter.address)
		expect(await context.viewFacet.hasRole(newSetter.address, setterRole)).to.equal(true)

		await expect(context.controlFacet.revokeRole(newSetter.address, setterRole))
			.to.emit(context.controlFacet, "RoleRevoked")
			.withArgs(setterRole, newSetter.address)
		expect(await context.viewFacet.hasRole(newSetter.address, setterRole)).to.equal(false)
	})

	it("requires SETTER_ROLE for system setters and persists emitted configuration changes", async function () {
		const nonSetter = context.signers.partyA1
		const collateral = await context.collateral.getAddress()

		await expect(context.controlFacet.connect(nonSetter).setMaxTradePerPartyA(42))
			.to.be.revertedWithCustomError(context.controlFacet, "MissingRole")
			.withArgs(nonSetter.address, role("SETTER_ROLE"))

		await expect(context.controlFacet.setMaxTradePerPartyA(42)).to.emit(context.controlFacet, "MaxTradePerPartyAUpdated").withArgs(42)
		await expect(context.controlFacet.setBalanceLimitPerUser(collateral, e(777)))
			.to.emit(context.controlFacet, "BalanceLimitPerUserUpdated")
			.withArgs(collateral, e(777))

		await expect(context.controlFacet.setTimingParameters(11, 12, 13, 14, 15, 16, 17, 18, 19))
			.to.emit(context.controlFacet, "PartyADeallocateCooldownUpdated")
			.withArgs(11)
			.and.to.emit(context.controlFacet, "DeactiveInstantActionModeCooldownUpdated")
			.withArgs(19)

		expect(await context.viewFacet.getMaxTradePerPartyA()).to.equal(42)
		expect(await context.viewFacet.getBalanceLimitPerUser(collateral)).to.equal(e(777))
		expect(await context.viewFacet.getPartyADeallocateCooldown()).to.equal(11)
		expect(await context.viewFacet.getPartyBDeallocateCooldown()).to.equal(12)
		expect(await context.viewFacet.getForceCancelOpenIntentTimeout()).to.equal(13)
		expect(await context.viewFacet.getForceCancelCloseIntentTimeout()).to.equal(14)
		expect(await context.viewFacet.getSettlementPriceSigValidTime()).to.equal(15)
		expect(await context.viewFacet.getUpnlSigValidTime()).to.equal(16)
		expect(await context.viewFacet.getPartyBExclusiveWindow()).to.equal(17)
		expect(await context.viewFacet.getUnbindingCooldown()).to.equal(18)
		expect(await context.viewFacet.getDeactiveInstantActionModeCooldown()).to.equal(19)
	})

	it("separates pause and unpause roles while updating pause state flags", async function () {
		const pauser = context.signers.partyA1
		const unpauser = context.signers.partyA2

		await context.controlFacet.grantRole(pauser.address, role("PAUSER_ROLE"))
		await context.controlFacet.grantRole(unpauser.address, role("UNPAUSER_ROLE"))

		await expect(context.controlFacet.connect(unpauser).pauseExternalTransfer())
			.to.be.revertedWithCustomError(context.controlFacet, "MissingRole")
			.withArgs(unpauser.address, role("PAUSER_ROLE"))
		await expect(context.controlFacet.connect(pauser).pauseGlobal()).to.emit(context.controlFacet, "GlobalPaused")
		await expect(context.controlFacet.connect(pauser).pauseExternalTransfer()).to.emit(context.controlFacet, "ExternalTransferPaused")
		await expect(context.controlFacet.connect(pauser).pauseInstantLayer()).to.emit(context.controlFacet, "InstantLayerPaused")

		expect(await context.viewFacet.isGlobalPaused()).to.equal(true)
		expect(await context.viewFacet.isExternalTransferPaused()).to.equal(true)
		expect(await context.viewFacet.isInstantLayerPaused()).to.equal(true)

		await expect(context.controlFacet.connect(pauser).unpauseExternalTransfer())
			.to.be.revertedWithCustomError(context.controlFacet, "MissingRole")
			.withArgs(pauser.address, role("UNPAUSER_ROLE"))
		await expect(context.controlFacet.connect(unpauser).unpauseGlobal()).to.emit(context.controlFacet, "GlobalUnpaused")
		await expect(context.controlFacet.connect(unpauser).unpauseExternalTransfer()).to.emit(context.controlFacet, "ExternalTransferUnpaused")
		await expect(context.controlFacet.connect(unpauser).unpauseInstantLayer()).to.emit(context.controlFacet, "InstantLayerUnpaused")

		expect(await context.viewFacet.isGlobalPaused()).to.equal(false)
		expect(await context.viewFacet.isExternalTransferPaused()).to.equal(false)
		expect(await context.viewFacet.isInstantLayerPaused()).to.equal(false)
	})

	it("manages oracle and symbol lifecycle with validation and event coverage", async function () {
		const collateral = await context.collateral.getAddress()
		const oracle2 = context.signers.oracle1.address
		const oracle3 = context.signers.others[1].address
		const nextOracleId = (await context.viewFacet.getLastOracleId()) + 1n
		const nextSymbolId = (await context.viewFacet.getLastSymbolId()) + 1n
		const platformFee = { openFee: e(0.03), closeFee: e(0.04) }
		const updatedFee = { openFee: e(0.05), closeFee: e(0.06) }

		await expect(context.controlFacet.connect(context.signers.partyA1).addOracle("secondary", oracle2))
			.to.be.revertedWithCustomError(context.controlFacet, "MissingRole")
			.withArgs(context.signers.partyA1.address, role("ORACLE_MANAGER_ROLE"))
		await expect(context.controlFacet.addOracle("", oracle2)).to.be.revertedWithCustomError(context.controlFacet, "EmptyField").withArgs("name")
		await expect(context.controlFacet.addOracle("secondary", ZeroAddress))
			.to.be.revertedWithCustomError(context.controlFacet, "ZeroAddress")
			.withArgs("contractAddress")

		await expect(context.controlFacet.addOracle("secondary", oracle2))
			.to.emit(context.controlFacet, "OracleAdded")
			.withArgs(nextOracleId, "secondary", oracle2)
		await expect(context.controlFacet.updateOracle(nextOracleId, oracle3))
			.to.emit(context.controlFacet, "OracleUpdated")
			.withArgs(nextOracleId, oracle2, oracle3)

		const oracle = await context.viewFacet.getOracle(nextOracleId)
		expect(oracle.name).to.equal("secondary")
		expect(oracle.contractAddress).to.equal(oracle3)

		await expect(context.controlFacet.addSymbol("ETH_CALL", OptionType.CALL, nextOracleId + 1n, collateral, platformFee, 7))
			.to.be.revertedWithCustomError(context.controlFacet, "OracleNotFound")
			.withArgs(nextOracleId + 1n)
		await expect(context.controlFacet.addSymbol("ETH_CALL", OptionType.CALL, nextOracleId, collateral, platformFee, 7))
			.to.emit(context.controlFacet, "SymbolAdded")
			.withArgs(nextSymbolId, "ETH_CALL", OptionType.CALL, nextOracleId, collateral, [platformFee.openFee, platformFee.closeFee], 7)

		await expect(context.controlFacet.setSymbolsNames([nextSymbolId], ["ETH_CALL_WEEKLY"]))
			.to.emit(context.controlFacet, "SymbolNameUpdated")
			.withArgs(nextSymbolId, "ETH_CALL_WEEKLY")
		await expect(context.controlFacet.setSymbolsTypes([nextSymbolId], [8]))
			.to.emit(context.controlFacet, "SymbolTypeUpdated")
			.withArgs(nextSymbolId, 8)
		await expect(context.controlFacet.setSymbolsValidationState([nextSymbolId], [false]))
			.to.emit(context.controlFacet, "SymbolStateUpdated")
			.withArgs(nextSymbolId, false)
		await expect(context.controlFacet.setSymbolsPlatformFees([nextSymbolId], [updatedFee]))
			.to.emit(context.controlFacet, "SymbolPlatformFeeUpdated")
			.withArgs(nextSymbolId, [platformFee.openFee, platformFee.closeFee], [updatedFee.openFee, updatedFee.closeFee])

		const symbol = await context.viewFacet.getSymbol(nextSymbolId)
		expect(symbol.name).to.equal("ETH_CALL_WEEKLY")
		expect(symbol.symbolType).to.equal(8)
		expect(symbol.isValid).to.equal(false)
		expect(symbol.platformFee.openFee).to.equal(updatedFee.openFee)
		expect(symbol.platformFee.closeFee).to.equal(updatedFee.closeFee)
	})

	it("validates fee collectors and affiliate fee manager permissions", async function () {
		const affiliate = context.signers.affiliate1
		const collector = context.signers.others[0]
		const setterOnly = context.signers.partyA1
		const fee = { openFee: e(0.11), closeFee: e(0.12) }

		await expect(context.controlFacet.setDefaultFeeCollector(ZeroAddress))
			.to.be.revertedWithCustomError(context.controlFacet, "ZeroAddress")
			.withArgs("collector")
		await expect(context.controlFacet.setDefaultFeeCollector(collector.address))
			.to.emit(context.controlFacet, "DefaultFeeCollectorUpdated")
			.withArgs(collector.address)
		expect(await context.viewFacet.getDefaultFeeCollector()).to.equal(collector.address)

		await expect(context.controlFacet.connect(context.signers.partyA1).setAffiliateStatus(affiliate.address, false))
			.to.be.revertedWithCustomError(context.controlFacet, "MissingRole")
			.withArgs(context.signers.partyA1.address, role("AFFILIATE_MANAGER_ROLE"))
		await expect(context.controlFacet.setAffiliateStatus(affiliate.address, false))
			.to.emit(context.controlFacet, "AffiliateStatusUpdated")
			.withArgs(affiliate.address, false)
		await expect(context.controlFacet.setAffiliateFeesCollector(affiliate.address, collector.address))
			.to.emit(context.controlFacet, "AffiliateFeesCollectorUpdated")
			.withArgs(affiliate.address, collector.address)

		await context.controlFacet.grantRole(setterOnly.address, role("SETTER_ROLE"))
		await expect(context.controlFacet.connect(setterOnly).setAffiliateFees(affiliate.address, [1], [fee]))
			.to.be.revertedWithCustomError(context.controlFacet, "UnauthorizedSender")
			.withArgs(setterOnly.address, affiliate.address)
		await expect(context.controlFacet.setAffiliateFees(affiliate.address, [1, 2], [fee])).to.be.revertedWithCustomError(
			context.controlFacet,
			"MismatchedLengths",
		)
		await expect(context.controlFacet.setAffiliateFees(affiliate.address, [1], [fee]))
			.to.emit(context.controlFacet, "AffiliateFeesUpdated")
			.withArgs(affiliate.address, 1, [fee.openFee, fee.closeFee])

		const storedFee = await context.viewFacet.getAffiliateFee(affiliate.address, 1)
		expect(await context.viewFacet.isAffiliateActive(affiliate.address)).to.equal(false)
		expect(await context.viewFacet.getAffiliateFeeCollector(affiliate.address)).to.equal(collector.address)
		expect(storedFee.openFee).to.equal(fee.openFee)
		expect(storedFee.closeFee).to.equal(fee.closeFee)
	})

	it("validates PartyB configuration, manual sync, and supported symbol type batches", async function () {
		const partyB = context.signers.others[0]
		const manager = context.signers.partyA1
		const activeConfig = { isActive: true, lossCoverage: e(2), oracleId: 1 }

		await expect(context.controlFacet.connect(manager).setPartyBConfig(partyB.address, activeConfig))
			.to.be.revertedWithCustomError(context.controlFacet, "MissingRole")
			.withArgs(manager.address, role("PARTY_B_MANAGER_ROLE"))
		await expect(context.controlFacet.setPartyBConfig(ZeroAddress, activeConfig))
			.to.be.revertedWithCustomError(context.controlFacet, "ZeroAddress")
			.withArgs("partyB")
		await expect(context.controlFacet.setPartyBConfig(partyB.address, { isActive: true, lossCoverage: 0, oracleId: 999 }))
			.to.be.revertedWithCustomError(context.controlFacet, "OracleNotFound")
			.withArgs(999)

		await expect(context.controlFacet.setPartyBConfig(partyB.address, activeConfig)).to.emit(context.controlFacet, "PartyBConfigUpdated")
		const storedConfig = await context.viewFacet.getPartyBConfig(partyB.address)
		expect(storedConfig.isActive).to.equal(true)
		expect(storedConfig.lossCoverage).to.equal(activeConfig.lossCoverage)
		expect(storedConfig.oracleId).to.equal(activeConfig.oracleId)
		expect(await context.viewFacet.isManualSync(partyB.address)).to.equal(true)

		await expect(context.controlFacet.setPartyBSupportedSymbolTypes(partyB.address, [1, 2], [true]))
			.to.be.revertedWithCustomError(context.controlFacet, "MismatchedLengths")
		await expect(context.controlFacet.setPartyBSupportedSymbolTypes(partyB.address, [1, 2], [true, false]))
			.to.emit(context.controlFacet, "PartyBSupportedSymbolTypesUpdated")
			.withArgs(partyB.address, 1, true)
			.and.to.emit(context.controlFacet, "PartyBSupportedSymbolTypesUpdated")
			.withArgs(partyB.address, 2, false)

		expect(await context.viewFacet.isSymbolTypesSupportedByPartyB(partyB.address, 1)).to.equal(true)
		expect(await context.viewFacet.isSymbolTypesSupportedByPartyB(partyB.address, 2)).to.equal(false)
	})

	it("validates suspension batch lengths, zero users, roles, and emitted suspension state", async function () {
		const suspender = context.signers.partyA1
		const user1 = context.signers.partyA2
		const user2 = context.signers.others[0]

		await expect(context.controlFacet.connect(suspender).suspendAddresses([user1.address], [true]))
			.to.be.revertedWithCustomError(context.controlFacet, "MissingRole")
			.withArgs(suspender.address, role("SUSPENDER_ROLE"))
		await expect(context.controlFacet.suspendAddresses([user1.address, user2.address], [true]))
			.to.be.revertedWithCustomError(context.controlFacet, "MismatchedLengths")
		await expect(context.controlFacet.suspendAddresses([user1.address, ZeroAddress], [true, false]))
			.to.be.revertedWithCustomError(context.controlFacet, "ZeroAddress")
			.withArgs("user")

		await expect(context.controlFacet.suspendAddresses([user1.address, user2.address], [true, false]))
			.to.emit(context.controlFacet, "AddressSuspended")
			.withArgs(user1.address, true)
			.and.to.emit(context.controlFacet, "AddressSuspended")
			.withArgs(user2.address, false)
		await expect(context.controlFacet.suspendWithdrawal(44, true))
			.to.emit(context.controlFacet, "WithdrawalSuspended")
			.withArgs(44, true)

		expect(await context.viewFacet.isAddressSuspended(user1.address)).to.equal(true)
		expect(await context.viewFacet.isAddressSuspended(user2.address)).to.equal(false)
		expect(await context.viewFacet.isWithdrawalSuspended(44)).to.equal(true)
	})

	it("gates external transfer target validation and changes downstream transfer validation", async function () {
		const partyA = new PartyA(context, context.signers.partyA1)
		const target = await context.hookHandler.getAddress()
		const collateral = await context.collateral.getAddress()

		await partyA.setBalances(context.collateral, 1000, 500)

		await expect(context.controlFacet.connect(context.signers.partyA1).setExternalTransferTargetValidationStatus(target, collateral, true))
			.to.be.revertedWithCustomError(context.controlFacet, "MissingRole")
			.withArgs(context.signers.partyA1.address, role("EXTERNAL_TRANSFER_TARGET_MANAGER_ROLE"))
		await context.controlFacet.grantRole(context.signers.admin.address, role("EXTERNAL_TRANSFER_TARGET_MANAGER_ROLE"))
		await expect(context.controlFacet.setExternalTransferTargetValidationStatus(ZeroAddress, collateral, true))
			.to.be.revertedWithCustomError(context.controlFacet, "ZeroAddress")
			.withArgs("target")
		await expect(context.controlFacet.setExternalTransferTargetValidationStatus(target, ZeroAddress, true))
			.to.be.revertedWithCustomError(context.controlFacet, "ZeroAddress")
			.withArgs("collateral")

		await expect(context.accountFacet.connect(partyA.getSigner).externalTransfer(collateral, context.signers.partyA2.address, 10, target))
			.to.be.revertedWithCustomError(context.accountFacet, "ExternalTransferTargetNotWhitelisted")
			.withArgs(target, collateral)
		await expect(context.controlFacet.setExternalTransferTargetValidationStatus(target, collateral, true))
			.to.emit(context.controlFacet, "ExternalTransferTargetValidationStatusUpdated")
			.withArgs(target, collateral, true)

		const targetBalanceBefore = await context.collateral.balanceOf(target)
		await context.accountFacet.connect(partyA.getSigner).externalTransfer(collateral, context.signers.partyA2.address, 10, target)
		expect((await context.collateral.balanceOf(target)) - targetBalanceBefore).to.equal(10)
	})
}
