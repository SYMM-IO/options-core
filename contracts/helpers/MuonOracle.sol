// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IMuonOracle } from "../interfaces/IMuonOracle.sol";
import { SchnorrSECP256K1Verifier } from "./SchnorrSECP256K1Verifier.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MuonOracle is IMuonOracle, SchnorrSECP256K1Verifier, AccessControlEnumerable {
	using ECDSA for bytes32;

	// Custom errors
	error InvalidSignature();
	error InvalidGatewaySignature(address signer, address expectedGateway);

	bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
	MuonConfig public config;
	bool public checkGatewaySignature;

	constructor(MuonConfig memory _config, address admin) {
		validatePubKey(_config.muonPublicKey.x);
		config = _config;
		_grantRole(DEFAULT_ADMIN_ROLE, admin);
		_grantRole(SETTER_ROLE, admin);
	}

	function verifyTSSAndGW(bytes32 _data, bytes calldata _reqId, SchnorrSign calldata _signature, bytes calldata _gatewaySignature) external view {
		bytes32 hash = keccak256(abi.encodePacked(config.muonAppId, _reqId, _data));

		if (!verifySignature(config.muonPublicKey.x, config.muonPublicKey.parity, _signature.signature, uint256(hash), _signature.nonce))
			revert InvalidSignature();

		hash = hash.toEthSignedMessageHash();
		address gatewaySignatureSigner = hash.recover(_gatewaySignature);

		if (gatewaySignatureSigner != config.validGateway) revert InvalidGatewaySignature(gatewaySignatureSigner, config.validGateway);
	}

	function setConfig(MuonConfig memory _config) external onlyRole(SETTER_ROLE) {
		validatePubKey(_config.muonPublicKey.x);
		config = _config;
		emit ConfigUpdated(_config);
	}
}
