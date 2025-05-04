import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect, use } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { RunContext } from "./run-context"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { PartyB } from "./models/partyB.model"
import { ethers, network } from "hardhat"
import { e } from "../utils/e"
import { ZeroAddress } from "ethers"
import { bigint } from "hardhat/internal/core/params/argumentTypes"
import { config } from "dotenv"

export function shouldBehaveLikePartyBOpenFacet(): void {
	let context: RunContext, partyA1: PartyA, partyB1: PartyB, partyB2: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)

		// await partyB1.setBalances(context.collateral,e(100000), e(100000))
		// await partyB2.setBalances(context.collateralNL,e(100000), e(100000))
		await partyA1.setBalances(context.collateral,e(100000), e(100000))

		const latestBlock = await ethers.provider.getBlock("latest")
		await partyA1.sendOpenIntent(
			openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 140)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.price(7)
				.build(),
		)
	})

	describe("lockOpenIntent", async function () {
		it("Should be failed when Sender address is Suspended", async () => {
			await context.controlFacet.suspendAddress(partyB1.getSigner(),true)			
			await expect(context.partyBOpenFacet.connect(context.signers.partyB1).lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "SuspendedAddress")
		})

		it("Should be failed when in Emergency Mode", async () => {
			await context.controlFacet.activeEmergencyMode();
			await expect(context.partyBOpenFacet.connect(context.signers.partyB1).lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "EmergencyMode")
		})	
		
		it("Should be failed when PartyB in Emergency Mode", async () => {
			await context.controlFacet.activePartyBEmergencyStatus(partyB1.getSigner())
			await expect(context.partyBOpenFacet.connect(context.signers.partyB1).lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "PartyBInEmergencyMode")
		})

		it("Should be failed when Globally Paused", async () => {
			await context.controlFacet.pauseGlobal()
			await expect(context.partyBOpenFacet.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "GlobalPaused")
		})

		it("Should failed when PartyB action Paused", async () => {
			await context.controlFacet.pausePartyBActions()
			await expect(context.partyBOpenFacet.lockOpenIntent(1)).to.be.revertedWithCustomError(context.partyBOpenFacet, "PartyBActionsPaused")
		})

		it("Should failed when msgSender is not PartyB", async () => {
			
			await expect(context.partyBOpenFacet.connect(context.signers.partyA1).lockOpenIntent(1)).to
				.be.revertedWithCustomError(context.partyBOpenFacet, "NotPartyB")
			
		})
		
		it("Should failed when intent status not  PENDING", async () => {

			await context.partyBOpenFacet.connect(context.signers.partyB1).lockOpenIntent(1)
			await expect(context.partyBOpenFacet.connect(context.signers.partyB1).lockOpenIntent(1)).to
				.be.revertedWithCustomError(context.partyBOpenFacet,"InvalidState")
		})

		it("Should failed when intent deadline reached", async () => {
			const newBlock = ((await ethers.provider.getBlock("latest"))?.timestamp ?? 0) + 150
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
			await network.provider.send("evm_mine")

			await expect(context.partyBOpenFacet.connect(context.signers.partyB1).lockOpenIntent(1)).to
			.be.revertedWithCustomError(context.partyBOpenFacet, "IntentExpired")
		})

		it("Should failed when symbol is not valid", async () => {
			const latestBlock = await ethers.provider.getBlock("latest")
			await partyA1.setBalances(context.collateralNL,e(10000),e(10000))
			// await partyB2.setBalances(context.collateralNL,e(10000),e(10000))
			
			const request = openIntentRequestBuilder()
			.partyBsWhiteList([partyB2.getSigner])
			.affiliate(context.signers.affiliate1)
			.feeToken(context.collateralNL)
			.symbolId(2)
			.deadline((latestBlock?.timestamp ?? 0) + 140)
			.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
			.exerciseFee({ cap: e(1), rate: "0" })
			.quantity(e(10))
			.price(1)
			.build()
			await partyA1.sendOpenIntent(request)
			
			await context.controlFacet.setSymbolState(2,false);
			await expect(context.partyBOpenFacet.connect(context.signers.partyB2).lockOpenIntent(2)).to.be.revertedWithCustomError(context.partyBOpenFacet,"InvalidSymbol")
		})

		it("should revert when partB symbol type mismatch intent symbol type", async () =>{			const latestBlock = await ethers.provider.getBlock("latest")

			await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 1,
				symbolType: 1,  // another category of symbols 
			});

			await expect(context.partyBOpenFacet.connect(partyB1.getSigner).lockOpenIntent(1)).to
			.be.revertedWithCustomError(context.partyBOpenFacet,"MismatchedSymbolType");	
		})

		it("Should failed when intent expiration has been passed", async () => {
			const newBlock = ((await ethers.provider.getBlock("latest"))?.timestamp ?? 0) + 130
			await network.provider.send("evm_setNextBlockTimestamp", [newBlock])

			await expect(context.partyBOpenFacet.connect(partyB1.getSigner).lockOpenIntent(1)).to
				.revertedWithCustomError(context.partyBOpenFacet,"ExpirationTimestampPassed");
		})

		it("Should failed when intent id not exist", async () => {
			await expect(context.partyBOpenFacet.connect(partyB1.getSigner).lockOpenIntent(200)).to
					.be.revertedWithCustomError(context.partyBOpenFacet,"InvalidIntentId");
		})

		it("Should failed when partyB oracle id not equal with intent symbol oracle id", async () => {
			await context.controlFacet.setPartyBConfig(partyB1.getSigner, {
				isActive: true,
				lossCoverage: 0,
				oracleId: 2,
				symbolType: 0,
			})

			await expect(context.partyBOpenFacet.connect(partyB1.getSigner).lockOpenIntent(1)).to
				.be.revertedWithCustomError(context.partyBOpenFacet,"OracleNotMatched");
		})
		
		it("Should failed when partyB is not Active or Valid", async () => {			

			await context.controlFacet.setPartyBConfig(partyB1.getSigner, {
				isActive: false,
				lossCoverage: 0,
				oracleId: 1,
				symbolType: 0,
			})

			await expect(context.partyBOpenFacet.connect(partyB1.getSigner).lockOpenIntent(1)).to
				.be.revertedWithCustomError(context.partyBOpenFacet,"NotPartyB");
		})

		it("Should failed when partyB not whitelisted in the intent sent by partyA", async () => {
			await expect(context.partyBOpenFacet.connect(partyB2.getSigner).lockOpenIntent(1)).to
				.be.revertedWithCustomError(context.partyBOpenFacet,"NotWhitelistedPartyB");
		})


		it("Should lock open intent successfully", async () => {
			await expect(context.partyBOpenFacet.connect(partyB1.getSigner).lockOpenIntent(1)).to.not.reverted

			const intent = await context.viewFacet.getOpenIntent(1)

			expect(intent.status).to.equal(1) // IntentStatus.LOCKED
			expect(intent.partyB).to.equal(partyB1.getSigner)

			// TODO ::: check intentLayout states
		})
	})


	describe("fillOpenIntent", async function () {
		beforeEach(async () => {
			await partyB1.lockOpenIntent("1")
		})

		it("Should failed when Global Paused", async () => {
			await context.controlFacet.pauseGlobal()
			await expect(partyB1.fillOpenIntent(1, 100, 7, 0)).to
			.be.revertedWithCustomError(context.partyBOpenFacet,"GlobalPaused") // MarginType: 0 for  Isolated margin, 1 for Cross
		}) 

		it("Should failed when PartyB action Paused", async () => {
			await context.controlFacet.pausePartyBActions()
			await expect(partyB1.fillOpenIntent(2, 100, 7, 0)).to.revertedWithCustomError(context.partyAOpenFacet,"PartyBActionsPaused")
		})

		it("Should failed when msgSender is not PartyB", async () => {
			await expect(partyB2.fillOpenIntent(2, 100, 7, 0)).to.revertedWithCustomError(context.partyBOpenFacet,
				"UnauthorizedSender",
			)// no matter the intent ID
		})

		it("Should failed when partyA suspended", async () => {
			await context.controlFacet.suspendAddress(partyA1.getSigner, true)

			await expect(partyB1.fillOpenIntent(2, 100, 7, 0)).to.revertedWithCustomError(context.partyBOpenFacet,"SuspendedAddress")
		})
		
		it("Should failed when symbol is not valid", async () => {
			await context.controlFacet.setSymbolState(1,false)
			
			await expect(partyB1.fillOpenIntent(1, 100, 7, 0)).to.revertedWithCustomError(context.partyBOpenFacet,"InvalidSymbol")
		})

	})
}
