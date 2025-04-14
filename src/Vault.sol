// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    IRebaseToken private immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    error Vault__RedeemFailed();

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}

    /**
     * @notice Deposit ETH to the vault
     * @dev The user will get the rebase token in return
     */
    function deposit() external payable {
        uint256 interestRate = i_rebaseToken.getInterestRate();
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Redeem the rebase token to get ETH
     * @param _amount The amount of rebase token to redeem
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        uint256 vaultBalance = address(this).balance;
        uint256 principal = i_rebaseToken.principalBalanceOf(msg.sender);

        // Scale the redemption amount if the vault does not have enough balance
        uint256 redeemableAmount = _amount > vaultBalance ? vaultBalance : principal;
        require(msg.sender != address(0), "Vault: Invalid sender address");
        // Transfer Ether BEFORE burning tokens
        (bool success,) = payable(msg.sender).call{value: redeemableAmount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }

        i_rebaseToken.burn(msg.sender, redeemableAmount);

        emit Redeem(msg.sender, redeemableAmount);
    }

    /**
     * @notice Get the rebase token address
     * @return The rebase token address
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
