// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

/**
 * @title  IBuffer
 * @notice Proxy contract that executes calls, value calls, and delegate calls.
 */
interface IBuffer {

    /**********************************************************************************************/
    /*** Custom Errors                                                                          ***/
    /**********************************************************************************************/

    /**
     * @notice Thrown when the caller is not the admin.
     * @param  caller The address of the caller.
     * @param  admin  The address of the admin.
     */
    error NotAdmin(address caller, address admin);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Performs a standard call to the specified `target` with the given `data`.
     *         Reverts if the call fails.
     * @param  target The address of the target contract to call.
     * @param  data   The calldata that will be sent to the target contract.
     * @return result The returned data from the call.
     */
    function doCall(address target, bytes calldata data) external returns (bytes memory result);

    /**
     * @notice This function allows for transferring `value` (ether) along with the call to the
     *         target contract. Reverts if the call fails.
     * @param  target The address of the target contract to call.
     * @param  data   The calldata that will be sent to the target contract.
     * @param  value  The amount of Ether (in wei) to send with the call.
     * @return result The returned data from the call.
     */
    function doCallWithValue(address target, bytes calldata data, uint256 value)
        external
        payable
        returns (bytes memory result);

    /**
     * @notice This function performs a delegate call to the specified `target` with the given
     *         `data`. Reverts if the call fails.
     * @param  target The address of the target contract to delegate call.
     * @param  data   The calldata that will be sent to the target contract.
     * @return result The returned data from the delegate call.
     */
    function doDelegateCall(address target, bytes calldata data)
        external
        returns (bytes memory result);

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /// @notice The admin address.
    function admin() external view returns (address);

}
