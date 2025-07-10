import { expect } from "chai"
import { ethers, network } from "hardhat"
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"
import { initializeTestFixture } from "./initialize-test.fixture"
import { PartyA } from "./models/partyA.model"
import { PartyB } from "./models/partyB.model"
import { openIntentRequestBuilder } from "./models/builders/send-open-intent.builder"
import { MarginType, TradeSide } from "./option-enums"
import { e } from "./../utils/e"
import { getLatestBlockTime } from "./../utils/time"
import { InstantLayer } from "./../types"
import { toUtf8Bytes, ZeroAddress } from "ethers"
import { RunContext } from "./run-context"
import { Context } from "mocha"

export function shouldBehaveLikeInstantLayerAuto(): void {
	let context: RunContext, partyA1: PartyA, partyB1: PartyB

	beforeEach(async function () {
		context = await loadFixture(initializeTestFixture)
		partyA1 = new PartyA(context, context.signers.partyA1)
		partyB1 = new PartyB(context, context.signers.partyB1)
		await partyA1.setBalances(context.collateral, "500", "100")
		await partyA1.setBalances(context.collateralNL, e(100000), e(100000))

		await context.controlFacet.setPartyBConfig(context.signers.partyB1, {
			isActive: true,
			lossCoverage: 0,
			oracleId: 1,
		})

		await context.controlFacet.setUnbindingCooldown(120)
	})

	describe("InstantLayer - executeBatch", function () {

		it("should Set the SYMMIO to Accept Instant Layer Actions", async function () {
			await context.controlFacet.setCallFromInstantLayer(true)
			expect(await context.viewFacet.isCallFromInstantLayer()).to.be.equal(true)
			
		})

		it("should allow PartyA to open and PartyB to lock/fill in a single batch", async function () {			
			const { instantLayer, collateralNL, partyAOpenFacet, partyBOpenFacet } = context

			const partyAAddress = partyA1.getSigner
			const partyBAddress = partyB1.getSigner

			const multiAccount = context.multiAccount

			// Register roles
			await instantLayer.registerPartyB(partyBAddress)
			await instantLayer.registerMultiAccount(multiAccount)

			// Build calldata
			const latestBlock = await getLatestBlockTime()
			const deadline = latestBlock + 300

			const request = openIntentRequestBuilder()
				.partyBsWhiteList([partyB1.address])
				.affiliate(context.signers.affiliate1.address)
				.feeToken(await collateralNL.getAddress())
				.symbolId(1)
				.deadline(deadline)
				.expirationTimestamp(deadline)
				.exerciseFee({ cap: e(1), rate: "0" })
				.marginType(MarginType.ISOLATED)
				.tradeSide(TradeSide.BUY)
				.strikePrice(e(1))
				.build()

			const openIntentCallData = partyAOpenFacet.interface.encodeFunctionData("sendOpenIntent", [
				request.partyBsWhiteList,
				request.symbolId,
				request.price,
				request.quantity,
				request.strikePrice,
				request.expirationTimestamp,
				request.mm,
				request.tradeSide,
				request.marginType,
				request.exerciseFee,
				request.deadline,
				request.feeToken,
				request.affiliate,
				request.userData,
			])

			const lockIntentCallData = partyBOpenFacet.interface.encodeFunctionData("lockOpenIntent", [1])
			const fillIntentCallData = partyBOpenFacet.interface.encodeFunctionData("fillOpenIntent", [1, e(100), 7])
			console.log("OpenIntent Interface:",openIntentCallData)
			console.log("LockIntent Interface:",lockIntentCallData)
			console.log("FillIntent Interface:",fillIntentCallData)

			const saltOpen = ethers.keccak256(ethers.toUtf8Bytes("saltOpen"))
			const saltLock = ethers.keccak256(ethers.toUtf8Bytes("saltLock"))
			const saltFill = ethers.keccak256(ethers.toUtf8Bytes("saltFill"))

			const opOpenA = {
				accountSource: multiAccount,
				signer: partyA1.address,
				callData: openIntentCallData,
				nonce: 0,
				salt: saltOpen,
				deadline,
				signature: "0x", // placeholder
			}

			const opLockB = {
				accountSource: ethers.ZeroAddress,
				signer: partyB1.address,
				callData: lockIntentCallData,
				nonce: 0,
				salt: saltLock,
				deadline,
				signature: "0x",
			}

			const opFillB = {
				accountSource: ethers.ZeroAddress,
				signer: partyB1.address,
				callData: fillIntentCallData,
				nonce: 0,
				salt: saltFill,
				deadline,
				signature: "0x",
			}

			//Sign using getOperationHash
			const opOpenAHash = await instantLayer.getOperationHash(opOpenA)
			const opLockBHash = await instantLayer.getOperationHash(opLockB)
			const opFillBHash = await instantLayer.getOperationHash(opFillB)

			opOpenA.signature = await partyA1.getSigner.signMessage(ethers.getBytes(opOpenAHash))
			opLockB.signature = await partyB1.getSigner.signMessage(ethers.getBytes(opLockBHash))
			opFillB.signature = await partyB1.getSigner.signMessage(ethers.getBytes(opFillBHash))

			const signedOps: InstantLayer.SignedOperationStruct[] = [opOpenA]

			await context.controlFacet.grantRole(context.instantLayer, ethers.keccak256(toUtf8Bytes("INSTANT_LAYER_ROLE")))

			// Execute the batch
			await expect(instantLayer.executeBatch(signedOps)).to.be.revertedWithCustomError(context.instantLayer, "OperationFailed")
		})

		
	})
}
