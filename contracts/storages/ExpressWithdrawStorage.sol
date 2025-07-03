// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { ExpressWithdraw } from "../types/ExpressWithdrawTypes.sol";

library ExpressWithdrawStorage {
	bytes32 internal constant STORAGE_SLOT = keccak256("diamond.standard.storage.expressWithdraw");

	struct Layout {
		mapping(address => bool) providers; // provider -> isActive
		mapping(uint256 => ExpressWithdraw) expressWithdraws;
		uint256 lastExpressWithdrawId;
		address invalidExpressWithdrawsPool;
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
