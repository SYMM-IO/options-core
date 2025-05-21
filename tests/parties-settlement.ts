import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { expect, use } from "chai"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { RunContext } from "./run-context"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { PartyB } from "./models/partyB.model"
import { TradeSide } from "./option-enums"
import { ethers, network } from "hardhat"
import { e } from "../utils/e"
import { ZeroAddress } from "ethers"
import { partyAClose } from "../types/contracts/facets"
import { TradeStructOutput } from "../types/contracts/facets/ViewFacet/IViewFacet"
import { SettlementPriceSigStruct } from "../types/contracts/facets/TradeSettlement/ITradeSettlementFacet"
import { settlementSigBuilder } from "./models/builders/settlement.builder"

export function shouldBehaveLikeSettlementFacet(): void {
	let context: RunContext, partyA1: PartyA, partyB1: PartyB, partyB2: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyB1 = new PartyB(context, context.signers.partyB1)
		partyB2 = new PartyB(context, context.signers.partyB2)

		await partyB1.setBalances(context.collateral, e(100000), e(100000))
		await partyA1.setBalances(context.collateral, e(100000), e(100000))

		const latestBlock = await ethers.provider.getBlock("latest")
		await partyA1.sendOpenIntent(
			openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.getSigner])
				.affiliate(context.signers.affiliate1)
				.feeToken(context.collateral)
				.symbolId(1)
				.deadline((latestBlock?.timestamp ?? 0) + 140)
				.expirationTimestamp((latestBlock?.timestamp ?? 0) + 150)
				.exerciseFee({ cap: e(1), rate: "0" })
				.quantity(e(100))
				.price(7)
				.build(),
		)

		await partyB1.lockOpenIntent(1)
		await partyB1.fillOpenIntent(1, 100, 7)
		await partyA1.sendCloseIntent(1, 7, 100, (latestBlock?.timestamp ?? 0) + 120)
		await partyB1.fillCloseIntent(1, 70, 7)

		const newBlock = ((await ethers.provider.getBlock("latest"))?.timestamp ?? 0) + 150
		await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
		await network.provider.send("evm_mine")
	})

	describe("executeTrade", async function () {
		it("Should be failed when Globally Paused", async () => {
			const timestamp = (await ethers.provider.getBlock("latest"))?.timestamp ?? 0
			await context.controlFacet.pauseGlobal()

			const ID = 1
			const priceSig: SettlementPriceSigStruct = settlementSigBuilder().build()
			await expect(context.tradeSettlementFacet.executeTrade(ID, priceSig)).to.be.revertedWithCustomError(
				context.tradeSettlementFacet,
				"GlobalPaused",
			)
		})

		it("Should failed when PartyB action Paused", async () => {
			await context.controlFacet.pausePartyBActions()
			const timestamp = (await ethers.provider.getBlock("latest"))?.timestamp ?? 0

			const ID = 1
			const priceSig: SettlementPriceSigStruct = {
				reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
				timestamp: timestamp + 100,
				symbolId: 1,
				settlementPrice: 7,
				settlementTimestamp: timestamp,
				collateralPrice: 8,
				gatewaySignature: "0xabcdef",
				sigs: {
					signature: 0x1234567890,
					owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
					nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
				},
			}

			// try{
			// 	await context.tradeSettlementFacet.executeTrade( ID ,priceSig)
			// }
			// catch(err){

			// 	console.log(err )
			// }
			await expect(context.tradeSettlementFacet.executeTrade(ID, priceSig)).to.be.revertedWithCustomError(
				context.partyBOpenFacet,
				"PartyBActionsPaused",
			)
		})

		// it("Should failed when partyA suspended", async () => {
		// 	await context.controlFacet.suspendAddress(partyA1.getSigner, true)
		// 	const timestamp = ((await ethers.provider.getBlock("latest"))?.timestamp ?? 0)

		// 	const ID = 1;
		// 	const priceSig: SettlementPriceSigStruct = {
		// 			reqId: ethers.toUtf8Bytes("1"), // or a Buffer/hex string
		// 			timestamp: timestamp,
		// 			symbolId: 1,
		// 			settlementPrice: e(7),
		// 			settlementTimestamp: timestamp,
		// 			collateralPrice: e(8),
		// 			gatewaySignature: ethers.toUtf8Bytes("0xabcdef"),
		// 			sigs: {
		// 				signature: 0x1234567890,
		// 				owner: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
		// 				nonce: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed"
		// 			}
		// 			};
		// 	await expect(partyB1.fillCloseIntent(1, 100, 7)).to.revertedWithCustomError(context.partyBCloseFacet,"SuspendedAddress")
		// })

		// it("Should failed when partyB suspended", async () => {
		// 	await context.controlFacet.suspendAddress(partyB1.getSigner, true)
		// 	await expect(partyB1.fillCloseIntent(1, 100, 7)).to.revertedWithCustomError(context.partyBCloseFacet,"SuspendedAddress")
		// })

		// it("Should failed when amount to fill not in range", async () => {
		// 	await partyB1.fillCloseIntent(1,5,7)
		// 	await expect(partyB1.fillCloseIntent(1, 96, 7)).to.revertedWithCustomError(context.partyBCloseFacet,"InvalidFilledAmount")
		// 	await expect(partyB1.fillCloseIntent(1, 95, 7)).not.to.revertedWithCustomError(context.partyBCloseFacet,"InvalidFilledAmount")
		// })

		// it("Should failed when Close Intent is expired", async () => {
		// 	const newBlock = ((await ethers.provider.getBlock("latest"))?.timestamp ?? 0) + 150
		// 	await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
		// 	await network.provider.send("evm_mine")

		// 	await expect(partyB1.fillCloseIntent(1, 96, 7)).to.revertedWithCustomError(context.partyBCloseFacet,"IntentExpired")
		// })

		// it("Should failed when Trade is expired", async () => {
		// 	const newBlockTime = ((await ethers.provider.getBlock("latest"))?.timestamp ?? 0) + 150

		// 	await partyA1.sendOpenIntent(
		// 		openIntentRequestBuilder()
		// 			.partyBsWhiteList([partyB1.getSigner])
		// 			.affiliate(context.signers.affiliate1)
		// 			.feeToken(context.collateral)
		// 			.symbolId(1)
		// 			.deadline(newBlockTime)
		// 			.expirationTimestamp(newBlockTime)
		// 			.exerciseFee({ cap: e(1), rate: "0" })
		// 			.quantity(e(100))
		// 			.price(7)
		// 			.build(),
		// 	)

		// 	await partyB1.lockOpenIntent(2);
		// 	await partyB1.fillOpenIntent(2,100,7);
		// 	await partyA1.sendCloseIntent(2,7,100, newBlockTime+180); // longer deadline than option expire

		// 	await network.provider.send("evm_setNextBlockTimestamp", [newBlockTime])
		// 	await network.provider.send("evm_mine")
		// 	await expect(partyB1.fillCloseIntent(2, 96, 7)).to.revertedWithCustomError(context.partyBCloseFacet,"TradeExpired")
		// })

		// it("Should failed when price to fill not in range", async () => {
		// 	let trade:TradeStructOutput =await context.viewFacet.getTrade(1);
		// 	if(trade.tradeAgreements.tradeSide == e(TradeSide.BUY)){
		// 		await expect(partyB1.fillCloseIntent(1, 96, 5)).to.revertedWithCustomError(context.partyBCloseFacet,"InvalidClosedPrice")
		// 		await expect(partyB1.fillCloseIntent(1, 96, 10)).not.to.revertedWithCustomError(context.partyBCloseFacet,"InvalidClosedPrice")
		// 	}
		// 	else if(trade.tradeAgreements.tradeSide == BigInt(TradeSide.SELL)){
		// 		await expect(partyB1.fillCloseIntent(1, 96, 10)).to.revertedWithCustomError(context.partyBCloseFacet,"InvalidClosedPrice")
		// 		await expect(partyB1.fillCloseIntent(1, 96, 5)).not.to.revertedWithCustomError(context.partyBCloseFacet,"InvalidClosedPrice")

		// 	}
		// })

		// it("Should failed when intent status not  PENDING", async () => {

		// 	await context.partyBOpenFacet.connect(context.signers.partyB1).lockOpenIntent(1)
		// 	await expect(context.partyBOpenFacet.connect(context.signers.partyB1).lockOpenIntent(1)).to
		// 		.be.revertedWithCustomError(context.partyBOpenFacet,"InvalidState")
		// })

		// it("Should failed when intent deadline reached", async () => {
		// 	const newBlock = ((await ethers.provider.getBlock("latest"))?.timestamp ?? 0) + 150
		// 	await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
		// 	await network.provider.send("evm_mine")

		// 	await expect(context.partyBOpenFacet.connect(context.signers.partyB1).lockOpenIntent(1)).to
		// 	.be.revertedWithCustomError(context.partyBOpenFacet, "IntentExpired")
		// })

		// it("Should failed when symbol is not valid", async () => {
		// 	const latestBlock = await ethers.provider.getBlock("latest")

		// 	const request = openIntentRequestBuilder()
		// 	.partyBsWhiteList([])
		// 	.affiliate(context.signers.affiliate1)
		// 	.feeToken(context.collateralNotListed)
		// 	.symbolId(2)
		// 	.deadline((latestBlock?.timestamp ?? 0) + 140)
		// 	.expirationTimestamp((latestBlock?.timestamp ?? 0) + 120)
		// 	.exerciseFee({ cap: e(1), rate: "0" })
		// 	.quantity(e(100))
		// 	.price(7)
		// 	.build()

		// 	await partyA1.sendOpenIntent(request)

		// 	// await expect(context.partyBOpenFacet.connect(context.signers.partyB1).lockOpenIntent(2)).to.be.revertedWithCustomError(context.partyBOpenFacet,"InvalidSymbol")
		// })

		// it("Should failed when intent expiration has been passed", async () => {
		// 	const newBlock = ((await ethers.provider.getBlock("latest"))?.timestamp ?? 0) + 130
		// 	await network.provider.send("evm_setNextBlockTimestamp", [newBlock])

		// 	await expect(context.partyBOpenFacet.connect(partyB1.getSigner).lockOpenIntent(1)).to
		// 		.revertedWithCustomError(context.partyBOpenFacet,"ExpirationTimestampPassed");
		// })

		// it("Should failed when intent id not exist", async () => {
		// 	await expect(context.partyBOpenFacet.connect(partyB1.getSigner).lockOpenIntent(2)).to
		// 			.be.revertedWithCustomError(context.partyBOpenFacet,"InvalidIntentId");
		// })

		// it("Should failed when partyB oracle id not equal with intent symbol oracle id", async () => {
		// 	await context.controlFacet.setPartyBConfig(partyB1.getSigner, {
		// 		isActive: true,
		// 		lossCoverage: 0,
		// 		oracleId: 2,
		// 		symbolType: 0,
		// 	})

		// 	await expect(context.partyBOpenFacet.connect(partyB1.getSigner).lockOpenIntent(1)).to
		// 		.be.revertedWithCustomError(context.partyBOpenFacet,"OracleNotMatched");
		// })

		//

		// it("Should failed when partyB is not Active or Valid", async () => {

		// 	await context.controlFacet.setPartyBConfig(partyB1.getSigner, {
		// 		isActive: false,
		// 		lossCoverage: 0,
		// 		oracleId: 1,
		// 		symbolType: 0,
		// 	})

		// 	await expect(context.partyBOpenFacet.connect(partyB1.getSigner).lockOpenIntent(1)).to
		// 		.be.revertedWithCustomError(context.partyBOpenFacet,"NotPartyB");
		// })

		// it("Should failed when partyB not whitelisted in the intent sent by partyA", async () => {
		// 	await expect(context.partyBOpenFacet.connect(partyB2.getSigner).lockOpenIntent(1)).to
		// 		.be.revertedWithCustomError(context.partyBOpenFacet,"NotWhitelistedPartyB");
		// })

		// it("Should failed when PartyB is in the liquidation process", async () => {
		// 	//TODO ::: it is handled in the close test section
		// })

		// 	it("Should lock open intent successfully", async () => {
		// 		await expect(context.partyBOpenFacet.connect(partyB1.getSigner).lockOpenIntent(1)).to.not.reverted

		// 		const intent = await context.viewFacet.getOpenIntent(1)

		// 		expect(intent.status).to.equal(1) // IntentStatus.LOCKED
		// 		expect(intent.partyB).to.equal(partyB1.getSigner)

		// 		// TODO ::: check intentLayout states
		// 	})
		// })

		// describe("unlockOpenIntent", async function () {
		// 	beforeEach(async () => {
		// 		await context.partyBOpenFacet.connect(partyB1.getSigner).lockOpenIntent(1)
		// 	})

		// 	it("Should failed when Global Paused", async () => {
		// 		await context.controlFacet.pauseGlobal()
		// 		await expect(partyB1.unlockOpenIntent("1")).to.revertedWith("Pausable: Global paused")
		// 	})

		// 	it("Should failed when PartyB action Paused", async () => {
		// 		await context.controlFacet.pausePartyBActions()
		// 		await expect(partyB1.unlockOpenIntent("1")).to.revertedWith("Pausable: PartyB actions paused")
		// 	})

		// 	it("Should failed when msgSender is not PartyB", async () => {
		// 		await expect(context.partyBOpenFacet.connect(context.signers.others[0]).unlockOpenIntent(1)).to.revertedWith("Accessibility: Should be partyB of Intent")
		// 	})

		// 	it("Should failed when intent status not LOCKED", async () => {
		// 		await partyA1.sendCancelOpenIntent(["1"])
		// 		await expect(partyB1.unlockOpenIntent("1")).to.revertedWith("LibPartyB: Invalid state")
		// 	})

		// 	it("Should failed when PartyB is in the liquidation process", async () => {
		// 		//TODO :::
		// 	})

		// 	it("Should change intent status to EXPIRED when deadline reached", async () => {
		// 		// TODO :::
		// 		// const newBlock = ((await ethers.provider.getBlock("latest"))?.timestamp ?? 0) + 150
		// 		// await network.provider.send("evm_setNextBlockTimestamp", [newBlock])
		// 		// expect(await context.partyBOpenFacet.connect(partyB1.getSigner).unlockOpenIntent(1)).to.not.reverted
		// 		// const intent = await context.viewFacet.getOpenIntent(1)
		// 		// expect(intent.status).to.equal(3)
		// 	})

		// 	it("Should change intent status to PENDING", async () => {
		// 		expect(await partyB1.unlockOpenIntent("1")).to.not.reverted

		// 		const intent = await context.viewFacet.getOpenIntent(1)

		// 		expect(intent.status).to.equal(0) //IntentStatus.PENDING
		// 		expect(intent.partyB).to.equal(ZeroAddress)
		// 	})
		// })

		// describe("fillOpenIntent", async function () {
		// 	beforeEach(async () => {
		// 		await partyB1.lockOpenIntent("1")
		// 	})

		// 	it("Should failed when Global Paused", async () => {
		// 		await context.controlFacet.pauseGlobal()
		// 		await expect(partyB1.fillOpenIntent(1, 100, 7, 0)).to.revertedWith("Pausable: Global paused") // MarginType: 0 for  Isolated margin, 1 for Cross
		// 	})

		// 	it("Should failed when PartyB action Paused", async () => {
		// 		await context.controlFacet.pausePartyBActions()
		// 		await expect(partyB1.fillOpenIntent(1, 100, 7, 0)).to.revertedWith("Pausable: PartyB actions paused")
		// 	})

		// 	it("Should failed when msgSender is not PartyB", async () => {
		// 		await expect(partyB2.fillOpenIntent(1, 100, 7, 0)).to.revertedWith(
		// 			"Accessibility: Should be partyB of Intent",
		// 		)
		// 	})

		// 	it("Should failed when partyA suspended", async () => {
		// 		await context.controlFacet.suspendAddress(partyA1.getSigner, true)
		// 		await expect(partyB1.fillOpenIntent(1, 100, 7, 0)).to.revertedWith("partyBOpenFacet: PartyA is suspended")
		// 	})
	})
}
