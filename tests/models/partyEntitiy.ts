import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers"
import { RunContext } from "../run-context"
import { runTx } from "../../utils/tx"
import { ethers } from "hardhat"
import { BigNumberish } from "ethers"
import { setBalance } from "@nomicfoundation/hardhat-network-helpers"
import { OpenIntent, openIntentRequestBuilder } from "./builders/send-open-intent.builder"
import { FakeStablecoin} from "../../types"


export class PartyEntity   {
	constructor(protected context: RunContext, protected signer: SignerWithAddress) {}

	public async setBalances(_collateral?: FakeStablecoin, collateralAmount?: BigNumberish, depositAmount?: BigNumberish) {
		const userAddress = this.signer.getAddress()
		let clt = this.context.collateral
		if (_collateral) {
        	clt = _collateral;
		}

		await runTx(clt.connect(this.signer).approve(this.context.diamond, ethers.MaxUint256))

		if (collateralAmount) await runTx(clt.connect(this.signer).mint(userAddress, collateralAmount))
		if (depositAmount) await runTx(this.context.accountFacet.connect(this.signer).deposit(await clt.getAddress(), depositAmount))
	}

	public async setNativeBalance(amount: bigint) {
		await setBalance(this.signer.address, amount)
	}

	public getSigner() {
		return this.signer
	}

	
}
