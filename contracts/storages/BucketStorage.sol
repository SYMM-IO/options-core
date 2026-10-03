// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
pragma solidity >=0.8.19;
import { BucketRelationship } from "../types/BucketTypes.sol";
library BucketStorage {
	// Compatibility namespace: retained to preserve existing storage locations.
	bytes32 internal constant BUCKET_STORAGE_SLOT = keccak256("diamond.standard.storage.explicitPools");
	struct Layout {
		mapping(address => mapping(uint256 => bool)) registered;
		mapping(address => mapping(uint256 => mapping(address => mapping(uint256 => uint256)))) relationshipIds;
		mapping(uint256 => BucketRelationship) relationships;
		uint256 lastRelationshipId;
		mapping(address => mapping(uint256 => bool)) suspendedBuckets;
		mapping(address => mapping(uint256 => bool)) partyBEmergencyBuckets;
		mapping(address => mapping(uint256 => address)) boundPartyBs;
		mapping(address => mapping(uint256 => uint256)) boundPartyBBucketIds;
		mapping(address => mapping(uint256 => uint256)) unbindingRequestTimes;
	}
	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = BUCKET_STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
