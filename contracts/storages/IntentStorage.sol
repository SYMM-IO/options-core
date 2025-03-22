// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

enum IntentStatus {
	PENDING,
	LOCKED,
	CANCEL_PENDING,
	CANCELED,
	FILLED,
	EXPIRED
}

enum TradeStatus {
	OPENED,
	CLOSED,
	EXERCISED,
	EXPIRED,
	LIQUIDATED
}

enum TradeSide {
	LONG,
	SHORT
}

enum MarginType {
	ISOLATED,
	CROSS
}

struct ExerciseFee {
	uint256 rate;
	uint256 cap;
}

struct TradingFee {
	address feeToken;
	uint256 tokenPrice;
	uint256 platformFee;
}

struct TradeAgreements {
	uint256 symbolId;
	uint256 quantity;
	uint256 strikePrice;
	uint256 expirationTimestamp;
	uint256 penalty;
	TradeSide tradeSide;
	MarginType marginType;
	ExerciseFee exerciseFee;
}

struct Trade {
	uint256 id;
	uint256 openIntentId;
	TradeAgreements tradeAgreements;
	address partyA;
	address partyB;
	uint256[] activeCloseIntentIds;
	address[] penaltyParticipants;
	uint256 settledPrice;
	uint256 openedPrice;
	uint256 closedAmountBeforeExpiration;
	uint256 closePendingAmount;
	uint256 avgClosedPriceBeforeExpiration;
	TradeStatus status;
	uint256 createTimestamp;
	uint256 statusModifyTimestamp;
}

struct OpenIntent {
	uint256 id;
	uint256 tradeId;
	TradeAgreements tradeAgreements;
	uint256 price;
	address partyA;
	address partyB;
	address[] partyBsWhiteList;
	IntentStatus status;
	uint256 parentId;
	uint256 createTimestamp;
	uint256 statusModifyTimestamp;
	uint256 deadline;
	TradingFee tradingFee;
	address affiliate;
	bytes userData;
}

struct CloseIntent {
	uint256 id;
	uint256 tradeId;
	uint256 price;
	uint256 quantity;
	uint256 filledAmount;
	IntentStatus status;
	uint256 createTimestamp;
	uint256 statusModifyTimestamp;
	uint256 deadline;
}

struct SignedOpenIntent {
	address partyA;
	address partyB;
	uint256 symbolId;
	uint256 price;
	uint256 quantity;
	uint256 strikePrice;
	uint256 expirationTimestamp;
	uint256 penalty;
	TradeSide tradeSide;
	MarginType marginType;
	ExerciseFee exerciseFee;
	uint256 deadline;
	address affiliate;
	address feeToken;
	bytes userData;
	uint256 salt;
}

struct SignedCloseIntent {
	address partyA;
	uint256 tradeId;
	uint256 price;
	uint256 quantity;
	uint256 deadline;
	uint256 salt;
}

struct SignedFillIntent {
	address partyB;
	bytes32 intentHash;
	uint256 price;
	uint256 quantity;
	uint256 deadline;
	uint256 salt;
}

struct SignedFillIntentById {
	address partyB;
	uint256 intentId;
	uint256 price;
	uint256 quantity;
	uint256 deadline;
	uint256 salt;
}

struct SignedSimpleActionIntent {
	address signer;
	uint256 intentId;
	uint256 deadline;
	uint256 salt;
}

enum TransferIntentStatus {
	PENDING,
	LOCKED,
	CANCEL_PENDING,
	CANCELED,
	FINALIZED
}

struct TransferIntent {
	uint256 id;
	uint256 tradeId;
	uint256 deadline;
	address sender;
	address[] whitelist;
	address receiver;
	uint256 proposedPrice;
	TransferIntentStatus status;
}

library IntentStorage {
	bytes32 internal constant INTENT_STORAGE_SLOT = keccak256("diamond.standard.storage.intent");

	struct Layout {
		/////////////////////////////////////////////////
		mapping(uint256 => OpenIntent) openIntents;
		mapping(address => uint256[]) openIntentsOf;
		mapping(address => uint256[]) activeOpenIntentsOf;
		mapping(address => uint256) activeOpenIntentsCount;
		mapping(uint256 => uint256) partyAOpenIntentsIndex;
		mapping(uint256 => uint256) partyBOpenIntentsIndex;
		uint256 lastOpenIntentId;
		/////////////////////////////////////////////////
		mapping(uint256 => Trade) trades;
		mapping(address => uint256[]) tradesOf;
		mapping(address => uint256[]) activeTradesOf;
		mapping(address => mapping(address => uint256[])) activeTradesOfPartyB; // partyBAddress => collateral => trades
		mapping(uint256 => uint256) partyATradesIndex;
		mapping(uint256 => uint256) partyBTradesIndex;
		uint256 lastTradeId;
		/////////////////////////////////////////////////
		mapping(uint256 => CloseIntent) closeIntents;
		mapping(uint256 => uint256[]) closeIntentIdsOf;
		uint256 lastCloseIntentId;
		/////////////////////////////////////////////////
		mapping(bytes32 => bool) isSigUsed;
		address signatureVerifier;
		/////////////////////////////////////////////////
		mapping(uint256 => TransferIntent) transferIntents;
		uint256 lastTransferIntentId;
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = INTENT_STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
