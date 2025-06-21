// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library PartyACloseErrors {
	error InvalidQuantity(uint256 requested, uint256 available);
	error TooManyCloseOrders(uint256 current, uint256 maximum);
	error ReceiverIsPartyB(address receiver, address partyB);
	error UnauthorizedTransfer(address sender, address partyA);
	error CrossTradeTransferNotAllowed(uint256 tradeId);
}
