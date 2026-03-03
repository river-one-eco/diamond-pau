// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { CCTPForwarder } from "../../lib/xchain-helpers/src/forwarders/CCTPForwarder.sol";

import { ControllerInstance }            from "../../deploy/ControllerInstance.sol";
import { MainnetControllerDeploy }       from "../../deploy/ControllerDeploy.sol";
import { MainnetControllerInit as Init } from "../../deploy/MainnetControllerInit.sol";

import { ALMProxy }          from "../../src/ALMProxy.sol";
import { MainnetController } from "../../src/MainnetController.sol";
import { RateLimits }        from "../../src/RateLimits.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

// Necessary to get error message assertions to work
contract LibraryWrapper {

    function initAlmSystem(
        ControllerInstance       memory controllerInst,
        Init.ConfigAddressParams memory configAddresses,
        Init.CheckAddressParams  memory checkAddresses
    )
        external
    {
        Init.initAlmSystem(controllerInst, configAddresses, checkAddresses);
    }

    function upgradeController(
        ControllerInstance       memory controllerInst,
        Init.ConfigAddressParams memory configAddresses,
        Init.CheckAddressParams  memory checkAddresses
    )
        external
    {
        Init.upgradeController(controllerInst, configAddresses, checkAddresses);
    }

}

abstract contract InitAndUpgrade_TestBase is ForkTestBase {

    uint32 internal constant destinationEndpointId = 30110;  // Arbitrum EID

    function _getDefaultParams()
        internal
        returns (
            Init.ConfigAddressParams memory configAddresses,
            Init.CheckAddressParams  memory checkAddresses
        )
    {
        address[] memory relayers = new address[](1);
        relayers[0] = RELAYER;

        configAddresses = Init.ConfigAddressParams(FREEZER, relayers, address(0));
        checkAddresses  = Init.CheckAddressParams(Ethereum.SPARK_PROXY, almProxy, address(rateLimits));
    }

}

contract MainnetController_InitAndUpgrade_Tests is InitAndUpgrade_TestBase {

    // NOTE: `initAlmSystem` and `upgradeController` are tested in the same contract because
    //       they both use _initController and have similar specific setups, so it
    //       less complex/repetitive to test them together.

    LibraryWrapper internal wrapper;

    ControllerInstance internal controllerInst;

    address internal mismatchAddress = makeAddr("mismatchAddress");

    address internal oldController;

    Init.ConfigAddressParams internal configAddresses;
    Init.CheckAddressParams  internal checkAddresses;

    function setUp() public override {
        super.setUp();

        oldController = address(mainnetController);  // Cache for later testing

        // NOTE: initAlmSystem will redundantly call rely and approve on already inited
        //       almProxy and rateLimits, this setup was chosen to easily test upgrade and init failures.
        //       It also should be noted that the almProxy and rateLimits that are being used in initAlmSystem
        //       are already deployed. This is technically possible to do and works in the same way, it was
        //       done also for make testing easier.
        mainnetController = MainnetController(
            MainnetControllerDeploy.deployController(Ethereum.SPARK_PROXY, almProxy, address(rateLimits))
        );

        ( configAddresses, checkAddresses ) = _getDefaultParams();

        controllerInst = ControllerInstance(almProxy, address(mainnetController), address(rateLimits));

        // Admin will be calling the library from its own address
        vm.etch(Ethereum.SPARK_PROXY, address(new LibraryWrapper()).code);

        wrapper = LibraryWrapper(Ethereum.SPARK_PROXY);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 21430000;  // Dec 18, 2024
    }

    /**********************************************************************************************/
    /*** ACL tests                                                                              ***/
    /**********************************************************************************************/

    function test_initAlmSystem_incorrectAdminAlmProxy() external {
        vm.prank(Ethereum.SPARK_PROXY);
        ALMProxy(almProxy).revokeRole(DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY);

        vm.expectRevert("MainnetControllerInit/incorrect-admin-almProxy");
        wrapper.initAlmSystem(controllerInst, configAddresses, checkAddresses);
    }

    function test_initAlmSystem_incorrectAdminRateLimits() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.revokeRole(DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY);

        vm.expectRevert("MainnetControllerInit/incorrect-admin-rateLimits");
        wrapper.initAlmSystem(controllerInst, configAddresses, checkAddresses);
    }

    function test_initAlmSystem_upgradeController_incorrectAdminController() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.revokeRole(DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY);

        _checkInitAndUpgradeFail(abi.encodePacked("MainnetControllerInit/incorrect-admin-controller"));
    }

    /**********************************************************************************************/
    /*** Constructor tests                                                                      ***/
    /**********************************************************************************************/

    function test_initAlmSystem_upgradeController_incorrectAlmProxy() external {
        // Deploy new address that will not EVM revert on OZ ACL check
        controllerInst.almProxy = address(new ALMProxy(Ethereum.SPARK_PROXY));

        _checkInitAndUpgradeFail(abi.encodePacked("MainnetControllerInit/incorrect-almProxy"));
    }

    function test_initAlmSystem_upgradeController_incorrectRateLimits() external {
        // Deploy new address that will not EVM revert on OZ ACL check
        controllerInst.rateLimits = address(new RateLimits(Ethereum.SPARK_PROXY));

        _checkInitAndUpgradeFail(abi.encodePacked("MainnetControllerInit/incorrect-rateLimits"));
    }

    function test_initAlmSystem_upgradeController_oldControllerIsNewController() external {
        configAddresses.oldController = controllerInst.controller;
        _checkInitAndUpgradeFail(abi.encodePacked("MainnetControllerInit/old-controller-is-new-controller"));
    }

    /**********************************************************************************************/
    /*** Upgrade tests                                                                          ***/
    /**********************************************************************************************/

    function test_upgradeController_oldControllerZeroAddress() external {
        configAddresses.oldController = address(0);

        vm.expectRevert("MainnetControllerInit/old-controller-zero-address");
        wrapper.upgradeController(controllerInst, configAddresses, checkAddresses);
    }

    function test_upgradeController_oldControllerDoesNotHaveRoleInAlmProxy() external {
        configAddresses.oldController = oldController;

        // Revoke the old controller address in ALM proxy
        vm.prank(Ethereum.SPARK_PROXY);
        ALMProxy(almProxy).revokeRole(CONTROLLER_ROLE, configAddresses.oldController);

        // Try to upgrade with the old controller address that is doesn't have the CONTROLLER role
        vm.expectRevert("MainnetControllerInit/old-controller-not-almProxy-controller");
        wrapper.upgradeController(controllerInst, configAddresses, checkAddresses);
    }

    function test_upgradeController_oldControllerDoesNotHaveRoleInRateLimits() external {
        configAddresses.oldController = oldController;

        // Revoke the old controller address in rate limits
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.revokeRole(CONTROLLER_ROLE, configAddresses.oldController);

        // Try to upgrade with the old controller address that is doesn't have the CONTROLLER role
        vm.expectRevert("MainnetControllerInit/old-controller-not-rateLimits-controller");
        wrapper.upgradeController(controllerInst, configAddresses, checkAddresses);
    }

    /**********************************************************************************************/
    /*** Helper functions                                                                       ***/
    /**********************************************************************************************/

    function _checkInitAndUpgradeFail(bytes memory expectedError) internal {
        vm.expectRevert(expectedError);
        wrapper.initAlmSystem(controllerInst, configAddresses, checkAddresses);

        vm.expectRevert(expectedError);
        wrapper.upgradeController(controllerInst, configAddresses, checkAddresses);
    }

}

contract MainnetController_InitAlmSystem_Tests is InitAndUpgrade_TestBase {

    LibraryWrapper internal wrapper;

    ControllerInstance internal controllerInst;

    address internal mismatchAddress = makeAddr("mismatchAddress");

    Init.ConfigAddressParams internal configAddresses;
    Init.CheckAddressParams  internal checkAddresses;

    function setUp() public override {
        super.setUp();

        controllerInst = MainnetControllerDeploy.deployFull(Ethereum.SPARK_PROXY);

        // Overwrite storage for all previous deployments in setUp and assert brand new deployment
        mainnetController = MainnetController(controllerInst.controller);
        almProxy          = payable(controllerInst.almProxy);
        rateLimits        = RateLimits(controllerInst.rateLimits);

        ( configAddresses, checkAddresses ) = _getDefaultParams();

        // Admin will be calling the library from its own address
        vm.etch(Ethereum.SPARK_PROXY, address(new LibraryWrapper()).code);

        wrapper = LibraryWrapper(Ethereum.SPARK_PROXY);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 21430000;  // Dec 18, 2024
    }

    function test_initAlmSystem() external {
        assertEq(mainnetController.hasRole(FREEZER_ROLE, FREEZER), false);
        assertEq(mainnetController.hasRole(RELAYER_ROLE, RELAYER), false);

        assertEq(ALMProxy(almProxy).hasRole(CONTROLLER_ROLE, address(mainnetController)), false);
        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,         address(mainnetController)), false);

        vm.prank(Ethereum.SPARK_PROXY);
        wrapper.initAlmSystem(controllerInst, configAddresses, checkAddresses);

        assertEq(mainnetController.hasRole(FREEZER_ROLE, FREEZER), true);
        assertEq(mainnetController.hasRole(RELAYER_ROLE, RELAYER), true);

        assertEq(ALMProxy(almProxy).hasRole(CONTROLLER_ROLE, address(mainnetController)), true);
        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,         address(mainnetController)), true);
    }

}

contract MainnetController_UpgradeController_Tests is InitAndUpgrade_TestBase {

    LibraryWrapper internal wrapper;

    ControllerInstance internal controllerInst;

    Init.ConfigAddressParams internal configAddresses;
    Init.CheckAddressParams  internal checkAddresses;

    MainnetController internal newController;

    function setUp() public override {
        super.setUp();

        ( configAddresses, checkAddresses ) = _getDefaultParams();

        newController = MainnetController(
            MainnetControllerDeploy.deployController(Ethereum.SPARK_PROXY, almProxy, address(rateLimits))
        );

        controllerInst = ControllerInstance(almProxy, address(newController), address(rateLimits));

        configAddresses.oldController = address(mainnetController);  // Revoke from old controller

        // Admin will be calling the library from its own address
        vm.etch(Ethereum.SPARK_PROXY, address(new LibraryWrapper()).code);

        wrapper = LibraryWrapper(Ethereum.SPARK_PROXY);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 21430000;  // Dec 18, 2024
    }

    function test_upgradeController() external {
        assertEq(newController.hasRole(FREEZER_ROLE, FREEZER), false);
        assertEq(newController.hasRole(RELAYER_ROLE, RELAYER), false);

        assertEq(ALMProxy(almProxy).hasRole(CONTROLLER_ROLE, address(mainnetController)), true);
        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,         address(mainnetController)), true);

        assertEq(ALMProxy(almProxy).hasRole(CONTROLLER_ROLE, address(newController)), false);
        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,         address(newController)), false);

        vm.prank(Ethereum.SPARK_PROXY);
        wrapper.upgradeController(controllerInst, configAddresses, checkAddresses);

        assertEq(newController.hasRole(FREEZER_ROLE, FREEZER), true);
        assertEq(newController.hasRole(RELAYER_ROLE, RELAYER), true);

        assertEq(ALMProxy(almProxy).hasRole(CONTROLLER_ROLE, address(mainnetController)), false);
        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,         address(mainnetController)), false);

        assertEq(ALMProxy(almProxy).hasRole(CONTROLLER_ROLE, address(newController)), true);
        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,         address(newController)), true);
    }

}
