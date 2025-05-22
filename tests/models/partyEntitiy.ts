import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers"
import { RunContext } from "../run-context"
import { runTx } from "../../utils/tx"
import { ethers } from "hardhat"
import { BigNumberish, BytesLike } from "ethers"
import { setBalance } from "@nomicfoundation/hardhat-network-helpers"
import { FakeStablecoin } from "../../types"

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
		if (depositAmount) await runTx(this.context.accountFacet.connect(this.signer).deposit(await clt.getAddress(), depositAmount))
	}

	public async setNativeBalance(amount: bigint) {
		await setBalance(this.signer.address, amount)
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
