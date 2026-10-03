// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
pragma solidity >=0.8.19;
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { AppStorage } from "../../storages/AppStorage.sol";
import { LiquidationStorage } from "../../storages/LiquidationStorage.sol";
import { MarginType } from "../../types/BaseTypes.sol";
import { ScheduledReleaseBalance } from "../../types/BalanceTypes.sol";
import { BalanceErrors } from "../../errors/BalanceErrors.sol";
library LibParty {
	function requireSolvent(address owner, address cp, address token, MarginType marginType) internal view {
		requireSolvent(owner, 0, cp, 0, token, marginType);
	}
	function requireSolvent(address owner, uint256 bucketId, address cp, uint256 cpBucketId, address token, MarginType marginType) internal view {
		if (!isSolvent(owner, bucketId, cp, cpBucketId, token, marginType)) revert BalanceErrors.NotSolvent(owner, cp, token, marginType);
	}
	function isSolvent(address owner, address cp, address token, MarginType marginType) internal view returns (bool) {
		return isSolvent(owner, 0, cp, 0, token, marginType);
	}
	function isSolvent(
		address owner,
		uint256 bucketId,
		address cp,
		uint256 cpBucketId,
		address token,
		MarginType marginType
	) internal view returns (bool) {
		if (isPartyB(owner))
			return
				marginType == MarginType.ISOLATED
					? liquidationId(address(0), 0, owner, bucketId, token) == 0
					: liquidationId(cp, cpBucketId, owner, bucketId, token) == 0;
		return marginType == MarginType.ISOLATED || liquidationId(owner, bucketId, cp, cpBucketId, token) == 0;
	}
	function liquidationId(address partyA, uint256 bucketA, address partyB, uint256 bucketB, address token) internal view returns (uint256) {
		if (bucketA == 0 && bucketB == 0) return LiquidationStorage.layout().inProgressLiquidationIds[partyA][partyB][token];
		return LiquidationStorage.layout().bucketInProgressLiquidationIds[partyA][bucketA][partyB][bucketB][token];
	}
	function isPartyB(address owner) internal view returns (bool) {
		return AppStorage.layout().partyBConfigs[owner].isActive;
	}
	function balanceOf(address owner, address token) internal view returns (ScheduledReleaseBalance storage) {
		return balanceOf(owner, 0, token);
	}
	function balanceOf(address owner, uint256 bucketId, address token) internal view returns (ScheduledReleaseBalance storage) {
		if (bucketId == 0) return AccountStorage.layout().balances[owner][token];
		return AccountStorage.layout().bucketedBalances[owner][bucketId][token];
	}
	function getReleaseInterval(address user) internal view returns (uint256) {
		AccountStorage.Layout storage l = AccountStorage.layout();
		return l.hasConfiguredInterval[user] ? l.releaseIntervals[user] : l.defaultReleaseInterval;
	}
}
