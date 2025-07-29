// Intent
export enum IntentStatus {
	PENDING,
	LOCKED,
	CANCEL_PENDING,
	CANCELED,
	FILLED,
	EXPIRED,
}

export enum CloseIntentStatus {
	PENDING,
	CANCEL_PENDING,
	CANCELED,
	FILLED,
	EXPIRED,
}

export enum TradeSide {
	BUY,
	SELL,
}

export enum MarginType {
	ISOLATED, // per‑position margin
	CROSS, // shared margin against a specific counter‑party
}

export enum OptionType {
	PUT,
	CALL,
}

export enum TradeStatus {
	OPENED,
	CLOSED,
	EXERCISED,
	EXPIRED,
	LIQUIDATED,
}

export enum WithdrawStatus {
	INITIATED,
	CANCELED,
	COMPLETED,
	SUSPENDED,
}

export enum LiquidationStatus {
	FLAGGED,
	IN_PROGRESS,
	CANCELLED,
}

export enum LiquidationSide {
	PARTY_A,
	PARTY_B,
}
