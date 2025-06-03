// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {console} from "forge-std/console.sol";

/**
 * @title RebaseToken
 * @author willownsenator
 * @notice This is a cross-chain token that can be used to rebase the value of a token.
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each user will have a unique interest rate
 */
contract RebaseToken is ERC20, AccessControl {
    // Errors

    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    uint256 private s_interestRate = 5e10;
    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    address private immutable i_owner;

    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    // Events
    event InterestRateSet(uint256 newInterestRate);
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed to, uint256 amount);
    event TransferStateUpdated(address indexed to, uint256 amount);
    event TransferFromStateUpdated(address indexed from, address indexed to, uint256 amount);
    event MintAndBurnRoleGranted(address indexed account);
    event AdminRoleGrantFailed(address indexed account);
    event PrincipalTransferred(address indexed from, address indexed to, uint256 amount);

    constructor() ERC20("Rebase Token", "RBT") {
        bool sucess = _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        require(sucess, "RebaseToken: Failed to grant admin role");
        i_owner = msg.sender;
    }

    /**
     * @notice Get the owner of the contract
     * @return The owner of the contract
     * @dev The owner of the contract is the address that deployed the contract
     */
    function owner() external view returns (address) {
        return i_owner;
    }

    /**
     * @notice Grant the mint and burn role to the user
     * @param _account The account address
     */
    function grantMintAndBurnRole(address _account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bool sucess = _grantRole(MINT_AND_BURN_ROLE, _account);
        require(sucess, "RebaseToken: Failed to grant mint and burn role");
        emit MintAndBurnRoleGranted(_account);
    }

    /**
     * @notice Set the interest rate for the user
     * @param _newInterestRate The new interest rate for the user
     * @dev The interest rate can only decrease
     */
    function setInterestRate(uint256 _newInterestRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Set the interest rate for the user
        if (_newInterestRate > s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Get the principal balance of the from not including the interest
     * @param _from The from address
     * @return The principal balance of the from
     */
    function principalBalanceOf(address _from) external view returns (uint256) {
        return super.balanceOf(_from);
    }

    /**
     * @notice Mint new tokens
     * @param _to The address to mint the tokens to
     * @param _amount The amount of tokens to mint
     * @param _userInterestRate The interest rate for the user
     * @dev The interest rate can only decrease
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        console.log("Mint called by:", msg.sender);
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = _userInterestRate;
        _mint(_to, _amount);

        emit Mint(_to, _amount);
    }

    /**
     * @notice Burn the tokens when the user withdraws from the vault
     * @param _from The address to burn the tokens from
     * @param _amount The amount of tokens to burn
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        console.log("Burn called by:", msg.sender);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }

        _mintAccruedInterest(_from);
        _burn(_from, _amount);

        emit Burn(_from, _amount);
        s_userLastUpdatedTimestamp[_from] = block.timestamp;
    }

    /**
     * @notice Balance of the user with the accumulated interest
     * @param _user The user address
     * @return The balance of the user
     */
    function balanceOf(address _user) public view override returns (uint256) {
        return (super.balanceOf(_user) * _calculateAccumulateUserInterest(_user)) / PRECISION_FACTOR;
    }

    /**
     * @notice Transfer the tokens to the recipient
     * @param _recipient The recipient address
     * @param _amount The amount of tokens to transfer
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        uint256 senderBalance = balanceOf(msg.sender);
        if (_amount == type(uint256).max) {
            _amount = senderBalance;
        }

        require(senderBalance >= _amount, "RebaseToken: Insufficient balance");

        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        _transfer(msg.sender, _recipient, _amount);
        s_userLastUpdatedTimestamp[_recipient] = block.timestamp;
        emit TransferStateUpdated(_recipient, _amount);
        return true;
    }

    /**
     * @notice Transfer the tokens from the sender to the recipient
     * @param _sender The sender address
     * @param _recipient The recipient address
     * @param _amount The amount of tokens to transfer
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }

        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        address spender = msg.sender;
        uint256 currentAllowance = allowance(_sender, spender);

        if (_sender != spender) {
            require(currentAllowance >= _amount, "RebaseToken: Unauthorized sender");
            _spendAllowance(_sender, spender, _amount);
        }

        _transfer(_sender, _recipient, _amount);
        emit TransferFromStateUpdated(_sender, _recipient, _amount);
        return true;
    }

    /**
     * @notice Calculate the accumulated interest for the user
     * @param _user The user address
     * @return linearInterest The accumulated interest for the user
     */
    function _calculateAccumulateUserInterest(address _user) internal view returns (uint256 linearInterest) {
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
        require(linearInterest >= PRECISION_FACTOR, "RebaseToken: Overflow in interest calculation");
    }

    /**
     * @notice Mint the accured interest for the user
     * @param _user The user address
     */
    function _mintAccruedInterest(address _user) internal {
        // Store the current timestamp and last updated timestamp
        uint256 currentTimestamp = block.timestamp;
        uint256 lastUpdatedTimestamp = s_userLastUpdatedTimestamp[_user];

        // Skip if this is the first interaction or no time has passed
        if (lastUpdatedTimestamp == 0 || currentTimestamp <= lastUpdatedTimestamp) {
            s_userLastUpdatedTimestamp[_user] = currentTimestamp;
            return;
        }

        // Calculate the linear interest based on the time elapsed without using balnceOf
        uint256 timeElapsed = currentTimestamp - lastUpdatedTimestamp;
        uint256 linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);

        uint256 previousPrincipalBalance = super.balanceOf(_user);
        uint256 currentBalance = (previousPrincipalBalance * linearInterest) / PRECISION_FACTOR;
        uint256 balanceIncrease = currentBalance - previousPrincipalBalance;

        // Mint the calculated interest to the user
        _mint(_user, balanceIncrease);

        // Update the timestamp AFTER calculating interest
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
    }

    /**
     * @notice Get the interest rate for the contract
     * @return The interest rate for the contract
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /**
     * @notice Get the interest rate for the user
     * @param _user The user address
     * @return The interest rate for the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }
}
