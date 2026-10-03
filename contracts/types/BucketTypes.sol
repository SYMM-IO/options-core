// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
pragma solidity >=0.8.19;

struct BucketRef { address owner; uint256 bucketId; }
struct Bucket { address owner; uint256 bucketId; bool registered; }
struct BucketRelationship { address partyA; uint256 partyABucketId; address partyB; uint256 partyBBucketId; bool exists; }

enum BucketBalanceOp { INCREASE, DECREASE, LOCK, UNLOCK, SYNC, MM_INCREASE, MM_DECREASE, ALLOCATE, DEALLOCATE }
