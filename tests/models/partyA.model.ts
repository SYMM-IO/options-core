import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers"
import { RunContext } from "../run-context"
import { runTx } from "../../utils/tx"
import { ethers } from "hardhat"
import { BigNumberish } from "ethers"
import { setBalance } from "@nomicfoundation/hardhat-network-helpers"
import { OpenIntent, openIntentRequestBuilder } from "./builders/send-open-intent.builder"

export class PartyA {
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

	public async sendOpenIntent(request: OpenIntent = openIntentRequestBuilder().build()) {
		await runTx(
			this.context.partyAFacet
				.connect(this.signer)
				.sendOpenIntent(
					request.partyBsWhiteList,
					request.symbolId,
					request.price,
					request.quantity,
					request.strikePrice,
					request.expirationTimestamp,
					request.exerciseFee,
					request.deadline,
					request.feeToken,
					request.affiliate,
					request.userData,
				),
		)
	}

	public async sendCancelOpenIntent(ids: string[]) {
		await runTx(this.context.partyAFacet.connect(this.signer).cancelOpenIntent(ids))
	}

	public async activateInstantActionMode() {
		await runTx(this.context.accountFacet.connect(this.signer).activateInstantActionMode())
	}

	public async deactivateInstantActionMode() {
		await runTx(this.context.accountFacet.connect(this.signer).deactivateInstantActionMode())
	}
}
