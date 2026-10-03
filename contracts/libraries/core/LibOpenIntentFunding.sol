// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
pragma solidity >=0.8.19;

import { LibParty } from "../models/LibParty.sol";
import { LibOpenIntentOps } from "../models/LibOpenIntent.sol";
import { ScheduledReleaseBalanceOps } from "../models/LibScheduledReleaseBalance.sol";
import { OpenIntentStorage } from "../../storages/OpenIntentStorage.sol";
import { FeeManagementStorage } from "../../storages/FeeManagementStorage.sol";
import { OpenIntent } from "../../types/IntentTypes.sol";
import { MarginType } from "../../types/BaseTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason } from "../../types/BalanceTypes.sol";

/// @notice Linked accounting implementation, executed in the Diamond's storage by library DELEGATECALL.
library LibOpenIntentFunding {
	using LibParty for address;
	using LibOpenIntentOps for OpenIntent;
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;

	function collectFees(uint256 intentId, uint256 price) external {
		OpenIntent storage intent = OpenIntentStorage.layout().openIntents[intentId];
		FeeManagementStorage.Layout storage feeLayout = FeeManagementStorage.layout();
		uint256[3] memory fees = intent.getFeesFromUser(price);

		address feeToken = intent.feeStructure.feeToken;

		// Determine affiliate fee collector (use default if none specified)
		address affiliateFeeCollector =
			feeLayout.affiliateFeeCollector[intent.affiliate] == address(0)
				? feeLayout.defaultFeeCollector
				: feeLayout.affiliateFeeCollector[intent.affiliate];

		// Pay platform fees
		ScheduledReleaseBalance storage defaultFeeCollectorBalance = feeLayout.defaultFeeCollector.balanceOf(feeToken);
		defaultFeeCollectorBalance.setup(feeLayout.defaultFeeCollector, feeToken);
		defaultFeeCollectorBalance.instantIsolatedAdd(fees[0], IncreaseBalanceReason.PLATFORM_FEE);

		// Pay affiliate fees
		ScheduledReleaseBalance storage affiliateFeeCollectorBalance = affiliateFeeCollector.balanceOf(feeToken);
		affiliateFeeCollectorBalance.setup(affiliateFeeCollector, feeToken);
		affiliateFeeCollectorBalance.instantIsolatedAdd(fees[1], IncreaseBalanceReason.AFFILIATE_FEE);

		// Pay solver fees
		ScheduledReleaseBalance storage solverFeeCollectorBalance = intent.partyB.balanceOf(intent.partyBBucketId, feeToken);
		solverFeeCollectorBalance.setup(intent.partyB, intent.partyBBucketId, feeToken);
		if (intent.tradeAgreements.marginType == MarginType.ISOLATED) {
			solverFeeCollectorBalance.instantIsolatedAdd(fees[2], IncreaseBalanceReason.SOLVER_FEE);
		} else {
			solverFeeCollectorBalance.scheduledAdd(intent.partyA, intent.partyABucketId, fees[2], MarginType.CROSS, IncreaseBalanceReason.SOLVER_FEE);
		}
	}
}
