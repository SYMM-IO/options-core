import { Builder } from "builder-pattern"
import { AddressLike, BigNumberish, BytesLike, toUtf8Bytes } from "ethers"
import { ethers } from "hardhat"
import { SettlementPriceSigStruct } from "../../../types/contracts/facets/TradeSettlement/ITradeSettlementFacet"


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
		nonce: "0x1234567890abcdef1234567890abcdef12345678"
	}	
}


export const settlementSigBuilder = () => Builder(settlementSig)
