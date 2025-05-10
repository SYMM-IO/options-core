import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers"
import { RunContext } from "../run-context"
import { runTx } from "../../utils/tx"
import { BigNumberish } from "ethers"
import { PartyEntity } from "./partyEntitiy"

export class PartyB extends PartyEntity {
	constructor(context: RunContext,  signer: SignerWithAddress) {super(context,signer)}

	public async lockOpenIntent(id: BigNumberish) {
		await runTx(this.context.partyBOpenFacet.connect(this.signer).lockOpenIntent(id))
	}

	public async unlockOpenIntent(id: BigNumberish) {
		await runTx(this.context.partyBOpenFacet.connect(this.signer).unlockOpenIntent(id))
	}

	public async fillOpenIntent(id: BigNumberish, quantity: BigNumberish, price: BigNumberish) {
		await runTx(this.context.partyBOpenFacet.connect(this.signer).fillOpenIntent(id, quantity, price))
	}

	public async acceptCancelOpenIntent(id: BigNumberish) {
		await runTx(this.context.partyBOpenFacet.connect(this.signer).acceptCancelOpenIntent(id))
	}

	public async fillCloseIntent(closeIntentId: BigNumberish, quantity: BigNumberish, price: BigNumberish) {
		await runTx(this.context.partyBCloseFacet.connect(this.signer).fillCloseIntent(closeIntentId, quantity, price))
	}
}
