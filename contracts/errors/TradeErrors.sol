// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library TradeErrors {
	// Trade limits
	error TooManyActiveTradesForPartyA(address partyA, uint256 currentCount, uint256 maxCount);

	// Trade lifecycle
	error TradeExpired(uint256 tradeId, uint256 currentTime, uint256 expirationTimestamp);

	// Trade transfer
	error ReceiverIsPartyB(address receiver, address partyB);
	error CrossTradeTransferNotAllowed(uint256 tradeId);
	error NFTMintingNotAllowedForCrossMarginTrade(uint256 tradeId);

	// Settlement
	error MismatchedSymbolId(uint256 providedSymbolId, uint256 tradeSymbolId);
	error TradeNotYetExpired(uint256 tradeId, uint256 currentTime, uint256 expirationTimestamp);
	error PartyBExclusiveWindowNotOver(uint256 currentTime, uint256 requiredTime);
}
