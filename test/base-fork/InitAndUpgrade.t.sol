// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Base } from "../../lib/spark-address-registry/src/Base.sol";

import { ControllerInstance }            from "../../deploy/ControllerInstance.sol";
import { ForeignControllerDeploy }       from "../../deploy/ControllerDeploy.sol";
import { ForeignControllerInit as Init } from "../../deploy/ForeignControllerInit.sol";

import { ALMProxy }          from "../../src/ALMProxy.sol";
import { ForeignController } from "../../src/ForeignController.sol";
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

    uint32 internal constant destinationEndpointId = 30101;  // Ethereum EID

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
        checkAddresses  = Init.CheckAddressParams(Base.SPARK_EXECUTOR, almProxy, address(rateLimits));
    }

}

contract ForeignController_InitAndUpgrade_Tests is InitAndUpgrade_TestBase {

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

        oldController = address(foreignController);  // Cache for later testing

        // Deploy new controller against existing system
        // NOTE: initAlmSystem will redundantly call rely and approve on already inited
        //       almProxy and rateLimits, this setup was chosen to easily test upgrade and init failures
        foreignController = ForeignController(
            ForeignControllerDeploy.deployController(Base.SPARK_EXECUTOR, almProxy, address(rateLimits))
        );

        ( configAddresses, checkAddresses ) = _getDefaultParams();

        controllerInst = ControllerInstance(almProxy, address(foreignController), address(rateLimits));

        // Admin will be calling the library from its own address
        vm.etch(Base.SPARK_EXECUTOR, address(new LibraryWrapper()).code);

        wrapper = LibraryWrapper(Base.SPARK_EXECUTOR);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 23900000;  // Dec 19, 2024
    }

    /**********************************************************************************************/
    /*** ACL tests                                                                              ***/
    /**********************************************************************************************/

    function test_initAlmSystem_upgradeController_incorrectAdminAlmProxy() external {
        vm.prank(Base.SPARK_EXECUTOR);
        ALMProxy(almProxy).revokeRole(DEFAULT_ADMIN_ROLE, Base.SPARK_EXECUTOR);

        vm.expectRevert("ForeignControllerInit/incorrect-admin-almProxy");
        wrapper.initAlmSystem(controllerInst, configAddresses, checkAddresses);
    }

    function test_initAlmSystem_upgradeController_incorrectAdminRateLimits() external {
        vm.prank(Base.SPARK_EXECUTOR);
        rateLimits.revokeRole(DEFAULT_ADMIN_ROLE, Base.SPARK_EXECUTOR);

        vm.expectRevert("ForeignControllerInit/incorrect-admin-rateLimits");
        wrapper.initAlmSystem(controllerInst, configAddresses, checkAddresses);
    }

    function test_initAlmSystem_upgradeController_incorrectAdminController() external {
        vm.prank(Base.SPARK_EXECUTOR);
        foreignController.revokeRole(DEFAULT_ADMIN_ROLE, Base.SPARK_EXECUTOR);

        _checkInitAndUpgradeFail(abi.encodePacked("ForeignControllerInit/incorrect-admin-controller"));
    }

    /**********************************************************************************************/
    /*** Constructor tests                                                                      ***/
    /**********************************************************************************************/

    function test_initAlmSystem_upgradeController_incorrectAlmProxy() external {
        // Deploy new address that will not EVM revert on OZ ACL check
        controllerInst.almProxy = address(new ALMProxy(Base.SPARK_EXECUTOR));

        _checkInitAndUpgradeFail(abi.encodePacked("ForeignControllerInit/incorrect-almProxy"));
    }

    function test_initAlmSystem_upgradeController_incorrectRateLimits() external {
        // Deploy new address that will not EVM revert on OZ ACL check
        controllerInst.rateLimits = address(new RateLimits(Base.SPARK_EXECUTOR));

        _checkInitAndUpgradeFail(abi.encodePacked("ForeignControllerInit/incorrect-rateLimits"));
    }

    function test_initAlmSystem_upgradeController_oldControllerIsNewController() external {
        configAddresses.oldController = controllerInst.controller;
        _checkInitAndUpgradeFail(abi.encodePacked("ForeignControllerInit/old-controller-is-new-controller"));
    }

    /**********************************************************************************************/
    /*** Upgrade tests                                                                          ***/
    /**********************************************************************************************/

    function test_upgradeController_oldControllerZeroAddress() external {
        configAddresses.oldController = address(0);

        vm.expectRevert("ForeignControllerInit/old-controller-zero-address");
        wrapper.upgradeController(controllerInst, configAddresses, checkAddresses);
    }

    function test_upgradeController_oldControllerDoesNotHaveRoleInAlmProxy() external {
        configAddresses.oldController = oldController;

        // Revoke the old controller address in ALM proxy
        vm.startPrank(Base.SPARK_EXECUTOR);
        ALMProxy(almProxy).revokeRole(CONTROLLER_ROLE, configAddresses.oldController);
        vm.stopPrank();

        // Try to upgrade with the old controller address that is doesn't have the CONTROLLER_ROLE role
        vm.expectRevert("ForeignControllerInit/old-controller-not-almProxy-controller");
        wrapper.upgradeController(controllerInst, configAddresses, checkAddresses);
    }

    function test_upgradeController_oldControllerDoesNotHaveRoleInRateLimits() external {
        configAddresses.oldController = oldController;

        // Revoke the old controller address in rate limits
        vm.startPrank(Base.SPARK_EXECUTOR);
        rateLimits.revokeRole(CONTROLLER_ROLE, configAddresses.oldController);
        vm.stopPrank();

        // Try to upgrade with the old controller address that is doesn't have the CONTROLLER_ROLE role
        vm.expectRevert("ForeignControllerInit/old-controller-not-rateLimits-controller");
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

    function _checkInitAndUpgradeSucceed() internal {
        uint256 id = vm.snapshot();

        wrapper.initAlmSystem(controllerInst, configAddresses, checkAddresses);

        vm.revertTo(id);

        configAddresses.oldController = oldController;

        wrapper.upgradeController(controllerInst, configAddresses, checkAddresses);
    }

}

contract ForeignController_InitAlmSystem_Tests is InitAndUpgrade_TestBase {

    LibraryWrapper internal wrapper;

    ControllerInstance internal controllerInst;

    Init.ConfigAddressParams internal configAddresses;
    Init.CheckAddressParams  internal checkAddresses;

    function setUp() public override {
        super.setUp();

        controllerInst = ForeignControllerDeploy.deployFull(Base.SPARK_EXECUTOR);

        // Overwrite storage for all previous deployments in setUp and assert brand new deployment
        foreignController = ForeignController(controllerInst.controller);
        almProxy          = payable(controllerInst.almProxy);
        rateLimits        = RateLimits(controllerInst.rateLimits);

        ( configAddresses, checkAddresses ) = _getDefaultParams();

        // Admin will be calling the library from its own address
        vm.etch(Base.SPARK_EXECUTOR, address(new LibraryWrapper()).code);

        wrapper = LibraryWrapper(Base.SPARK_EXECUTOR);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 21430000;  // Dec 18, 2024
    }

    function test_initAlmSystem() external {
        assertEq(foreignController.hasRole(FREEZER_ROLE, FREEZER), false);
        assertEq(foreignController.hasRole(RELAYER_ROLE, RELAYER), false);

        assertEq(ALMProxy(almProxy).hasRole(CONTROLLER_ROLE, address(foreignController)), false);
        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,         address(foreignController)), false);

        vm.prank(Base.SPARK_EXECUTOR);
        wrapper.initAlmSystem(controllerInst, configAddresses, checkAddresses);

        assertEq(foreignController.hasRole(FREEZER_ROLE, FREEZER), true);
        assertEq(foreignController.hasRole(RELAYER_ROLE, RELAYER), true);

        assertEq(ALMProxy(almProxy).hasRole(CONTROLLER_ROLE, address(foreignController)), true);
        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,         address(foreignController)), true);
    }

}

contract ForeignController_UpgradeController_Tests is InitAndUpgrade_TestBase {

    LibraryWrapper internal wrapper;

    ControllerInstance internal controllerInst;

    Init.ConfigAddressParams internal configAddresses;
    Init.CheckAddressParams  internal checkAddresses;

    ForeignController internal newController;

    function setUp() public override {
        super.setUp();

        ( configAddresses, checkAddresses ) = _getDefaultParams();

        newController = ForeignController(
            ForeignControllerDeploy.deployController(Base.SPARK_EXECUTOR, almProxy, address(rateLimits))
        );

        controllerInst = ControllerInstance(almProxy, address(newController), address(rateLimits));

        configAddresses.oldController = address(foreignController);  // Revoke from old controller

        // Admin will be calling the library from its own address
        vm.etch(Base.SPARK_EXECUTOR, address(new LibraryWrapper()).code);

        wrapper = LibraryWrapper(Base.SPARK_EXECUTOR);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 21430000;  // Dec 18, 2024
    }

    function test_upgradeController() external {
        assertEq(newController.hasRole(FREEZER_ROLE, FREEZER), false);
        assertEq(newController.hasRole(RELAYER_ROLE, RELAYER), false);

        assertEq(ALMProxy(almProxy).hasRole(CONTROLLER_ROLE, address(foreignController)), true);
        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,         address(foreignController)), true);

        assertEq(ALMProxy(almProxy).hasRole(CONTROLLER_ROLE, address(newController)), false);
        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,         address(newController)), false);

        vm.startPrank(Base.SPARK_EXECUTOR);
        wrapper.upgradeController(controllerInst, configAddresses, checkAddresses);
        vm.stopPrank();

        assertEq(newController.hasRole(FREEZER_ROLE, FREEZER), true);
        assertEq(newController.hasRole(RELAYER_ROLE, RELAYER), true);

        assertEq(ALMProxy(almProxy).hasRole(CONTROLLER_ROLE, address(foreignController)), false);
        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,         address(foreignController)), false);

        assertEq(ALMProxy(almProxy).hasRole(CONTROLLER_ROLE, address(newController)), true);
        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,         address(newController)), true);
    }

}
