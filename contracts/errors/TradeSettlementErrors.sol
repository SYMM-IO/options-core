// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library TradeSettlementErrors {
	error MismatchedSymbolId(uint256 providedSymbolId, uint256 tradeSymbolId);
	error TradeNotYetExpired(uint256 tradeId, uint256 currentTime, uint256 expirationTimestamp);
	error OwnerExclusiveWindowActive(uint256 currentTime, uint256 requiredTime);
}
