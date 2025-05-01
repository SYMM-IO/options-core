// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { MarginType, TradeAgreements } from "./BaseTypes.sol";

enum TradeStatus {
	OPENED,
	CLOSED,
	EXERCISED,
	EXPIRED,
	LIQUIDATED
}

struct Trade {
	uint256 id;
	uint256 openIntentId;
	TradeAgreements tradeAgreements;
	address partyA;
	address partyB;
	uint256[] activeCloseIntentIds;
	uint256 settledPrice;
	uint256 openedPrice;
	uint256 closedAmountBeforeExpiration;
	uint256 closePendingAmount;
	uint256 avgClosedPriceBeforeExpiration;
	TradeStatus status;
	uint256 createTimestamp;
	uint256 statusModifyTimestamp;
}
