// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { AccountStorage } from "../storages/AccountStorage.sol";
import { AppStorage } from "../storages/AppStorage.sol";
import { LiquidationStorage } from "../storages/LiquidationStorage.sol";

import { LiquidationStatus, LiquidationState, LiquidationDetail } from "../types/LiquidationTypes.sol";
import { MarginType } from "../types/BaseTypes.sol";

import { CommonErrors } from "./CommonErrors.sol";

library LibParty {
	// Custom errors
	error NotSolvent(address user, address counterParty, address collateral, MarginType marginType);

	function requireSolventParty(address self, address counterParty, address collateral, MarginType marginType) internal view {
		if (!isSolvent(self, counterParty, collateral, marginType)) revert NotSolvent(self, counterParty, collateral, marginType);
	}

	function requireSolventPartyA(address self, address counterParty, address collateral) internal view {
		if (LiquidationStorage.layout().partyALiquidationState[self][counterParty][collateral].status != LiquidationStatus.SOLVENT)
			revert NotSolvent(self, counterParty, collateral, MarginType.CROSS);
	}

	function requireSolventPartyB(address self, address counterParty, address collateral, MarginType marginType) internal view {
		if (
			marginType == MarginType.ISOLATED &&
			LiquidationStorage.layout().partyBIsolatedLiquidationState[self][collateral].status != LiquidationStatus.SOLVENT
		) revert NotSolvent(self, counterParty, collateral, marginType);
		if (
			marginType == MarginType.CROSS &&
			LiquidationStorage.layout().partyBCrossLiquidationState[self][counterParty][collateral].status != LiquidationStatus.SOLVENT
		) revert NotSolvent(self, counterParty, collateral, marginType);
	}

	function requirePartyAInLiquidationProgress(address self, address partyB, address collateral) internal view {
		if (LiquidationStorage.layout().partyALiquidationState[self][partyB][collateral].status != LiquidationStatus.IN_PROGRESS) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(LiquidationStatus.IN_PROGRESS);
			revert CommonErrors.InvalidState(
				"LiquidationStatus",
				uint8(LiquidationStorage.layout().partyALiquidationState[self][partyB][collateral].status),
				requiredStatuses
			);
		}
	}

	function requirePartyBInCrossLiquidationProgress(address self, address partyA, address collateral) internal view {
		if (LiquidationStorage.layout().partyBCrossLiquidationState[self][partyA][collateral].status != LiquidationStatus.IN_PROGRESS) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(LiquidationStatus.IN_PROGRESS);
			revert CommonErrors.InvalidState(
				"LiquidationStatus",
				uint8(LiquidationStorage.layout().partyBCrossLiquidationState[self][partyA][collateral].status),
				requiredStatuses
			);
		}
	}

	function requirePartyBInIsolatedLiquidationProgress(address self, address collateral) internal view {
		if (LiquidationStorage.layout().partyBIsolatedLiquidationState[self][collateral].status != LiquidationStatus.IN_PROGRESS) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(LiquidationStatus.IN_PROGRESS);
			revert CommonErrors.InvalidState(
				"LiquidationStatus",
				uint8(LiquidationStorage.layout().partyBIsolatedLiquidationState[self][collateral].status),
				requiredStatuses
			);
		}
	}

	function isSolvent(address self, address counterParty, address collateral, MarginType marginType) internal view returns (bool) {
		if (AppStorage.layout().partyBConfigs[self].isActive) {
			if (
				marginType == MarginType.ISOLATED &&
				LiquidationStorage.layout().partyBIsolatedLiquidationState[self][collateral].status != LiquidationStatus.SOLVENT
			) return false;
			if (
				marginType == MarginType.CROSS &&
				LiquidationStorage.layout().partyBCrossLiquidationState[self][counterParty][collateral].status != LiquidationStatus.SOLVENT
			) return false;
		} else {
			if (
				marginType == MarginType.CROSS &&
				LiquidationStorage.layout().partyALiquidationState[self][counterParty][collateral].status != LiquidationStatus.SOLVENT
			) return false;
		}
		return true;
	}

	function getReleaseInterval(address user) internal view returns (uint256) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		return accountLayout.hasConfiguredInterval[user] ? accountLayout.releaseIntervals[user] : accountLayout.defaultReleaseInterval;
	}
}
