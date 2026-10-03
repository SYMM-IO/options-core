import { loadFixture } from "@nomicfoundation/hardhat-network-helpers"
import { expect } from "chai"
import { ZeroAddress } from "ethers"
import { ethers } from "hardhat"

async function deployTradeNFTFixture() {
	const [deployer, alice, bob, operator] = await ethers.getSigners()
	const symmio = await (await ethers.getContractFactory("MockTradeNFTSymmio")).deploy()
	await symmio.waitForDeployment()
	const nft = await (await ethers.getContractFactory("TradeNFT")).deploy(await symmio.getAddress())
	await nft.waitForDeployment()
	await symmio.setNFT(await nft.getAddress())
	await symmio.mint(alice.address, 1n)
	return { deployer, alice, bob, operator, symmio, nft }
}

export function shouldBehaveLikeTradeNFT(): void {
	it("rejects a zero Symmio address", async function () {
		const factory = await ethers.getContractFactory("TradeNFT")
		await expect(factory.deploy(ZeroAddress)).to.be.revertedWithCustomError(factory, "InvalidSymmioAddress")
	})

	it("makes the deployer the owner", async function () {
		const { deployer, nft } = await loadFixture(deployTradeNFTFixture)
		expect(await nft.owner()).to.equal(deployer.address)
	})

	it("only lets Symmio mint", async function () {
		const { alice, symmio, nft } = await loadFixture(deployTradeNFTFixture)
		await expect(nft.connect(alice).mintNFTForTrade(alice.address, 2n))
			.to.be.revertedWithCustomError(nft, "UnauthorizedSender")
			.withArgs(alice.address, await symmio.getAddress())
	})

	it("mints through Symmio without calling back into Symmio", async function () {
		const { bob, symmio, nft } = await loadFixture(deployTradeNFTFixture)
		await expect(symmio.mint(bob.address, 2n)).to.emit(nft, "TradeNFTMinted").withArgs(bob.address, 2n)
		expect(await nft.ownerOf(2n)).to.equal(bob.address)
		expect(await symmio.callCount()).to.equal(0n)
	})

	it("syncs a holder's transfer to Symmio before ownership moves", async function () {
		const { alice, bob, symmio, nft } = await loadFixture(deployTradeNFTFixture)
		await expect(nft.connect(alice).transferFrom(alice.address, bob.address, 1n))
			.to.emit(nft, "TradeNFTTransferred")
			.withArgs(1n, alice.address, bob.address)
		expect(await symmio.callCount()).to.equal(1n)
		const call = await symmio.calls(0)
		expect(call.from).to.equal(alice.address)
		expect(call.to).to.equal(bob.address)
		expect(call.tradeId).to.equal(1n)
		expect(call.ownerAtCall).to.equal(alice.address)
		expect(await nft.ownerOf(1n)).to.equal(bob.address)
	})

	it("syncs safeTransferFrom to Symmio", async function () {
		const { alice, bob, symmio, nft } = await loadFixture(deployTradeNFTFixture)
		await nft.connect(alice)["safeTransferFrom(address,address,uint256)"](alice.address, bob.address, 1n)
		expect(await symmio.callCount()).to.equal(1n)
		expect(await nft.ownerOf(1n)).to.equal(bob.address)
	})

	it("syncs an approved operator's transfer to Symmio", async function () {
		const { alice, bob, operator, symmio, nft } = await loadFixture(deployTradeNFTFixture)
		await nft.connect(alice).approve(operator.address, 1n)
		await nft.connect(operator).transferFrom(alice.address, bob.address, 1n)
		const call = await symmio.calls(0)
		expect(call.from).to.equal(alice.address)
		expect(call.to).to.equal(bob.address)
		expect(await nft.ownerOf(1n)).to.equal(bob.address)
	})

	it("does not call back when Symmio moves the trade", async function () {
		const { alice, bob, symmio, nft } = await loadFixture(deployTradeNFTFixture)
		await expect(symmio.moveTrade(alice.address, bob.address, 1n)).not.to.emit(nft, "TradeNFTTransferred")
		expect(await nft.ownerOf(1n)).to.equal(bob.address)
		expect(await symmio.callCount()).to.equal(0n)
	})

	it("ignores a Symmio move of an unminted trade", async function () {
		const { alice, bob, symmio, nft } = await loadFixture(deployTradeNFTFixture)
		await expect(symmio.moveTrade(alice.address, bob.address, 99n)).not.to.be.reverted
		expect(await nft.balanceOf(bob.address)).to.equal(0n)
	})

	it("rejects a transfer by someone who is neither owner nor approved", async function () {
		const { alice, bob, symmio, nft } = await loadFixture(deployTradeNFTFixture)
		await symmio.setRevertOnCallback(true)
		// If the Symmio callback ran before the authorization check, this would revert with CallbackReached instead.
		await expect(nft.connect(bob).transferFrom(alice.address, bob.address, 1n))
			.to.be.revertedWithCustomError(nft, "ERC721InsufficientApproval")
			.withArgs(bob.address, 1n)
		expect(await nft.ownerOf(1n)).to.equal(alice.address)
		// Control: an authorized transfer does reach the callback, so the flag discriminates.
		await expect(nft.connect(alice).transferFrom(alice.address, bob.address, 1n)).to.be.revertedWithCustomError(symmio, "CallbackReached")
	})

	it("rejects a transfer that names the wrong current owner", async function () {
		const { alice, bob, nft } = await loadFixture(deployTradeNFTFixture)
		await expect(nft.connect(alice).transferFrom(bob.address, alice.address, 1n))
			.to.be.revertedWithCustomError(nft, "ERC721IncorrectOwner")
			.withArgs(bob.address, 1n, alice.address)
	})

	it("reports ERC165, ERC721 and ERC721Enumerable support", async function () {
		const { nft } = await loadFixture(deployTradeNFTFixture)
		expect(await nft.supportsInterface("0x01ffc9a7")).to.equal(true) // IERC165
		expect(await nft.supportsInterface("0x80ac58cd")).to.equal(true) // IERC721
		expect(await nft.supportsInterface("0x780e9d63")).to.equal(true) // IERC721Enumerable
		expect(await nft.supportsInterface("0xffffffff")).to.equal(false)
	})
}
