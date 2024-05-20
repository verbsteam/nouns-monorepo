// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { INounsDAOLogic } from '../../../contracts/interfaces/INounsDAOLogic.sol';
import { NounsTokenLike } from '../../../contracts/governance/NounsDAOInterfaces.sol';
import { NounDelegationToken } from '../../../contracts/governance/NounDelegationToken.sol';

library DelegationHelpers {
    function allVotesOf(address user, INounsDAOLogic dao) internal view returns (uint256[] memory tokenIds) {
        return allVotesOf(user, dao, block.number - 1);
    }

    /***
     * @dev Assumes all Nouns are owned by user and all delegation tokens are also owned by user.
     */
    function allVotesOf(
        address user,
        INounsDAOLogic dao,
        uint256 atBlock
    ) internal view returns (uint256[] memory tokenIds) {
        NounsTokenLike nouns = dao.nouns();
        NounDelegationToken dt = NounDelegationToken(dao.delegationToken());

        uint256 nounBalance = nouns.balanceOf(user);
        tokenIds = new uint256[](nounBalance);
        uint256 actualCount = 0;
        for (uint256 i = 0; i < nounBalance; i++) {
            uint256 tokenId = nouns.tokenOfOwnerByIndex(user, i);
            if (dt.getPastOwner(tokenId, atBlock) == user) {
                tokenIds[i] = tokenId;
                actualCount++;
            }
        }

        if (nounBalance > actualCount) {
            assembly {
                mstore(tokenIds, actualCount)
            }
        }
    }
}
