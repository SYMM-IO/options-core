import { Builder } from "builder-pattern"
import { CloseIntentStruct } from "../../../types/contracts/interfaces/ISymmio"

const defaultCloseIntent: CloseIntentStruct = {
	id: 0,
	tradeId: 0,
	price: 0,
	quantity: 0,
	filledAmount: 0,
	status: 0,
	createTimestamp: 0,
	statusModifyTimestamp: 0,
	deadline: 0,
}

export const closeIntentBuilder = () => Builder<CloseIntentStruct>(defaultCloseIntent)
