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
        for (uint256 i = 0; i < nounBalance; i++) {
            tokenIds[i] = nouns.tokenOfOwnerByIndex(user, i);
        }

        for (uint256 i = 0; i < delegationBalance; i++) {
            tokenIds[nounBalance + i] = dt.tokenOfOwnerByIndex(user, i);
        }
    }
}
