// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title RebaseToken
 * @author willownsenator
 * @notice This is a cross-chain token that can be used to rebase the value of a token.
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each user will have a unique interest rate
 */
contract RebaseToken is ERC20 {
    // Errors
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    uint256 private s_interestRate = 5e10;
    uint256 private constant PRECISION_FACTOR = 1e18;
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    // Events
    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") {}

    /**
     * @notice Set the interest rate for the user
     * @param _newInterestRate The new interest rate for the user
     * @dev The interest rate can only decrease
     */
    function setInterestRate(uint256 _newInterestRate) external {
        // Set the interest rate for the user
        if (_newInterestRate < s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Mint new tokens
     * @param _to The address to mint the tokens to
     * @param _amount The amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) external {
        _mintAccuredInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
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
     * @notice Calculate the accumulated interest for the user
     * @param _user The user address
     * @return linearInterest The accumulated interest for the user
     */
    function _calculateAccumulateUserInterest(address _user) internal view returns (uint256 linearInterest) {
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
    }

    /**
     * @notice Mint the accrued interest for the user
     * @param _user The user address
     */
    function _mintAccuredInterest(address _user) internal {
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        uint256 balance = balanceOf(_user);
        _mint(_user, balance);
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
