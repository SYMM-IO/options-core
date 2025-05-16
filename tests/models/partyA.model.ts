import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers"
import { RunContext } from "../run-context"
import { runTx } from "../../utils/tx"
import { OpenIntent, openIntentRequestBuilder } from "./builders/send-open-intent.builder"
import { PartyEntity } from "./partyEntitiy"
import { BigNumberish } from "ethers"

export class PartyA extends PartyEntity {
	constructor(context: RunContext, signer: SignerWithAddress) {
		super(context, signer)
	}

	public async sendOpenIntent(request: OpenIntent = openIntentRequestBuilder().build()): Promise<any> {
		return await runTx(
			this.context.partyAOpenFacet
				.connect(this.signer)
				.sendOpenIntent(
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
				),
		)
	}

	public async sendCancelOpenIntent(ids: string[]) {
		await runTx(this.context.partyAOpenFacet.connect(this.signer).cancelOpenIntent(ids))
	}

	public async sendCloseIntent(tradeId: BigNumberish, price: BigNumberish, quantity: BigNumberish, deadline: BigNumberish) {
		await runTx(this.context.partyACloseFacet.connect(this.signer).sendCloseIntent(tradeId, price, quantity, deadline))
	}

	public async sendCancelCloseIntent(ids: string[]) {
		await runTx(this.context.partyACloseFacet.connect(this.signer).cancelCloseIntent(ids))
	}

	public async activateInstantActionMode() {
		await runTx(this.context.accountFacet.connect(this.signer).activateInstantActionMode())
	}

	public async deactivateInstantActionMode() {
		await runTx(this.context.accountFacet.connect(this.signer).deactivateInstantActionMode())
	}

	public async forceCancelOpenIntent(id: string) {
		await runTx(this.context.forceActionsFacet.connect(this.signer).forceCancelOpenIntent(id))
	}
}
