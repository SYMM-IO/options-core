// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { AccessControlStorage } from "../storages/AccessControlStorage.sol";
import { ReentrancyGuardErrors } from "../errors/ReentrancyGuardErrors.sol";

abstract contract ReentrancyGuard {
	uint8 private constant _NOT_ENTERED = 0;
	uint8 private constant _ENTERED = 1;

	modifier nonReentrant() {
		AccessControlStorage.Layout storage layout = AccessControlStorage.layout();
		if (layout.reentrancyGuardStatus == _ENTERED) revert ReentrancyGuardErrors.ReentrantCall();
		layout.reentrancyGuardStatus = _ENTERED;
		_;
		layout.reentrancyGuardStatus = _NOT_ENTERED;
	}
}
