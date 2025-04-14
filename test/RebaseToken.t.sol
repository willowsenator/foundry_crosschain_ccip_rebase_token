// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

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

        vm.deal(user, amount);
        vm.startPrank(user);
        vault.deposit{value: amount}();
        vm.stopPrank();
        assertEq(rebaseToken.balanceOf(user), amount);

        // Redeem the user's actual balance
        vm.startPrank(user);
        uint256 userBalance = rebaseToken.balanceOf(user);
        vault.redeem(userBalance);
        vm.stopPrank();

        assertEq(rebaseToken.balanceOf(user), 0);
        assertGe(user.balance, amount);
    }

    function testRedeemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, 1095 days); // Limit time to a maximum of 3 years
        depositAmount = bound(depositAmount, 1e5, 100e18); // Limit deposit to a maximum of 100 ETH

        // Fund the user with the deposit amount
        vm.deal(user, depositAmount);

        // User deposits Ether into the Vault
        vm.startPrank(user);
        vault.deposit{value: depositAmount}();
        vm.stopPrank();

        // Simulate time passing
        vm.warp(block.timestamp + time);

        // Calculate the user's balance with interest
        uint256 userBalanceWithInterest = rebaseToken.balanceOf(user);
        console.log("User Balance with Interest", userBalanceWithInterest);

        // Add rewards to the Vault to ensure it can cover the redemption
        uint256 rewardsNeeded = userBalanceWithInterest > depositAmount ? (userBalanceWithInterest - depositAmount) : 0;
        console.log("Rewards needed to cover redemption:", rewardsNeeded);
        if (rewardsNeeded > 0) {
            vm.deal(owner, rewardsNeeded);
            vm.startPrank(owner);
            addRewardsToVault(rewardsNeeded);
            vm.stopPrank();
        }

        console.log("Vault Balance", address(vault).balance);
        userBalanceWithInterest = rebaseToken.balanceOf(user);
        console.log("User Balance with Interest after adding rewards", userBalanceWithInterest);

        vm.startPrank(user);
        // Redeem the user's balance with interest
        vault.redeem(userBalanceWithInterest);
        vm.stopPrank();

        // Check the user's Ether balance after redemption
        uint256 userEthBalanceAfter = address(user).balance;
        userBalanceWithInterest = rebaseToken.balanceOf(user);

        // Assertions
        console.log("Rebase Token Balance after redemption", rebaseToken.balanceOf(user));
        assertEq(rebaseToken.balanceOf(user), 0); // User's token balance should be 0 after redemption
        assertGe(userEthBalanceAfter, userBalanceWithInterest); // User's Ether balance should match their token balance*/
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5, 100e18);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        // Get the vault's balance after deposit and interest accumulation
        uint256 userBalance = rebaseToken.balanceOf(user);

        // Transfer the specified amount to another user
        address user2 = makeAddr("User2");
        uint256 user2Balance = rebaseToken.balanceOf(user2);

        // Bound amountToSend to the user's rebase token balance
        amountToSend = bound(amountToSend, 1e5, userBalance);

        assertEq(user2Balance, 0);

        // Transfer tokens
        vm.startPrank(user);
        console.log("User balance before transfer", userBalance);
        rebaseToken.transfer(user2, amountToSend);
        vm.stopPrank();

        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);

        assertApproxEqAbs(userBalanceAfterTransfer + user2BalanceAfterTransfer, userBalance, 1);

        // Check the interest rate for both users
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
        rebaseToken.mint(user, 100, rebaseToken.getInterestRate());

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
