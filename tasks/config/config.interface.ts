export interface IConfig {
	configTitle?: string
	version?: string
	admin?: string

	roles?: {
		grant?: Array<{ address: string; role: string }>
		revoke?: Array<{ address: string; role: string }>
	}

	collateral?: {
		whiteList?: string[]
		removeFromWhitelist?: string[]
	}

	pause?: {
		global?: boolean
		deposit?: boolean
		withdraw?: boolean
		partyBActions?: boolean
		partyAActions?: boolean
		liquidating?: boolean
	}

	emergencyMode?: boolean
	partyBEmergencyMode?: Array<{
		address: string
		active: boolean
	}>

	priceOracleAddress?: string
	defaultFeeCollector?: string
	affiliateFeeCollector?: Array<{
		affiliate: string
		collector: string
	}>

	deactiveInstantActionModeCooldown?: number
	unbindingCooldown?: number
	maxConnectedPartyBs?: number
	partyADeallocateCooldown?: number
	partyBDeallocateCooldown?: number

	forceCancelOpenIntentTimeout?: number
	forceCancelCloseIntentTimeout?: number
	settlementPriceSigValidTime?: string
	liquidationSigValidTime?: string

	maxCloseOrdersLength?: number
	balanceLimitPerUser?: number

	partyB?: Array<{
		address: string
		isActive: boolean
		lossCoverage: number
		oracleId: number
		symbolType: number
	}>

	oracles?: Array<{
		name: string
		address: string
	}>

	symbols?: Array<{
		name: string
		symbolId: string
		isValid: boolean
		collateral: string
		optionType: string
		oracleId: string
		isStableCoin: boolean
		tradingFee: string
		symbolType: string
	}>

	affiliates?: Array<{
		address: string
		status: boolean
	}>

	partyBReleaseInterval?: Array<{
		partyB: string
		interval: number
	}>

	suspendAddress?: Array<{
		address: string
		suspend: boolean
	}>

	suspendWithdrawal?: Array<{
		withdrawId: string
		suspend: boolean
	}>

	instantActionsMode?: Array<{
		address: string
		active: boolean
	}>

	instantActionsModeDeactivateTime?: Array<{
		address: string
		time: number
	}>
}
