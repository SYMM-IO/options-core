// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
pragma solidity >=0.8.19;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

interface IMultiAccount {
	function _call(address account, bytes[] memory _callDatas) external;
	function owners(address account) external view returns (address);
}

interface ISymmioPartyB {
	function _call(bytes[] calldata _callDatas) external;
}

interface ISymmio {
	function setCallFromInstantLayer(bool _callFromInstantLayer) external;
}

contract InstantLayer is AccessControlEnumerable, ReentrancyGuard, EIP712 {
	bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
	bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

	// EIP-712 type hash
	bytes32 public constant OPERATION_TYPEHASH =
		keccak256("SignedOperation(address account,address accountSource,address signer,bytes callData,uint256 nonce,uint256 deadline)");

	ISymmio public immutable symmio;

	mapping(address => uint256) public nonces;
	mapping(uint256 => Template) public templates;
	mapping(address => bool) public registeredPartyBs;
	mapping(address => bool) public registeredMultiAccounts;
	uint256 public nextTemplateId;

	struct Operation {
		address account; // For PartyA operations - which account to use
		bytes callData; // The actual calldata with placeholders
		uint256[] insertionPoints; // Where to insert return values
		uint256[] sourceIndices; // Which operation's return value to use
		address signer; // Expected signer for this operation
	}

	struct Template {
		string name;
		Operation[] operations;
		bool active;
	}

	struct SignedOperation {
		address account; // The account to use (for PartyA operations)
		address accountSource; // The MultiAccount contract (for PartyA operations)
		address signer; // The signer
		bytes callData; // The actual Symmio core call
		uint256 nonce;
		uint256 deadline;
		bytes signature;
	}

	event TemplateAdded(uint256 indexed templateId, string name);
	event TemplateUpdated(uint256 indexed templateId, bool active);
	event OperationsExecuted(uint256 indexed templateId, address indexed executor);
	event BatchExecuted(address indexed executor, uint256 operationCount);
	event NonceIncremented(address indexed user, uint256 newNonce);
	event PartyBRegistered(address indexed partyB);
	event PartyBUnregistered(address indexed partyB);
	event MultiAccountRegistered(address indexed multiAccount);
	event MultiAccountUnregistered(address indexed multiAccount);

	error InvalidSignature(address signer);
	error DeadlineExpired(uint256 deadline);
	error InvalidNonce(address user, uint256 expected, uint256 provided);
	error TemplateNotActive(uint256 templateId);
	error InvalidTemplate(uint256 templateId);
	error OperationFailed(uint256 operationIndex);
	error ArrayLengthMismatch();
	error InvalidAccount(address account);
	error InvalidSigner(address expected, address provided);
	error UnregisteredTarget();
	error UnregisteredPartyB(address partyB);

	constructor(address _symmio, address _admin) EIP712("SymmioInstantLayer", "1") {
		symmio = ISymmio(_symmio);

		_grantRole(DEFAULT_ADMIN_ROLE, _admin);
		_grantRole(ADMIN_ROLE, _admin);
		_grantRole(OPERATOR_ROLE, _admin);
	}

	/**
	 * @notice Register a PartyB contract
	 * @param partyB Address to register as PartyB
	 */
	function registerPartyB(address partyB) external onlyRole(ADMIN_ROLE) {
		registeredPartyBs[partyB] = true;
		emit PartyBRegistered(partyB);
	}

	/**
	 * @notice Unregister a PartyB contract
	 * @param partyB Address to unregister
	 */
	function unregisterPartyB(address partyB) external onlyRole(ADMIN_ROLE) {
		registeredPartyBs[partyB] = false;
		emit PartyBUnregistered(partyB);
	}

	/**
	 * @notice Register a MultiAccount contract
	 * @param multiAccount Address to register as MultiAccount
	 */
	function registerMultiAccount(address multiAccount) external onlyRole(ADMIN_ROLE) {
		registeredMultiAccounts[multiAccount] = true;
		emit MultiAccountRegistered(multiAccount);
	}

	/**
	 * @notice Unregister a MultiAccount contract
	 * @param multiAccount Address to unregister
	 */
	function unregisterMultiAccount(address multiAccount) external onlyRole(ADMIN_ROLE) {
		registeredMultiAccounts[multiAccount] = false;
		emit MultiAccountUnregistered(multiAccount);
	}

	/**
	 * @notice Register multiple PartyB contracts
	 * @param partyBs Array of addresses to register
	 */
	function registerPartyBBatch(address[] calldata partyBs) external onlyRole(ADMIN_ROLE) {
		for (uint256 i = 0; i < partyBs.length; i++) {
			registeredPartyBs[partyBs[i]] = true;
			emit PartyBRegistered(partyBs[i]);
		}
	}

	/**
	 * @notice Register multiple MultiAccount contracts
	 * @param multiAccounts Array of addresses to register
	 */
	function registerMultiAccountBatch(address[] calldata multiAccounts) external onlyRole(ADMIN_ROLE) {
		for (uint256 i = 0; i < multiAccounts.length; i++) {
			registeredMultiAccounts[multiAccounts[i]] = true;
			emit MultiAccountRegistered(multiAccounts[i]);
		}
	}

	/**
	 * @notice Check if an address is a registered PartyB
	 * @param addr Address to check
	 * @return Whether the address is a registered PartyB
	 */
	function isPartyB(address addr) public view returns (bool) {
		return registeredPartyBs[addr];
	}

	/**
	 * @notice Check if an address is a registered MultiAccount
	 * @param addr Address to check
	 * @return Whether the address is a registered MultiAccount
	 */
	function isMultiAccount(address addr) public view returns (bool) {
		return registeredMultiAccounts[addr];
	}

	/**
	 * @notice Add a new template
	 * @param name Template name
	 * @param operations Array of operations in the template
	 */
	function addTemplate(string calldata name, Operation[] calldata operations) external onlyRole(ADMIN_ROLE) {
		uint256 templateId = nextTemplateId++;
		Template storage template = templates[templateId];
		template.name = name;
		template.active = true;

		for (uint256 i = 0; i < operations.length; i++) {
			template.operations.push(operations[i]);
		}

		emit TemplateAdded(templateId, name);
	}

	/**
	 * @notice Toggle template active status
	 * @param templateId Template to update
	 * @param active New status
	 */
	function setTemplateActive(uint256 templateId, bool active) external onlyRole(ADMIN_ROLE) {
		if (templateId >= nextTemplateId) revert InvalidTemplate(templateId);
		templates[templateId].active = active;
		emit TemplateUpdated(templateId, active);
	}

	/**
	 * @notice Execute operations based on a template
	 * @param templateId Template to use
	 * @param signedOps Array of signed operations matching the template
	 */
	function executeTemplate(uint256 templateId, SignedOperation[] calldata signedOps) external nonReentrant {
		if (templateId >= nextTemplateId) revert InvalidTemplate(templateId);

		Template storage template = templates[templateId];
		if (!template.active) revert TemplateNotActive(templateId);
		if (signedOps.length != template.operations.length) revert ArrayLengthMismatch();

		// Set instant mode active
		symmio.setCallFromInstantLayer(true);

		bytes[] memory results = new bytes[](signedOps.length);

		bool success = true;
		for (uint256 i = 0; i < signedOps.length && success; i++) {
			Operation memory op = template.operations[i];
			SignedOperation calldata signedOp = signedOps[i];

			// Verify signature and nonce
			_verifyOperation(op, signedOp);

			// Prepare calldata with insertions from previous results
			bytes memory finalCallData = _insertResults(signedOp.callData, op.insertionPoints, op.sourceIndices, results);

			// Update operation with account from signed op
			op.account = signedOp.account;

			// Execute operation
			(success, results[i]) = _executeOperationSafe(signedOp, finalCallData);
			if (!success) {
				symmio.setCallFromInstantLayer(false);
				revert OperationFailed(i);
			}
		}

		// Reset instant mode
		symmio.setCallFromInstantLayer(false);
		emit OperationsExecuted(templateId, msg.sender);
	}

	/**
	 * @notice Execute a batch of operations without template
	 * @param signedOps Array of signed operations
	 */
	function executeBatch(SignedOperation[] calldata signedOps) external nonReentrant {
		symmio.setCallFromInstantLayer(true);

		bool success = true;
		for (uint256 i = 0; i < signedOps.length && success; i++) {
			Operation memory op = Operation({
				account: signedOps[i].account,
				callData: "",
				insertionPoints: new uint256[](0),
				sourceIndices: new uint256[](0),
				signer: signedOps[i].signer
			});

			// Verify signature and nonce
			_verifyOperation(op, signedOps[i]);

			(success, ) = _executeOperationSafe(signedOps[i], signedOps[i].callData);
			if (!success) {
				symmio.setCallFromInstantLayer(false);
				revert OperationFailed(i);
			}
		}

		symmio.setCallFromInstantLayer(false);
		emit BatchExecuted(msg.sender, signedOps.length);
	}

	/**
	 * @notice Verify signature for an operation
	 * @param op The operation details
	 * @param signedOp The signed operation
	 */
	function _verifyOperation(Operation memory op, SignedOperation calldata signedOp) private {
		if (signedOp.deadline < block.timestamp) revert DeadlineExpired(signedOp.deadline);

		address expectedSigner;

		// Determine if this is a PartyB operation based on accountSource
		if (isPartyB(signedOp.signer)) {
			// PartyB operation - the signer is the PartyB contract itself
			expectedSigner = signedOp.signer;

			// Verify the signer matches accountSource for PartyB
			if (signedOp.signer != signedOp.accountSource) {
				revert InvalidSigner(signedOp.accountSource, signedOp.signer);
			}
		} else if (isMultiAccount(signedOp.accountSource)) {
			// PartyA operation - verify the account owner's signature
			if (signedOp.account == address(0)) revert InvalidAccount(signedOp.account);

			IMultiAccount multiAccount = IMultiAccount(signedOp.accountSource);
			address owner = multiAccount.owners(signedOp.account);
			if (owner == address(0)) revert InvalidAccount(signedOp.account);
			expectedSigner = owner;
		} else {
			// Neither registered PartyB nor MultiAccount
			revert UnregisteredTarget();
		}

		// Check template signer requirement if specified
		if (op.signer != address(0) && op.signer != expectedSigner) {
			revert InvalidSigner(op.signer, expectedSigner);
		}

		bytes32 hash = getOperationHash(signedOp);

		// Verify signature using OpenZeppelin's SignatureChecker
		if (!SignatureChecker.isValidSignatureNow(expectedSigner, hash, signedOp.signature)) {
			revert InvalidSignature(expectedSigner);
		}

		// Verify and increment nonce
		uint256 expectedNonce = nonces[expectedSigner];
		if (signedOp.nonce != expectedNonce) {
			revert InvalidNonce(expectedSigner, expectedNonce, signedOp.nonce);
		}

		nonces[expectedSigner]++;
		emit NonceIncremented(expectedSigner, nonces[expectedSigner]);
	}

	/**
	 * @notice Execute operation safely
	 * @param signedOp Signed operation details
	 * @param callData The calldata to execute
	 * @return success Whether the operation succeeded
	 * @return result The return data
	 */
	function _executeOperationSafe(SignedOperation calldata signedOp, bytes memory callData) private returns (bool success, bytes memory result) {
		// Determine target based on accountSource type
		bool isPartyBOperation = isPartyB(signedOp.signer);

		bytes[] memory callDatas = new bytes[](1);
		callDatas[0] = callData;

		if (!isPartyBOperation) {
			// PartyA operation through MultiAccount
			(success, result) = signedOp.accountSource.call(abi.encodeWithSelector(IMultiAccount._call.selector, signedOp.account, callDatas));
		} else {
			// PartyB operation
			(success, result) = signedOp.signer.call(abi.encodeWithSelector(ISymmioPartyB._call.selector, callDatas));
		}
	}

	function _insertResults(
		bytes memory callData,
		uint256[] memory insertionPoints,
		uint256[] memory sourceIndices,
		bytes[] memory results
	) private pure returns (bytes memory) {
		if (insertionPoints.length == 0) return callData;

		// Copy callData to modify it
		bytes memory modifiedCallData = callData;

		// Replace each result at its insertion point
		for (uint256 i = 0; i < insertionPoints.length; i++) {
			if (sourceIndices[i] < results.length) {
				// Decode as bytes32 (works for address, uint256, etc.)
				bytes32 value = abi.decode(results[sourceIndices[i]], (bytes32));

				uint256 offset = insertionPoints[i];
				assembly {
					mstore(add(modifiedCallData, add(32, offset)), value)
				}
			}
		}

		return modifiedCallData;
	}

	/**
	 * @notice Get the EIP-712 typed data hash for an operation
	 * @param op The signed operation
	 * @return The EIP-712 hash that should be signed
	 */
	function getOperationHash(SignedOperation calldata op) public view returns (bytes32) {
		bytes32 structHash = keccak256(
			abi.encode(OPERATION_TYPEHASH, op.account, op.accountSource, op.signer, keccak256(op.callData), op.nonce, op.deadline)
		);

		return _hashTypedDataV4(structHash);
	}

	/**
	 * @notice Get the EIP-712 domain separator
	 * @return The domain separator for this contract
	 */
	function domainSeparator() external view returns (bytes32) {
		return _domainSeparatorV4();
	}

	// View functions
	function getTemplate(uint256 templateId) external view returns (Template memory) {
		return templates[templateId];
	}

	function getTemplateOperations(uint256 templateId) external view returns (Operation[] memory) {
		return templates[templateId].operations;
	}

	/**
	 * @notice Verify a signature externally (useful for testing)
	 * @param signer Expected signer address
	 * @param hash Message hash
	 * @param signature Signature bytes
	 * @return Whether the signature is valid
	 */
	function verifySignature(address signer, bytes32 hash, bytes calldata signature) external view returns (bool) {
		return SignatureChecker.isValidSignatureNow(signer, hash, signature);
	}
}
