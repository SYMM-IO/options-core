// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { Fee } from "../types/BaseTypes.sol";

library FeeManagementStorage {
	bytes32 internal constant FEE_MANAGEMENT_STORAGE_SLOT = keccak256("diamond.standard.storage.feeManagement");

	struct Layout {
		address defaultFeeCollector;
		mapping(address => bool) affiliateStatus;
		mapping(address => address) affiliateFeeCollector;
		mapping(address => mapping(uint256 => Fee)) affiliateFees; // affiliate address => symbolId => fee
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = FEE_MANAGEMENT_STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
