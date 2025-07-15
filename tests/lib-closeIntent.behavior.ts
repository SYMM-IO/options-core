import { loadFixture } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"
import { ethers } from "hardhat"

import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { PartyB } from "./models/partyB.model"
import { RunContext } from "./run-context"
import { tradeBuilder } from "./models/builders/trade.builder"
import { closeIntentBuilder } from "./models/builders/close-intent.builder"
import { TradeStruct } from "../types/contracts/interfaces/ISymmio"
import { CloseIntentStatus } from "./option-enums"

export function shouldBehaveLikeLibCloseIntent(): void {
	let context: RunContext
	let partyA1: PartyA, partyB1: PartyB

	beforeEach(async () => {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyB1 = new PartyB(context, context.signers.partyB1)
		await partyA1.setBalances(undefined, "500", "500")
	})

	describe("LibCloseIntent", () => {
		describe("save", () => {
			it("should save successfully", async () => {
				const trade = tradeBuilder().build()
				const closeIntent = closeIntentBuilder().build()

				await context.mocks.libCloseIntentMock.setTrade(trade.id, trade)
				await expect(context.mocks.libCloseIntentMock.testSave(closeIntent)).to.not.be.reverted

				const storedTrade = await context.mocks.libCloseIntentMock.getTrade(trade.id)
				const storedIntent = await context.mocks.libCloseIntentMock.getCloseIntent(closeIntent.id)

				expect(storedIntent.id).to.equal(closeIntent.id)
				expect(storedIntent.tradeId).to.equal(closeIntent.tradeId)
				expect(storedIntent.price).to.equal(closeIntent.price)
				expect(storedIntent.quantity).to.equal(closeIntent.quantity)
				expect(storedIntent.filledAmount).to.equal(closeIntent.filledAmount)
				expect(storedIntent.status).to.equal(closeIntent.status)
				expect(storedIntent.createTimestamp).to.equal(closeIntent.createTimestamp)
				expect(storedIntent.statusModifyTimestamp).to.equal(closeIntent.statusModifyTimestamp)
				expect(storedIntent.deadline).to.equal(closeIntent.deadline)

				expect(storedTrade.activeCloseIntentIds.map(id => id.toString())).to.include(closeIntent.id.toString())
				expect(storedTrade.closePendingAmount).to.equal(closeIntent.quantity)
				//TODO must be adopted to recent changes to FEE structure
			})
		})

		describe("expire", () => {
			let latestTimestamp: number
			let trade: TradeStruct
			let closeIntentBuilderInstance: ReturnType<typeof closeIntentBuilder>

			beforeEach(async () => {
				const latestBlock = await ethers.provider.getBlock("latest")
				latestTimestamp = latestBlock?.timestamp ?? 0

				trade = tradeBuilder().build()
				closeIntentBuilderInstance = closeIntentBuilder()
				await context.mocks.libCloseIntentMock.setTrade(trade.id, trade)
			})

			it("should revert if deadline not reached", async () => {
				const closeIntent = closeIntentBuilderInstance.deadline(latestTimestamp + 500).build()

				await context.mocks.libCloseIntentMock.testSave(closeIntent)

				await expect(context.mocks.libCloseIntentMock.testExpire(closeIntent.id)).to.be.revertedWithCustomError(
					context.mocks.libCloseIntentMock,
					"IntentNotExpired",
				)
			})

			it("should revert if status is not PENDING or CANCEL_PENDING", async () => {
				const closeIntent = closeIntentBuilderInstance
					.status(CloseIntentStatus.FILLED) // e.g. status = FILLED
					.deadline(latestTimestamp - 10) // to avoid IntentNotExpired revert
					.build()

				await context.mocks.libCloseIntentMock.testSave(closeIntent)

				await expect(context.mocks.libCloseIntentMock.testExpire(closeIntent.id)).to.be.revertedWithCustomError(
					context.mocks.libCloseIntentMock,
					"InvalidState",
				)
			})

			it("should successfully expire", async () => {
				const closeIntent = closeIntentBuilderInstance
					.status(0) // to avoid InvalidState revert
					.deadline(latestTimestamp - 10) // to avoid IntentNotExpired revert
					.build()

				await context.mocks.libCloseIntentMock.testSave(closeIntent)
				expect(await context.mocks.libCloseIntentMock.testExpire(closeIntent.id)).to.not.reverted

				const latestBlock = await ethers.provider.getBlock("latest")
				latestTimestamp = latestBlock?.timestamp ?? 0

				const storedIntent = await context.mocks.libCloseIntentMock.getCloseIntent(closeIntent.id)
				expect(storedIntent.statusModifyTimestamp).to.approximately(latestTimestamp, 12)
				expect(storedIntent.status).to.equal(CloseIntentStatus.EXPIRED) // IntentStatus.EXPIRED
			})
		})
	})
}
