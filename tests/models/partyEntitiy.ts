import { ethers, networkHelpers } from "../connection.js"
import type { HardhatEthersSigner as SignerWithAddress } from "@nomicfoundation/hardhat-ethers/types"
import { RunContext } from "../run-context.js"
import { runTx } from "../../utils/tx.js"
import { BigNumberish, BytesLike } from "ethers"
import { FakeStablecoin } from "../../types/index.js"

export class PartyEntity {
	constructor(
		protected context: RunContext,
		protected signer: SignerWithAddress,
	) {}

	public async setBalances(_collateral?: FakeStablecoin, collateralAmountToMint?: BigNumberish, depositAmount?: BigNumberish) {
		const userAddress = this.signer.getAddress()
		let clt = this.context.collateral
		if (_collateral) {
			clt = _collateral
		}

		await runTx(clt.connect(this.signer).approve(this.context.common.diamondAddress, ethers.MaxUint256))

		if (collateralAmountToMint) await runTx(clt.connect(this.signer).mint(userAddress, collateralAmountToMint))
		if (depositAmount) await runTx(this.context.accountFacet.connect(this.signer)["deposit(address,uint256)"](await clt.getAddress(), depositAmount))
	}

	public async setNativeBalance(amount: bigint) {
		await networkHelpers.setBalance(this.signer.address, amount)
	}

	public get getSigner() {
		return this.signer
	}

	public get address() {
		return this.signer.address
	}

	public async sign(hash: BytesLike): Promise<string> {
		return await this.getSigner.signMessage(ethers.getBytes(hash))
	}
}
