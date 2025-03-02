// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/IntentStorage.sol";

interface IPartiesEvents {
	event SendOpenIntent(
		address partyA,
		uint256 intentId,
		address[] partyBsWhiteList,
		uint256 symbolId,
		uint256 price,
		uint256 quantity,
		uint256 strikePrice,
		uint256 expirationTimestamp,
		ExerciseFee exerciseFee,
		TradingFee tradingFee,
		uint256 deadline
	);
	event ExpireOpenIntent(uint256 intentId);
	event ExpireCloseIntent(uint256 intentId);
}
