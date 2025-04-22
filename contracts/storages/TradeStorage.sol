// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { Trade } from "../types/TradeTypes.sol";

library TradeStorage {
	bytes32 internal constant SYMBOL_STORAGE_SLOT = keccak256("diamond.standard.storage.trade");

	struct Layout {
		mapping(uint256 => Trade) trades;
		mapping(address => uint256[]) tradesOf;
		mapping(address => uint256[]) activeTradesOf;
		mapping(address => mapping(address => uint256[])) activeTradesOfPartyB; // partyBAddress => collateral => trades
		mapping(uint256 => uint256) partyATradesIndex;
		mapping(uint256 => uint256) partyBTradesIndex;
		uint256 lastTradeId;
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = SYMBOL_STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
