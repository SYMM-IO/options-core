// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
pragma solidity >=0.8.19;
import { MarginType } from "../../types/BaseTypes.sol";
import { Bucket, BucketRelationship, BucketBalanceOp } from "../../types/BucketTypes.sol";
interface IBucketFacet {
	event BucketBalanceChanged(
		address indexed owner,
		uint256 bucketId,
		address indexed counterParty,
		uint256 counterPartyBucketId,
		address indexed collateral,
		uint256 amount,
		BucketBalanceOp operation,
		MarginType marginType
	);
	event BucketCreated(address indexed owner, uint256 indexed bucketId);
	event BucketRelationshipCreated(
		uint256 indexed relationshipId,
		address indexed partyA,
		uint256 partyABucketId,
		address indexed partyB,
		uint256 partyBBucketId
	);
	event IntentRelationshipAssigned(uint256 indexed intentId, uint256 indexed relationshipId);
	event TradeRelationshipAssigned(uint256 indexed tradeId, uint256 indexed relationshipId);
	event BucketFundsTransferred(address indexed owner, uint256 indexed fromBucketId, uint256 indexed toBucketId, address collateral, uint256 amount);
	function createBucket(uint256 bucketId) external;
	function getBucket(address owner, uint256 bucketId) external view returns (Bucket memory);
	function isBucketRegistered(address owner, uint256 bucketId) external view returns (bool);
	function transferBetweenBuckets(uint256 fromBucketId, uint256 toBucketId, address collateral, uint256 amount) external;
	function getRelationshipId(address partyA, uint256 partyABucketId, address partyB, uint256 partyBBucketId) external view returns (uint256);
	function getRelationship(uint256 id) external view returns (BucketRelationship memory);
	function getIntentRelationship(uint256 intentId) external view returns (uint256);
	function getTradeRelationship(uint256 tradeId) external view returns (uint256);
}
