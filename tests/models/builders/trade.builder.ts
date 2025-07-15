import { Builder } from "builder-pattern"
import { TradeStruct } from "../../../types/contracts/interfaces/ISymmio"
import { ZeroAddress } from "ethers"

const defaultTrade: TradeStruct = {
	id: 0,
	openIntentId: 0,
	tradeAgreements: {
		tradeSide: 0,
		exerciseFee: {
			cap: 0,
			rate: 0,
		},
		expirationTimestamp: 0,
		marginType: 0,
		mm: 0,
		quantity: 0,
		strikePrice: 0,
		symbolId: 0,
	},
	partyA: "0x0000000000000000000000000000000000000000",
	partyB: "0x0000000000000000000000000000000000000000",
	activeCloseIntentIds: [],
	settledPrice: 0,
	openedPrice: 0,
	closedAmountBeforeExpiration: 0,
	closePendingAmount: 0,
	avgClosedPriceBeforeExpiration: 0,
	status: 0,
	createTimestamp: 0,
	statusModifyTimestamp: 0,
	feeStructure: {
		feeToken: ZeroAddress,
		tokenPriceInCollateral: 1,
		affiliateFee: {
			openFee: 1,
			closeFee: 1,
		},
		solverFee: {
			openFee: 1,
			closeFee: 1,
		},
		platformFee: {
			openFee: 1,
			closeFee: 1,
		},
	},
}

export const tradeBuilder = () => Builder<TradeStruct>(defaultTrade)
