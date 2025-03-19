// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";

import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;
    address public owner = makeAddr("Owner");
    address public user = makeAddr("User");

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) public {
        (bool success,) = address(vault).call{value: rewardAmount}("");
        require(success, "Failed to add rewards to the vault");
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, 100e18);

        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("startBalance", startBalance);
        assertEq(startBalance, amount);
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        console.log("middleBalance", middleBalance);
        assertGt(middleBalance, startBalance);
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        console.log("endBalance", endBalance);
        assertGt(endBalance, middleBalance);

        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);
        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, 100e18);

        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);

        // Redeem the user's actual balance
        uint256 userBalance = rebaseToken.balanceOf(user);
        vault.redeem(userBalance);

        assertEq(rebaseToken.balanceOf(user), 0);
        assertGe(user.balance, amount);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, 1095 days); // Limit time to a maximum of 3 years
        depositAmount = bound(depositAmount, 1e5, 100e18); // Limit deposit to a maximum of 100 ETH

        // Fund the user with the deposit amount
        vm.deal(user, depositAmount);

        // User deposits Ether into the Vault
        vm.prank(user);
        vault.deposit{value: depositAmount}();

        // Simulate time passing
        vm.warp(block.timestamp + time);

        // Calculate the user's balance with interest
        uint256 userBalanceWithInterest = rebaseToken.balanceOf(user);

        // Add rewards to the Vault to ensure it can cover the redemption
        uint256 rewardsNeeded = userBalanceWithInterest > depositAmount ? userBalanceWithInterest - depositAmount : 0;
        if (rewardsNeeded > 0) {
            vm.deal(owner, rewardsNeeded);
            vm.prank(owner);
            addRewardsToVault(rewardsNeeded);
        }

        // Redeem the user's balance with interest
        vm.prank(user);
        vault.redeem(userBalanceWithInterest);

        // Check the user's Ether balance after redemption
        uint256 userEthBalanceAfter = address(user).balance;

        // Assertions
        assertEq(rebaseToken.balanceOf(user), 0); // User's token balance should be 0 after redemption
        assertEq(userEthBalanceAfter, userBalanceWithInterest); // User's Ether balance should match their token balance
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5, 100e18);
        amountToSend = bound(amountToSend, 1e5, amount);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        // Transfer the tokens to another user
        address user2 = makeAddr("User2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);

        assertEq(userBalance, amount);
        assertEq(user2Balance, 0);

        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);

        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(user2BalanceAfterTransfer, amountToSend);

        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
        assertEq(rebaseToken.getUserInterestRate(user2), 5e10);
    }

    function testCannotSetInterestRate(uint256 _newInterestRate) public {
        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(_newInterestRate);
    }

    function testCannotCallMintAndBurn() public {
        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.mint(user, 100);

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.burn(user, 100);
    }

    function testGetPrincipalBalance(uint256 amount) public {
        amount = bound(amount, 1e5, 100e18);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        assertEq(rebaseToken.principalBalanceOf(user), amount);

        vm.warp(block.timestamp + 1 hours);
        assertEq(rebaseToken.principalBalanceOf(user), amount);
    }

    function testGetRebaseTokenAddress() public view {
        assertEq(address(vault.getRebaseTokenAddress()), address(rebaseToken));
    }

    function testInterestRateCanOnlyDecrease(uint256 _newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        _newInterestRate = bound(_newInterestRate, initialInterestRate, initialInterestRate + 2);
        vm.prank(owner);

        vm.expectPartialRevert(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector);
        rebaseToken.setInterestRate(_newInterestRate);

        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }
}
