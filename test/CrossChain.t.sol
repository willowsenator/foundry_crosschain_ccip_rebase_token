// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";

import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";

contract CrossChain is Test {
    uint256 sepoliaForkId;
    uint256 arbSepoliaForkId;
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    RebaseToken sepoliaToken;
    RebaseToken arbSepoliaToken;

    Vault sepoliaVault;
    Vault arbSepoliaVault;

    RebaseTokenPool sepoliaTokenPool;
    RebaseTokenPool arbSepoliaTokenPool;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    address owner = makeAddr("Owner");

    function setUp() public {
        sepoliaForkId = vm.createSelectFork("sepolia");
        arbSepoliaForkId = vm.createFork("arb-sepolia");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // 1. Deploy sepolia
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        sepoliaToken = new RebaseToken();
        sepoliaVault = new Vault(IRebaseToken(address(sepoliaToken)));
        sepoliaTokenPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            new address[](0),
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );

        sepoliaToken.grantMintAndBurnRole(address(sepoliaVault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaTokenPool));

        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(sepoliaToken)
        );

        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));

        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(sepoliaToken), address(sepoliaTokenPool)
        );

        vm.stopPrank();

        // 2. Deploy  Arb sepolia
        vm.selectFork(arbSepoliaForkId);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        arbSepoliaToken = new RebaseToken();
        arbSepoliaTokenPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            new address[](0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );

        arbSepoliaVault = new Vault(IRebaseToken(address(arbSepoliaToken)));

        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaVault));
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaTokenPool));

        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(arbSepoliaToken)
        );

        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));

        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(arbSepoliaToken), address(arbSepoliaTokenPool)
        );

        configureTokenPool(
            sepoliaForkId,
            address(sepoliaTokenPool),
            arbSepoliaNetworkDetails.chainSelector,
            address(arbSepoliaTokenPool),
            address(arbSepoliaToken)
        );
        configureTokenPool(
            arbSepoliaForkId,
            address(arbSepoliaTokenPool),
            sepoliaNetworkDetails.chainSelector,
            address(sepoliaTokenPool),
            address(sepoliaToken)
        );
        vm.stopPrank();
    }

    function configureTokenPool(
        uint256 forkId,
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteToken
    ) public {
        vm.selectFork(forkId);
        TokenPool.ChainUpdate[] memory chainUpdates = new TokenPool.ChainUpdate[](1);
        chainUpdates[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(remotePool),
            remoteTokenAddress: abi.encode(remoteToken),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        vm.prank(owner);
        TokenPool(localPool).applyChainUpdates(chainUpdates);
    }
}
