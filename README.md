# Public Lock (Unlock Protocol) Modules

This repo contains a Hats Protocol module that adds a subscription to a hat using [Unlock Protocol](https://github.com/unlock-protocol/unlock). The latest version uses [Unlock V14](https://docs.unlock-protocol.com/core-protocol/public-lock/#version-14).

## Overview and Usage

The Public Lock V14 module enables an organization to require that a user pay a subscription in order to wear a given hat.

It creates a tight coupling between the hat and a lock. When the module is deployed, it creates a new lock contract. The module sets itself as a hook on the lock contract, which is called whenever a key is purchased from the lock contract.

When users purchase a key, they are also automatically minted the hat. To remain eligible for the hat, they must maintain their subscription to the key.

The module must serve as both a Hats eligibility module and a hatter contract. To mint the target hat when a user purchases a new key, it must be an amin of hte target hat — i.e. wear one of the target hat's admin hats — which makes it a hatter contract. To control eligibility for the target hat, it must also be set as the eligibility module for the target hat.

## Implementation Deployment

In order to deploy a new implementation — eg to a new network — you must not only call the constructor but also the `setUnlock()` initializer function. This function sets the address of the Unlock contract that instances created from the new implementation will use. This is separate from the constructor to enable deployment to use the same initCode and therefore achieve the same address across multiple chains, even though the Unlock address differs by chain.

The full flow is included in the `script/Deploy.s.sol` script.

## Development

This repo uses Foundry for development and testing. To get started:

1. Fork the project
2. Install [Foundry](https://book.getfoundry.sh/getting-started/installation)
3. To install dependencies, run `forge install`
4. To compile the contracts, run `forge build`
5. To test, run `forge test`
