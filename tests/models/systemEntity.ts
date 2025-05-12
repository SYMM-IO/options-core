import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers"
import { RunContext } from "../run-context"
import { runTx } from "../../utils/tx"
import { ethers } from "hardhat"
import { BigNumberish } from "ethers"
import { setBalance } from "@nomicfoundation/hardhat-network-helpers"
import { OpenIntent, openIntentRequestBuilder } from "./builders/send-open-intent.builder"
import { FakeStablecoin} from "../../types"


export class SystemEntity   {
	constructor(protected context: RunContext, protected signer: SignerWithAddress) {}

	public async setNativeBalance(amount: bigint) {
		await setBalance(this.signer.address, amount)
	}

	public getSigner() {
		return this.signer
	}	
}
