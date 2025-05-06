// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library PartyACloseFacetErrors {
	// Quantity errors
	error InvalidQuantity(uint256 requested, uint256 available);

	// Close orders errors
	error TooManyCloseOrders(uint256 current, uint256 maximum);

	// Transfer errors
	error ReceiverIsPartyB(address receiver, address partyB);
	error OnlyPartyACanTransfer(address sender, address partyA);
	error TradeInCrossCannotBeTransfered(uint256 tradeId);
}
