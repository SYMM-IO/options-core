import { Builder } from "builder-pattern"
import { CloseIntentStruct } from "../../../types/contracts/interfaces/ISymmio"
import { ZeroAddress } from "ethers"

const defaultCloseIntent: CloseIntentStruct = {
	id: 0,
	tradeId: 0,
	price: 0,
	quantity: 0,
	filledAmount: 0,
	createTimestamp: 0,
	statusModifyTimestamp: 0,
	deadline: 0,
	status: 0,
	feeStructure:{
		feeToken:ZeroAddress,
		tokenPriceInCollateral:1,
		affiliateFee:{
			openFee:1,
			closeFee:1
		},
		solverFee:{
			openFee:1,
			closeFee:1
		},
		platformFee:{
			openFee:1,
			closeFee:1
		},
	}
}

export const closeIntentBuilder = () => Builder<CloseIntentStruct>(defaultCloseIntent)
