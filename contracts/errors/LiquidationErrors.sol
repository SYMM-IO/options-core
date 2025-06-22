// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library LiquidationErrors {
	error ZeroLossCoverage(address partyB);
	error MismatchedArrayLengths(uint256 tradeIdsLength, uint256 pricesLength);
	error PartyASolvent(address partyA, address partyB, address token);
	error PartyBSolvent(address partyA, address partyB, address token);
	error TradeNotInLiquidation(uint256 liquidationId, uint256 tradeId);
	error PartiesNotInLiquidation(address partyA, address partyB, address collateral);
}
