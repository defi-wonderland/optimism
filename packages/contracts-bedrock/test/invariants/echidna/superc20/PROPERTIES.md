supERC20 properties
===================

Valid state
-----------

| id    | description                                                           | halmos | echidna |
| ----- | -----                                                                 | -----  | -----   |
|   0   | calls to sendERC20 succeed as long as caller has enough balance       |        |         |

Variable transition
-------------------

| id    | description                                                           | halmos | echidna |
| ----- | -----                                                                 | -----  | -----   |
|   1   | sendERC20 decreases the token's totalSupply in the source chain       |        |         |
|   2   | relayERC20 increases the token's totalSupply in the destination chain |        |         |
|   3   | only calls to `convert()` can increase the total supply across chains |        |         |

High level
----------

| id    | description                                                                                                  | halmos | echidna |
| ----- | -----                                                                                                        | -----  | -----   |
|   4   | sum of total supply across all chains is always `<=` to `convert()`ed amount                                 |        |         |
|   5   | tokens `sendERC20`-ed to a chain can be `relayERC20`-ed as long as the source chain is in the dependency set |        |         |

Unit test
---------

| id    | description                                                                | halmos | echidna |
| ----- | -----                                                                      | -----  | -----   |
|   6   | supERC20 token address does not depend on chainID                          |        |         |
|   7   | supERC20 token address depends on name, remote token, address and decimals |        |         |

Expected external interactions
==============================
- regular ERC20 transfers between any accounts on the same chain



