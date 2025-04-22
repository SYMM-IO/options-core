// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

struct PublicKey {
	uint256 x;
	uint8 parity;
}

struct MuonConfig {
	uint256 muonAppId;
	PublicKey muonPublicKey;
	address validGateway;
}

struct SchnorrSign {
	uint256 signature;
	address owner;
	address nonce;
}
