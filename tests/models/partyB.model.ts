import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers"
import { RunContext } from "../run-context"
import { runTx } from "../../utils/tx"
import { ethers } from "hardhat"
import { BigNumberish } from "ethers"
import { setBalance } from "@nomicfoundation/hardhat-network-helpers"

export class PartyB {
	constructor(private context: RunContext, private signer: SignerWithAddress) {}

	public async setBalances(collateralAmount?: BigNumberish, depositAmount?: BigNumberish) {
		const userAddress = this.signer.getAddress()

		await runTx(this.context.collateral.connect(this.signer).approve(this.context.diamond, ethers.MaxUint256))

		if (collateralAmount) await runTx(this.context.collateral.connect(this.signer).mint(userAddress, collateralAmount))
		if (depositAmount) await runTx(this.context.accountFacet.connect(this.signer).deposit(await this.context.collateral.getAddress(), depositAmount))
	}

	public async setNativeBalance(amount: bigint) {
		await setBalance(this.signer.address, amount)
	}

	public getSigner() {
		return this.signer
	}
}
