// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { SettlementPriceSig } from "../../types/TradeTypes.sol";

import { ITradeEvents } from "./ITradeEvents.sol";

interface ITradeFacet is ITradeEvents {
	function transferTrade(address receiver, uint256 tradeId) external;

	function transferTradeFromNFT(address sender, address receiver, uint256 tradeId) external;

	function executeTrades(uint256[] memory tradeIds, SettlementPriceSig memory settlementPriceSig) external;

	function mintNFTForTrade(uint256 tradeId) external;
}
