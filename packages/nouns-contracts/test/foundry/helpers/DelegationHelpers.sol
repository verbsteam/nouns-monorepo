// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { INounsDAOLogic } from '../../../contracts/interfaces/INounsDAOLogic.sol';
import { NounsTokenLike } from '../../../contracts/governance/NounsDAOInterfaces.sol';
import { NounDelegationToken } from '../../../contracts/governance/NounDelegationToken.sol';

library DelegationHelpers {
    /***
     * @dev Assumes there is no overlap between owned Nouns and Delegation tokens.
     */
    function allVotesOf(address user, INounsDAOLogic dao) internal view returns (uint256[] memory tokenIds) {
        NounsTokenLike nouns = dao.nouns();
        NounDelegationToken dt = NounDelegationToken(dao.delegationToken());

        uint256 nounBalance = nouns.balanceOf(user);
        uint256 delegationBalance = dt.balanceOf(user);

        tokenIds = new uint256[](nounBalance + delegationBalance);
        uint256 i = 0;
        for (; i < nounBalance; i++) {
            tokenIds[i] = nouns.tokenOfOwnerByIndex(user, i);
        }

        uint256 totalSupply = nouns.totalSupply();
        for (uint256 j = 0; j < totalSupply; j++) {
            if (dt.ownerOfNoRevert(j) == user) {
                tokenIds[i++] = j;
            }
        }
    }
}
