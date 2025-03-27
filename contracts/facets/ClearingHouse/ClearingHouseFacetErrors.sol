// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library ClearingHouseFacetErrors {
	// PartyB errors
	error ZeroLossCoverage(address partyB);

	// Liquidation state errors
	error PartyBIsSolvent(address partyB, address collateral, int256 available, int256 required);

	// Upnl errors
	error InvalidUpnl(int256 upnl);

	// Withdrawal errors
	error InvalidWithdrawalUser(uint256 withdrawId, address user, address partyB);
	error InsufficientCollateralForDebts(address partyB, address collateral, uint256 collected, uint256 required);

	// Open trades errors
	error PartyBHasOpenTrades(address partyB, address collateral, uint256 openTradesCount);

	// Arrays errors
	error MismatchedArrays(uint256 tradeIdsLength, uint256 pricesLength);
}
