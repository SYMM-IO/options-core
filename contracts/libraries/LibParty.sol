// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { AppStorage } from "../storages/AppStorage.sol";
import { AccountStorage } from "../storages/AccountStorage.sol";
import { LiquidationStorage } from "../storages/LiquidationStorage.sol";
import { CommonErrors } from "./CommonErrors.sol";
import { LiquidationStatus, LiquidationState, LiquidationDetail } from "../types/LiquidationTypes.sol";

library LibParty {
	// Custom errors
	error NotSolvent(address user, address collateral);

	function requireSolvent(address self, address collateral) internal view {
		if (!isSolvent(self, collateral)) revert NotSolvent(self, collateral);
	}

	function requireInProgressLiquidation(address self, address collateral) internal view {
		if (LiquidationStorage.layout().liquidationStates[self][collateral].status != LiquidationStatus.IN_PROGRESS) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(LiquidationStatus.IN_PROGRESS);
			revert CommonErrors.InvalidState(
				"LiquidationStatus",
				uint8(AppStorage.layout().liquidationStates[self][collateral].status),
				requiredStatuses
			);
		}
	}

	function isSolvent(address self, address collateral) internal view returns (bool) {
		return AppStorage.layout().liquidationStates[self][collateral].status == LiquidationStatus.SOLVENT;
	}

	function getLiquidationState(address self, address collateral) internal view returns (LiquidationState storage) {
		return AppStorage.layout().liquidationStates[self][collateral];
	}

	function getInProgressLiquidationDetail(address self, address collateral) internal view returns (LiquidationDetail storage) {
		return AppStorage.layout().liquidationDetails[getLiquidationState(self, collateral).inProgressLiquidationId];
	}

	function getReleaseInterval(address user) external view returns (uint256) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		return accountLayout.hasConfiguredInterval[user] ? accountLayout.releaseIntervals[user] : accountLayout.defaultReleaseInterval;
	}
}
