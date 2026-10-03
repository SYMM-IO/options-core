// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
pragma solidity >=0.8.19;
import { BucketStorage } from "../../storages/BucketStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { CounterPartyRelationsStorage } from "../../storages/CounterPartyRelationsStorage.sol";
import { OpenIntentStorage } from "../../storages/OpenIntentStorage.sol";
import { TradeStorage } from "../../storages/TradeStorage.sol";
import { CrossEntry, ScheduledReleaseBalance } from "../../types/BalanceTypes.sol";
import { BucketRelationship } from "../../types/BucketTypes.sol";
import { BucketErrors } from "../../errors/BucketErrors.sol";
import { IBucketFacet } from "../../facets/Bucket/IBucketFacet.sol";
import { StateControlStorage } from "../../storages/StateControlStorage.sol";
import { AppStorage } from "../../storages/AppStorage.sol";
import { SystemErrors } from "../../errors/SystemErrors.sol";
import { PartyRelationsErrors } from "../../errors/PartyRelationsErrors.sol";
/// @notice Bucket identities are wallet and owner-local index tuples, never caller identities.
library LibBucket {
	function isSuspended(address owner, uint256 bucketId) internal view returns (bool) {
		return StateControlStorage.layout().suspendedAddresses[owner] || BucketStorage.layout().suspendedBuckets[owner][bucketId];
	}
	function isPartyBEmergency(address owner, uint256 bucketId) internal view returns (bool) {
		return StateControlStorage.layout().partyBEmergencyMode[owner] || BucketStorage.layout().partyBEmergencyBuckets[owner][bucketId];
	}
	function requireNotSuspended(address owner, uint256 bucketId) internal view {
		if (isSuspended(owner, bucketId)) revert SystemErrors.UserSuspended(owner);
	}
	function requirePartyBNotEmergency(address owner, uint256 bucketId) internal view {
		if (isPartyBEmergency(owner, bucketId)) revert SystemErrors.PartyBInEmergencyMode(owner);
	}
	function requireInstantModeInactive(address owner, uint256 bucketId) internal view {
		if (bucketId == 0 && CounterPartyRelationsStorage.layout().instantActionsMode[owner] && !AppStorage.layout().callFromInstantLayer)
			revert PartyRelationsErrors.InstantModeActive(owner);
	}
	function register(address owner, uint256 bucketId) internal {
		if (owner == address(0)) revert BucketErrors.InvalidBucketOwner(owner);
		if (!BucketStorage.layout().registered[owner][bucketId]) {
			BucketStorage.layout().registered[owner][bucketId] = true;
			emit IBucketFacet.BucketCreated(owner, bucketId);
		}
	}
	function isRegistered(address owner, uint256 bucketId) internal view returns (bool) {
		return owner != address(0) && (bucketId == 0 || BucketStorage.layout().registered[owner][bucketId]);
	}
	function requireRegistered(address owner, uint256 bucketId) internal view {
		if (!isRegistered(owner, bucketId)) revert BucketErrors.BucketNotRegistered(owner, bucketId);
	}
	function boundPartyB(address owner, uint256 bucketId) internal view returns (address) {
		return bucketId == 0 ? CounterPartyRelationsStorage.layout().boundPartyB[owner] : BucketStorage.layout().boundPartyBs[owner][bucketId];
	}
	function boundPartyBBucketId(address owner, uint256 bucketId) internal view returns (uint256) {
		return BucketStorage.layout().boundPartyBBucketIds[owner][bucketId];
	}
	function bindIntentRelationship(
		uint256 intentId,
		address partyA,
		uint256 bucketA,
		address partyB,
		uint256 bucketB
	) internal returns (uint256 id) {
		register(partyA, bucketA);
		requireRegistered(partyB, bucketB);
		if (partyA == partyB) revert BucketErrors.NativeCounterpartyRequired();
		BucketStorage.Layout storage l = BucketStorage.layout();
		id = l.relationshipIds[partyA][bucketA][partyB][bucketB];
		if (id == 0) {
			id = ++l.lastRelationshipId;
			l.relationshipIds[partyA][bucketA][partyB][bucketB] = id;
			l.relationships[id] = BucketRelationship(partyA, bucketA, partyB, bucketB, true);
			emit IBucketFacet.BucketRelationshipCreated(id, partyA, bucketA, partyB, bucketB);
		}
		emit IBucketFacet.IntentRelationshipAssigned(intentId, id);
	}
	function validateIntentRelationship(uint256 intentId, address partyA, uint256 bucketA, address partyB, uint256 bucketB) internal view {
		uint256 id = OpenIntentStorage.layout().openIntents[intentId].relationshipId;
		if (id == 0) return;
		BucketRelationship storage r = BucketStorage.layout().relationships[id];
		if (r.partyA != partyA || r.partyABucketId != bucketA || r.partyB != partyB || r.partyBBucketId != bucketB)
			revert BucketErrors.RelationshipMismatch(intentId);
	}
	function inheritIntentRelationship(uint256 parentIntentId, uint256 childIntentId) internal returns (uint256 id) {
		id = OpenIntentStorage.layout().openIntents[parentIntentId].relationshipId;
		if (id != 0) emit IBucketFacet.IntentRelationshipAssigned(childIntentId, id);
	}
	function bindTradeRelationship(uint256 tradeId, uint256 intentId) internal returns (uint256 id) {
		id = OpenIntentStorage.layout().openIntents[intentId].relationshipId;
		if (id != 0) emit IBucketFacet.TradeRelationshipAssigned(tradeId, id);
	}
	function isNativeIntent(uint256 id) internal view returns (bool) {
		return OpenIntentStorage.layout().openIntents[id].relationshipId != 0;
	}
	function validateNativeTradeTransfer(uint256 id) internal view {
		if (TradeStorage.layout().trades[id].relationshipId != 0) revert BucketErrors.NativeTradeTransferUnsupported(id);
	}
	function nonce(address owner, uint256 bucketId, address cp, uint256 cpBucketId) internal view returns (uint256) {
		if (bucketId == 0 && cpBucketId == 0) return AccountStorage.layout().nonces[owner][cp];
		return AccountStorage.layout().bucketNonces[owner][bucketId][cp][cpBucketId];
	}
	function incrementNonce(address owner, uint256 bucketId, address cp, uint256 cpBucketId) internal {
		if (bucketId == 0 && cpBucketId == 0) AccountStorage.layout().nonces[owner][cp] += 1;
		else AccountStorage.layout().bucketNonces[owner][bucketId][cp][cpBucketId] += 1;
	}
	function requireNativeBacking(
		uint256 id,
		address account,
		uint256 bucketId,
		address cp,
		uint256 cpBucketId,
		address collateral,
		address feeToken
	) internal view {
		if (!isNativeIntent(id)) return;
		_requireCash(account, bucketId, cp, cpBucketId, collateral);
		if (feeToken != collateral) _requireCash(account, bucketId, cp, cpBucketId, feeToken);
	}
	function requireNativeTradeBacking(
		uint256 id,
		address account,
		uint256 bucketId,
		address cp,
		uint256 cpBucketId,
		address collateral,
		address feeToken
	) internal view {
		if (TradeStorage.layout().trades[id].relationshipId == 0) return;
		_requireCash(account, bucketId, cp, cpBucketId, collateral);
		if (feeToken != collateral) _requireCash(account, bucketId, cp, cpBucketId, feeToken);
	}
	function _requireCash(address account, uint256 bucketId, address cp, uint256 cpBucketId, address token) private view {
		ScheduledReleaseBalance storage balance =
			bucketId == 0 ? AccountStorage.layout().balances[account][token] : AccountStorage.layout().bucketedBalances[account][bucketId][token];
		CrossEntry storage entry = cpBucketId == 0 ? balance.crossBalance[cp] : balance.bucketedCrossBalance[cp][cpBucketId];
		if (entry.balance < 0) revert BucketErrors.NativeBackingInsufficient(account, bucketId, cp, cpBucketId, token);
		uint256 cash = uint256(entry.balance);
		if (entry.locked > cash || entry.totalMM > cash - entry.locked)
			revert BucketErrors.NativeBackingInsufficient(account, bucketId, cp, cpBucketId, token);
	}
}
