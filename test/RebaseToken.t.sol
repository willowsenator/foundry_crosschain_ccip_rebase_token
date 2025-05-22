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

    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

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
        console.log("difference: ", amount > startBalance ? amount - startBalance : startBalance - amount);
        assertApproxEqAbs(startBalance, amount, 1e13);

        vm.warp(block.timestamp + 1 hours);

        uint256 middleBalance = rebaseToken.balanceOf(user);
        console.log("middleBalance", middleBalance);
        assertGt(middleBalance, startBalance);

        vm.warp(block.timestamp + 1 hours);

        uint256 endBalance = rebaseToken.balanceOf(user);
        console.log("endBalance", endBalance);
        assertEq(endBalance, middleBalance);

        //assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);
        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, 100e18);

        vm.deal(user, amount);
        vm.startPrank(user);
        vault.deposit{value: amount}();
        vm.stopPrank();
        assertApproxEqAbs(rebaseToken.balanceOf(user), amount, 1e13);

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

        userBalanceWithInterest = rebaseToken.balanceOf(user);
        console.log("User Balance with Interest after adding rewards", userBalanceWithInterest);

        vm.startPrank(user);
        // Redeem the user's balance with interest
        vault.redeem(userBalanceWithInterest);
        vm.stopPrank();

        // Assertions
        assertGe(userBalanceWithInterest, user.balance);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e18, 100e18);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        // Get the vault's balance after deposit and interest accumulation
        uint256 userBalance = rebaseToken.balanceOf(user);
        console.log("User balance after deposit", userBalance);

        // Transfer the specified amount to another user
        address user2 = makeAddr("User2");
        uint256 user2Balance = rebaseToken.balanceOf(user2);

        // Make sure amount to send is reasonable and smaller than user balance
        // Ensure minimum is always less than maximum
        uint256 maxSendAmount = userBalance * 9 / 10; // 90% of balance
        uint256 minSendAmount = 1e5; // Small minimum amount

        // Safety check to prevent bound errors
        if (maxSendAmount < minSendAmount) {
            minSendAmount = 1; // If userBalance is very small, use 1 as minimum
        }

        amountToSend = bound(amountToSend, minSendAmount, maxSendAmount);

        assertEq(user2Balance, 0);
        console.log("Amount to send:", amountToSend);

        // Transfer tokens
        vm.startPrank(user);
        console.log("User balance before transfer", userBalance);
        bool success = rebaseToken.transfer(user2, amountToSend);
        vm.stopPrank();

        assertTrue(success, "Transfer failed");

        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);

        console.log("User balance after transfer", userBalanceAfterTransfer);
        console.log("User2 balance after transfer", user2BalanceAfterTransfer);
        console.log("Total balance after transfer", userBalanceAfterTransfer + user2BalanceAfterTransfer);
        console.log("Original balance", userBalance);

        assertApproxEqAbs(userBalanceAfterTransfer + user2BalanceAfterTransfer, userBalance, 1e14);

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

        uint256 interestRate = rebaseToken.getInterestRate();

        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.mint(user, 100, interestRate);

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
        _newInterestRate = bound(_newInterestRate, initialInterestRate + 1, initialInterestRate + 1000);
        vm.prank(owner);

        vm.expectPartialRevert(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector);
        rebaseToken.setInterestRate(_newInterestRate);

        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }
}
