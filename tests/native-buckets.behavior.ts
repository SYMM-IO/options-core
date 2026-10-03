import { expect } from "chai"
import { MaxUint256, ZeroAddress, solidityPackedKeccak256, keccak256, toUtf8Bytes } from "ethers"
import type { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/types"
import { ethers, networkHelpers } from "./connection.js"
import { initializeNativeBucketsFixture } from "./fixtures/native-buckets.fixture.js"
import type { RunContext } from "./run-context.js"
import type { BucketFacet, NativeBucketStrictOracle } from "../types/index.js"
import type { UpnlSigStruct } from "../types/facets/Account/AccountFacet.js"
import { e } from "../utils/e.js"
import { CloseIntentStatus, IntentStatus, MarginType, TradeSide, TradeStatus, WithdrawStatus } from "./option-enums.js"
import { getLatestBlockTime } from "./utils/time.js"
import { openIntentRequestBuilder, type OpenIntent } from "./models/builders/send-open-intent.builder.js"
import { settlementSigBuilder } from "./models/builders/settlement.builder.js"

const DEPOSIT = "deposit(uint256,address,uint256)" as const
const ALLOCATE = "allocate(uint256,address,address,uint256,uint256)" as const
const WITHDRAW = "initiateWithdraw(uint256,address,uint256,address)" as const
const DEALLOCATE =
	"deallocate(uint256,address,address,uint256,uint256,bool,(bytes,int256,int256,uint256,uint256,bytes,(uint256,address,address)))" as const
const SEND =
	"sendOpenIntent(uint256,address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint8,uint8,(uint256,uint256),(uint256,uint256),uint256,address,address,bytes)" as const
const ISOLATED = "getIsolatedBalance(address,uint256,address)" as const
const RESERVE = "getReserveBalance(address,uint256,address)" as const
const CROSS = "getCrossBalance(address,uint256,address,address,uint256)" as const
const NONCE = "getNonce(address,uint256,address,uint256)" as const
const SCHEDULE = "getScheduledReleaseEntry(address,uint256,address,address,uint256)" as const

type Actor = { signer: HardhatEthersSigner; owner: string; bucketId: number }
type Fixture = { context: RunContext; bucket: BucketFacet; a: Actor[]; b: Actor[]; token: string }

async function nativeFixture(): Promise<Fixture> {
	const context = await initializeNativeBucketsFixture()
	const bucket = await ethers.getContractAt("BucketFacet", context.common.diamondAddress)
	const token = await context.collateral.getAddress()
	const a: Actor[] = [],
		b: Actor[] = []
	for (const [signer, actors] of [
		[context.signers.partyA1, a],
		[context.signers.partyB1, b],
	] as const) {
		await context.collateral.mint(signer.address, e(100000))
		await context.collateral.connect(signer).approve(context.common.diamondAddress, MaxUint256)
		for (const bucketId of [0, 1, 2, 7]) {
			if (bucketId !== 0) await bucket.connect(signer).createBucket(bucketId)
			await context.accountFacet.connect(signer)[DEPOSIT](bucketId, token, e(10000))
			actors.push({ signer, owner: signer.address, bucketId })
		}
	}
	return { context, bucket, a, b, token }
}

async function allocate(f: Fixture, actor: Actor, cp: Actor, amount = e(5000), token = f.token) {
	return f.context.accountFacet.connect(actor.signer)[ALLOCATE](actor.bucketId, token, cp.owner, cp.bucketId, amount)
}
async function fund(f: Fixture, a: Actor, b: Actor, amount = e(5000)) {
	await allocate(f, a, b, amount)
	await allocate(f, b, a, amount)
}
async function request(f: Fixture, b: Actor, overrides: Partial<OpenIntent> = {}): Promise<OpenIntent> {
	const now = await getLatestBlockTime()
	return {
		...openIntentRequestBuilder()
			.partyBsWhiteList([b.owner])
			.symbolId(1)
			.price(e(10))
			.quantity(e(4))
			.strikePrice(e(100))
			.expirationTimestamp(now + 300)
			.deadline(now + 250)
			.marginType(MarginType.CROSS)
			.tradeSide(TradeSide.BUY)
			.mm(e(8))
			.exerciseFee({ cap: 0, rate: 0 })
			.solverFee({ openFee: e(0.01), closeFee: e(0.01) })
			.feeToken(f.token)
			.affiliate(f.context.signers.affiliate1.address)
			.build(),
		...overrides,
	}
}
async function send(f: Fixture, a: Actor, b: Actor, overrides: Partial<OpenIntent> = {}) {
	const r = await request(f, b, overrides)
	await f.context.partyAOpenFacet
		.connect(a.signer)
		[SEND](
			a.bucketId,
			b.owner,
			b.bucketId,
			r.symbolId,
			r.price,
			r.quantity,
			r.strikePrice,
			r.expirationTimestamp,
			r.mm,
			r.tradeSide,
			r.marginType,
			r.exerciseFee,
			r.solverFee,
			r.deadline,
			r.feeToken,
			r.affiliate,
			r.userData,
		)
	return { id: await f.context.viewFacet.getLastOpenIntentId(), request: r }
}
async function fill(f: Fixture, b: Actor, id: bigint, quantity = e(4), price = e(10)) {
	await f.context.partyBOpenFacet.connect(b.signer).lockOpenIntent(id)
	await f.context.partyBOpenFacet.connect(b.signer).fillOpenIntent(id, quantity, price)
	return f.context.viewFacet.getLastTradeId()
}
async function cross(f: Fixture, a: Actor, b: Actor, token = f.token) {
	return f.context.viewFacet[CROSS](a.owner, a.bucketId, token, b.owner, b.bucketId)
}
async function snapshot(f: Fixture, a: Actor, b: Actor, token = f.token) {
	const v = f.context.viewFacet
	return {
		aFree: await v[ISOLATED](a.owner, a.bucketId, token),
		bFree: await v[ISOLATED](b.owner, b.bucketId, token),
		aCross: Array.from(await cross(f, a, b, token)),
		bCross: Array.from(await cross(f, b, a, token)),
		aNonce: await v[NONCE](a.owner, a.bucketId, b.owner, b.bucketId),
		bNonce: await v[NONCE](b.owner, b.bucketId, a.owner, a.bucketId),
	}
}
async function assertBacking(f: Fixture, a: Actor, b: Actor, token = f.token) {
	for (const [actor, cp] of [
		[a, b],
		[b, a],
	] as const) {
		const entry = await cross(f, actor, cp, token)
		expect(entry.balance).to.be.greaterThanOrEqual(0n)
		expect(entry.balance - entry.locked - entry.totalMM).to.be.greaterThanOrEqual(0n)
	}
}
// Disjoint liabilities: locked/MM are subsets, whereas BUY premium escrow and pending withdrawals are additional custody claims.
async function assertConservation(f: Fixture, token = f.token) {
	const v = f.context.viewFacet
	const actors = [...f.a, ...f.b, { owner: f.context.signers.feeCollector.address, bucketId: 0 }]
	let claims = 0n
	for (const actor of actors) {
		claims += await v[ISOLATED](actor.owner, actor.bucketId, token)
		claims += await v[RESERVE](actor.owner, actor.bucketId, token)
		for (const cp of actors) {
			claims += (await v[CROSS](actor.owner, actor.bucketId, token, cp.owner, cp.bucketId)).balance
			const release = await v[SCHEDULE](actor.owner, actor.bucketId, token, cp.owner, cp.bucketId)
			claims += release.scheduled + release.transitioning
		}
	}
	for (let id = 1n; id <= (await v.getLastTradeId()); id++) {
		const trade = await v.getTrade(id)
		const symbol = await v.getSymbol(trade.tradeAgreements.symbolId)
		if (symbol.collateral === token && trade.status === BigInt(TradeStatus.OPENED) && trade.tradeAgreements.tradeSide === BigInt(TradeSide.BUY)) {
			claims += ((await v.getTradeOpenAmount(id)) * trade.openedPrice) / e(1)
		}
	}
	for (let id = 1n; id <= (await v.getLastWithdrawalId()); id++) {
		const withdrawal = await v.getWithdrawal(id)
		if (withdrawal.collateral === token && withdrawal.status === BigInt(WithdrawStatus.INITIATED)) claims += withdrawal.amount
	}
	const collateral = await ethers.getContractAt("FakeStablecoin", token)
	expect(claims).to.equal((await collateral.balanceOf(f.context.common.diamondAddress)) * 10n ** (18n - (await collateral.decimals())))
}
async function strictSig(
	f: Fixture,
	oracle: NativeBucketStrictOracle,
	a: Actor,
	b: Actor,
	options: { nonce?: bigint; contract?: string; chainId?: number; omitBuckets?: boolean } = {},
): Promise<UpnlSigStruct> {
	const sig: UpnlSigStruct = {
		reqId: "0x1234",
		partyUpnl: 0,
		counterPartyUpnl: 0,
		collateralPrice: e(1),
		timestamp: await getLatestBlockTime(),
		gatewaySignature: "0x",
		sigs: { signature: 0, owner: ZeroAddress, nonce: ZeroAddress },
	}
	const baseTypes = ["bytes", "address", "string"]
	const withBuckets = !options.omitBuckets && (a.bucketId !== 0 || b.bucketId !== 0)
	const types = [
		...baseTypes,
		...(withBuckets ? ["address", "uint256", "address", "uint256"] : ["address", "address"]),
		"int256",
		"int256",
		"address",
		"uint256",
		"uint256",
		"uint256",
		"uint256",
	]
	const values = [
		sig.reqId,
		options.contract ?? f.context.common.diamondAddress,
		withBuckets ? "verifyPoolUpnlSig" : "verifyUpnlSig",
		...(withBuckets ? [a.owner, a.bucketId, b.owner, b.bucketId] : [a.owner, b.owner]),
		0,
		0,
		f.token,
		e(1),
		options.nonce ?? (await f.context.viewFacet[NONCE](a.owner, a.bucketId, b.owner, b.bucketId)),
		sig.timestamp,
		options.chainId ?? f.context.common.chainId,
	]
	await oracle.setExpectedHash(solidityPackedKeccak256(types, values))
	return sig
}
async function deallocate(f: Fixture, a: Actor, b: Actor, sig: UpnlSigStruct, amount = e(1), token = f.token) {
	return f.context.accountFacet.connect(a.signer)[DEALLOCATE](a.bucketId, token, b.owner, b.bucketId, amount, a.owner === f.b[0].owner, sig)
}

describe("Native owner-local funding buckets through ordinary diamond calls", function () {
	let f: Fixture
	beforeEach(async function () {
		f = await networkHelpers.loadFixture(nativeFixture)
	})

	it("keeps wallets as the parties and registers many numeric buckets without deploying account contracts", async function () {
		for (const actors of [f.a, f.b])
			for (const actor of actors) {
				expect(await f.bucket.isBucketRegistered(actor.owner, actor.bucketId)).to.equal(true)
				const bucket = await f.bucket.getBucket(actor.owner, actor.bucketId)
				expect(bucket.owner).to.equal(actor.owner)
				expect(bucket.bucketId).to.equal(actor.bucketId)
				expect(await f.context.viewFacet[ISOLATED](actor.owner, actor.bucketId, f.token)).to.equal(e(10000))
			}
		expect(await f.context.collateral.balanceOf(f.a[1].owner)).to.equal(e(60000))
		expect(f.bucket.interface.hasFunction("executePool(uint256,bytes)")).to.equal(false)
		await assertConservation(f)
	})

	it("requires nonzero bucket registration and cannot spend another owner's bucket by reusing its local ID", async function () {
		const before = await snapshot(f, f.a[1], f.b[1])
		await expect(f.context.accountFacet.connect(f.context.signers.others[0])[WITHDRAW](1, f.token, e(1), f.a[1].owner)).to.revert(ethers)
		await expect(f.context.accountFacet.connect(f.a[1].signer)[DEPOSIT](99, f.token, 0)).to.revert(ethers)
		await expect(allocate(f, f.a[1], f.b[1], e(10001))).to.revert(ethers)
		expect(await snapshot(f, f.a[1], f.b[1])).to.deep.equal(before)
		expect(await f.context.viewFacet[ISOLATED](f.a[2].owner, 2, f.token)).to.equal(e(10000))
	})

	it("lazily registers self-owned buckets on deposit but rejects creating another owner's bucket through funding", async function () {
		const account = f.context.accountFacet.connect(f.a[1].signer)
		await expect(account["depositFor(uint256,address,address,uint256)"](93, f.token, f.context.signers.partyA2.address, e(1)))
			.to.be.revertedWithCustomError(account, "BucketNotRegistered")
			.withArgs(f.context.signers.partyA2.address, 93)
		await account[DEPOSIT](93, f.token, e(1))
		expect(await f.bucket.isBucketRegistered(f.a[1].owner, 93)).to.equal(true)
		expect(await f.context.viewFacet[ISOLATED](f.a[1].owner, 93, f.token)).to.equal(e(1))
		f.a.push({ ...f.a[1], bucketId: 93 })
		await assertConservation(f)
	})

	it("uses role-backed virtual credits, external transfer and express withdrawal from the explicitly selected bucket", async function () {
		const account = f.context.accountFacet.connect(f.a[1].signer),
			hooks = await (await ethers.getContractFactory("NativeBucketHooks")).deploy()
		const target = await hooks.getAddress(),
			recipient = f.context.signers.partyA2.address
		const initialWallet = await f.context.collateral.balanceOf(f.a[1].owner),
			sibling = await snapshot(f, f.a[2], f.b[2])
		await expect(account["virtualDepositFor(uint256,address,address,uint256)"](1, f.token, f.a[1].owner, e(5))).to.be.revertedWithCustomError(
			account,
			"MissingRole",
		)
		await f.context.controlFacet.grantRole(f.a[1].owner, keccak256(toUtf8Bytes("VIRTUAL_DEPOSITOR_ROLE")))
		// Virtual deposits authorize credits for custody supplied separately by the role holder.
		await f.context.collateral.mint(f.context.common.diamondAddress, e(5))
		await account["virtualDepositFor(uint256,address,address,uint256)"](1, f.token, f.a[1].owner, e(5))
		expect(await f.context.collateral.balanceOf(f.a[1].owner)).to.equal(initialWallet)
		expect(await f.context.viewFacet[ISOLATED](f.a[1].owner, 1, f.token)).to.equal(e(10005))
		await f.context.controlFacet.grantRole(f.context.signers.admin.address, keccak256(toUtf8Bytes("EXTERNAL_TRANSFER_TARGET_MANAGER_ROLE")))
		await f.context.controlFacet.setExternalTransferTargetValidationStatus(target, f.token, true)
		await account["externalTransfer(uint256,address,address,uint256,address)"](1, f.token, recipient, e(7), target)
		expect([await hooks.sender(), await hooks.receiver(), await hooks.collateral(), await hooks.amount()]).to.deep.equal([
			f.a[1].owner,
			recipient,
			f.token,
			e(7),
		])
		expect(await f.context.collateral.balanceOf(target)).to.equal(e(7))
		expect(await f.context.viewFacet[ISOLATED](recipient, 0, f.token)).to.equal(0)
		await f.context.controlFacet.setExpressWithdrawProviderConfig(target, f.token, { isActive: true, isVirtual: false, receiver: recipient })
		await hooks.setRejectWithdraw(true)
		await expect(account["initiateExpressWithdraw(uint256,address,uint256,address,address,bytes)"](1, f.token, e(11), f.a[1].owner, target, "0x1234"))
			.to.be.revertedWithCustomError(account, "ExpressWithdrawRejectedByProvider")
			.withArgs(target, "test rejection")
		expect(await f.context.viewFacet.getLastWithdrawalId()).to.equal(0)
		await hooks.setRejectWithdraw(false)
		await account["initiateExpressWithdraw(uint256,address,uint256,address,address,bytes)"](1, f.token, e(11), f.a[1].owner, target, "0x1234")
		const id = await f.context.viewFacet.getLastWithdrawalId(),
			withdrawal = await f.context.viewFacet.getWithdrawal(id)
		expect([withdrawal.user, withdrawal.bucketId, withdrawal.provider, withdrawal.userData]).to.deep.equal([f.a[1].owner, 1n, target, "0x1234"])
		await expect(account.cancelWithdraw(id)).to.be.revertedWithCustomError(account, "ExpressWithdrawCancellationNotAllowed").withArgs(target)
		await networkHelpers.time.increase(1000)
		const recipientBefore = await f.context.collateral.balanceOf(recipient)
		await account.completeWithdraw(id)
		expect(await f.context.collateral.balanceOf(recipient)).to.equal(recipientBefore + e(11))
		expect(await f.context.viewFacet[ISOLATED](f.a[1].owner, 1, f.token)).to.equal(e(9987))
		expect(await snapshot(f, f.a[2], f.b[2])).to.deep.equal(sibling)
		await assertConservation(f)
	})

	it("keeps ordinary bucket-zero calls independent after explicit nonzero success and revert", async function () {
		await expect(f.context.accountFacet.connect(f.a[1].signer)[WITHDRAW](1, f.token, e(20000), f.a[1].owner)).to.revert(ethers)
		await f.context.accountFacet.connect(f.a[1].signer)["allocateToReserveBalance(uint256,address,uint256)"](1, f.token, e(10))
		await f.context.accountFacet.connect(f.a[0].signer)["deposit(address,uint256)"](f.token, e(3))
		expect(await f.context.viewFacet[ISOLATED](f.a[0].owner, 0, f.token)).to.equal(e(10003))
		expect(await f.context.viewFacet[ISOLATED](f.a[1].owner, 1, f.token)).to.equal(e(9990))
		expect(await f.context.viewFacet[RESERVE](f.a[1].owner, 1, f.token)).to.equal(e(10))
		await assertConservation(f)
	})

	it("inherits wallet-level solver configuration and suspension for all buckets", async function () {
		await fund(f, f.a[1], f.b[1])
		const intent = await send(f, f.a[1], f.b[1])
		await f.context.partyBOpenFacet.connect(f.b[1].signer).lockOpenIntent(intent.id)
		await f.context.controlFacet.suspendAddress(f.b[1].owner, true)
		await expect(f.context.partyBOpenFacet.connect(f.b[1].signer).fillOpenIntent(intent.id, e(4), e(10))).to.revert(ethers)
		await expect(f.context.accountFacet.connect(f.b[2].signer)[DEPOSIT](2, f.token, e(1))).to.revert(ethers)
	})

	it("enforces bucket-local suspension through legacy zero-bucket adapters while sibling buckets remain usable", async function () {
		const account = f.context.accountFacet.connect(f.a[0].signer),
			control = f.context.controlFacet
		await control.suspendBucket(f.a[0].owner, 0, true)
		const zero = await snapshot(f, f.a[0], f.b[0])
		for (const call of [
			() => account["deposit(address,uint256)"](f.token, e(1)),
			() => account["allocate(address,address,uint256)"](f.token, f.b[0].owner, e(1)),
			() => account["initiateWithdraw(address,uint256,address)"](f.token, e(1), f.a[0].owner),
		])
			await expect(call()).to.be.revertedWithCustomError(account, "UserSuspended").withArgs(f.a[0].owner)
		expect(await snapshot(f, f.a[0], f.b[0])).to.deep.equal(zero)
		await account[DEPOSIT](1, f.token, e(1))
		await allocate(f, f.a[1], f.b[1], e(1))
		await control.suspendBucket(f.a[0].owner, 0, false)
		await control.suspendBucket(f.a[1].owner, 1, true)
		await account["deposit(address,uint256)"](f.token, e(1))
		await expect(account[DEPOSIT](1, f.token, e(1)))
			.to.be.revertedWithCustomError(account, "UserSuspended")
			.withArgs(f.a[1].owner)
		await control.suspendBucket(f.a[1].owner, 1, false)
		await control.suspendAddress(f.a[0].owner, true)
		await expect(account["deposit(address,uint256)"](f.token, e(1)))
			.to.be.revertedWithCustomError(account, "UserSuspended")
			.withArgs(f.a[0].owner)
		await expect(account[DEPOSIT](1, f.token, e(1)))
			.to.be.revertedWithCustomError(account, "UserSuspended")
			.withArgs(f.a[1].owner)
		await assertConservation(f)
	})

	it("applies solver emergency status to selected bucket IDs and global wallet policy", async function () {
		await fund(f, f.a[1], f.b[1])
		await fund(f, f.a[2], f.b[2])
		const first = await send(f, f.a[1], f.b[1]),
			second = await send(f, f.a[2], f.b[2])
		await f.context.controlFacet["activePartyBEmergencyMode(address,uint256)"](f.b[1].owner, 1)
		await expect(f.context.partyBOpenFacet.connect(f.b[1].signer).lockOpenIntent(first.id))
			.to.be.revertedWithCustomError(f.context.partyBOpenFacet, "PartyBInEmergencyMode")
			.withArgs(f.b[1].owner)
		await f.context.partyBOpenFacet.connect(f.b[2].signer).lockOpenIntent(second.id)
		await f.context.controlFacet["deactivePartyBEmergencyMode(address,uint256)"](f.b[1].owner, 1)
		await f.context.controlFacet["activePartyBEmergencyMode(address)"](f.b[1].owner)
		await expect(f.context.partyBOpenFacet.connect(f.b[1].signer).lockOpenIntent(first.id))
			.to.be.revertedWithCustomError(f.context.partyBOpenFacet, "PartyBInEmergencyMode")
			.withArgs(f.b[1].owner)
		await expect(f.context.partyBOpenFacet.connect(f.b[2].signer).fillOpenIntent(second.id, e(4), e(10)))
			.to.be.revertedWithCustomError(f.context.partyBOpenFacet, "PartyBInEmergencyMode")
			.withArgs(f.b[2].owner)
		await assertConservation(f)
	})

	it("applies bucket-zero suspension to old relationship adapters while sibling binding remains available", async function () {
		const relation = f.context.counterPartyRelation.connect(f.a[0].signer)
		await f.context.controlFacet.suspendBucket(f.a[0].owner, 0, true)
		await expect(relation["bindToPartyB(address)"](f.b[0].owner)).to.be.revertedWithCustomError(relation, "UserSuspended").withArgs(f.a[0].owner)
		await relation["bindToPartyB(uint256,address,uint256)"](1, f.b[1].owner, 1)
		const bound = await f.context.viewFacet["getBoundPartyB(address,uint256)"](f.a[1].owner, 1)
		expect([bound.partyB, bound.partyBBucketId]).to.deep.equal([f.b[1].owner, 1n])
		await f.context.controlFacet.suspendBucket(f.a[0].owner, 0, false)
		await relation["bindToPartyB(address)"](f.b[0].owner)
		await f.context.controlFacet.suspendBucket(f.a[0].owner, 0, true)
		await expect(relation["initiateUnbindingFromPartyB()"]()).to.be.revertedWithCustomError(relation, "UserSuspended").withArgs(f.a[0].owner)
		await relation["initiateUnbindingFromPartyB(uint256)"](1)
	})

	it("protects isolated intent reservations from both legacy and explicit-zero external transfers", async function () {
		const hooks = await (await ethers.getContractFactory("NativeBucketHooks")).deploy(),
			target = await hooks.getAddress()
		await f.context.controlFacet.grantRole(f.context.signers.admin.address, keccak256(toUtf8Bytes("EXTERNAL_TRANSFER_TARGET_MANAGER_ROLE")))
		await f.context.controlFacet.setExternalTransferTargetValidationStatus(target, f.token, true)
		const r = await request(f, f.b[0], { marginType: MarginType.ISOLATED })
		await f.context.partyAOpenFacet
			.connect(f.a[0].signer)
			[
				"sendOpenIntent(address[],uint256,uint256,uint256,uint256,uint256,uint256,uint8,uint8,(uint256,uint256),(uint256,uint256),uint256,address,address,bytes)"
			](
				r.partyBsWhiteList,
				r.symbolId,
				r.price,
				r.quantity,
				r.strikePrice,
				r.expirationTimestamp,
				r.mm,
				r.tradeSide,
				r.marginType,
				r.exerciseFee,
				r.solverFee,
				r.deadline,
				r.feeToken,
				r.affiliate,
				r.userData,
			)
		const balance = await f.context.viewFacet[ISOLATED](f.a[0].owner, 0, f.token),
			locked = await f.context.viewFacet["getIsolatedLockedBalance(address,uint256,address)"](f.a[0].owner, 0, f.token)
		expect(locked).to.be.greaterThan(0n)
		const amount = balance - locked + 1n,
			account = f.context.accountFacet.connect(f.a[0].signer)
		await expect(account["externalTransfer(address,address,uint256,address)"](f.token, f.a[0].owner, amount, target))
			.to.be.revertedWithCustomError(account, "InsufficientBalance")
			.withArgs(f.a[0].owner, f.token, amount, balance - locked)
		await expect(account["externalTransfer(uint256,address,address,uint256,address)"](0, f.token, f.a[0].owner, amount, target))
			.to.be.revertedWithCustomError(account, "InsufficientBalance")
			.withArgs(f.a[0].owner, f.token, amount, balance - locked)
		expect(await f.context.viewFacet[ISOLATED](f.a[0].owner, 0, f.token)).to.equal(balance)
		expect(await f.context.collateral.balanceOf(target)).to.equal(0)
		await account["externalTransfer(uint256,address,address,uint256,address)"](1, f.token, f.a[0].owner, e(1), target)
		expect(await f.context.viewFacet[ISOLATED](f.a[1].owner, 1, f.token)).to.equal(e(9999))
		await assertConservation(f)
	})

	it("blocks external transfers from an isolated-liquidating solver bucket without freezing sibling bucket funds", async function () {
		const hooks = await (await ethers.getContractFactory("NativeBucketHooks")).deploy(),
			target = await hooks.getAddress()
		await f.context.controlFacet.grantRole(f.context.signers.admin.address, keccak256(toUtf8Bytes("EXTERNAL_TRANSFER_TARGET_MANAGER_ROLE")))
		await f.context.controlFacet.setExternalTransferTargetValidationStatus(target, f.token, true)
		await f.context.controlFacet.setPartyBConfig(f.b[0].owner, { isActive: true, lossCoverage: e(1), oracleId: 1 })
		await f.context.clearingHouse.connect(f.context.signers.clearingHouse).flagIsolatedPartyBLiquidation(f.b[0].owner, f.token)
		const account = f.context.accountFacet.connect(f.b[0].signer)
		await expect(account["externalTransfer(address,address,uint256,address)"](f.token, f.b[0].owner, e(1), target))
			.to.be.revertedWithCustomError(account, "NotSolvent")
			.withArgs(f.b[0].owner, ZeroAddress, f.token, MarginType.ISOLATED)
		await expect(account["externalTransfer(uint256,address,address,uint256,address)"](0, f.token, f.b[0].owner, e(1), target))
			.to.be.revertedWithCustomError(account, "NotSolvent")
			.withArgs(f.b[0].owner, ZeroAddress, f.token, MarginType.ISOLATED)
		await account["externalTransfer(uint256,address,address,uint256,address)"](1, f.token, f.b[0].owner, e(1), target)
		expect(await f.context.viewFacet[ISOLATED](f.b[0].owner, 0, f.token)).to.equal(e(10000))
		expect(await f.context.viewFacet[ISOLATED](f.b[1].owner, 1, f.token)).to.equal(e(9999))
		await assertConservation(f)
	})

	it("pins a native relationship even when both explicit bucket IDs are zero", async function () {
		await fund(f, f.a[0], f.b[0])
		await expect(send(f, f.a[0], f.b[0], { marginType: MarginType.ISOLATED })).to.revert(ethers)
		const intent = await send(f, f.a[0], f.b[0])
		const trade = await fill(f, f.b[0], intent.id)
		expect((await f.context.viewFacet.getTrade(trade)).relationshipId).to.be.greaterThan(0n)
		await expect(f.context.tradeFacet.connect(f.a[0].signer).transferTrade(f.context.signers.partyA2.address, trade)).to.revert(ethers)
		await expect(f.context.tradeFacet.connect(f.a[0].signer).mintNFTForTrade(trade)).to.revert(ethers)
	})

	for (const [aIndex, bIndex] of [
		[0, 1],
		[1, 0],
		[1, 2],
	] as const) {
		it(`uses immutable wallet/bucket tuples through mixed ${aIndex}/${bIndex} funding, acceptance and closing`, async function () {
			const a = f.a[aIndex],
				b = f.b[bIndex]
			await fund(f, a, b)
			const sibling = await snapshot(f, f.a[3], f.b[3])
			const intent = await send(f, a, b)
			const tradeId = await fill(f, b, intent.id)
			const trade = await f.context.viewFacet.getTrade(tradeId)
			expect([trade.partyA, trade.partyABucketId, trade.partyB, trade.partyBBucketId]).to.deep.equal([
				a.owner,
				BigInt(a.bucketId),
				b.owner,
				BigInt(b.bucketId),
			])
			const relationId = await f.bucket.getRelationshipId(a.owner, a.bucketId, b.owner, b.bucketId)
			expect(trade.relationshipId).to.equal(relationId)
			expect(await f.bucket.getIntentRelationship(intent.id)).to.equal(relationId)
			const relation = await f.bucket.getRelationship(relationId)
			expect([relation.partyA, relation.partyABucketId, relation.partyB, relation.partyBBucketId, relation.exists]).to.deep.equal([
				a.owner,
				BigInt(a.bucketId),
				b.owner,
				BigInt(b.bucketId),
				true,
			])
			await expect(
				f.context.partyACloseFacet.connect(f.context.signers.partyA2).sendCloseIntent(tradeId, e(1), e(10), (await getLatestBlockTime()) + 120),
			).to.revert(ethers)
			await f.context.partyACloseFacet.connect(a.signer).sendCloseIntent(tradeId, e(4), e(12), (await getLatestBlockTime()) + 120)
			const close = await f.context.viewFacet.getLastCloseIntentId()
			await expect(f.context.partyBCloseFacet.connect(f.context.signers.partyB2).fillCloseIntent(close, e(4), e(12))).to.revert(ethers)
			await f.context.partyBCloseFacet.connect(b.signer).fillCloseIntent(close, e(4), e(12))
			expect((await f.context.viewFacet.getTrade(tradeId)).status).to.equal(TradeStatus.CLOSED)
			expect(await snapshot(f, f.a[3], f.b[3])).to.deep.equal(sibling)
			await assertConservation(f)
		})
	}

	it("runs simultaneous same-wallet relationships and never redirects stored buckets during lifecycle calls", async function () {
		await fund(f, f.a[1], f.b[1])
		await fund(f, f.a[2], f.b[2])
		const first = await send(f, f.a[1], f.b[1]),
			second = await send(f, f.a[2], f.b[2])
		await expect(f.context.partyAOpenFacet.connect(f.context.signers.partyA2).cancelOpenIntent([first.id])).to.revert(ethers)
		await expect(f.context.partyBOpenFacet.connect(f.context.signers.partyB2).lockOpenIntent(first.id)).to.revert(ethers)
		const firstTrade = await fill(f, f.b[1], first.id),
			secondTrade = await fill(f, f.b[2], second.id)
		expect(await f.bucket.getTradeRelationship(firstTrade)).not.to.equal(await f.bucket.getTradeRelationship(secondTrade))
		const sibling = await snapshot(f, f.a[2], f.b[2])
		await f.context.partyACloseFacet.connect(f.a[1].signer).sendCloseIntent(firstTrade, e(1), e(10), (await getLatestBlockTime()) + 120)
		await f.context.partyBCloseFacet.connect(f.b[1].signer).fillCloseIntent(await f.context.viewFacet.getLastCloseIntentId(), e(1), e(10))
		expect(await snapshot(f, f.a[2], f.b[2])).to.deep.equal(sibling)
		await assertConservation(f)
	})

	it("divides one user's bucket across relationships and rejects double allocation and cumulative commitments", async function () {
		await allocate(f, f.a[1], f.b[1], e(6000))
		await allocate(f, f.a[1], f.b[2], e(4000))
		await allocate(f, f.b[1], f.a[1])
		await allocate(f, f.b[2], f.a[1])
		await expect(allocate(f, f.a[1], f.b[2], e(1))).to.revert(ethers)
		await send(f, f.a[1], f.b[2], { quantity: e(300) })
		const sibling = await snapshot(f, f.a[1], f.b[1]),
			before = await snapshot(f, f.a[1], f.b[2])
		await expect(send(f, f.a[1], f.b[2], { quantity: e(100) }))
			.to.be.revertedWithCustomError(f.context.partyAOpenFacet, "NativeBackingInsufficient")
			.withArgs(f.a[1].owner, 1, f.b[2].owner, 2, f.token)
		expect(await snapshot(f, f.a[1], f.b[1])).to.deep.equal(sibling)
		expect(await snapshot(f, f.a[1], f.b[2])).to.deep.equal(before)
		await assertBacking(f, f.a[1], f.b[2])
		await assertConservation(f)
	})

	it("transfers only free solver funds between local buckets, preserving committed relationship collateral", async function () {
		await allocate(f, f.b[1], f.a[1], e(6000))
		await f.bucket.connect(f.b[1].signer).transferBetweenBuckets(1, 2, f.token, e(4000))
		expect(await f.context.viewFacet[ISOLATED](f.b[1].owner, 1, f.token)).to.equal(0)
		expect(await f.context.viewFacet[ISOLATED](f.b[2].owner, 2, f.token)).to.equal(e(14000))
		expect((await cross(f, f.b[1], f.a[1])).balance).to.equal(e(6000))
		await expect(f.bucket.connect(f.b[1].signer).transferBetweenBuckets(1, 2, f.token, e(1))).to.revert(ethers)
		await assertConservation(f)
	})

	it("normalizes six-decimal collateral while token deposits charge the real wallet", async function () {
		const token = await (await ethers.getContractFactory("NativeBucketSixDecimalToken")).deploy()
		const address = await token.getAddress()
		await f.context.controlFacet.whiteListCollateral(address)
		await f.context.controlFacet.setBalanceLimitPerUser(address, e(1000))
		await token.mint(f.a[1].owner, 1234567)
		await token.connect(f.a[1].signer).approve(f.context.common.diamondAddress, MaxUint256)
		await f.context.accountFacet.connect(f.a[1].signer)[DEPOSIT](1, address, 1234567)
		expect(await f.context.viewFacet[ISOLATED](f.a[1].owner, 1, address)).to.equal(1234567n * 10n ** 12n)
		expect(await token.balanceOf(f.a[1].owner)).to.equal(0)
		await assertConservation(f, address)
		await f.context.accountFacet.connect(f.a[1].signer)[WITHDRAW](1, address, 234567n * 10n ** 12n, f.a[1].owner)
		const id = await f.context.viewFacet.getLastWithdrawalId()
		await assertConservation(f, address)
		await networkHelpers.time.increase(1000)
		await f.context.accountFacet.completeWithdraw(id)
		expect(await token.balanceOf(f.a[1].owner)).to.equal(234567)
		await assertConservation(f, address)
	})

	it("keeps alternate fee-token funding in the same immutable SELL relationship tuple", async function () {
		const feeToken = await f.context.collateralNL.getAddress()
		await fund(f, f.a[1], f.b[1])
		for (const actor of [f.a[1], f.b[1]]) {
			await f.context.collateralNL.mint(actor.owner, e(1000))
			await f.context.collateralNL.connect(actor.signer).approve(f.context.common.diamondAddress, MaxUint256)
			await f.context.accountFacet.connect(actor.signer)[DEPOSIT](actor.bucketId, feeToken, e(1000))
		}
		await allocate(f, f.a[1], f.b[1], e(500), feeToken)
		await allocate(f, f.b[1], f.a[1], e(500), feeToken)
		const sibling = await snapshot(f, f.a[2], f.b[2])
		const intent = await send(f, f.a[1], f.b[1], { tradeSide: TradeSide.SELL, feeToken })
		const trade = await fill(f, f.b[1], intent.id)
		expect((await cross(f, f.a[1], f.b[1])).totalMM).to.equal(e(8))
		await assertConservation(f)
		await assertConservation(f, feeToken)
		await f.context.partyACloseFacet.connect(f.a[1].signer).sendCloseIntent(trade, e(4), e(12), (await getLatestBlockTime()) + 120)
		await f.context.partyBCloseFacet.connect(f.b[1].signer).fillCloseIntent(await f.context.viewFacet.getLastCloseIntentId(), e(4), e(12))
		expect((await cross(f, f.a[1], f.b[1])).totalMM).to.equal(0)
		expect(await snapshot(f, f.a[2], f.b[2])).to.deep.equal(sibling)
		await assertConservation(f)
		await assertConservation(f, feeToken)
	})

	it("pins partial-fill residuals and releases cancellation and expiry locks into the original bucket", async function () {
		await fund(f, f.a[1], f.b[1])
		const sibling = await snapshot(f, f.a[2], f.b[2])
		const intent = await send(f, f.a[1], f.b[1]),
			trade = await fill(f, f.b[1], intent.id, e(1))
		const childId = await f.context.viewFacet.getLastOpenIntentId(),
			child = await f.context.viewFacet.getOpenIntent(childId)
		expect([child.partyA, child.partyABucketId, child.partyBBucketId]).to.deep.equal([f.a[1].owner, 1n, 1n])
		expect(child.relationshipId).to.equal(await f.bucket.getTradeRelationship(trade))
		await f.context.partyAOpenFacet.connect(f.a[1].signer).cancelOpenIntent([childId])
		expect((await cross(f, f.a[1], f.b[1])).locked).to.equal(0)
		const expiry = await send(f, f.a[1], f.b[1], { deadline: (await getLatestBlockTime()) + 10 })
		await networkHelpers.time.increase(11)
		await f.context.partyAOpenFacet.connect(f.context.signers.others[0]).expireOpenIntent([expiry.id])
		expect((await f.context.viewFacet.getOpenIntent(expiry.id)).status).to.equal(IntentStatus.EXPIRED)
		expect(await snapshot(f, f.a[2], f.b[2])).to.deep.equal(sibling)
		await assertConservation(f)
	})

	for (const side of [TradeSide.BUY, TradeSide.SELL])
		it(`releases canceled ${TradeSide[side]} residuals after cancellation-pending partial fills`, async function () {
			await fund(f, f.a[1], f.b[1])
			await fund(f, f.a[2], f.b[2])
			const sibling = await snapshot(f, f.a[2], f.b[2]),
				intent = await send(f, f.a[1], f.b[1], { tradeSide: side })
			await f.context.partyBOpenFacet.connect(f.b[1].signer).lockOpenIntent(intent.id)
			await f.context.partyAOpenFacet.connect(f.a[1].signer).cancelOpenIntent([intent.id])
			await f.context.partyBOpenFacet.connect(f.b[1].signer).fillOpenIntent(intent.id, e(1), e(10))
			const child = await f.context.viewFacet.getOpenIntent(await f.context.viewFacet.getLastOpenIntentId())
			expect(child.status).to.equal(IntentStatus.CANCELED)
			expect(child.relationshipId).to.equal(await f.bucket.getTradeRelationship(await f.context.viewFacet.getLastTradeId()))
			const entry = await cross(f, f.a[1], f.b[1])
			expect(entry.locked).to.equal(0)
			expect(entry.totalMM).to.equal(side === TradeSide.SELL ? e(2) : 0)
			expect(entry.balance).to.equal(e(5000) + (side === TradeSide.SELL ? e(10) : -e(10)) - e(0.3))
			expect(await snapshot(f, f.a[2], f.b[2])).to.deep.equal(sibling)
			await assertBacking(f, f.a[1], f.b[1])
			await assertConservation(f)
		})

	it("withdraws only free funds and refunds cancellation into the immutable recorded bucket", async function () {
		await fund(f, f.a[1], f.b[1], e(10000))
		await send(f, f.a[1], f.b[1])
		await expect(f.context.accountFacet.connect(f.a[1].signer)[WITHDRAW](1, f.token, e(1), f.a[1].owner)).to.revert(ethers)
		await f.context.accountFacet.connect(f.a[2].signer)[WITHDRAW](2, f.token, e(123), f.a[2].owner)
		const id = await f.context.viewFacet.getLastWithdrawalId(),
			withdrawal = await f.context.viewFacet.getWithdrawal(id)
		expect([withdrawal.user, withdrawal.bucketId, withdrawal.to]).to.deep.equal([f.a[2].owner, 2n, f.a[2].owner])
		await f.context.accountFacet.cancelWithdraw(id)
		expect(await f.context.viewFacet[ISOLATED](f.a[2].owner, 2, f.token)).to.equal(e(10000))
		expect(await f.context.viewFacet[ISOLATED](f.a[1].owner, 1, f.token)).to.equal(0)
		await assertConservation(f)
	})

	it("settles permissionlessly at maturity without changing sibling buckets or paying twice", async function () {
		await fund(f, f.a[1], f.b[1])
		await fund(f, f.a[2], f.b[2])
		const first = await send(f, f.a[1], f.b[1]),
			second = await send(f, f.a[2], f.b[2])
		const trade = await fill(f, f.b[1], first.id)
		await fill(f, f.b[2], second.id)
		const sibling = await snapshot(f, f.a[2], f.b[2])
		await networkHelpers.time.increaseTo(BigInt(first.request.expirationTimestamp.toString()) + 1n)
		const sig = settlementSigBuilder()
			.timestamp(await getLatestBlockTime())
			.settlementPrice(e(100))
			.collateralPrice(e(1))
			.build()
		await f.context.tradeFacet.connect(f.context.signers.others[0]).executeTrades([trade], sig)
		expect((await f.context.viewFacet.getTrade(trade)).status).to.equal(TradeStatus.EXPIRED)
		expect(await snapshot(f, f.a[2], f.b[2])).to.deep.equal(sibling)
		const settled = await snapshot(f, f.a[1], f.b[1])
		await f.context.tradeFacet.executeTrades([trade], sig)
		expect(await snapshot(f, f.a[1], f.b[1])).to.deep.equal(settled)
		await assertConservation(f)
	})

	for (const [aIndex, bIndex] of [
		[0, 0],
		[0, 1],
		[1, 0],
		[1, 2],
	] as const)
		it(`liquidates only the ${aIndex}/${bIndex} relationship and leaves same-wallet sibling buckets trading`, async function () {
			const a = f.a[aIndex],
				b = f.b[bIndex],
				siblingA = f.a[3],
				siblingB = f.b[3]
			await f.context.controlFacet.setPartyBConfig(b.owner, { isActive: true, lossCoverage: e(1), oracleId: 1 })
			await fund(f, a, b)
			await fund(f, siblingA, siblingB)
			const first = await send(f, a, b),
				firstTrade = await fill(f, b, first.id)
			const siblingBefore = await snapshot(f, siblingA, siblingB)
			const clearing = f.context.clearingHouse.connect(f.context.signers.clearingHouse)
			await clearing["flagCrossPartyBLiquidation(address,uint256,address,uint256,address)"](b.owner, b.bucketId, a.owner, a.bucketId, f.token)
			await clearing["liquidateCrossPartyB(address,uint256,address,uint256,address,int256,uint256)"](
				b.owner,
				b.bucketId,
				a.owner,
				a.bucketId,
				f.token,
				e(-10000),
				e(1),
			)
			const id = await f.context.viewFacet["getInProgressLiquidationId(address,uint256,address,uint256,address)"](
				a.owner,
				a.bucketId,
				b.owner,
				b.bucketId,
				f.token,
			)
			expect(id).to.be.greaterThan(0n)
			expect(
				await f.context.viewFacet["getInProgressLiquidationId(address,uint256,address,uint256,address)"](
					siblingA.owner,
					siblingA.bucketId,
					siblingB.owner,
					siblingB.bucketId,
					f.token,
				),
			).to.equal(0)
			expect(await snapshot(f, siblingA, siblingB)).to.deep.equal(siblingBefore)
			const second = await send(f, siblingA, siblingB),
				secondTrade = await fill(f, siblingB, second.id)
			await expect(clearing.closeTrades(id, [secondTrade], [e(10)])).to.be.revertedWithCustomError(clearing, "TradeNotInLiquidation")
			await clearing.closeTrades(id, [firstTrade], [e(10)])
			expect((await f.context.viewFacet.getTrade(firstTrade)).status).to.equal(TradeStatus.LIQUIDATED)
			expect((await f.context.viewFacet.getTrade(secondTrade)).status).to.equal(TradeStatus.OPENED)
			await assertConservation(f)
		})

	it("infers user liquidation buckets from the stored detail and closes only the pinned SELL relationship", async function () {
		const a = f.a[1],
			b = f.b[2]
		await fund(f, a, b)
		await fund(f, f.a[2], f.b[1])
		const intent = await send(f, a, b, { tradeSide: TradeSide.SELL }),
			trade = await fill(f, b, intent.id)
		const sibling = await snapshot(f, f.a[2], f.b[1]),
			clearing = f.context.clearingHouse.connect(f.context.signers.clearingHouse)
		await clearing["flagPartyALiquidation(address,uint256,address,uint256,address)"](a.owner, a.bucketId, b.owner, b.bucketId, f.token)
		const id = await f.context.viewFacet["getInProgressLiquidationId(address,uint256,address,uint256,address)"](
			a.owner,
			a.bucketId,
			b.owner,
			b.bucketId,
			f.token,
		)
		await clearing.liquidateCrossPartyA(id, a.owner, b.owner, f.token, e(-10000), e(1))
		await clearing.closeTrades(id, [trade], [e(10)])
		expect((await f.context.viewFacet.getTrade(trade)).status).to.equal(TradeStatus.LIQUIDATED)
		expect((await cross(f, a, b)).totalMM).to.equal(0)
		expect(await snapshot(f, f.a[2], f.b[1])).to.deep.equal(sibling)
		await assertConservation(f)
	})

	for (const aIndex of [0, 1] as const)
		it(`rejects legacy wildcard isolated liquidation closing a native ${aIndex}/0 trade`, async function () {
			const a = f.a[aIndex],
				b = f.b[0]
			await f.context.controlFacet.setPartyBConfig(b.owner, { isActive: true, lossCoverage: e(1), oracleId: 1 })
			await fund(f, a, b)
			await fund(f, f.a[2], f.b[2])
			const intent = await send(f, a, b),
				trade = await fill(f, b, intent.id),
				clearing = f.context.clearingHouse.connect(f.context.signers.clearingHouse)
			await clearing.flagIsolatedPartyBLiquidation(b.owner, f.token)
			await clearing.liquidateIsolatedPartyB(b.owner, f.token, e(-20000), e(1))
			const id = await f.context.viewFacet["getInProgressLiquidationId(address,address,address)"](ZeroAddress, b.owner, f.token)
			const before = await snapshot(f, a, b),
				sibling = await snapshot(f, f.a[2], f.b[2])
			await expect(clearing.closeTrades(id, [trade], [e(10)]))
				.to.be.revertedWithCustomError(clearing, "TradeNotInLiquidation")
				.withArgs(id, trade)
			expect((await f.context.viewFacet.getTrade(trade)).status).to.equal(TradeStatus.OPENED)
			expect(await snapshot(f, a, b)).to.deep.equal(before)
			expect(await snapshot(f, f.a[2], f.b[2])).to.deep.equal(sibling)
			await assertConservation(f)
		})

	for (const bucketIndex of [0, 1] as const)
		it(`confines native ${bucketIndex}/${bucketIndex} confiscation and distribution to the recorded pair, buckets and token`, async function () {
			const a = f.a[bucketIndex],
				b = f.b[bucketIndex]
			await f.context.controlFacet.setPartyBConfig(b.owner, { isActive: true, lossCoverage: e(1), oracleId: 1 })
			await fund(f, a, b)
			await fund(f, f.a[2], f.b[2])
			const intent = await send(f, a, b)
			await fill(f, b, intent.id)
			const clearing = f.context.clearingHouse.connect(f.context.signers.clearingHouse)
			await clearing["flagCrossPartyBLiquidation(address,uint256,address,uint256,address)"](b.owner, b.bucketId, a.owner, a.bucketId, f.token)
			await clearing["liquidateCrossPartyB(address,uint256,address,uint256,address,int256,uint256)"](
				b.owner,
				b.bucketId,
				a.owner,
				a.bucketId,
				f.token,
				e(-10000),
				e(1),
			)
			const id = await f.context.viewFacet["getInProgressLiquidationId(address,uint256,address,uint256,address)"](
				a.owner,
				a.bucketId,
				b.owner,
				b.bucketId,
				f.token,
			)
			const before = await snapshot(f, a, b),
				sibling = await snapshot(f, f.a[2], f.b[2])
			const detail = await f.context.viewFacet.getLiquidationDetail(id)
			expect([detail.partyABucketId, detail.partyBBucketId, detail.isBucketLiquidation]).to.deep.equal([BigInt(a.bucketId), BigInt(b.bucketId), true])
			const confiscate = "confiscate(uint256,address,uint256,address[],uint256[],uint256[],uint8)" as const
			const distribute = "distributeCollateral(uint256,address,uint256,address,uint8,address[],uint256[],uint256[])" as const
			for (const [owner, bucketId, cp, cpBucketId, margin] of [
				[a.owner, 2, b.owner, b.bucketId, MarginType.CROSS],
				[a.owner, a.bucketId, b.owner, 2, MarginType.CROSS],
				[a.owner, a.bucketId, f.context.signers.partyB2.address, b.bucketId, MarginType.CROSS],
				[a.owner, a.bucketId, b.owner, b.bucketId, MarginType.ISOLATED],
			] as const)
				await expect(clearing[confiscate](id, owner, bucketId, [cp], [cpBucketId], [e(1)], margin))
					.to.be.revertedWithCustomError(clearing, "LiquidationScopeMismatch")
					.withArgs(id)
			if (bucketIndex !== 0)
				await expect(clearing["confiscate(uint256,address,address[],uint256[],uint8)"](id, a.owner, [b.owner], [e(1)], MarginType.CROSS))
					.to.be.revertedWithCustomError(clearing, "LiquidationScopeMismatch")
					.withArgs(id)
			expect(await snapshot(f, a, b)).to.deep.equal(before)
			expect((await f.context.viewFacet.getLiquidationDetail(id)).confiscatedAmount).to.equal(0)
			await clearing[confiscate](id, a.owner, a.bucketId, [b.owner], [b.bucketId], [e(10)], MarginType.CROSS)
			const afterConfiscate = await snapshot(f, a, b)
			for (const [owner, bucketId, token, receiver, receiverBucketId, margin] of [
				[b.owner, 2, f.token, a.owner, a.bucketId, MarginType.CROSS],
				[b.owner, b.bucketId, f.token, a.owner, 2, MarginType.CROSS],
				[b.owner, b.bucketId, await f.context.collateralNL.getAddress(), a.owner, a.bucketId, MarginType.CROSS],
				[b.owner, b.bucketId, f.token, f.context.signers.partyA2.address, a.bucketId, MarginType.CROSS],
				[b.owner, b.bucketId, f.token, a.owner, a.bucketId, MarginType.ISOLATED],
			] as const)
				await expect(clearing[distribute](id, owner, bucketId, token, margin, [receiver], [receiverBucketId], [e(1)]))
					.to.be.revertedWithCustomError(clearing, "LiquidationScopeMismatch")
					.withArgs(id)
			if (bucketIndex !== 0)
				await expect(
					clearing["distributeCollateral(uint256,address,address,uint8,address[],uint256[])"](
						id,
						b.owner,
						f.token,
						MarginType.CROSS,
						[a.owner],
						[e(1)],
					),
				)
					.to.be.revertedWithCustomError(clearing, "LiquidationScopeMismatch")
					.withArgs(id)
			expect(await snapshot(f, a, b)).to.deep.equal(afterConfiscate)
			expect((await f.context.viewFacet.getLiquidationDetail(id)).distributedAmount).to.equal(0)
			await clearing[distribute](id, b.owner, b.bucketId, f.token, MarginType.CROSS, [a.owner], [a.bucketId], [e(10)])
			expect((await f.context.viewFacet.getLiquidationDetail(id)).distributedAmount).to.equal(e(10))
			expect(await snapshot(f, f.a[2], f.b[2])).to.deep.equal(sibling)
			await assertConservation(f)
		})

	for (const [aIndex, bIndex] of [
		[0, 0],
		[0, 1],
		[1, 0],
		[1, 2],
	] as const)
		it(`scopes ${aIndex}/${bIndex} oracle attestations and nonces to exact wallet/bucket tuples`, async function () {
			const a = f.a[aIndex],
				b = f.b[bIndex],
				oracle = await (await ethers.getContractFactory("NativeBucketStrictOracle")).deploy()
			await f.context.controlFacet.updateOracle(1, await oracle.getAddress())
			await fund(f, a, b)
			const sig = await strictSig(f, oracle, a, b)
			await deallocate(f, a, b, sig)
			const sibling = await snapshot(f, f.a[3], f.b[3])
			const intent = await send(f, a, b)
			await fill(f, b, intent.id)
			await expect(deallocate(f, a, b, sig)).to.be.revertedWithCustomError(oracle, "UnexpectedOracleHash")
			expect(await snapshot(f, f.a[3], f.b[3])).to.deep.equal(sibling)
			await deallocate(f, a, b, await strictSig(f, oracle, a, b))
			await assertConservation(f)
		})

	it("rejects altered bucket IDs, oracle fields, wallet-only digests, wrong domains and expired attestations", async function () {
		const oracle = await (await ethers.getContractFactory("NativeBucketStrictOracle")).deploy()
		await f.context.controlFacet.updateOracle(1, await oracle.getAddress())
		await fund(f, f.a[1], f.b[1])
		await fund(f, f.a[2], f.b[2])
		const sig = await strictSig(f, oracle, f.a[1], f.b[1])
		await expect(deallocate(f, f.a[2], f.b[1], sig)).to.be.revertedWithCustomError(oracle, "UnexpectedOracleHash")
		await expect(deallocate(f, f.a[1], f.b[2], sig)).to.be.revertedWithCustomError(oracle, "UnexpectedOracleHash")
		for (const changed of [
			{ ...sig, reqId: "0xabcd" },
			{ ...sig, partyUpnl: e(1) },
			{ ...sig, counterPartyUpnl: e(1) },
			{ ...sig, collateralPrice: e(2) },
			{ ...sig, timestamp: Number(sig.timestamp) + 1 },
		]) {
			await expect(deallocate(f, f.a[1], f.b[1], changed)).to.be.revertedWithCustomError(oracle, "UnexpectedOracleHash")
		}
		for (const domain of [{ omitBuckets: true }, { contract: ZeroAddress }, { chainId: f.context.common.chainId + 1 }]) {
			await expect(deallocate(f, f.a[1], f.b[1], await strictSig(f, oracle, f.a[1], f.b[1], domain))).to.be.revertedWithCustomError(
				oracle,
				"UnexpectedOracleHash",
			)
		}
		const expired = await strictSig(f, oracle, f.a[1], f.b[1])
		await networkHelpers.time.increase(301)
		await expect(deallocate(f, f.a[1], f.b[1], expired)).to.be.revertedWithCustomError(f.context.accountFacet, "ExpiredSignature")
	})

	it("rejects unfunded SELL margin and alternate-token fees before creating an intent", async function () {
		await fund(f, f.a[1], f.b[1], e(100))
		const before = await snapshot(f, f.a[1], f.b[1]),
			sibling = await snapshot(f, f.a[2], f.b[2])
		await expect(send(f, f.a[1], f.b[1], { tradeSide: TradeSide.SELL, quantity: e(1), mm: e(101) }))
			.to.be.revertedWithCustomError(f.context.partyAOpenFacet, "NativeBackingInsufficient")
			.withArgs(f.a[1].owner, 1, f.b[1].owner, 1, f.token)
		const feeToken = await f.context.collateralNL.getAddress()
		await expect(send(f, f.a[1], f.b[1], { tradeSide: TradeSide.SELL, quantity: e(1), mm: e(2), feeToken }))
			.to.be.revertedWithCustomError(f.context.partyAOpenFacet, "NativeBackingInsufficient")
			.withArgs(f.a[1].owner, 1, f.b[1].owner, 1, feeToken)
		expect(await snapshot(f, f.a[1], f.b[1])).to.deep.equal(before)
		expect(await snapshot(f, f.a[2], f.b[2])).to.deep.equal(sibling)
		await assertBacking(f, f.a[1], f.b[1])
		await assertConservation(f)
	})

	it("rejects oversized SELL fills while allowing a funded partial fill at the same price", async function () {
		await allocate(f, f.a[1], f.b[1])
		await allocate(f, f.b[1], f.a[1], e(100))
		await allocate(f, f.b[1], f.a[2])
		const intent = await send(f, f.a[1], f.b[1], { tradeSide: TradeSide.SELL, quantity: e(1), mm: e(2) })
		await f.context.partyBOpenFacet.connect(f.b[1].signer).lockOpenIntent(intent.id)
		const before = await snapshot(f, f.a[1], f.b[1]),
			sibling = await snapshot(f, f.a[2], f.b[1])
		await expect(f.context.partyBOpenFacet.connect(f.b[1].signer).fillOpenIntent(intent.id, e(1), e(200)))
			.to.be.revertedWithCustomError(f.context.partyBOpenFacet, "NativeBackingInsufficient")
			.withArgs(f.b[1].owner, 1, f.a[1].owner, 1, f.token)
		expect(await snapshot(f, f.a[1], f.b[1])).to.deep.equal(before)
		expect(await snapshot(f, f.a[2], f.b[1])).to.deep.equal(sibling)
		await f.context.partyBOpenFacet.connect(f.b[1].signer).fillOpenIntent(intent.id, e(0.25), e(200))
		expect((await f.context.viewFacet.getTrade(await f.context.viewFacet.getLastTradeId())).tradeAgreements.quantity).to.equal(e(0.25))
		expect((await f.context.viewFacet.getOpenIntent(await f.context.viewFacet.getLastOpenIntentId())).tradeAgreements.quantity).to.equal(e(0.75))
		expect(await snapshot(f, f.a[2], f.b[1])).to.deep.equal(sibling)
		await assertBacking(f, f.a[1], f.b[1])
		await assertConservation(f)
	})

	it("rejects actual fill fees beyond separate fee-token funding and rolls back all buckets atomically", async function () {
		const feeToken = await f.context.collateralNL.getAddress()
		await fund(f, f.a[1], f.b[1])
		await f.context.collateralNL.mint(f.a[1].owner, e(10))
		await f.context.collateralNL.connect(f.a[1].signer).approve(f.context.common.diamondAddress, MaxUint256)
		await f.context.accountFacet.connect(f.a[1].signer)[DEPOSIT](1, feeToken, e(10))
		await allocate(f, f.a[1], f.b[1], e(0.5), feeToken)
		const intent = await send(f, f.a[1], f.b[1], { tradeSide: TradeSide.SELL, quantity: e(1), mm: e(2), feeToken })
		await f.context.partyBOpenFacet.connect(f.b[1].signer).lockOpenIntent(intent.id)
		const before = await snapshot(f, f.a[1], f.b[1]),
			feeBefore = await snapshot(f, f.a[1], f.b[1], feeToken)
		await expect(f.context.partyBOpenFacet.connect(f.b[1].signer).fillOpenIntent(intent.id, e(1), e(100)))
			.to.be.revertedWithCustomError(f.context.partyBOpenFacet, "NativeBackingInsufficient")
			.withArgs(f.a[1].owner, 1, f.b[1].owner, 1, feeToken)
		expect(await snapshot(f, f.a[1], f.b[1])).to.deep.equal(before)
		expect(await snapshot(f, f.a[1], f.b[1], feeToken)).to.deep.equal(feeBefore)
		await f.context.partyBOpenFacet.connect(f.b[1].signer).fillOpenIntent(intent.id, e(1), e(10))
		await assertConservation(f)
		await assertConservation(f, feeToken)
	})

	it("rejects a voluntary close that spends another relationship's solver funding", async function () {
		await fund(f, f.a[1], f.b[1])
		await fund(f, f.a[2], f.b[2])
		const intent = await send(f, f.a[1], f.b[1]),
			trade = await fill(f, f.b[1], intent.id)
		await f.context.partyACloseFacet.connect(f.a[1].signer).sendCloseIntent(trade, e(4), e(10000), (await getLatestBlockTime()) + 120)
		const close = await f.context.viewFacet.getLastCloseIntentId(),
			before = await snapshot(f, f.a[1], f.b[1]),
			sibling = await snapshot(f, f.a[2], f.b[2])
		await expect(f.context.partyBCloseFacet.connect(f.b[1].signer).fillCloseIntent(close, e(4), e(10000)))
			.to.be.revertedWithCustomError(f.context.partyBCloseFacet, "NativeBackingInsufficient")
			.withArgs(f.b[1].owner, 1, f.a[1].owner, 1, f.token)
		expect(await snapshot(f, f.a[1], f.b[1])).to.deep.equal(before)
		expect(await snapshot(f, f.a[2], f.b[2])).to.deep.equal(sibling)
		expect((await f.context.viewFacet.getTrade(trade)).closedAmountBeforeExpiration).to.equal(0)
		expect((await f.context.viewFacet.getCloseIntent(close)).filledAmount).to.equal(0)
		await f.context.partyBCloseFacet.connect(f.b[1].signer).fillCloseIntent(close, e(0.1), e(10000))
		expect((await f.context.viewFacet.getTrade(trade)).closedAmountBeforeExpiration).to.equal(e(0.1))
		await assertBacking(f, f.a[1], f.b[1])
		await assertConservation(f)
	})

	it("gives callbacks only their actual caller's authority and uses explicit bucket fields for owner-wallet callbacks", async function () {
		const token = await (await ethers.getContractFactory("NativeBucketCallbackToken")).deploy()
		const wallet = await (await ethers.getContractFactory("NativeBucketCallbackWallet")).deploy()
		const tokenAddress = await token.getAddress(),
			walletAddress = await wallet.getAddress()
		await f.context.controlFacet.whiteListCollateral(tokenAddress)
		await f.context.controlFacet.setBalanceLimitPerUser(tokenAddress, e(1000000))
		await token.mint(f.a[1].owner, e(10))
		await token.connect(f.a[1].signer).approve(f.context.common.diamondAddress, MaxUint256)
		const victimBefore = await snapshot(f, f.a[1], f.b[1])
		await token.configureCallback(
			f.context.common.diamondAddress,
			f.context.accountFacet.interface.encodeFunctionData(WITHDRAW, [1, f.token, e(1), tokenAddress]),
		)
		await f.context.accountFacet.connect(f.a[1].signer)[DEPOSIT](1, tokenAddress, e(1))
		expect(await token.callbackSucceeded()).to.equal(false)
		expect(await snapshot(f, f.a[1], f.b[1])).to.deep.equal(victimBefore)
		expect(await f.context.viewFacet.getLastWithdrawalId()).to.equal(0)
		await token.execute(f.context.common.diamondAddress, f.bucket.interface.encodeFunctionData("createBucket", [1]))
		await token.configureCallback(
			f.context.common.diamondAddress,
			f.context.accountFacet.interface.encodeFunctionData("allocateToReserveBalance(uint256,address,uint256)", [1, f.token, e(1)]),
		)
		await f.context.accountFacet.connect(f.a[1].signer)[DEPOSIT](1, tokenAddress, e(1))
		expect(await token.callbackSucceeded()).to.equal(false)
		const failure = f.context.accountFacet.interface.parseError(await token.callbackResult())
		expect(failure?.name).to.equal("InsufficientBalance")
		expect(Array.from(failure!.args)).to.deep.equal([tokenAddress, f.token, e(1), 0n])
		expect(await snapshot(f, f.a[1], f.b[1])).to.deep.equal(victimBefore)
		await token.configureCallback(ZeroAddress, "0x")
		await token.mint(walletAddress, e(10))
		await wallet.execute(tokenAddress, token.interface.encodeFunctionData("approve", [f.context.common.diamondAddress, MaxUint256]))
		await wallet.execute(f.context.common.diamondAddress, f.bucket.interface.encodeFunctionData("createBucket", [1]))
		await wallet.execute(f.context.common.diamondAddress, f.context.accountFacet.interface.encodeFunctionData(DEPOSIT, [0, tokenAddress, e(2)]))
		await wallet.execute(f.context.common.diamondAddress, f.context.accountFacet.interface.encodeFunctionData(DEPOSIT, [1, tokenAddress, e(2)]))
		await wallet.configureReentry(
			f.context.common.diamondAddress,
			f.context.accountFacet.interface.encodeFunctionData("allocateToReserveBalance(uint256,address,uint256)", [0, tokenAddress, e(1)]),
		)
		await token.configureCallback(walletAddress, wallet.interface.encodeFunctionData("onTokenCallback"))
		await wallet.execute(f.context.common.diamondAddress, f.context.accountFacet.interface.encodeFunctionData(DEPOSIT, [1, tokenAddress, e(2)]))
		expect(await token.callbackSucceeded()).to.equal(true)
		const moved = (await wallet.reentrySucceeded()) ? e(1) : 0n
		// Either the ordinary shared reentrancy guard rejects, or the actual wallet
		// performs the explicitly requested bucket-zero action. Bucket one is never inherited.
		expect(await f.context.viewFacet[ISOLATED](walletAddress, 0, tokenAddress)).to.equal(e(2) - moved)
		expect(await f.context.viewFacet[RESERVE](walletAddress, 0, tokenAddress)).to.equal(moved)
		expect(await f.context.viewFacet[ISOLATED](walletAddress, 1, tokenAddress)).to.equal(e(4))
		expect(await f.context.viewFacet[RESERVE](walletAddress, 1, tokenAddress)).to.equal(0)
		expect(await token.balanceOf(f.context.common.diamondAddress)).to.equal(e(8))
	})

	it("keeps bounded lifecycle sequences conserved after every deposit, lock, fill, cancel, close and withdrawal", async function () {
		await fund(f, f.a[1], f.b[1])
		await fund(f, f.a[2], f.b[2])
		await assertConservation(f)
		for (const [a, b, quantity] of [
			[f.a[1], f.b[1], e(2)],
			[f.a[2], f.b[2], e(3)],
		] as const) {
			const intent = await send(f, a, b, { quantity })
			await assertConservation(f)
			const trade = await fill(f, b, intent.id, e(1))
			await assertConservation(f)
			await f.context.partyAOpenFacet.connect(a.signer).cancelOpenIntent([await f.context.viewFacet.getLastOpenIntentId()])
			await assertConservation(f)
			await f.context.partyACloseFacet.connect(a.signer).sendCloseIntent(trade, e(1), e(12), (await getLatestBlockTime()) + 120)
			const close = await f.context.viewFacet.getLastCloseIntentId()
			await f.context.partyBCloseFacet.connect(b.signer).fillCloseIntent(close, e(1), e(12))
			expect((await f.context.viewFacet.getCloseIntent(close)).status).to.equal(CloseIntentStatus.FILLED)
			await assertConservation(f)
			await f.context.accountFacet.connect(a.signer)[WITHDRAW](a.bucketId, f.token, e(17), a.owner)
			await assertConservation(f)
			const withdrawal = await f.context.viewFacet.getLastWithdrawalId()
			await networkHelpers.time.increase(1000)
			await f.context.accountFacet.completeWithdraw(withdrawal)
			await assertConservation(f)
		}
		expect(await f.context.viewFacet[ISOLATED](f.a[0].owner, 0, f.token)).to.equal(e(10000))
	})
})
