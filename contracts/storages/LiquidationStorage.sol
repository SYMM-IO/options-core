// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LiquidationState, LiquidationDetail } from "../types/LiquidationTypes.sol";

library LiquidationStorage {
	bytes32 internal constant SYMBOL_STORAGE_SLOT = keccak256("diamond.standard.storage.liquidation");

	struct Layout {
		mapping(address => mapping(address => LiquidationState)) liquidationStates; // partyBAddress => collateral => liquidationState
		mapping(uint256 => LiquidationDetail) liquidationDetails; // liquidationId => detail
		mapping(address => mapping(address => mapping(address => uint256))) liquidationDebtsToPartyAs; // partyB => collateral => partyA => amount
		mapping(address => mapping(address => uint256)) involvedPartyAsCountInLiquidation; // partyB => collateral => number of connected partyAs
		uint256 lastLiquidationId;
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = SYMBOL_STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
