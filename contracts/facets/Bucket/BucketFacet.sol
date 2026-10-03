// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
pragma solidity >=0.8.19;
import { LibBucket } from "../../libraries/core/LibBucket.sol";
import { LibParty } from "../../libraries/models/LibParty.sol";
import { LibBalanceOperations } from "../../libraries/core/LibBalanceOperations.sol";
import { BucketStorage } from "../../storages/BucketStorage.sol";
import { OpenIntentStorage } from "../../storages/OpenIntentStorage.sol";
import { TradeStorage } from "../../storages/TradeStorage.sol";
import { Bucket, BucketRelationship } from "../../types/BucketTypes.sol";
import { MarginType } from "../../types/BaseTypes.sol";
import { BucketErrors } from "../../errors/BucketErrors.sol";
import { Pausable } from "../../utils/Pausable.sol";
import { ReentrancyGuard } from "../../utils/ReentrancyGuard.sol";
import { IBucketFacet } from "./IBucketFacet.sol";
/// @notice Native owner-local funding buckets use ordinary wallet authorization and explicit indices.
contract BucketFacet is IBucketFacet, Pausable, ReentrancyGuard {
	using LibParty for address;
	function createBucket(uint256 bucketId) external {
		LibBucket.register(msg.sender, bucketId);
	}
	function getBucket(address owner, uint256 bucketId) external view returns (Bucket memory) {
		return Bucket(owner, bucketId, LibBucket.isRegistered(owner, bucketId));
	}
	function isBucketRegistered(address owner, uint256 bucketId) external view returns (bool) {
		return LibBucket.isRegistered(owner, bucketId);
	}
	function transferBetweenBuckets(
		uint256 fromBucketId,
		uint256 toBucketId,
		address collateral,
		uint256 amount
	) external nonReentrant whenInternalTransferNotPaused whenPartyNotPaused(msg.sender) {
		if (fromBucketId == toBucketId) revert BucketErrors.SameBucket();
		LibBucket.requireNotSuspended(msg.sender, fromBucketId);
		LibBucket.requireNotSuspended(msg.sender, toBucketId);
		LibBucket.requireInstantModeInactive(msg.sender, fromBucketId);
		LibBucket.register(msg.sender, toBucketId);
		LibBucket.requireRegistered(msg.sender, fromBucketId);
		msg.sender.requireSolvent(fromBucketId, address(0), 0, collateral, MarginType.ISOLATED);
		msg.sender.requireSolvent(toBucketId, address(0), 0, collateral, MarginType.ISOLATED);
		LibBalanceOperations.internalTransfer(collateral, msg.sender, fromBucketId, msg.sender, toBucketId, amount);
		emit BucketFundsTransferred(msg.sender, fromBucketId, toBucketId, collateral, amount);
	}
	function getRelationshipId(address a, uint256 bucketA, address b, uint256 bucketB) external view returns (uint256) {
		return BucketStorage.layout().relationshipIds[a][bucketA][b][bucketB];
	}
	function getRelationship(uint256 id) external view returns (BucketRelationship memory) {
		return BucketStorage.layout().relationships[id];
	}
	function getIntentRelationship(uint256 id) external view returns (uint256) {
		return OpenIntentStorage.layout().openIntents[id].relationshipId;
	}
	function getTradeRelationship(uint256 id) external view returns (uint256) {
		return TradeStorage.layout().trades[id].relationshipId;
	}
}
