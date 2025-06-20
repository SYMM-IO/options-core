// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

library LibDecimals {
	// Constants
	uint256 private constant PRECISION_FACTOR = 1e18;

	function normalizeAmount(address token, uint256 amount) internal view returns (uint256) {
		uint8 decimals = IERC20Metadata(token).decimals();
		return (amount * PRECISION_FACTOR) / (10 ** decimals);
	}

	function denormalizeAmount(address token, uint256 amount) internal view returns (uint256) {
		uint8 decimals = IERC20Metadata(token).decimals();
		return (amount * (10 ** decimals)) / PRECISION_FACTOR;
	}
}
