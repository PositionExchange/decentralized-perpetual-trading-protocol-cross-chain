// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IRelayerHub {
    /**
     * Verify relayer is signer for a blockchain
     *
     * @param _address The relayer address
     */
    function isRelayer(address _address) external view returns (bool);

    /**
     * Register relayer for a blockchain
     */
    function register() external;

    /**
     * Unregister relayer for a blockchain
     */
    function unregister() external;

    /**
     * Register relayer for a blockchain use only for owner
     *
     * @param _address The relayer address
     */
    function adminRegister(address _address) external;

    /**
     * Unregister relayer for a blockchain use only for owner
     *
     * @param _address The relayer address
     */
    function adminUnregister(address _address) external;

    /**
     * Update registration status public
     */
    function enablePublicRegistration() external;

    /**
     * Update registration status private
     */
    function disablePublicRegistration() external;

    /**
     * Update required deposit amount
     *
     * @param _requiredDeposit Required deposit amount
     */
    function updateRequiredDeposit(uint256 _requiredDeposit) external;

    /**
     * Update dues amount
     *
     * @param _dues Registration dues amount
     */
    function updateDues(uint256 _dues) external;
}
