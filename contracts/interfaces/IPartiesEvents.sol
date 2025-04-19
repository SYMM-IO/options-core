// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

interface IPartiesEvents {
	event SendOpenIntent(
		address partyA,
		uint256 intentId,
		address[] partyBsWhiteList,
		bytes requestedParams // encodePacked (symbolId, price, quantity, strikePrice, expirationTimestamp, mm, tradeSide, marginType, exerciseFee.rate, exerciseFee.cap, deadline)
	);
	event ExpireOpenIntent(uint256 intentId);
	event ExpireCloseIntent(uint256 intentId);
}
