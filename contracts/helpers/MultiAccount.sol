// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

/**
 * @title  MultiAccount
 * @notice Advanced multi-account management system for the Symmio protocol.
 *         Enables users to create and manage multiple trading accounts with signature
 *         verification, access control, and seamless integration with InstantLayer operations.
 *
 * @dev    Core features include:
 *         • Upgradeable contract architecture with proper initialization
 *         • CREATE2-based deterministic account deployment
 *         • EIP-1271 signature verification for account operations
 *         • Role-based access control with granular permissions
 *         • InstantLayer integration for authorized batch operations
 *         • Admin functionality for PartyA contract management
 *         • Pause functionality for emergency controls
 *         • Comprehensive account lifecycle management
 *
 *         The contract extends SignatureVerifier for advanced cryptographic operations
 *         and maintains full compatibility with the Symmio protocol ecosystem through
 *         seamless call forwarding and signature validation mechanisms.
 */

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { ISymmio } from "../interfaces/ISymmio.sol";
import { IMultiAccount } from "../interfaces/IMultiAccount.sol";
import { ISymmioPartyA } from "../interfaces/ISymmioPartyA.sol";

import { SignatureVerifier } from "./SignatureVerifier.sol";

contract MultiAccount is IMultiAccount, Initializable, SignatureVerifier, PausableUpgradeable, AccessControlUpgradeable {
	using SafeERC20Upgradeable for IERC20Upgradeable;

	/* ─────────────────────────────── Roles ─────────────────────────────── */

	/// @notice Role for updating contract configuration and account implementations.
	bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");

	/// @notice Role that can pause contract operations.
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

	/// @notice Role that can unpause contract operations.
	bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

	/* ──────────────────────── Storage Variables ──────────────────────── */

	/// @notice Address of the core Symmio protocol contract.
	address public symmioAddress;

	/// @notice Address of the TradeNFT contract.
	address public tradeNFTAddress;

	/// @notice Counter for generating unique CREATE2 salts for account deployment.
	uint256 public saltCounter;

	/// @notice Bytecode of the account implementation contract.
	bytes public accountImplementation;

	/// @notice Mapping from user addresses to their array of trading accounts.
	mapping(address => Account[]) public accounts;

	/// @notice Mapping from account address to its index in the owner's accounts array.
	mapping(address => uint256) public indexOfAccount;

	/// @notice Mapping from account address to its owner address.
	mapping(address => address) public owners;

	/* ─────────────────────────────── Structs ─────────────────────────────── */

	/**
	 * @notice Account struct containing account address and name.
	 * @param account Account address.
	 * @param name    Human-readable name for the account.
	 */
	struct Account {
		address account;
		string name;
	}

	/* ─────────────────────────────── Events ─────────────────────────────── */

	/**
	 * @notice Emitted when account implementation bytecode is updated.
	 * @param oldImplementation Previous implementation bytecode.
	 * @param newImplementation New implementation bytecode.
	 */
	event SetAccountImplementation(bytes oldImplementation, bytes newImplementation);

	/**
	 * @notice Emitted when the Symmio protocol address is updated.
	 * @param oldSymmioAddress Previous Symmio contract address.
	 * @param newSymmioAddress New Symmio contract address.
	 */
	event SetSymmioAddress(address oldSymmioAddress, address newSymmioAddress);

	/**
	 * @notice Emitted when the TradeNFT contract address is updated.
	 * @param oldTradeNFTAddress Previous TradeNFT contract address.
	 * @param newTradeNFTAddress New TradeNFT contract address.
	 */
	event SetTradeNFTAddress(address oldTradeNFTAddress, address newTradeNFTAddress);

	/**
	 * @notice Emitted when a new account is created for a user.
	 * @param user    User who owns the new account.
	 * @param account Address of the newly created account.
	 * @param name    Human-readable name for the account.
	 */
	event AddAccount(address indexed user, address indexed account, string name);

	/**
	 * @notice Emitted when an account's name is updated.
	 * @param user           Account owner address.
	 * @param accountAddress Account address being renamed.
	 * @param name           New account name.
	 */
	event EditAccountName(address indexed user, address indexed accountAddress, string name);

	/**
	 * @notice Emitted when a new contract is deployed via CREATE2.
	 * @param deployer        Address that initiated the deployment.
	 * @param contractAddress Address of the newly deployed contract.
	 */
	event DeployContract(address indexed deployer, address indexed contractAddress);

	/**
	 * @notice Emitted when a function call is executed on behalf of an account.
	 * @param sender     Address that initiated the call.
	 * @param account    Account address the call was made for.
	 * @param callData   Encoded function call data.
	 * @param success    Whether the call was successful.
	 * @param resultData Return data from the call.
	 */
	event Call(address indexed sender, address indexed account, bytes callData, bool success, bytes resultData);

	/**
	 * @notice Emitted when an admin call is made to a PartyA contract.
	 * @param partyA     PartyA contract address.
	 * @param data       Call data sent to the contract.
	 * @param success    Whether the call was successful.
	 * @param returnData Return data from the call.
	 */
	event AdminPartyACall(address indexed partyA, bytes data, bool success, bytes returnData);

	/* ─────────────────────────────── Errors ─────────────────────────────── */

	error NotOwnerOfAccount(address sender, address account, address owner); // caller not account owner
	error ContractDeploymentFailed(); // CREATE2 deployment failed
	error PartyACallFailed(bytes returnData); // admin call to PartyA failed
	error InvalidCallData(bytes callData); // call data is invalid
	error UnauthorizedAccess(address account, address sender, bytes4 selector); // unauthorized call attempt

	/* ─────────────────────────── Initialization ─────────────────────────── */

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	/**
	 * @notice Initialize the upgradeable MultiAccount contract.
	 * @param admin                     Address receiving all admin roles.
	 * @param symmioAddress_            Address of the core Symmio protocol contract.
	 * @param accountImplementation_    Bytecode of the account implementation contract.
	 *
	 * @dev Sets up initial roles and contract references. The admin receives
	 *      DEFAULT_ADMIN_ROLE, SETTER_ROLE, PAUSER_ROLE, and UNPAUSER_ROLE.
	 */
	function initialize(address admin, address symmioAddress_, bytes memory accountImplementation_, address tradeNFTAddress_) public initializer {
		__Pausable_init();
		__AccessControl_init();

		_grantRole(DEFAULT_ADMIN_ROLE, admin);
		_grantRole(PAUSER_ROLE, admin);
		_grantRole(UNPAUSER_ROLE, admin);
		_grantRole(SETTER_ROLE, admin);
		symmioAddress = symmioAddress_;
		accountImplementation = accountImplementation_;
		tradeNFTAddress = tradeNFTAddress_;
	}

	/* ────────────────────────── Account Management ────────────────────────── */

	/**
	 * @notice Create a new trading account for the caller.
	 * @param name Human-readable name for the new account.
	 *
	 * @dev Deploys a new PartyA account contract using CREATE2 for deterministic addresses.
	 */
	function addAccount(string memory name) external whenNotPaused {
		address account = _deployPartyA();
		indexOfAccount[account] = accounts[msg.sender].length;
		accounts[msg.sender].push(Account(account, name));
		owners[account] = msg.sender;
		emit AddAccount(msg.sender, account, name);
	}

	/**
	 * @notice Update the display name of an existing account.
	 * @param accountAddress Address of the account to rename.
	 * @param name           New display name for the account.
	 *
	 * @dev Only the account owner can change the account name.
	 */
	function editAccountName(address accountAddress, string memory name) external whenNotPaused onlyOwner(accountAddress, msg.sender) {
		uint256 index = indexOfAccount[accountAddress];
		accounts[msg.sender][index].name = name;
		emit EditAccountName(msg.sender, accountAddress, name);
	}

	/* ───────────────────── Call Execution & Management ───────────────────── */

	/**
	 * @notice Execute multiple function calls on behalf of a PartyA account.
	 * @param account    Account address to execute calls for.
	 * @param _callDatas Array of encoded function call data.
	 *
	 * @dev Access is restricted to account owners or InstantLayer when enabled.
	 *      All calls must succeed for the transaction to complete.
	 */
	function _call(address account, bytes[] memory _callDatas) external whenNotPaused {
		if (msg.sender != owners[account] && !ISymmio(symmioAddress).isCallFromInstantLayer())
			revert UnauthorizedAccess(account, msg.sender, bytes4(0));
		for (uint8 i; i < _callDatas.length; i++) innerCall(account, _callDatas[i]);
	}

	/**
	 * @notice Transfer a trade NFT from one account to another address.
	 * @param account Address of the account to transfer the NFT from.
	 * @param to      Address of the account to transfer the NFT to.
	 * @param tokenId The ID of the NFT to transfer.
	 */
	function transferTradeNFT(address account, address to, uint256 tokenId) external whenNotPaused onlyOwner(account, msg.sender) {
		ISymmioPartyA(account).transferTradeNFT(tradeNFTAddress, to, tokenId);
	}

	/**
	 * @notice Verify signature for an account using EIP-1271 standard.
	 * @param account   Account address to verify signature for.
	 * @param hash      Hash of the data that was signed.
	 * @param signature Signature bytes to verify.
	 * @return Magic value (0x1626ba7e) if signature is valid, 0xffffffff otherwise.
	 *
	 * @dev Delegates signature verification to the account owner using SignatureVerifier.
	 */
	function verifySignatureOfAccount(address account, bytes32 hash, bytes calldata signature) external view returns (bytes4) {
		return isValidSignatureEIP1271(owners[account], hash, signature);
	}

	/* ───────────────────────── Internal Helpers ───────────────────────── */

	/**
	 * @dev Execute a function call on a PartyA account with comprehensive error handling.
	 * @param account   Account address to call.
	 * @param _callData Encoded function call data.
	 */
	function innerCall(address account, bytes memory _callData) internal {
		(bool _success, bytes memory _resultData) = ISymmioPartyA(account).call(_callData);
		emit Call(msg.sender, account, _callData, _success, _resultData);
		if (!_success) {
			assembly {
				revert(add(_resultData, 32), mload(_resultData))
			}
		}
	}

	/**
	 * @dev Deploy a new PartyA account contract using CREATE2.
	 * @return account Address of the newly deployed account contract.
	 */
	function _deployPartyA() internal returns (address account) {
		bytes32 salt = keccak256(abi.encodePacked("MultiAccount_", saltCounter));
		saltCounter += 1;

		bytes memory bytecode = abi.encodePacked(accountImplementation, abi.encode(address(this), symmioAddress));
		account = _deployContract(bytecode, salt);
		return account;
	}

	/**
	 * @dev Deploy a contract using CREATE2 with the specified bytecode and salt.
	 * @param bytecode Bytecode of the contract to deploy.
	 * @param salt     Salt for CREATE2 deployment.
	 * @return contractAddress Address of the deployed contract.
	 */
	function _deployContract(bytes memory bytecode, bytes32 salt) internal returns (address contractAddress) {
		assembly {
			contractAddress := create2(0, add(bytecode, 32), mload(bytecode), salt)
		}
		if (contractAddress == address(0)) revert ContractDeploymentFailed();
		emit DeployContract(msg.sender, contractAddress);
		return contractAddress;
	}

	/* ────────────────────────── Admin Functions ────────────────────────── */

	/**
	 * @notice Update the bytecode for new account deployments.
	 * @param accountImplementation_ New account implementation bytecode.
	 *
	 * @dev Only callable by accounts with SETTER_ROLE.
	 */
	function setAccountImplementation(bytes memory accountImplementation_) external onlyRole(SETTER_ROLE) {
		emit SetAccountImplementation(accountImplementation, accountImplementation_);
		accountImplementation = accountImplementation_;
	}

	/**
	 * @notice Update the Symmio protocol contract address.
	 * @param addr New Symmio protocol address.
	 *
	 * @dev Only callable by accounts with SETTER_ROLE.
	 */
	function setSymmioAddress(address addr) external onlyRole(SETTER_ROLE) {
		emit SetSymmioAddress(symmioAddress, addr);
		symmioAddress = addr;
	}

	/**
	 * @notice Update the TradeNFT contract address.
	 * @param addr New TradeNFT contract address.
	 *
	 * @dev Only callable by accounts with SETTER_ROLE.
	 */
	function setTradeNFTAddress(address addr) external onlyRole(SETTER_ROLE) {
		emit SetTradeNFTAddress(tradeNFTAddress, addr);
		tradeNFTAddress = addr;
	}

	/**
	 * @notice Execute an arbitrary admin call on a PartyA contract.
	 * @param partyA PartyA contract address to call.
	 * @param data   Encoded function call data for the admin operation.
	 *
	 * @dev Only callable by accounts with SETTER_ROLE. Used for forwarding
	 *      admin-level operations to PartyA contracts.
	 */
	function adminCallPartyA(address partyA, bytes calldata data) external onlyRole(SETTER_ROLE) {
		(bool success, bytes memory returnData) = partyA.call(data);
		if (!success) revert PartyACallFailed(returnData);
		emit AdminPartyACall(partyA, data, success, returnData);
	}

	/**
	 * @notice Pause all contract operations except view functions.
	 * @dev Only callable by accounts with PAUSER_ROLE.
	 */
	function pause() external onlyRole(PAUSER_ROLE) {
		_pause();
	}

	/**
	 * @notice Resume all contract operations.
	 * @dev Only callable by accounts with UNPAUSER_ROLE.
	 */
	function unpause() external onlyRole(UNPAUSER_ROLE) {
		_unpause();
	}

	/* ────────────────────────── View Functions ────────────────────────── */

	/**
	 * @notice Get the number of accounts owned by a user.
	 * @param user User address to query.
	 * @return Number of accounts owned by the user.
	 */
	function getAccountsLength(address user) external view returns (uint256) {
		return accounts[user].length;
	}

	/**
	 * @notice Get a paginated list of accounts owned by a user.
	 * @param user  User address to query.
	 * @param start Starting index for pagination.
	 * @param size  Maximum number of accounts to return.
	 * @return Array of Account structures.
	 */
	function getAccounts(address user, uint256 start, uint256 size) external view returns (Account[] memory) {
		uint256 len = size > accounts[user].length - start ? accounts[user].length - start : size;
		Account[] memory userAccounts = new Account[](len);
		for (uint256 i = start; i < start + len; i++) {
			userAccounts[i - start] = accounts[user][i];
		}
		return userAccounts;
	}

	/* ─────────────────────────────── Modifiers ─────────────────────────────── */

	/**
	 * @notice Restricts function access to the owner of the specified account.
	 * @param account Account address to check ownership for.
	 * @param sender  Address to verify as owner.
	 */
	modifier onlyOwner(address account, address sender) {
		if (owners[account] != sender) revert NotOwnerOfAccount(sender, account, owners[account]);
		_;
	}
}
