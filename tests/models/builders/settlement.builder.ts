import { Builder } from "builder-pattern"
import { SettlementPriceSigStruct } from "../../../types/contracts/interfaces/ISymmio"

const settlementSig: SettlementPriceSigStruct = {
	reqId: "0x",
	timestamp: 23,
	symbolId: 1,
	settlementPrice: 7,
	settlementTimestamp: 23,
	collateralPrice: 8,
	gatewaySignature: "0x",
	sigs: {
		signature: 0,
		owner: "0x1234567890abcdef1234567890abcdef12345678",
		nonce: "0x1234567890abcdef1234567890abcdef12345678",
	},
}

export const settlementSigBuilder = () => Builder(settlementSig)
