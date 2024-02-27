// SPDX-License-Identifier: GPL-3.0

/// @title Library for Nouns DAO Logic containing delegation functions

/*********************************
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░█████████░░█████████░░░ *
 * ░░░░░░██░░░████░░██░░░████░░░ *
 * ░░██████░░░████████░░░████░░░ *
 * ░░██░░██░░░████░░██░░░████░░░ *
 * ░░██░░██░░░████░░██░░░████░░░ *
 * ░░░░░░█████████░░█████████░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 *********************************/

pragma solidity ^0.8.19;

import './NounsDAOInterfaces.sol';
import { NounDelegationToken } from './NounDelegationToken.sol';

library NounsDAODelegation {
    function isDelegate(address account, uint256[] memory tokenIds) external view returns (bool) {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (delegateOf(tokenIds[i]) != account) {
                return false;
            }
        }
        return true;
    }

    function delegateOf(uint256 tokenId) public view returns (address) {
        address delegationOwner = NounDelegationToken(ds().delegationToken).ownerOfNoRevert(tokenId);
        if (delegationOwner != address(0)) return delegationOwner;

        return ds().nouns.ownerOf(tokenId);
    }

    /***
     * @dev Used to access the DAO's storage struct without receiving it as a function argument.
     * Created as part of the DAO logic refactor where this admin library is called in the DAO's fallback function,
     * since the DAO no longer makes explicit calls to this library.
     * This function assumes the storage struct starts at slot 0.
     */
    function ds() internal pure returns (NounsDAOTypes.Storage storage ds_) {
        assembly {
            ds_.slot := 0
        }
    }
}
