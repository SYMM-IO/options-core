// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
pragma solidity >=0.8.19;
library BucketErrors {
	error InvalidBucketOwner(address owner);
	error BucketNotRegistered(address owner, uint256 bucketId);
	error SameBucket();
	error NativeCrossMarginRequired();
	error NativeCounterpartyRequired();
	error RelationshipMismatch(uint256 intentId);
	error NativeTradeTransferUnsupported(uint256 tradeId);
	error NativeIntegrationUnsupported();
	error NativeBackingInsufficient(address account, uint256 bucketId, address counterParty, uint256 counterPartyBucketId, address token);
}
