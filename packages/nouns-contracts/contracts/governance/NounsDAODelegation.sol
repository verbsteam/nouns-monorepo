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
    function isDelegate(address account, uint256[] memory tokenIds) internal view returns (bool) {
        NounDelegationToken dt = NounDelegationToken(ds().delegationToken);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (delegateOf(tokenIds[i], dt) != account) {
                return false;
            }
        }
        return true;
    }

    function delegateOf(uint256 tokenId, NounDelegationToken dt) internal view returns (address) {
        address delegationOwner = dt.ownerOfNoRevert(tokenId);
        require(
            dt.getTokenLastTransfer(tokenId) < block.timestamp,
            'cannot use voting power updated in the current block'
        );
        if (delegationOwner != address(0)) return delegationOwner;

        NounsTokenLike nouns = ds().nouns;
        address nouner = nouns.ownerOf(tokenId);
        address nounsTokenDelegate = nouns.delegates(nouner);
        (uint32 fromBlock, ) = nouns.checkpoints(nounsTokenDelegate, nouns.numCheckpoints(nounsTokenDelegate) - 1);
        require(fromBlock < block.number, 'cannot use voting power updated in the current block');

        return nouner;
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
